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
// Usage: node scripts/qa/readme_table.mjs [--no-selfscan] [--falsify]
//
// `--no-selfscan` SKIPS the live self-scan and checks only what is OFFLINE:
// the committed-artefact rows against their summaries, the two places that
// repeat the self-scan numbers against the README's own row, the committed
// artefact's OWN totals against the prose that publishes them, and the three
// test cells against each other. That is the mode for the CI runner, which
// installs the NEWEST toolchain -- a count the newest parser reads
// differently from the one that measured the numbers would fail there for a
// reason that has nothing to do with this tree. The live measurement is the
// LOCAL release-prep check, where the toolchain is the one that produced the
// numbers.
//
// `--falsify` INVERTS the artefact-total expectations on purpose: every
// measured number is nudged by one, so every one of those claims has to fail.
// A claim that still passes is vacuous -- it is not really compared with the
// artefact -- and the check reports that as a failure. The mode exits 0 when
// the inversion WAS caught, so it can be a gate step.
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
// `--falsify` INVERTS the artefact-total expectations on purpose, so every one
// of them has to fail. A claim that still passes is vacuous -- it is not
// really compared with the artefact -- and the check reports that as a
// failure. The convention is `scripts/qa/size_taint.mjs --falsify`: the mode
// exits 0 when the inversion WAS caught.
const falsify = process.argv.includes('--falsify');

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
    return 'reports/riantr_moonbit_static_analysis@latest_0.5.4_summary.json';
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

