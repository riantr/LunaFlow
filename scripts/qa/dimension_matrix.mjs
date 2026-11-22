#!/usr/bin/env node
// THE DIMENSION MATRIX, CHECKED AGAINST WHAT IT CROSSES.
//
// §5.11 of a report crosses the finding FAMILIES with the METHOD that found
// each one.  It is the one table in the report that is not a list of
// findings: its rows are families and its cells are COUNTS.  So the numbers
// in it are a CLAIM -- that the matrix counts the findings the report
// shows -- and a claim has to be measured.
//
// What is checked, on every report in front of us:
//
//   * a row's cells add up to the row's own total, and a column's cells add
//     up to the column's own total
//   * the totals add up to the grand total, and the rows do too
//   * every family the matrix lists is a family the findings tables show,
//     and its count IS the count the tables show for it
//   * the grand total is the number of findings the tables were given --
//     including the rows a truncated table left out, which the report states
//   * the closing sentence names EXACTLY the families more than one method
//     found, and says so when there are none
//
// It runs over the COMMITTED ARTEFACTS and over a LIVE run of the analyser.
// The artefacts are the published reports, so a matrix that is wrong there is
// wrong in public; the live run is what proves the wiring -- that the matrix
// reads the same sink the tables fill -- on the tree as it stands now, and
// not only on the bytes that were published.
//
// The numbers it compares are TOOLCHAIN-INDEPENDENT: the matrix is
// compared with the tables of the SAME report, so a newer toolchain that
// finds more findings moves both sides together.  The numbers the README
// publishes about the matrix are measured by `scripts/qa/readme_table.mjs`,
// against a live self-scan, for the same reason.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';
import {
  cellKey,
  corroboratedFamilies,
  findingCounts,
  namedFamilies,
  parseMatrix,
} from './report_matrix.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ------------------------------------------------------- one report, checked

/// The invariants of ONE report.  The label names the report, so a failure
/// says which report disagreed.
function checkReport(label, text) {
  const matrix = parseMatrix(text);
  check(`${label}: the report has the dimension matrix`, matrix !== null);
  if (!matrix) return null;

  check(
    `${label}: the matrix crosses families with methods`,
    matrix.methods.length > 0 && matrix.rows.length > 0,
    `${matrix.rows.length} families over ${matrix.methods.length} method(s)`,
  );
  check(
    `${label}: every cell in the matrix is a count or a dot`,
    matrix.broken.length === 0,
    matrix.broken.join('; '),
  );

  // The table checks ITSELF: a row adds up to its own total, a column adds
  // up to its own total, and the totals add up to the grand total.
  const badRows = matrix.rows.filter(
    (r) => r.cells.reduce((a, b) => a + b, 0) !== r.total,
  );
  check(
    `${label}: every row adds up to its own total`,
    badRows.length === 0,
    badRows.map((r) => `${r.family}: ${r.cells.join('+')} vs ${r.total}`).join('; '),
  );

  const badColumns = [];
  for (let c = 0; c < matrix.methods.length; c += 1) {
    const sum = matrix.rows.reduce((a, r) => a + r.cells[c], 0);
    if (!matrix.totals || sum !== matrix.totals[c]) {
      badColumns.push(`${matrix.methods[c]}: ${sum} vs ${matrix.totals?.[c]}`);
    }
  }
  check(
    `${label}: every column adds up to its own total`,
    badColumns.length === 0,
    badColumns.join('; '),
  );

  const sumOfTotals = (matrix.totals ?? []).reduce((a, b) => a + b, 0);
  check(
    `${label}: the totals add up to the grand total`,
    sumOfTotals === matrix.grand,
    `${sumOfTotals} vs ${matrix.grand}`,
  );
  const sumOfRows = matrix.rows.reduce((a, r) => a + r.total, 0);
  check(
    `${label}: the rows add up to the grand total`,
    sumOfRows === matrix.grand,
    `${sumOfRows} vs ${matrix.grand}`,
  );

  // And the matrix has to count the findings the report shows.
  const found = findingCounts(text);
  check(`${label}: the findings tables could be read`, found.error === null, found.error ?? '');
  const missing = [...found.counts.keys()].filter(
    (f) => !matrix.rows.some((r) => r.family === f),
  );
  check(
    `${label}: the matrix lists every family the findings tables show`,
    missing.length === 0,
    missing.join(', '),
  );
  const extra = matrix.rows.filter((r) => !found.counts.has(r.family));
  check(
    `${label}: every family the matrix lists has findings`,
    extra.length === 0,
    extra.map((r) => r.family).join(', '),
  );
  const wrong = matrix.rows.filter((r) => found.counts.get(r.family) !== r.total);
  check(
    `${label}: every family's count is the count the findings tables show`,
    wrong.length === 0,
    wrong.map((r) => `${r.family}: ${r.total} vs ${found.counts.get(r.family)}`).join('; '),
  );
  check(
    `${label}: the grand total is the number of findings the tables were given`,
    matrix.grand === found.total,
    `${matrix.grand} vs ${found.total} over ${found.tables} table(s)`,
  );

  // And every CELL: the count of the findings of that family that that
  // method found.  When no table was truncated the cross-tabulation is
  // complete, so the cells are compared exactly; when one was, the rows it
  // left out are unknown, so a cell may only be LARGER than what is shown.
  const cellProblems = [];
  for (const row of matrix.rows) {
    for (let c = 0; c < matrix.methods.length; c += 1) {
      const shown = found.cells.get(cellKey(row.family, matrix.methods[c])) ?? 0;
      const cell = row.cells[c];
      if (found.truncated ? cell < shown : cell !== shown) {
        cellProblems.push(`${row.family}/${matrix.methods[c]}: ${cell} vs ${shown}`);
      }
    }
  }
  check(
    found.truncated
      ? `${label}: every cell is at least the findings of that family by that method`
      : `${label}: every cell is the count of findings of that family by that method`,
    cellProblems.length === 0,
    cellProblems.slice(0, 6).join('; '),
  );

  // The closing sentence: it names the families that two lenses found, and
  // it says so in words when there are none.
  const corroborated = corroboratedFamilies(matrix);
  if (corroborated.length === 0) {
    check(
      `${label}: the matrix says that no family is corroborated`,
      matrix.prose.includes('found by exactly ONE method'),
    );
  } else {
    const named = namedFamilies(matrix.prose);
    const want = corroborated.map((c) => c.family).sort();
    const got = (named ?? []).slice().sort();
    check(
      `${label}: the matrix names exactly the families two lenses found`,
      named !== null &&
        got.length === want.length &&
        got.every((f, i) => f === want[i]),
      `named ${JSON.stringify(got)} vs found ${JSON.stringify(want)}`,
    );
  }
  return matrix;
}

