#!/usr/bin/env node
// THE GATE'S VERDICTS: a FAIL is not an UNKNOWN.
//
// The gate runs every check this repository has, and a check can end in
// three ways:
//
//   exit 0   the check ran, and every claim it made agreed.        PASS
//   exit 1   the check ran, and a claim did NOT agree.               FAIL
//   exit 2   the check could NOT produce a verdict at all.         UNKNOWN
//
// THE THIRD ONE IS THE POINT.  A check that cannot RUN -- the registry is
// unreachable, the analyser wrote no findings, the build failed, there is
// nothing to compare -- says NOTHING about the tree.  Reading it as a
// failure says "the module is broken" when the truth is "nobody knows".
//
// The harnesses under `scripts/qa/` ALREADY used exit 2 for "no verdict" --
// 28 sites across 17 scripts -- and exit 1 for "the checks failed".  What was
// missing was a gate that READS it, so "I could not verify" was printed as
// `FAIL(2)` and weighed the same as a real defect.
//
// This check proves the three things that have to hold together:
//
//   1. THE CLASSIFIER.  Given steps that exit 0, 1 and 2, the gate puts
//      each in its own bucket, and its own exit code says which of the two
//      bad things happened: 1 for a FAIL, 2 for an UNKNOWN with no FAIL.
//      An UNEXPECTED exit code is a FAIL -- the gate fails closed.
//
//   2. THE CONVENTION.  Three shipped checks are driven into the path where
//      they cannot produce a verdict, and each must exit 2 -- not 1.  A
//      check that cannot decide must not claim that it decided.
//
//   3. THE REACHABILITY.  The shipped step list must contain a step whose
//      script CAN exit 2, or the UNKNOWN bucket is dead code and a reader
//      would be right to ignore it.
//
// Usage: node scripts/qa/gate_verdicts.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(process.cwd());
const runner = join(root, 'scripts', 'qa', 'gate.ps1');
const stepsFile = join(root, 'scripts', 'qa', 'gate-steps.json');
const scratch = join(root, '_build', 'qa', 'gate_verdicts');

let failures = 0;
let assertions = 0;
function check(name, ok, detail = '') {
  assertions += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

// ---------------------------------------------------------------------------
// the harness
// ---------------------------------------------------------------------------

///|
/// The PowerShell to run the gate with.  `powershell` is Windows PowerShell;
/// `pwsh` is what a Linux CI runner has.  The runner itself is written in
/// the subset both understand.
function findPowerShell() {
  for (const c of ['powershell', 'pwsh']) {
    const r = spawnSync(c, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'], {
      encoding: 'utf8',
      timeout: 120000,
    });
    if (r.status === 0) return c;
  }
  return null;
}

if (!existsSync(runner)) {
  console.error(`the gate runner is missing: ${runner}`);
  process.exit(2);
}
const ps = findPowerShell();
if (ps === null) {
  // No verdict: this check could not run at all.  That is exit 2 by the
  // convention this very file is about.
  console.error('no PowerShell on this machine (powershell or pwsh) — the check could not run');
  process.exit(2);
}

rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });

///|
/// Run the gate against a step list of our own, and return its exit code
/// and its output.
function runGate(steps, label) {
  const file = join(scratch, `${label}.json`);
  writeFileSync(file, JSON.stringify(steps, null, 2), 'utf8');
  const r = spawnSync(
    ps,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', runner, '-Steps', file],
    { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
  );
  return { code: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

///|
/// The gate's own summary line: "GATE: 1 passed, 1 failed, 1 unknown ...".
function summary(out) {
  const m = /GATE: (\d+) passed, (\d+) failed, (\d+) unknown/.exec(out);
  return m ? { pass: Number(m[1]), fail: Number(m[2]), unknown: Number(m[3]) } : null;
}

///|
/// A step whose only job is to exit with a given code, and whose text says
/// which one it is -- so the gate's own output can be matched against it.
const exitsWith = (code, tag) => `node -e "process.exit(${code}) /* ${tag} */"`;

// ---------------------------------------------------------------------------
// 1. the classifier
// ---------------------------------------------------------------------------

console.log('== the classifier ==');

const mixed = runGate(
  [exitsWith(0, 'CASE_ZERO'), exitsWith(1, 'CASE_FAIL'), exitsWith(2, 'CASE_UNKNOWN')],
  'mixed',
);
const mixedSummary = summary(mixed.out);
check(
  'the gate counts a 0, a 1 and a 2 as one pass, one fail and one unknown',
  mixedSummary !== null &&
    mixedSummary.pass === 1 &&
    mixedSummary.fail === 1 &&
    mixedSummary.unknown === 1,
  mixedSummary ? JSON.stringify(mixedSummary) : 'the gate printed no summary line',
);
check(
  'the gate prints the exit-2 step as UNKNOWN, not as a failure',
  /UNKNOWN\(2\)\s+.*CASE_UNKNOWN/.test(mixed.out) && !/FAIL\(\d+\)\s+.*CASE_UNKNOWN/.test(mixed.out),
);
check(
  'the gate prints the exit-1 step as a failure',
  /FAIL\(1\)\s+.*CASE_FAIL/.test(mixed.out),
);
check(
  'a run with a FAIL exits 1 — the tree is broken',
  mixed.code === 1,
  `exit ${mixed.code}`,
);

const onlyUnknown = runGate([exitsWith(0, 'CASE_ZERO'), exitsWith(2, 'CASE_UNKNOWN')], 'only_unknown');
const onlyUnknownSummary = summary(onlyUnknown.out);
check(
  'a run with no failure but one unverified step exits 2 — not 0',
  onlyUnknown.code === 2,
  `exit ${onlyUnknown.code}`,
);
check(
  '  and it still counts the unverified step separately',
  onlyUnknownSummary !== null && onlyUnknownSummary.fail === 0 && onlyUnknownSummary.unknown === 1,
  onlyUnknownSummary ? JSON.stringify(onlyUnknownSummary) : 'the gate printed no summary line',
);

const allPass = runGate([exitsWith(0, 'CASE_ZERO'), exitsWith(0, 'CASE_ZERO')], 'all_pass');
check(
  'a run where every step passes exits 0',
  allPass.code === 0,
  `exit ${allPass.code}`,
);

const odd = runGate([exitsWith(0, 'CASE_ZERO'), exitsWith(3, 'CASE_ODD')], 'odd');
const oddSummary = summary(odd.out);
check(
  'an exit code the gate does not know is a FAIL — the gate fails closed',
  oddSummary !== null && oddSummary.fail === 1 && oddSummary.unknown === 0,
  oddSummary ? JSON.stringify(oddSummary) : 'the gate printed no summary line',
);
check('  and the run exits 1', odd.code === 1, `exit ${odd.code}`);

// ---------------------------------------------------------------------------
// 2. the convention, on the shipped checks
// ---------------------------------------------------------------------------

console.log('\n== the convention, on the shipped checks ==');

///|
/// Run a script and return its exit code.
const runScript = (script, args, cwd) => {
  const r = spawnSync('node', [script, ...args], {
    cwd: cwd ?? root,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
};

// (a) a usage error: the check was invoked wrongly, so it cannot produce a
//     verdict about the tree.
const headings = runScript(join(root, 'scripts', 'qa', 'headings.mjs'), []);
check(
  'headings.mjs, invoked with nothing to check, exits 2 — no verdict',
  headings.code === 2,
  `exit ${headings.code}`,
);

// (b) the artefact under test is unusable: a README with no Verification
//     table, so there is nothing for the drift detector to compare.
const readmeCase = join(scratch, 'readme_case');
mkdirSync(readmeCase, { recursive: true });
writeFileSync(join(readmeCase, 'README.md'), '# a README with no Verification table\n', 'utf8');
const readme = runScript(join(root, 'scripts', 'qa', 'readme_table.mjs'), [], readmeCase);
check(
  'readme_table.mjs, given a README with no table to compare, exits 2 — no verdict',
  readme.code === 2,
  `exit ${readme.code}`,
);

// (c) nothing to compare: a repository with a version but no tag below it.
const taglessCase = join(scratch, 'tagless_case');
mkdirSync(taglessCase, { recursive: true });
writeFileSync(join(taglessCase, 'moon.mod'), 'name = "test/nothing"\n\nversion = "0.1.32"\n', 'utf8');
writeFileSync(join(taglessCase, 'README.md'), '# nothing here\n', 'utf8');
const init = spawnSync('git', ['init', '--quiet'], { cwd: taglessCase, encoding: 'utf8' });
if (init.status !== 0) {
  check('a tagless repository could be prepared for the check', false, init.stderr ?? init.stdout);
} else {
  const tagless = runScript(join(root, 'scripts', 'qa', 'release_interface.mjs'), [], taglessCase);
  check(
    'release_interface.mjs, with no tag to compare against, exits 2 — no verdict',
    tagless.code === 2,
    `exit ${tagless.code}`,
  );
}

// (d) END TO END: a real shipped check, in the state where it cannot
//     decide, must land in the gate's UNKNOWN bucket -- and the gate must
//     exit 2, not 1.
const endToEnd = runGate([exitsWith(0, 'CASE_ZERO'), 'node scripts/qa/headings.mjs'], 'end_to_end');
const endToEndSummary = summary(endToEnd.out);
check(
  'a shipped check that cannot decide lands in the UNKNOWN bucket',
  endToEndSummary !== null && endToEndSummary.unknown === 1 && endToEndSummary.fail === 0,
  endToEndSummary ? JSON.stringify(endToEndSummary) : 'the gate printed no summary line',
);
check(
  '  and the gate exits 2 — "could not verify", not "broken"',
  endToEnd.code === 2,
  `exit ${endToEnd.code}`,
);

// ---------------------------------------------------------------------------
// 3. the bucket is reachable, and this check is in the gate
// ---------------------------------------------------------------------------

console.log('\n== the shipped step list ==');

if (!existsSync(stepsFile)) {
  check('the shipped step list exists', false, stepsFile);
} else {
  const shipped = JSON.parse(readFileSync(stepsFile, 'utf8'));
  check('the shipped step list exists', true);
  check(
    'this check is itself a step of the gate',
    shipped.includes('node scripts/qa/gate_verdicts.mjs'),
  );

  // How many of the gate's own steps can report UNKNOWN?  If none can, the
  // bucket is dead code and the distinction above is theatre.
  const canBeUnknown = [];
  for (const step of shipped) {
    const m = /^node\s+(scripts[\/\\][^\s]+\.mjs)/.exec(step);
    if (!m) continue;
    const p = join(root, m[1].replace(/\\/g, '/'));
    if (!existsSync(p)) continue;
    if (/process\.exit\(2\)/.test(readFileSync(p, 'utf8'))) canBeUnknown.push(m[1]);
  }
  check(
    'the gate has steps that can report UNKNOWN — the bucket is not dead code',
    canBeUnknown.length > 0,
    `${canBeUnknown.length} step(s) can exit 2`,
  );
  console.log(`      ${canBeUnknown.join('\n      ')}`);
}

console.log('');
console.log(
  failures === 0
    ? `RESULT: PASS (${assertions} assertion(s), 0 failure(s))`
    : `RESULT: FAIL (${assertions} assertion(s), ${failures} failure(s))`,
);
process.exit(failures === 0 ? 0 : 1);
