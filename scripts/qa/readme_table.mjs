#!/usr/bin/env node
// THE README'S LIVE TABLE, CHECKED AGAINST THE TREE.
//
// The README publishes a measured-performance table: four rows, each with the
// counts a run produced. Three of the rows are the committed artefacts and
// the fourth is the analyser over its OWN source. Every cell in those rows is
// a MEASUREMENT, and a measurement goes stale the moment the tree moves.
//
// It did, twice, in one session:
//
//   * the D1+D2 commit left the PREVIOUS RELEASE's numbers in the performance
//     row -- the tree at 7e35063 measures 53 files, 6,579 statements and 59
//     L2 findings (with the analyser built from that tree), where the row
//     still read 51 / 6,388 / 46, so the commit's own effect was missing
//     from the table that reports it;
//   * the fourth-defect repair left the PREVIOUS COMMIT's numbers in that row
//     -- 6,776 statements where the tree read 6,780 -- and it also moved the
//     TEST COUNT from 262 to 264, which three rows of the gate table and the
//     newest-toolchain paragraph still published as 262.
//
// Nothing noticed, because every gate step that touched the README checked
// its HEADINGS or its version references, and no step compared its NUMBERS
// with anything.
//
// This check closes that. It MEASURES and compares:
//
//   * the three committed-artefact rows against `reports/*_summary.json`;
//   * the self-scan row against a LIVE run of the analyser over this tree;
//   * the README's prose sentence, which repeats the same numbers;
//   * the phase document's self-scan table, which repeats them a third time;
//   * the gate table's TEST COUNT against a LIVE run of the tests, and the
//     two other targets' cells against the native one.
//
// The TIME column is NOT compared: the wall clock is the machine's, and the
// same tree read 672 ms and 710 ms for the self-scan in one session. The
// counts are the deterministic measure, and those are what is checked.
//
// Usage: node scripts/qa/readme_table.mjs [--no-selfscan]
//
// `--no-selfscan` SKIPS the live self-scan and checks only what is OFFLINE:
// the committed-artefact rows against their summaries, the two places that
// repeat the self-scan numbers against the README's own row, and the three
// test cells against each other. That is the mode for the CI runner, which
// installs the NEWEST toolchain -- a count the newest parser reads
// differently from the one that measured the numbers would fail there for a
// reason that has nothing to do with this tree. The live measurement is the
// LOCAL release-prep check, where the toolchain is the one that produced the
// numbers.
//
// The TEST COUNT is measured in BOTH modes: the number of tests in src/app is
// this repository's own, and it does not depend on the toolchain.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = resolve(process.cwd());
const readmePath = join(root, 'README.md');
const phasePath = join(root, 'docs', 'qa', 'IFDS_PHASE1.md');
const skipSelfScan = process.argv.includes('--no-selfscan');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

const num = (cell) => {
  const t = cell.trim().replace(/,/g, '');
  return /^\d+$/.test(t) ? Number(t) : null;
};

///|
/// The live table, by the HEADER's column names.
function liveTable(md) {
  const start = md.indexOf('## Verification');
  if (start < 0) return null;
  const end = md.indexOf('\n## ', start + 5);
  const section = md.slice(start, end < 0 ? undefined : end);
  const lines = section.split('\n');
  const h = lines.findIndex((l) => l.startsWith('| Module | Files |'));
  if (h < 0) return null;
  const header = lines[h]
    .split('|')
    .slice(1, -1)
    .map((s) => s.trim());
  const rows = [];
  for (const line of lines.slice(h + 2)) {
    if (!line.startsWith('| `')) break;
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((s) => s.trim());
    rows.push({ key: cells[0], cells });
  }
  return { header, rows };
}

///|
/// The gate table, by the HEADER's column names.
function gateTable(md) {
  const start = md.indexOf('## Verification');
  if (start < 0) return null;
  const end = md.indexOf('\n## ', start + 5);
  const section = md.slice(start, end < 0 ? undefined : end);
  const lines = section.split('\n');
  const h = lines.findIndex((l) => l.startsWith('| Command | Result |'));
  if (h < 0) return null;
  const rows = [];
  for (const line of lines.slice(h + 2)) {
    if (!line.startsWith('| `')) break;
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((s) => s.trim());
    rows.push({ cmd: cells[0], result: cells[1] ?? '' });
  }
  return rows;
}

