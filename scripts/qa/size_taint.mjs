#!/usr/bin/env node
// IFDS PHASE 2 -- THE SIZE OF A CONTAINER, AND THE TAINT OF ITS CONTENTS.
//
// The check runs the ANALYSER -- the product, over a real module on disk -- and
// compares what it says with what the phase claims. It does not read a
// document to find out whether the phase happened.
//
// Two things are checked:
//
//   1. THE BEHAVIOUR. A module of nine shapes is written into the work
//      directory and analysed. Four of the shapes are NEGATIVE -- the size is
//      not the untrusted input's to choose, so no claim may be made -- and five
//      are POSITIVE -- the size really is the untrusted input's to choose, so
//      the claim must be made, and it must name the sources that decide the
//      size and nothing else.
//
//   2. THE COVERAGE LEDGER. The repair removed twenty claims from doubleML.
//      `docs/qa/IFDS_PHASE2_LEDGER.json` names every one of them, and this
//      check verifies that the COMMITTED doubleML artefact does not carry any
//      of them -- so the cost stays registered instead of becoming a silent
//      gap, and a change that puts one of them back has to say so.
//
// The binary under test is BUILT here, not assumed: a binary left over from an
// earlier build measures the product as it WAS.
//
// Usage: node scripts/qa/size_taint.mjs [--no-build] [--falsify]
//
// `--falsify` inverts ONE expectation on purpose and requires the check to
// FAIL. A check that cannot fail is not a check.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = resolve(process.cwd());
const work = join(root, '_build', 'qa', 'size_taint', 'shapes');
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
/// THE SIZE OF A CONTAINER, AND THE TAINT OF ITS CONTENTS -- nine shapes.
///
/// A container's SIZE and its CONTENTS carry different taints, and these nine
/// functions are the shapes where the two can disagree. Four of them are
/// NEGATIVE: the size is not the untrusted input's to choose, so no claim may
/// be made. Five are POSITIVE: the size really is the untrusted input's to
/// choose, so the claim must be made -- and it must name the sources that
/// decide the SIZE, and no others.

// ---------------------------------------------------------------------------
// NEGATIVES.
// ---------------------------------------------------------------------------

///|
/// The array holds ONE element, so its length is 1 whatever that element is.
/// A tainted element says NOTHING about the count.
pub fn size_of_literal_contents(user : String) -> Array[Int32] {
  let a = [user]
  Array::make(a.length(), 0)
}

///|
/// The same shape through a binding: the length is read into a variable
/// first, and the claim must still not be made.
pub fn size_of_bound_length(user : String) -> Array[Int32] {
  let a = [user]
  let n = a.length()
  Array::make(n, 0)
}

///|
/// A pushed array: the length is 2, a constant, and the element's taint
/// still says nothing about it.
pub fn size_after_push(user : String) -> Array[Int32] {
  let mut a = [user]
  a.push(0)
  Array::make(a.length(), 0)
}

///|
/// The ELEMENTS of a sized array are the values that were put in it -- not
/// the size. \`Array::make(n, 0)\` fills the array with ZEROS, so reading one
/// back gives a zero, and a zero controls no size. ONE claim: the first
/// allocation's, whose size IS \`n\`.
pub fn element_of_sized_array(n : Int32) -> Array[Int32] {
  let a = Array::make(n, 0)
  let e = a[0]
  Array::make(e, 0)
}

///|
/// The count is NOT a constant here, so nothing masks the claim: \`a\` holds
/// \`n\` copies of \`user\`, and its LENGTH is \`n\`. The caller chose how many
/// elements there are; \`user\` says what is in them. So the second
/// allocation's size is \`n\`, and the label must name \`n\` and NOT \`user\`.
pub fn size_of_made_contents(n : Int32, user : String) -> Array[Int32] {
  let a = Array::make(n, user)
  let len = a.length()
  Array::make(len, 0)
}

// ---------------------------------------------------------------------------
// POSITIVES.
// ---------------------------------------------------------------------------

///|
/// The size is a parameter: the caller chose it.
pub fn size_from_parameter(n : Int32) -> Array[Int32] {
  Array::make(n, 0)
}

///|
/// The size is the length of a CALLER-SUPPLIED array: the caller chose how
/// many elements it has.
pub fn size_from_parameter_length(xs : Array[Int32]) -> Array[Int32] {
  Array::make(xs.length(), 0)
}

