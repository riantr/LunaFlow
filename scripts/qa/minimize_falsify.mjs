#!/usr/bin/env node
// FALSIFY THE COUNTEREXAMPLE MINIMISATION.
//
// A check that cannot fail proves nothing.  This one breaks the minimiser in
// the ways that matter, one at a time, and asserts that the test which PINS
// THE MINIMALITY goes RED.
//
// MUTATES THE SOURCE TREE.  This is a MANUAL, LOCAL tool -- it is NOT a gate
// step and it is deliberately NOT wired into CI.  It rewrites ONE tracked
// file, `src/app/minimize.mbt`, and restores it BYTE FOR BYTE after every
// case, proving the restore with SHA-256, so "the source came back" is
// measured rather than asserted.
//
// It refuses to run while THAT file has uncommitted work: that is the work a
// crash could lose.  The files it does not touch are none of its business.
//
// The cases:
//
//   F1  the walk stops at the FIRST input -- the counterexample is the first
//       product element whatever it is, and the minimality claim is gone
//   F2  the walk takes the LAST input that reproduces -- the walk no longer
//       stops at the first one, so the answer is a reproducing input that
//       is not the smallest
//   F3  the reproduction check is loosened to the file alone -- inputs that
//       do not reproduce the finding count as reproducing it, so the walk
//       stops before the real answer
//
// The point of this file is the SECOND half of every case: the REPORT-level
// check (`scripts/qa/counterexamples.mjs`) stays GREEN.  It cannot see the
// minimality -- it reads the artefacts, and every one of these mutations
// produces artefacts that are internally consistent.  The minimality is
// pinned by the UNIT TEST and by nothing else, and this file is what says
// so with a measurement instead of an assertion.
//
// `moon test` prints a failure as:
//
//   [riantr/LunaFlow] test src/app/minimize_wbtest.mbt:81
//   ("the minimiser returns an input that reproduces the finding") failed
//
// so the tests that broke are in `("...")` on a `failed` line.  The parser
// splits on /\r?\n/ because Windows writes CRLF and `.` does not match `\r`.
//
// Usage: node scripts/qa/minimize_falsify.mjs

import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const abs = `${root}/src/app/minimize.mbt`;

const sha = (b) => createHash('sha256').update(b).digest('hex');
const original = readFileSync(abs);
const before = sha(original);
const text = original.toString('utf8');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// --- refuse to run while the file this tool rewrites has uncommitted work ----
const dirty = execFileSync(
  'git',
  ['status', '--porcelain', '--untracked-files=no', '--', 'src/app/minimize.mbt'],
  { cwd: root, encoding: 'utf8' },
).trim();
if (dirty !== '') {
  console.error('REFUSED: src/app/minimize.mbt has uncommitted work, and this tool');
  console.error('rewrites that file. Commit it first.\n' + dirty);
  process.exit(2);
}

const CASES = [
  {
    id: 'F1',
    name: 'the walk stops at the first input',
    what: 'the first input of the product is taken whatever it is',
    find: 'if self.reproduces(g, trials[i], target) {',
    replace: 'if i == 0 {',
    mustBreak: 'no input before it in the analyser',
  },
  {
    id: 'F2',
    name: 'the walk takes the last reproducing input',
    what: 'the walk does not stop at the first input that reproduces',
    find:
      'if self.reproduces(g, trials[i], target) {\n      found = Some(trials[i])\n      tried = self.runs - before\n      break\n    }',
    replace:
      'if self.reproduces(g, trials[i], target) {\n      found = Some(trials[i])\n      tried = self.runs - before\n    }',
    mustBreak: 'no input before it in the analyser',
  },
  {
    id: 'F3',
    name: 'the reproduction check is loosened to the file alone',
    what: 'any finding in the same file counts as the finding',
    find: 'if same_site(f, target) {',
    replace: 'if f.file == target.file {',
    mustBreak: 'no input before it in the analyser',
  },
];

function runTests() {
  const r = spawnSync('moon', ['test', 'src/app', '--target', 'native'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

function runReportCheck() {
  const r = spawnSync('node', ['scripts/qa/counterexamples.mjs'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

/// The names of the tests that failed, taken from `("...")` on a `failed` line.
function failedTests(out) {
  const names = [];
  for (const line of out.split(/\r?\n/)) {
    if (!/failed/.test(line)) continue;
    const m = /\("(.*)"\)/.exec(line);
    if (m) names.push(m[1]);
  }
  return names;
}

function restore() {
  writeFileSync(abs, original);
  const now = sha(readFileSync(abs));
  if (now !== before) {
    console.error(`RESTORE FAILED: ${now} != ${before}`);
    process.exit(2);
  }
}

// The baseline: the unmutated tree is green, so a red result below is the
// mutation's doing and not the tree's.
const base = runTests();
check(
  'the minimiser tests pass BEFORE any mutation',
  base.code === 0,
  base.code === 0 ? 'the baseline is green' : `exit ${base.code}: ${failedTests(base.out).join(' | ')}`,
);
const baseReport = runReportCheck();
check(
  'the report-level counterexample check passes BEFORE any mutation',
  baseReport.code === 0,
  baseReport.code === 0 ? 'the baseline is green' : `exit ${baseReport.code}`,
);

for (const c of CASES) {
  restore();
  if (!text.includes(c.find)) {
    check(`${c.id} ${c.name}`, false, 'the anchor this case mutates is not in the source');
    continue;
  }
  writeFileSync(abs, text.replace(c.find, c.replace), 'utf8');

  const unit = runTests();
  const broke = failedTests(unit.out);
  const red = unit.code !== 0;
  check(
    `${c.id} ${c.name} — ${c.what}`,
    red,
    red ? 'the minimiser tests went red, as they must' : 'THE TESTS STILL PASS: this assertion is decoration',
  );
  const rightReason = broke.some((n) => n.includes(c.mustBreak));
  check(
    `${c.id} … and the test that broke is the one about it`,
    rightReason,
    rightReason ? `"${c.mustBreak}" broke` : `broke: ${broke.join(' | ') || '(none)'}`,
  );

  // And the REPORT-level check must NOT see it: the artefacts stay
  // internally consistent, and only the unit test knows the difference.
  const report = runReportCheck();
  check(
    `${c.id} … and the report-level check cannot see it`,
    report.code === 0,
    report.code === 0
      ? 'the report check stayed green: the minimality is pinned by the unit test alone'
      : `the report check went red (exit ${report.code})`,
  );
}

restore();
check(
  'the source came back byte for byte',
  sha(readFileSync(abs)) === before,
  sha(readFileSync(abs)).slice(0, 16),
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