// --- the committed artefact's OWN numbers, measured -------------------------
//
// The README publishes four MEASUREMENTS of the committed doubleML artefact
// outside the live table: the L2 table's total (the marker row), the sidecar's
// row count, the size of the family that could not fire, and the share of the
// L2 table's findings that sit in test files. `docs/design.md` and
// `docs/qa/LOOP_ACCEPTANCE.md` repeat them.
//
// They DRIFTED once already. Phase 2 regenerated the doubleML artefact -- the
// repair removed twenty claims from it -- and the README's "What changed in
// 0.1.30" section still quoted the PREVIOUS artefact's totals (2,535 and
// 3,524) while the artefact said 2,515 and 3,504. Nothing caught it: this
// check compared the live TABLE with the summaries, and the prose that repeats
// the artefact's own totals was never compared with anything.
//
// So they are measured HERE, from the artefact itself, and the prose is
// compared with the measurement. The check reads the artefact; it does not
// carry the numbers.
const artefactBase = 'reports/riantr_moonbit_doubleML@latest_0.164.64';
const artefactMdPath = join(root, artefactBase + '.md');
const artefactJsonlPath = join(root, artefactBase + '_findings.jsonl');
if (!existsSync(artefactMdPath) || !existsSync(artefactJsonlPath)) {
  check('the committed doubleML artefact is present', false, artefactBase);
} else {
  const artefactMd = readFileSync(artefactMdPath, 'utf8');
  const artefactRows = readFileSync(artefactJsonlPath, 'utf8')
    .trim()
    .split('\n')
    .filter((l) => l.trim() !== '')
    .map((l) => JSON.parse(l));

  // 5.2's table total: the marker row the README quotes verbatim.
  const marker = /truncated at 300 of (\d+) rows/.exec(artefactMd);
  const tableTotal = marker ? Number(marker[1]) : null;

  // the sidecar: one JSON object per finding.
  const sidecarRows = artefactRows.length;

  // 5.2 is the L2 ABSTRACT table; the sidecar also holds the L2-EVA rows
  // (5.3), the taint sinks (5.1) and the budget rows.
  const l2 = artefactRows.filter((r) => r.method === 'L2-abstract');
  const l2Test = l2.filter((r) => /_test\.mbt$/.test(r.file ?? ''));
  const testShare = l2.length === 0 ? null : (100 * l2Test.length) / l2.length;

  // the family that could not fire: the dead-rule repair's whole point.
  const taintAlloc = artefactRows.filter((r) => r.rule === 'TAINT-ALLOC').length;

  if (tableTotal === null) {
    check('the committed artefact states its 5.2 table total', false);
  } else {
    const pct = testShare === null ? null : Number(testShare.toFixed(1));

    // Each claim: the file it lives in, how to find the sentence, and what
    // the numbers in it must be.
    const claims = [
      {
        name: "the README quotes the artefact's marker row",
        file: 'README.md',
        re: /the marker row reads \*\((?:truncated at 300 of )(\d+) rows\)\*/,
        want: [tableTotal],
      },
      {
        name: "the README states the artefact's table total and sidecar count",
        file: 'README.md',
        re:
          /the L2's table shows 300 of \*\*([\d,]+)\*\*, its count\s+table sums to \*\*([\d,]+)\*\*, and the sidecar holds \*\*([\d,]+)\*\*/,
        want: [tableTotal, tableTotal, sidecarRows],
      },
      {
        name: 'the README states the size of the family that could not fire',
        file: 'README.md',
        re: /now reports \*\*([\d,]+)\*\* findings in the committed artefact/,
        want: [taintAlloc],
      },
      {
        name: 'the README states the test-file share of the 5.2 table',
        file: 'README.md',
        re:
          /\*\*(\d+) of the ([\d,]+)\*\* findings in §5\.2 \(\*\*([\d.]+) %\*\*\) are in the/,
        want: [l2Test.length, tableTotal, pct],
      },
      {
        name: 'the design document states the test-file share of the 5.2 table',
        file: 'docs/design.md',
        re:
          /\*\*(\d+) of the ([\d,]+) findings shown in §5\.2 \(([\d.]+) %\) are in test files\*\*/,
        want: [l2Test.length, tableTotal, pct],
      },
      {
        name: 'the loop acceptance record states the artefact totals',
        file: 'docs/qa/LOOP_ACCEPTANCE.md',
        re:
          /shows the cap of \*\*300 of ([\d,]+)\*\*,\s+its count table sums to \*\*([\d,]+)\*\*, and its sidecar holds \*\*([\d,]+)\*\* findings/,
        want: [tableTotal, tableTotal, sidecarRows],
      },
    ];

    for (const c of claims) {
      const path = join(root, c.file);
      if (!existsSync(path)) {
        check(c.name, false, `${c.file} is missing`);
        continue;
      }
      const text = readFileSync(path, 'utf8');
      const m = c.re.exec(text);
      if (!m) {
        check(c.name, false, 'the sentence was not found');
        continue;
      }
      const got = m.slice(1, 1 + c.want.length).map((x) => Number(x.replace(/,/g, '')));
      const same = c.want.every((w, i) => w === got[i]);

      if (falsify) {
        // The expectation is INVERTED on purpose: each measured number is
        // nudged by one, so every claim MUST fail. A claim that still passes
        // is VACUOUS -- it is not really being compared -- and the check says
        // so instead of reporting a green row.
        const nudged = c.want.map((w, i) => (i === c.want.length - 1 && w % 1 !== 0 ? w + 0.1 : w + 1));
        const stillPasses = got.every((g, i) => g === nudged[i]);
        check(
          `${c.name} -- the falsified expectation fails, as it must`,
          !stillPasses,
          stillPasses ? 'the claim passed with a wrong expectation: it is vacuous' : '',
        );
      } else {
        check(
          c.name,
          same,
          same ? '' : `the text says ${JSON.stringify(got)} and the artefact says ${JSON.stringify(c.want)}`,
        );
      }
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

// --- the per-package measurement table, against the tracked measurement ---
//
// The release publishes what the per-package mode MEASURED: how far it gets
// past the analysis cap, and what the split does to the publish ceiling's two
// numbers.  Those numbers are in the artefact the measurement driver writes
// -- `docs/qa/PER_PACKAGE_MEASUREMENTS.json` -- and the README repeats them
// in a table.
//
// So the table is compared with the ARTEFACT, the same way the committed
// artefact rows are compared with their summaries: the numbers come from a
// file, not from this check.  A table that was typed by hand and drifted away
// from the measurement goes red here.
//
// The artefact is READ, never re-measured: the corpora are not fetched on a
// CI runner, and a check that cannot obtain its dependency must report
// UNKNOWN rather than a false accusation.
//
// The mode is NAMED on both sides: the README says "module-wide" and
// "--per-package", the artefact says "wide" and "per".  The mapping is
// written out here rather than guessed, so a mode that appears in one and
// not the other is caught instead of silently skipped.
const MEAS_PATH = join(root, 'docs', 'qa', 'PER_PACKAGE_MEASUREMENTS.json');
const MEAS_MODE = {
  'module-wide': 'wide',
  '--per-package': 'per',
};

///|
/// The README's measurement table, by its header.
function measurementTable(text) {
  const lines = text.split('\n');
  const h = lines.findIndex((l) => l.startsWith('| corpus | mode | trace files |'));
  if (h < 0) return null;
  const rows = [];
  for (const line of lines.slice(h + 2)) {
    if (!line.startsWith('|')) break;
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((s) => s.trim());
    rows.push(cells);
  }
  return rows;
}

///|
/// A published cell: no emphasis, no thousands separator.
function plain(cell) {
  return String(cell ?? '')
    .replace(/\*\*/g, '')
    .replace(/\`/g, '')
    .replace(/,/g, '')
    .trim();
}

if (!existsSync(MEAS_PATH)) {
  check('the per-package measurement artefact is present', false, MEAS_PATH);
} else {
  const meas = JSON.parse(readFileSync(MEAS_PATH, 'utf8'));
  const measRows = measurementTable(md);
  if (!measRows) {
    check('the README publishes the per-package measurement table', false);
  } else {
    const byKey = new Map();
    for (const r of meas.results ?? []) byKey.set(`${r.corpus}|${r.mode}`, r);

    for (const cells of measRows) {
      const corpus = plain(cells[0]);
      const modeLabel = plain(cells[1]);
      const mode = MEAS_MODE[modeLabel];
      const label = `the measurement table's ${corpus} / ${modeLabel} row`;

      if (!mode) {
        check(`${label}: the mode is one this check knows`, false, modeLabel);
        continue;
      }
      const found = byKey.get(`${corpus}|${mode}`);
      if (!found) {
        check(`${label}: the measurement has this row`, false, `${corpus}|${mode} is not in the artefact`);
        continue;
      }

      // The three numbers the row publishes: the trace files, their total
      // size and their largest one.
      const published = [plain(cells[2]), plain(cells[3]), plain(cells[4])].map((x) => Number(x));
      const measured = [found.trace_files, found.trace_total_bytes, found.trace_largest_bytes];
      const names = ['trace files', 'total bytes', 'largest entry'];

      if (falsify) {
        // The expectations are INVERTED on purpose: each measured number is
        // nudged by one, so every one of those claims MUST fail.  A claim that
        // still passes is VACUOUS -- it is not really being compared -- and the
        // check says so instead of reporting a green row.
        const nudged = measured.map((w) => w + 1);
        const stillPasses = published.every((p, i) => p === nudged[i]);
        check(
          `${label}: the falsified expectation fails, as it must`,
          !stillPasses,
          stillPasses ? 'the claim passed with a wrong expectation: it is vacuous' : '',
        );
      } else {
        const diffs = [];
        published.forEach((p, i) => {
          if (p !== measured[i]) diffs.push(`${names[i]}: README ${p} vs the artefact ${measured[i]}`);
        });
        check(`${label}: every number matches the measurement artefact`, diffs.length === 0, diffs.join('; '));
      }
    }
  }
}

console.log('');
if (falsify) {
  console.log('the falsification mode broke the artefact-total checks, as it must.');
  console.log(
    failures === 0
      ? `README live table and gate table: all ${checks} checks agree.`
      : `README live table and gate table: ${failures} of ${checks} checks FAILED.`,
  );
} else {
  console.log(
    failures === 0
      ? `README live table and gate table: all ${checks} checks match the tree.`
      : `README live table and gate table: ${failures} of ${checks} checks FAILED.`,
  );
}
process.exit(failures === 0 ? 0 : 1);
