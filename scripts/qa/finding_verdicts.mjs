#!/usr/bin/env node
// THE VERDICT: a FAIL is not an UNKNOWN, AND AN UNDECIDED CLAIM IS NOT AN
// ABSENT ONE.
//
// The gate learned to read an exit code (`gate_verdicts.mjs`).  This is the
// same distinction ONE LEVEL DOWN, inside the analyser itself: a CLAIM the
// analyser could not decide must not look like a claim it decided and found
// clean.
//
// The check runs the ANALYSER -- the product, over a real module on disk --
// and looks at what it says:
//
//   1. THE VOCABULARY   every finding carries a verdict, and the sidecar
//                       says which one.
//   2. THE PRODUCER     a claim the analyser could not decide is reported as
//                       UNDECIDED, with the reason -- not silently absent.
//   3. THE POLICY       an undecided claim carries the severity the POLICY
//                       gives it, and the policy is fail-closed.
//   4. THE REPORTING    the report has a Verdict column and says how many
//                       claims could not be decided.
//
// The producer is the analyser's OWN step budget: a loop that runs past it
// means the rest of the function was never analysed, so nothing about it was
// decided.  That is the smallest honest "we could not tell" there is, and it
// is reachable from the command line -- the interpreter's budget is 2,000
// steps.
//
// The binary under test is BUILT here, not assumed: a binary left over from
// an earlier build measures the product as it WAS.
//
// Usage: node scripts/qa/finding_verdicts.mjs [--no-build] [--falsify]
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
const work = join(root, '_build', 'qa', 'finding_verdicts');
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
// THE MODULE.
//
// A loop the interpreter cannot finish.  The interpreter's budget is 2,000
// steps and one `while` loop is capped at 64 iterations, so the loops are
// NESTED: 64 x 64 iterations is far past the budget, and the analyser gives
// up on the function.  What it gives up on is a claim it could NOT DECIDE.
//
// The module also contains an ordinary claim the analyser DOES decide, so
// the two have to be distinguishable in the output.
// ---------------------------------------------------------------------------
const MODULE = `///|
/// A loop the interpreter cannot finish: the budget is 2,000 steps, and this
/// one runs for 64 x 64.
pub fn spin() -> Int32 {
  let mut total = 0
  let mut i = 0
  while i < 100 {
    let mut j = 0
    while j < 100 {
      total = total + 1
      j = j + 1
    }
    i = i + 1
  }
  total
}

///|
/// An ordinary claim the analyser DOES decide: a tainted value may reach an
/// array index.
pub fn lookup(index : Int32) -> Int32 {
  let xs = [1, 2, 3]
  xs[index]
}
`;

// ---------------------------------------------------------------------------
// 1. build the analyser and run it over the module
// ---------------------------------------------------------------------------
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });
writeFileSync(join(work, 'lib.mbt'), MODULE, 'utf8');
writeFileSync(
  join(work, 'moon.mod'),
  'name = "demo/verdicts"\n\nversion = "0.0.1"\n',
  'utf8',
);

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