// ------------------------------------------------- the COMMITTED artefacts

const reportsDir = join(ROOT, 'reports');
const artefacts = existsSync(reportsDir)
  ? readdirSync(reportsDir)
      .filter((f) => f.endsWith('.md'))
      .sort()
  : [];
if (artefacts.length === 0) {
  console.error(`no committed report artefact in ${reportsDir}`);
  process.exit(2);
}
for (const name of artefacts) {
  const text = readFileSync(join(reportsDir, name), 'utf8');
  checkReport(`artefact ${name}`, text);
}

// ---------------------------------------------------- the LIVE self-scan
//
// The artefacts are the published reports, so a matrix that is wrong in them
// is wrong in public.  The LIVE run is the other half: the artefacts were
// published once, and the wiring can be broken after that.  So the analyser
// is run over this tree, and the matrix of the report it writes is checked
// the same way.
//
// The binary is BUILT here, not assumed: a binary left over from an earlier
// build measures the product as it WAS.
const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
  cwd: ROOT,
  encoding: 'utf8',
  timeout: 900000,
  maxBuffer: 32 * 1024 * 1024,
  shell: true,
});
if (build.status !== 0) {
  console.error('the CLI build failed, so there is nothing to measure:');
  console.error((build.stderr ?? '') + (build.stdout ?? ''));
  process.exit(2);
}

const out = join(ROOT, '_build', 'qa', 'dimension_matrix');
mkdirSync(out, { recursive: true });
const run = spawnSync(
  requireCli(ROOT),
  ['analyze', '--dir', '.', '--out', out, '--funnel'],
  { cwd: ROOT, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
);
if (run.status !== 0) {
  console.error(`the self-scan did not run: exit ${run.status}`);
  console.error((run.stderr ?? '') + (run.stdout ?? ''));
  process.exit(2);
}
const liveReport = readdirSync(out)
  .filter((f) => f.endsWith('.md'))
  .sort()
  .pop();
if (!liveReport) {
  console.error(`the self-scan wrote no report into ${out}`);
  process.exit(2);
}
checkReport('the live self-scan', readFileSync(join(out, liveReport), 'utf8'));

console.log(
  `\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks - failures} passed, ${failures} failure(s))`,
);
process.exit(failures === 0 ? 0 : 1);
