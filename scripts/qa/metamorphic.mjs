#!/usr/bin/env node
// A METAMORPHIC GATE: the findings must not depend on how the source is
// written down.
//
// A check that runs the analyser once measures ONE shape of the input.  A
// check that runs it over MUTATED shapes measures the analyser itself: the
// relations below are properties of the ANALYSIS, not of the text.
//
//   RENAME    the same program with different identifiers must produce the
//             same claims.  An analyser whose claims depend on the NAME of a
//             local is not analysing the program.
//   REORDER   the same program with its functions in another order must
//             produce the same claims.  A finding that depends on how many
//             functions happen to precede it is a finding about the FILE
//             ORDER, not about the program -- and the report already says
//             the CFG pass takes the FIRST functions in file order, so this
//             is a property worth pinning.
//   SWAP      `a + b` and `b + a` are the same count, so they must produce
//             the same claims.  The COUNT of a `+`-built array is the sum of
//             the two counts, and a sum does not remember which side was
//             first.
//
// And two more, because a metamorphic gate that cannot fail is decoration:
//
//   SENSITIVE the comparison must be able to TELL two programs apart: a
//             program whose claims really are different must produce a
//             different signature.
//   STABLE    the same program analysed TWICE must produce the same findings
//             IN THE SAME ORDER -- a hash-order artefact would show up here
//             and nowhere else.
//
// The signature of a finding is its rule, severity, verdict, function,
// method, message and evidence, with the RENAMED identifiers folded to one
// placeholder.  The LINE is not in the signature: the reorder relation
// legitimately moves a finding's line, and what has to be invariant is WHICH
// claims the analyser makes and WHAT it says -- not where they sit in a file.
//
// The binary under test is BUILT here, not assumed: a binary left over from
// an earlier build measures the product as it WAS.
//
// Usage: node scripts/qa/metamorphic.mjs [--no-build] [--falsify]
//
// `--falsify` inverts ONE expectation on purpose and requires the check to
// FAIL.  A check that cannot fail is not a check.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = resolve(process.cwd());
const work = join(root, '_build', 'qa', 'metamorphic');
const skipBuild = process.argv.includes('--no-build');
const falsify = process.argv.includes('--falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ---------------------------------------------------------------------------
// THE PROGRAMS.
//
// The base is the starting point; every variant below is the SAME program
// written a different way, except the last one, which is a different program
// on purpose.
// ---------------------------------------------------------------------------
const BASE = `pub fn concat(user : String, size : Int32) -> Array[String] {
  let a = [user]
  let b = [user, user]
  let c = a + b
  Array::make(c.length(), 0)
}

pub fn lookup(index : Int32) -> Int32 {
  let xs = [1, 2, 3]
  xs[index]
}
`;

// The RENAMED program: the same, with different identifiers.
const RENAMED = `pub fn concat(qqq : String, size : Int32) -> Array[String] {
  let a = [qqq]
  let b = [qqq, qqq]
  let c = a + b
  Array::make(c.length(), 0)
}

pub fn lookup(zzz : Int32) -> Int32 {
  let www = [1, 2, 3]
  www[zzz]
}
`;

// The REORDERED program: the same, with the functions in the other order.
const REORDERED = `pub fn lookup(index : Int32) -> Int32 {
  let xs = [1, 2, 3]
  xs[index]
}

pub fn concat(user : String, size : Int32) -> Array[String] {
  let a = [user]
  let b = [user, user]
  let c = a + b
  Array::make(c.length(), 0)
}
`;

// The SWAPPED program: the same, with the concatenation the other way round.
const SWAPPED = `pub fn concat(user : String, size : Int32) -> Array[String] {
  let a = [user]
  let b = [user, user]
  let c = b + a
  Array::make(c.length(), 0)
}

pub fn lookup(index : Int32) -> Int32 {
  let xs = [1, 2, 3]
  xs[index]
}
`;

// The DIFFERENT program: the index read is gone, so the claims about it must
// be gone too.  This one exists to prove the comparison can tell two
// programs apart.
const DIFFERENT = `pub fn concat(user : String, size : Int32) -> Array[String] {
  let a = [user]
  let b = [user, user]
  let c = a + b
  Array::make(c.length(), 0)
}

pub fn lookup(index : Int32) -> Int32 {
  let xs = [1, 2, 3]
  let _ = index
  xs[0]
}
`;

// Every identifier that any variant renames, folded to ONE placeholder.  The
// SAME map is applied to every variant, so a renamed program and the base
// are comparable.
const RENAMES = ['user', 'qqq', 'index', 'zzz', 'xs', 'www'];

///|
/// The signature of a finding: everything that must not depend on how the
/// source is written down, with the renamed identifiers folded away.
function signature(findings) {
  return findings
    .map((f) => {
      let msg = f.message;
      let ev = f.evidence;
      for (const name of RENAMES) {
        msg = msg.split(name).join('<ID>');
        ev = ev.split(name).join('<ID>');
      }
      return [f.rule, f.severity, f.verdict, f.fn, f.method, msg, ev].join(' | ');
    })
    .sort();
}

///|
/// The order the findings came in, with the same folding.  The metamorphic
/// relations compare the SET of claims; the ORDER is a separate property, and
/// it is checked by the STABLE relation below.
function orderedSignature(findings) {
  const folded = findings.map((f) => {
    let msg = f.message;
    let ev = f.evidence;
    for (const name of RENAMES) {
      msg = msg.split(name).join('<ID>');
      ev = ev.split(name).join('<ID>');
    }
    return [f.rule, f.severity, f.verdict, f.fn, f.method, msg, ev].join(' | ');
  });
  return folded.join('\n');
}

// ---------------------------------------------------------------------------
// run the analyser over one program
// ---------------------------------------------------------------------------
function analyse(name, source) {
  const dir = join(work, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'lib.mbt'), source, 'utf8');
  writeFileSync(join(dir, 'moon.mod'), 'name = "demo/meta"\n\nversion = "0.0.1"\n', 'utf8');
  const out = join(dir, 'out');
  const run = spawnSync(
    resolveCli(root),
    ['analyze', '--dir', dir, '--out', out, '--funnel'],
    { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (run.status !== 0) {
    console.error(`the analyser failed on ${name}`);
    console.error(`${run.stdout ?? ''}${run.stderr ?? ''}`);
    process.exit(2);
  }
  const sidecar = readdirSync(out).find((f) => f.endsWith('_findings.jsonl'));
  if (!sidecar) {
    console.error(`the analyser wrote no findings sidecar for ${name}`);
    process.exit(2);
  }
  return readFileSync(join(out, sidecar), 'utf8')
    .split('\n')
    .filter((l) => l.trim() !== '')
    .map((l) => JSON.parse(l));
}

// ---------------------------------------------------------------------------
// 1. build, and run every variant
// ---------------------------------------------------------------------------
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });

if (!skipBuild) {
  const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (build.status !== 0) {
    console.error('the analyser did not build');
    console.error(`${build.stdout ?? ''}${build.stderr ?? ''}`);
    process.exit(2);
  }
}

const base = analyse('base', BASE);
const renamed = analyse('renamed', RENAMED);
const reordered = analyse('reordered', REORDERED);
const swapped = analyse('swapped', SWAPPED);
const different = analyse('different', DIFFERENT);
const baseAgain = analyse('base_again', BASE);

const sigBase = signature(base);
console.log(`the analyser produced ${base.length} finding(s) for the base program\n`);

if (base.length === 0) {
  console.error('the analyser produced no findings at all — the relations would be vacuous');
  process.exit(2);
}

// ---------------------------------------------------------------------------
// 2. the relations
// ---------------------------------------------------------------------------
check(
  'RENAME: the same program with different identifiers makes the same claims',
  JSON.stringify(signature(renamed)) === JSON.stringify(sigBase),
  `${signature(renamed).length} claim(s)`,
);
check(
  'REORDER: the same program with its functions in another order makes the same claims',
  JSON.stringify(signature(reordered)) === JSON.stringify(sigBase),
  `${signature(reordered).length} claim(s)`,
);
check(
  'SWAP: `a + b` and `b + a` make the same claims — a sum does not remember which side was first',
  JSON.stringify(signature(swapped)) === JSON.stringify(sigBase),
  `${signature(swapped).length} claim(s)`,
);

// ---------------------------------------------------------------------------
// 3. the comparison can tell two programs apart
// ---------------------------------------------------------------------------
check(
  'SENSITIVE: a program whose claims really are different gets a different signature',
  JSON.stringify(signature(different)) !== JSON.stringify(sigBase),
  `${signature(different).length} claim(s) vs ${sigBase.length}`,
);

// ---------------------------------------------------------------------------
// 4. the same program, twice
// ---------------------------------------------------------------------------
check(
  'STABLE: the same program analysed twice gives the same findings in the same ORDER',
  orderedSignature(baseAgain) === orderedSignature(base),
);
check(
  '  and the same number of them',
  baseAgain.length === base.length,
  `${baseAgain.length} vs ${base.length}`,
);

// ---------------------------------------------------------------------------
// 5. the falsification
// ---------------------------------------------------------------------------
if (falsify) {
  // The expectation that is inverted on purpose: the renamed program makes
  // DIFFERENT claims.  If the check cannot fail, it is not a check.
  check(
    'FALSIFIED: the renamed program makes different claims',
    JSON.stringify(signature(renamed)) !== JSON.stringify(sigBase),
    'the falsification must fail',
  );
}

console.log('');
console.log(
  failures === 0
    ? `RESULT: PASS (${checks} check(s), 0 failure(s))`
    : `RESULT: FAIL (${checks} check(s), ${failures} failure(s))`,
);
process.exit(failures === 0 ? 0 : 1);
