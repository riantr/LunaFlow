#!/usr/bin/env node
// FALSIFY THE RULE x DIMENSION MATRIX.
//
// A check that cannot fail proves nothing. This one breaks the matrix in the
// ways that matter, one at a time, and asserts that the checks below it go
// RED -- and that they go red in the check that is ABOUT the thing broken.
//
// MUTATES THE SOURCE TREE. This is a MANUAL, LOCAL tool -- it is NOT a gate
// step and it is deliberately NOT wired into CI. It rewrites ONE tracked
// file, `src/app/report.mbt`, and restores it BYTE FOR BYTE after every
// case, proving the restore with SHA-256, so "the source came back" is
// measured rather than asserted.
//
// It refuses to run while THAT file has uncommitted work: that is the work a
// crash could lose. The files it does not touch are none of its business.
//
// The cases:
//
//   F1  a row loses its total           -- the ` Total |` cell is dropped, so a
//       row no longer adds up to what it claims
//   F2  an empty cell stops reading `·` -- a cell with no findings prints 0,
//       so "this lens did not fire" stops being visually distinct
//   F3  the corroboration sentence goes -- the matrix still renders, but it
//       stops naming WHICH families two lenses found, which is the whole
//       reason the section exists
//   F4  the matrix counts ANOTHER set of findings -- the section is wired to
//       the taint sinks instead of the sink the findings tables fill
//   F5  the matrix is not rendered at all
//
// F4 and F5 are the cases the UNIT TESTS cannot catch: the tests call
// `rule_dimension_matrix` directly, so a matrix wired to the wrong sink
// still passes every one of them. `scripts/qa/dimension_matrix.mjs` reads
// the REPORT, so it sees the wiring -- and these two cases are what that
// check is FOR. The falsifier asserts that the unit tests stayed GREEN
// while the report-level check went red.
//
// `moon test` prints a failure as:
//
//   [riantr/LunaFlow] test src/app/report_wbtest.mbt:167
//   ("the dimension matrix: the rows and columns are the counts it claims") failed
//
// so the tests that broke are in `("...")` on a `failed` line. The parser
// splits on /\r?\n/ because Windows writes CRLF and `.` does not match `\r`.
//
// Usage: node scripts/qa/matrix_falsify.mjs

import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const abs = `${root}/src/app/report.mbt`;

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
  ['status', '--porcelain', '--untracked-files=no', '--', 'src/app/report.mbt'],
  { cwd: root, encoding: 'utf8' },
).trim();
if (dirty !== '') {
  console.error('REFUSED: src/app/report.mbt has uncommitted work, and this tool');
  console.error('rewrites that file. Commit it first.\n' + dirty);
  process.exit(2);
}

const CASES = [
  {
    id: 'F1',
    name: 'a row loses its total',
    what: 'the ` Total |` cell is dropped from every row',
    find: 'out.write_string(" " + family_totals[a].to_string() + " |\\n")',
    replace: 'out.write_string("\\n")',
    mustBreak: 'the rows and columns are the counts it claims',
    where: 'unit',
  },
  {
    id: 'F2',
    name: 'an empty cell stops reading as a dot',
    what: 'the zero cell prints 0 instead of `·`',
    find: '(if n == 0 { "·" } else { n.to_string() })',
    replace: 'n.to_string()',
    // Both of these assert the dot, so either one going red is the mutation
    // being caught; the first is the one that is ABOUT the dot.
    mustBreak: 'a lens that did not fire reads as a dot',
    alsoAcceptable: ['the rows and columns are the counts it claims'],
    where: 'unit',
  },
  {
    id: 'F3',
    name: 'the corroboration sentence goes',
    what: 'the list of multi-method families is replaced by an empty string',
    find: '      corroborated.join(", ") +',
    replace: '      "" +',
    mustBreak: 'it names the families two lenses corroborate',
    where: 'unit',
  },
  {
    id: 'F4',
    name: 'the matrix counts another set of findings',
    what: 'the section is wired to the taint sinks instead of the findings sink',
    find: 'out.write_string(rule_dimension_matrix(findings_out))',
    replace: 'out.write_string(rule_dimension_matrix(input.taint.sinks))',
    where: 'report',
  },
  {
    id: 'F5',
    name: 'the matrix is not rendered at all',
    what: 'the report no longer writes the section',
    find: 'out.write_string(rule_dimension_matrix(findings_out))',
    replace: 'out.write_string("")',
    where: 'report',
  },
];

function runTests() {
  const r = spawnSync('moon', ['test', 'src/app', '--target', 'native', '-f', 'the dimension matrix*'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

/// The gate step that reads the REPORT, so it sees the wiring.
function runReportCheck() {
  const r = spawnSync('node', ['scripts/qa/dimension_matrix.mjs'], {
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

/// The checks that failed in the report-level check.
function failedChecks(out) {
  const names = [];
  for (const line of out.split(/\r?\n/)) {
    if (!line.startsWith('FAIL')) continue;
    names.push(line);
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
  'the matrix tests pass BEFORE any mutation',
  base.code === 0,
  base.code === 0 ? 'the baseline is green' : `exit ${base.code}: ${failedTests(base.out).join(' | ')}`,
);
const baseReport = runReportCheck();
check(
  'the report-level matrix check passes BEFORE any mutation',
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

  if (c.where === 'unit') {
    const r = runTests();
    const broke = failedTests(r.out);
    const red = r.code !== 0;
    check(
      `${c.id} ${c.name} — ${c.what}`,
      red,
      red ? 'the matrix tests went red, as they must' : 'THE TESTS STILL PASS: this assertion is decoration',
    );
    // It must break the test that is ABOUT this defect -- not merely some test.
    const acceptable = [c.mustBreak, ...(c.alsoAcceptable ?? [])];
    const rightReason = broke.some((n) => acceptable.some((want) => n.includes(want)));
    check(
      `${c.id} … and the test that broke is the one about it`,
      rightReason,
      rightReason
        ? `"${c.mustBreak}" broke`
        : `broke: ${broke.join(' | ') || '(none)'} — wanted "${c.mustBreak}"`,
    );
    continue;
  }

  // The REPORT-level cases: the unit tests call the function directly, so
  // they CANNOT see the wiring. They have to stay green, and the check that
  // reads the report has to go red.
  const unit = runTests();
  const report = runReportCheck();
  const red = report.code !== 0;
  check(
    `${c.id} ${c.name} — ${c.what}`,
    red,
    red
      ? 'the report-level check went red, as it must'
      : 'THE CHECK STILL PASSES: this assertion is decoration',
  );
  const broke = failedChecks(report.out);
  const rightReason = broke.some((l) => l.includes('the live self-scan'));
  check(
    `${c.id} … and it broke the LIVE report check, and the unit tests stayed green`,
    rightReason && unit.code === 0,
    rightReason
      ? unit.code === 0
        ? `"the live self-scan" broke and the unit tests stayed green`
        : `the unit tests went red too: ${failedTests(unit.out).join(' | ')}`
      : `broke: ${broke.join(' | ') || '(none)'} — wanted "the live self-scan"`,
  );
}

restore();
check(
  'the source was restored byte for byte',
  sha(readFileSync(abs)) === before,
  before.slice(0, 16),
);

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