///|
/// The summary file that goes with a table row.
function summaryFor(key) {
  if (key.includes('doubleML'))
    return 'reports/riantr_moonbit_doubleML@latest_0.164.64_summary.json';
  if (key.includes('static_analysis'))
    return 'reports/riantr_moonbit_static_analysis@latest_0.5.0_summary.json';
  if (key.includes('vuln_demo')) return 'reports/local_module_0.0.0_summary.json';
  return null;
}

const md = readFileSync(readmePath, 'utf8');
const table = liveTable(md);
if (!table) {
  console.error('the live measured-performance table was not found under "## Verification"');
  process.exit(2);
}

// The column a summary field belongs to.
const COLUMN = {
  Files: 'files',
  Statements: 'statements',
  'L1 events': 'trace_events',
  'L2 findings': 'abstract_findings',
  Dead: 'dead_code',
  'Taint sinks': 'taint_sinks',
};

console.log(`README live table: ${table.header.join(' | ')}\n`);

// --- the three committed artefacts -----------------------------------------
for (const row of table.rows) {
  const file = summaryFor(row.key);
  if (!file) continue;
  if (!existsSync(join(root, file))) {
    check(`${row.key}: summary exists`, false, file);
    continue;
  }
  const s = JSON.parse(readFileSync(join(root, file), 'utf8'));
  const diffs = [];
  table.header.forEach((h, i) => {
    const f = COLUMN[h];
    if (!f) return; // the L3 VCs and the Time are not summary fields
    const cell = num(row.cells[i] ?? '');
    if (cell === null) return;
    if (cell !== s[f]) diffs.push(`${h}: README ${cell} vs ${file} ${s[f]}`);
  });
  check(
    `${row.key}: every count matches ${file.split('/').pop()}`,
    diffs.length === 0,
    diffs.join('; '),
  );
}

