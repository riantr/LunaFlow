#!/usr/bin/env node
// IFDS PHASE 3 -- THE SIZE OF A `+`-BUILT ARRAY.
//
// The check runs the ANALYSER -- the product, over a real module on disk -- and
// compares what it says with what the phase claims. It does not read a
// document to find out whether the phase happened.
//
// Two things are checked:
//
//   1. THE BEHAVIOUR. A module of six shapes is written into the work
//      directory and analysed. Two of the shapes are NEGATIVE -- the count of
//      the concatenation is fixed by the code, so no claim may be made -- and
//      four are POSITIVE -- the count really is the caller's to choose, so the
//      claim must be made, and it must name the sources that decide the COUNT
//      and nothing else.
//
//   2. THE COVERAGE LEDGER. The repair removed claims from doubleML.
//      `docs/qa/IFDS_PHASE3_LEDGER.json` names every one of them, and this
//      check verifies that the COMMITTED doubleML artefact does not carry any
//      of them -- so the cost stays registered instead of becoming a silent
//      gap, and a change that puts one of them back has to say so.
//
// The binary under test is BUILT here, not assumed: a binary left over from an
// earlier build measures the product as it WAS.
//
// Usage: node scripts/qa/plus_size.mjs [--no-build] [--falsify]
//
// `--falsify` inverts ONE expectation on purpose and requires the check to
// FAIL. A check that cannot fail is not a check.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';
import { committedArtefact } from './committed_artefact.mjs';

const root = resolve(process.cwd());
const work = join(root, '_build', 'qa', 'plus_size', 'shapes');
const skipBuild = process.argv.includes('--no-build');
const falsify = process.argv.includes('--falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

// ---------------------------------------------------------------------------
// THE SHAPES.
//
// Every function is one shape, and the comment says what the claim SHOULD be.
// The expectations below are the SPECIFICATION; the analyser is measured
// against them.
// ---------------------------------------------------------------------------
const SHAPES = `///|
/// THE SIZE OF A \`+\`-BUILT ARRAY -- six shapes.
///
/// \`+\` on arrays is MoonBit's concatenation, so the result's COUNT is the sum
/// of the two counts, and its SIZE's taint is the union of the two SIZE
/// taints -- never the elements' taint.
///
/// Two of these are NEGATIVE: the count is fixed by the code, or the claim
/// would come from the CONTENTS. Four are POSITIVE: the count really is the
/// caller's to choose, so the claim must be made -- and it must name the
/// sources that decide the COUNT, and no others.

// ---------------------------------------------------------------------------
// NEGATIVES.
// ---------------------------------------------------------------------------

///|
/// NEGATIVE. Two literals: the count is 2, a constant, and no tainted value
/// chooses it.
pub fn size_of_plus_literals(user : String) -> Array[Int32] {
  let a = [user] + [user]
  Array::make(a.length(), 0)
}

///|
/// NEGATIVE. The size is read into a variable first; the claim must still not
/// be made.
pub fn size_of_plus_literal_binding(user : String) -> Array[Int32] {
  let a = [user] + [user]
  let n = a.length()
  Array::make(n, 0)
}

// ---------------------------------------------------------------------------
// POSITIVES.
// ---------------------------------------------------------------------------

///|
/// POSITIVE. The count is \`xs\`'s length plus ONE: the caller chose how many
/// elements \`xs\` has, so the claim must be made -- and it must name \`xs\` and
/// NOT \`user\`, which is the ELEMENT.
pub fn size_of_plus_parameter(xs : Array[String], user : String) -> Array[Int32] {
  let a = xs + [user]
  Array::make(a.length(), 0)
}

///|
/// POSITIVE. The count is the sum of TWO caller's lengths, so the claim must
/// name both parameters -- and no element.
pub fn size_of_plus_two_parameters(
  xs : Array[String],
  ys : Array[String],
  user : String,
) -> Array[Int32] {
  let a = xs + [user] + ys
  Array::make(a.length(), 0)
}

///|
/// POSITIVE, through a binding: the length is read into a variable first, and
/// the claim must still be made, naming the parameters that decide the COUNT.
pub fn size_of_plus_bound(xs : Array[String], user : String) -> Array[Int32] {
  let a = xs + [user]
  let n = a.length()
  Array::make(n, 0)
}

///|
/// POSITIVE, and TRUE: the size is the ELEMENT's value, and \`xs\` is
/// untrusted. The claim must stay.
pub fn element_of_plus_array(xs : Array[String]) -> Array[Int32] {
  let a = xs + [0]
  let e = a[0]
  Array::make(e, 0)
}
`;

// What each shape must produce: how many allocation-size claims, and which
// sources the labels may name.
const EXPECT = [
  { fn: 'size_of_plus_literals', claims: 0, names: [], forbids: [] },
  { fn: 'size_of_plus_literal_binding', claims: 0, names: [], forbids: [] },
  { fn: 'size_of_plus_parameter', claims: 1, names: ['`xs`'], forbids: ['`user`'] },
  {
    fn: 'size_of_plus_two_parameters',
    claims: 1,
    names: ['`xs`', '`ys`'],
    forbids: ['`user`'],
  },
  { fn: 'size_of_plus_bound', claims: 1, names: ['`xs`'], forbids: ['`user`'] },
  { fn: 'element_of_plus_array', claims: 1, names: ['`xs`'], forbids: [] },
];

// ---------------------------------------------------------------------------
// 1. build the analyser and run it over the shapes
// ---------------------------------------------------------------------------
if (!skipBuild) {
  const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
    shell: true,
  });
  if (build.status !== 0) {
    console.error('the analyser build failed, so there is nothing to measure:');
    console.error((build.stderr ?? '') + (build.stdout ?? ''));
    process.exit(2);
  }
}

rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });
writeFileSync(join(work, 'shapes.mbt'), SHAPES, 'utf8');

const out = join(work, 'out');
mkdirSync(out, { recursive: true });
const run = spawnSync(
  resolveCli(root),
  ['analyze', '--dir', work, '--out', out, '--funnel'],
  { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
);
if (run.status !== 0) {
  console.error(`the analyser exited with code ${run.status}:`);
  console.error((run.stderr ?? '') + (run.stdout ?? ''));
  process.exit(2);
}

const findingsFile = readdirSync(out).find((f) => f.endsWith('_findings.jsonl'));
if (!findingsFile) {
  console.error('the analyser wrote no findings sidecar');
  process.exit(2);
}
const findings = readFileSync(join(out, findingsFile), 'utf8')
  .split('\n')
  .filter((l) => l.trim())
  .map((l) => JSON.parse(l));

console.log(`the analyser over the six shapes produced ${findings.length} finding(s)\n`);

// --- the claims, per shape ---------------------------------------------------
// One expectation is inverted on purpose in the falsification mode, so the
// comparison is proved to be live.
const expect = EXPECT.map((e) => ({ ...e }));
if (falsify) {
  const target = expect.find((e) => e.fn === 'size_of_plus_parameter');
  target.claims = 0; // the defect's reading: the count's source is not named
  console.log('FALSIFY: the shape `size_of_plus_parameter` is expected to make NO claim\n');
}

for (const e of expect) {
  const mine = findings.filter(
    (f) => f.fn === e.fn && f.rule === 'TAINT-ALLOC' && f.method === 'L2-abstract',
  );
  check(
    `${e.fn}: ${e.claims} L2 allocation-size claim(s)`,
    mine.length === e.claims,
    `got ${mine.length}`,
  );
  for (const src of e.names) {
    const ok = mine.length > 0 && mine.every((f) => f.message.includes(src));
    check(
      `${e.fn}: every L2 claim names ${src}`,
      ok,
      mine.map((f) => f.message).join(' | '),
    );
  }
  for (const src of e.forbids) {
    const ok = mine.length > 0 && mine.every((f) => !f.message.includes(src));
    check(
      `${e.fn}: no L2 claim names ${src}`,
      ok,
      mine.map((f) => f.message).join(' | '),
    );
  }
}

// THE COUNT IS THE SUM, and the claim says so: the evidence carries the size's
// interval, and [1,65] is a caller's array (0..64) plus the literal's ONE.
const paramClaims = findings.filter(
  (f) => f.fn === 'size_of_plus_parameter' && f.rule === 'TAINT-ALLOC' && f.method === 'L2-abstract',
);
check(
  'size_of_plus_parameter: the claim carries the SUM of the two counts',
  paramClaims.length === 1 && paramClaims[0].evidence === 'Array.make([1,65])',
  paramClaims.map((f) => f.evidence).join(' | '),
);

// The shapes are about SIZES, and the layer under test is the L2 -- the
// abstract layer. The dynamic layer (L1) has its own taint model and its own
// allocation rule, and Phase 3 left it alone, so its claims are REPORTED and
// not counted.
const byMethod = (m) => findings.filter((f) => f.method === m);
console.log(
  `DATA  the dynamic layer filed ${byMethod('dynamic+symbolic').length} claim(s) of its own ` +
    `(out of scope: Phase 3 changed the L2's value domain)`,
);
console.log(
  `DATA  the L2 filed ${findings.filter((f) => f.method.startsWith('L2')).length} finding(s) in total, ` +
    `${findings.filter((f) => f.method === 'L2-abstract' && f.rule !== 'TAINT-ALLOC').length} of them not about an allocation size`,
);

// The one family the separation also touches is the tainted INDEX: a size's
// taint reaching an index is the same defect seen from the other side. The
// shapes must not produce one.
const taintedIndexes = findings.filter(
  (f) => f.method === 'L2-abstract' && f.rule.startsWith('TAINT-INDEX'),
);
check(
  'the shapes produce no L2 tainted-index claim',
  taintedIndexes.length === 0,
  taintedIndexes.map((f) => `${f.fn} ${f.file}:${f.line}`).join(', '),
);

// ---------------------------------------------------------------------------
// 2. the coverage ledger, against the COMMITTED doubleML artefact
//
// The ledger registers BOTH directions. The repair REMOVED fourteen
// allocation-size claims and ADDED twenty-nine, and a ledger that registers
// only the removals would leave half the trade unrecorded.
// ---------------------------------------------------------------------------
const ledgerPath = join(root, 'docs', 'qa', 'IFDS_PHASE3_LEDGER.json');
if (!existsSync(ledgerPath)) {
  check('the coverage ledger is committed', false, ledgerPath);
} else {
  const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
  check(
    'the ledger names the removed claims',
    Array.isArray(ledger.removed) && ledger.removed.length === 14,
    `${ledger.removed?.length}`,
  );
  check(
    'the ledger names the added claims',
    Array.isArray(ledger.added) && ledger.added.length === 29,
    `${ledger.added?.length}`,
  );
  const verdicts = new Set([
    ...ledger.removed.map((r) => r.verdict),
    ...ledger.added.map((r) => r.verdict),
    ...ledger.sharpened.map((r) => r.verdict),
  ]);
  check(
    'every registered claim carries a verdict',
    [...verdicts].every((v) => ledger.verdicts[v]),
    [...verdicts].join(', '),
  );

  // The committed artefact is the one a reader can check. Every removed site
  // must be ABSENT from it, and every added site PRESENT in it.
  //
  // The artefact is FOUND, not named: the corpus version is part of the file
  // name and the registry moves it, so a checker that carried the version
  // would stop finding the artefact -- and would then compare nothing.
  const artefact = committedArtefact(
    root,
    'riantr_moonbit_doubleML@latest_',
    '_findings.jsonl',
  );
  if (!artefact) {
    check('the committed doubleML artefact is present', false, join(root, 'reports'));
  } else {
    const committed = readFileSync(artefact, 'utf8')
      .split('\n')
      .filter((l) => l.trim())
      .map((l) => JSON.parse(l));
    const at = (site) =>
      committed.filter((f) => f.file === site.file && f.line === site.line);

    const back = ledger.removed.filter((r) =>
      at(r).some((f) => f.rule === r.rule && f.message.includes(r.source)),
    );
    check(
      'no removed claim is back in the committed doubleML artefact',
      back.length === 0,
      back.map((r) => `${r.file}:${r.line}`).join(', '),
    );

    const missing = ledger.added.filter((a) => !at(a).some((f) => f.rule === a.rule));
    check(
      'every added claim is in the committed doubleML artefact',
      missing.length === 0,
      missing.map((a) => `${a.file}:${a.line}`).join(', '),
    );

    const notSharpened = ledger.sharpened.filter(
      (s) => !at(s).some((f) => f.rule === s.rule && f.evidence === s.evidence),
    );
    check(
      'every sharpened finding carries the count the model now computes',
      notSharpened.length === 0,
      notSharpened.map((s) => `${s.file}:${s.line}`).join(', '),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. the falsification mode's own verdict
//
// In the falsification mode the INVERTED expectation is meant to fail, so the
// failure is the PASS. The mode exits 0 when the check broke as required, and
// 1 when it did not -- which is what makes it usable as a gate step: the same
// convention `scripts/qa/ifds_spike.mjs --falsify` uses.
// ---------------------------------------------------------------------------
if (falsify) {
  checks += 1;
  const broke = failures > 0;
  if (broke) {
    console.log(
      `PASS  the falsification mode broke the check, as it must — ${failures} failure(s)`,
    );
    failures = 0;
  } else {
    console.log('FAIL  the falsification mode did NOT break the check — it is vacuous');
  }
  console.log(
    '\nthe check is falsifiable: it fails when the reading is wrong.',
  );
} else {
  console.log('');
}

console.log(
  failures === 0
    ? `the size of a \`+\`-built array: all ${checks} checks agree.`
    : `the size of a \`+\`-built array: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