const out = join(work, 'out');
const run = spawnSync(
  resolveCli(root),
  ['analyze', '--dir', work, '--out', out, '--funnel'],
  { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
);
if (run.status !== 0) {
  console.error(`the analyser exited ${run.status}`);
  console.error(`${run.stdout ?? ''}${run.stderr ?? ''}`);
  process.exit(2);
}

const findingsFile = readdirSync(out).find((f) => f.endsWith('_findings.jsonl'));
if (!findingsFile) {
  console.error('the analyser wrote no findings sidecar');
  process.exit(2);
}
const reportFile = readdirSync(out).find((f) => f.endsWith('.md'));
if (!reportFile) {
  console.error('the analyser wrote no report');
  process.exit(2);
}

const findings = readFileSync(join(out, findingsFile), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => JSON.parse(l));
const report = readFileSync(join(out, reportFile), 'utf8');

console.log(`the analyser over the module produced ${findings.length} finding(s)\n`);

// ---------------------------------------------------------------------------
// 2. the vocabulary
// ---------------------------------------------------------------------------
check(
  'every finding in the sidecar carries a verdict',
  findings.length > 0 && findings.every((f) => f.verdict === 'certain' || f.verdict === 'unknown'),
  `${findings.length} finding(s)`,
);

const undecided = findings.filter((f) => f.verdict === 'unknown');
const decided = findings.filter((f) => f.verdict === 'certain');

check(
  'the analyser produced BOTH kinds -- a decided claim and an undecided one',
  decided.length > 0 && undecided.length > 0,
  `${decided.length} decided, ${undecided.length} undecided`,
);

// ---------------------------------------------------------------------------
// 3. the producer: the budget claim is UNDECIDED, and says why
// ---------------------------------------------------------------------------
const budget = undecided.filter((f) => f.rule === 'BUDGET-EXCEEDED');
check(
  'the claim the analyser could not decide is the BUDGET one',
  budget.length > 0,
  `${budget.length} undecided finding(s)`,
);
check(
  '  and it says WHY it could not decide',
  budget.length > 0 &&
    budget.every((f) => /not (analysed|executed)/.test(f.message)),
  budget.length > 0 ? budget[0].message : '',
);
check(
  '  and it is NOT a decided claim -- the two are distinguishable',
  budget.length > 0 && budget.every((f) => f.verdict !== 'certain'),
);

// ---------------------------------------------------------------------------
// 4. the policy: the severity of an undecided claim is the POLICY's
// ---------------------------------------------------------------------------
check(
  'an undecided claim carries the severity the policy gives it',
  budget.length > 0 && budget.every((f) => f.severity === 'warning'),
  budget.length > 0 ? budget[0].severity : '',
);
check(
  '  and a decided claim of a safety family still carries its own severity',
  decided.length > 0 && decided.every((f) => f.severity === 'error' || f.severity === 'warning' || f.severity === 'info'),
);

// ---------------------------------------------------------------------------
// 5. the reporting: the column, and the count
// ---------------------------------------------------------------------------
check(
  'the findings table has a Verdict column',
  report.includes('| Rule | Severity | Verdict | Function | Location | Message | Method | Confidence |'),
);
check(
  '  and an undecided row says so in the table',
  /\| BUDGET-EXCEEDED \| warning \| unknown \|/.test(report),
);
check(
  '  and a decided row says so too',
  /\| [A-Z-]+ \| (error|warning|info) \| certain \|/.test(report),
);
check(
  'the report has a section for the claims that could not be decided',
  report.includes('### 5.10 Claims that could not be decided'),
);
check(
  '  and it says how many there are',
  new RegExp(`${undecided.length} claim\\(s\\) could not be decided`).test(report),
  `${undecided.length} undecided`,
);
check(
  '  and it does not list a DECIDED claim there',
  report.includes('### 5.10 Claims that could not be decided') &&
    !report
      .split('### 5.10 Claims that could not be decided')[1]
      .split('## 6.')[0]
      .includes('certain |'),
);

// ---------------------------------------------------------------------------
// 6. THE ROW SHAPE ITSELF.
//
// The findings table's columns are an INTERFACE: the other checks match a
// row by its columns -- `FFI-LENGTH-MISMATCH | warning | wrong_length` -- and
// a NEGATIVE check over that shape does not fail when a column is added.  It
// stops MATCHING, so it passes for the wrong reason: the check is vacuous
// and says nothing about the tree.
//
// That happened when the Verdict column was added: four negative checks over
// the FFI and memory rows silently stopped matching, and only the one
// POSITIVE check over a row went red.  So the shape is checked here, once,
// for every row of every findings table in the report.
// ---------------------------------------------------------------------------
const HEADER = '| Rule | Severity | Verdict | Function | Location | Message | Method | Confidence |';
function rowCells(line) {
  return line.split('|').length - 2;
}
const lines = report.split(/\r?\n/);
let tables = 0;
const offenders = [];
for (let i = 0; i < lines.length; i += 1) {
  if (lines[i].trim() !== HEADER.trim()) continue;
  tables += 1;
  const want = rowCells(HEADER);
  for (let j = i + 1; j < lines.length; j += 1) {
    if (!lines[j].startsWith('|')) break;
    const got = rowCells(lines[j]);
    if (got !== want) offenders.push(lines[j].slice(0, 70));
  }
}
check(
  'every findings table has the header it declares',
  tables > 0,
  `${tables} table(s)`,
);
check(
  '  and every row in it has that header\'s number of cells',
  offenders.length === 0,
  offenders.length === 0 ? '' : `${offenders.length} row(s): ${offenders[0]}`,
);

// ---------------------------------------------------------------------------
// 7. the falsification
// ---------------------------------------------------------------------------
if (falsify) {
  // The expectation that is inverted on purpose: the analyser DID decide
  // everything.  If the check cannot fail, it is not a check.
  check(
    'FALSIFIED: every finding is a decided claim',
    undecided.length === 0,
    `${undecided.length} undecided finding(s) -- the falsification must fail`,
  );
}

console.log('');
console.log(
  failures === 0
    ? `RESULT: PASS (${checks} check(s), 0 failure(s))`
    : `RESULT: FAIL (${checks} check(s), ${failures} failure(s))`,
);
process.exit(failures === 0 ? 0 : 1);