///|
/// The size is the length of a caller-supplied string.
pub fn size_from_string_length(s : String) -> Array[Int32] {
  Array::make(s.length(), 0)
}

///|
/// The size is the length of a string BUILT from untrusted input, so the
/// input's length decides it.
pub fn size_from_built_string(user : String) -> Array[Int32] {
  let s = "x" + user
  Array::make(s.length(), 0)
}
`;

// What each shape must produce: how many allocation-size claims, and which
// sources the labels may name.
const EXPECT = [
  { fn: 'size_of_literal_contents', claims: 0, names: [], forbids: [] },
  { fn: 'size_of_bound_length', claims: 0, names: [], forbids: [] },
  { fn: 'size_after_push', claims: 0, names: [], forbids: [] },
  { fn: 'element_of_sized_array', claims: 1, names: ['`n`'], forbids: [] },
  { fn: 'size_of_made_contents', claims: 2, names: ['`n`'], forbids: ['`user`'] },
  { fn: 'size_from_parameter', claims: 1, names: ['`n`'], forbids: [] },
  { fn: 'size_from_parameter_length', claims: 1, names: ['`xs`'], forbids: [] },
  { fn: 'size_from_string_length', claims: 1, names: ['`s`'], forbids: [] },
  { fn: 'size_from_built_string', claims: 1, names: ['`user`'], forbids: [] },
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

console.log(`the analyser over the nine shapes produced ${findings.length} finding(s)\n`);

// --- the claims, per shape ---------------------------------------------------
// One expectation is inverted on purpose in the falsification mode, so the
// comparison is proved to be live.
const expect = EXPECT.map((e) => ({ ...e }));
if (falsify) {
  const target = expect.find((e) => e.fn === 'size_of_made_contents');
  target.claims = 1; // the defect's reading: the second allocation is silent
  console.log('FALSIFY: the shape `size_of_made_contents` is expected to make ONE claim\n');
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

// The shapes are about SIZES, and the layer under test is the L2 -- the
// abstract layer. The dynamic layer (L1) has its own taint model and its own
// allocation rule, and Phase 2 left it alone, so its claims are REPORTED and
// not counted. The same goes for the families that are about the size's
// INTERVAL rather than its taint: they belong to other rules, and the shapes
// produce them on purpose (an `Int32` parameter's interval reaches below
// zero).
const byMethod = (m) => findings.filter((f) => f.method === m);
console.log(
  `DATA  the dynamic layer filed ${byMethod('dynamic+symbolic').length} claim(s) of its own ` +
    `(out of scope: Phase 2 changed the L2's value domain)`,
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
// ---------------------------------------------------------------------------
const ledgerPath = join(root, 'docs', 'qa', 'IFDS_PHASE2_LEDGER.json');
if (!existsSync(ledgerPath)) {
  check('the coverage ledger is committed', false, ledgerPath);
} else {
  const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
  check(
    'the ledger names the twenty removed claims',
    ledger.removed.length === 20,
    `${ledger.removed.length}`,
  );
  check(
    'the ledger records that no claim was added',
    Array.isArray(ledger.added) && ledger.added.length === 0,
    JSON.stringify(ledger.added),
  );
  const verdicts = new Set(ledger.removed.map((r) => r.verdict));
  check(
    'every removed claim carries a verdict',
    [...verdicts].every((v) => ledger.verdicts[v]),
    [...verdicts].join(', '),
  );

  // The committed artefact is the one a reader can check. Every ledger site
  // must be ABSENT from it.
  const artefact = join(
    root,
    'reports',
    'riantr_moonbit_doubleML@latest_0.164.64_findings.jsonl',
  );
  if (!existsSync(artefact)) {
    check('the committed doubleML artefact is present', false, artefact);
  } else {
    const committed = readFileSync(artefact, 'utf8')
      .split('\n')
      .filter((l) => l.trim())
      .map((l) => JSON.parse(l));
    const stillThere = ledger.removed.filter((r) =>
      committed.some(
        (f) =>
          f.rule === r.rule &&
          f.file === r.file &&
          f.line === r.line &&
          f.message.includes(r.source),
      ),
    );
    check(
      'no ledger site is back in the committed doubleML artefact',
      stillThere.length === 0,
      stillThere.map((r) => `${r.file}:${r.line}`).join(', '),
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
    ? `the size-taint separation: all ${checks} checks agree.`
    : `the size-taint separation: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