// --- the self-scan row: a LIVE run ------------------------------------------
const selfRow = table.rows.find((r) => r.key.includes('--dir .'));
if (!selfRow) {
  check('the self-scan row is present in the live table', false);
} else {
  // The numbers the README's own row states. The prose and the phase
  // document must repeat THESE, and -- unless the live run is skipped --
  // they must also be what the tree measures.
  const rowCounts = {};
  table.header.forEach((h, i) => {
    const f = COLUMN[h];
    if (!f) return;
    const cell = num(selfRow.cells[i] ?? '');
    if (cell !== null) rowCounts[f] = cell;
  });
  const want = [
    rowCounts.files,
    rowCounts.statements,
    rowCounts.trace_events,
    rowCounts.abstract_findings,
    rowCounts.dead_code,
    rowCounts.taint_sinks,
  ];

  // --- the prose that repeats the same numbers ----------------------------
  const prose = /On this tree the row reads \*\*(\d+) files, ([\d,]+) statements, ([\d,]+) events, (\d+) L2\s+findings, (\d+) dead and (\d+) taint sinks\*\*/.exec(
    md,
  );
  if (!prose) {
    check('the README repeats the self-scan numbers in prose', false, 'the sentence was not found');
  } else {
    const got = [prose[1], prose[2], prose[3], prose[4], prose[5], prose[6]].map((x) =>
      Number(x.replace(/,/g, '')),
    );
    const same = want.every((w, i) => w === got[i]);
    check(
      'the README prose repeats the self-scan row correctly',
      same,
      same ? '' : `prose ${JSON.stringify(got)} vs the row ${JSON.stringify(want)}`,
    );
  }

  // --- the phase document's table, which repeats them a third time ---------
  if (existsSync(phasePath)) {
    const phase = readFileSync(phasePath, 'utf8');
    const row = phase.match(/^\| the repaired tree \| (\d+) \| ([\d,]+) \| ([\d,]+) \| \*\*(\d+)\*\* \| (\d+) \|$/m);
    if (!row) {
      check('the phase document has the repaired-tree row', false);
    } else {
      // The phase table has FIVE columns (it does not carry the dead-code
      // count), so it is compared with the matching five.
      const want5 = [
        rowCounts.files,
        rowCounts.statements,
        rowCounts.trace_events,
        rowCounts.abstract_findings,
        rowCounts.taint_sinks,
      ];
      const got = [row[1], row[2], row[3], row[4], row[5]].map((x) => Number(x.replace(/,/g, '')));
      const same = want5.every((w, i) => w === got[i]);
      check(
        'the phase document table matches the README row',
        same,
        same ? '' : `doc ${JSON.stringify(got)} vs the row ${JSON.stringify(want5)}`,
      );
    }
  }

  if (skipSelfScan) {
    console.log('  (the live self-scan was skipped: --no-selfscan)');
  } else {
    // The binary under test is BUILT here, not assumed: a binary left over
    // from an earlier build measures the product as it WAS.
    const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
      cwd: root,
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
    const out = join(root, '_build', 'qa', 'readme_table');
    mkdirSync(out, { recursive: true });
    const run = spawnSync(
      resolveCli(root),
      ['analyze', '--dir', '.', '--out', out, '--funnel'],
      { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
    );
    if (run.status !== 0) {
      check('the self-scan ran', false, `exit ${run.status}`);
    } else {
      const file = readdirSync(out)
        .filter((f) => f.endsWith('_summary.json'))
        .sort()
        .pop();
      const s = JSON.parse(readFileSync(join(out, file), 'utf8'));
      const diffs = [];
      table.header.forEach((h, i) => {
        const f = COLUMN[h];
        if (!f) return;
        const cell = num(selfRow.cells[i] ?? '');
        if (cell === null) return;
        if (cell !== s[f]) diffs.push(`${h}: README ${cell} vs the tree ${s[f]}`);
      });
      check(
        'the self-scan row: every count matches a LIVE run over this tree',
        diffs.length === 0,
        diffs.join('; '),
      );
    }
  }
}

// --- the gate table: the TEST COUNT ------------------------------------------
// Every new assertion is a new test, so the test count is the cell that moves
// when the tree moves -- and it moved twice in this session (262 -> 264), in
// three rows of the gate table and once more in the newest-toolchain
// paragraph. It is measured here, and the two other targets' cells are
// compared with the native one, so a cell that drifts apart from the others is
// caught even when no run was made for that target.
//
// The test count is this repository's own, so it does NOT depend on the
// toolchain: unlike the self-scan, it is measured in the offline mode too.
const gate = gateTable(md);
if (!gate) {
  check('the gate table is present in the Verification section', false);
} else {
  const cells = {};
  for (const target of ['native', 'wasm', 'js']) {
    const row = gate.find((r) => r.cmd.includes(`moon test src/app --target ${target}`));
    const m = row ? /(\d+)\s+passed/.exec(row.result) : null;
    cells[target] = m ? Number(m[1]) : null;
  }
  if (cells.native === null || cells.wasm === null || cells.js === null) {
    check('the gate table publishes a test count for each target', false, JSON.stringify(cells));
  } else {
    check(
      'the wasm test cell publishes the same count as the native one',
      cells.wasm === cells.native,
      `${cells.wasm} vs ${cells.native}`,
    );
    check(
      'the js test cell publishes the same count as the native one',
      cells.js === cells.native,
      `${cells.js} vs ${cells.native}`,
    );
    const run = spawnSync('moon', ['test', 'src/app', '--target', 'native'], {
      cwd: root,
      encoding: 'utf8',
      timeout: 1800000,
      maxBuffer: 64 * 1024 * 1024,
      shell: true,
    });
    const text = (run.stdout ?? '') + (run.stderr ?? '');
    const m = /Total tests:\s*(\d+)/.exec(text);
    if (run.status !== 0 || !m) {
      check('the test run behind the README\'s test count succeeded', false, `exit ${run.status}`);
    } else {
      check(
        'the gate table\'s test count matches a LIVE run of the tests',
        Number(m[1]) === cells.native,
        `README ${cells.native} vs the tree ${m[1]}`,
      );
    }
  }
}

// --- the TIME column is present, but NOT compared ---------------------------
for (const row of table.rows) {
  const i = table.header.indexOf('Time');
  if (i < 0) continue;
  const cell = (row.cells[i] ?? '').trim();
  check(`${row.key}: the Time cell states a time`, /\d/.test(cell), cell);
  break;
}

console.log('');
console.log(
  failures === 0
    ? `README live table and gate table: all ${checks} checks match the tree.`
    : `README live table and gate table: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
