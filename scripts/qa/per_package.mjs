#!/usr/bin/env node
// THE PER-PACKAGE MODE, MEASURED.
//
// The step budget is a bound on the WORK, and the work of a module is the
// work of its PACKAGES.  A module-wide budget is therefore spent on the
// first packages in file order, and the rest of the tree is never
// interpreted.  The per-package mode gives each package its own budget, so
// a module of N packages has a budget of N times the one.
//
// This check states that rule and then MEASURES it, on six readings:
//
//   * the LOADER records the packages: every package the report's table
//     names is a directory of the tree that holds a `moon.pkg`, and every
//     package of the files the trace names is in the table;
//   * the TRACE is split one file per package, and the split LOSES NOTHING:
//     the events of the files add up to the module's event count, and every
//     event of a package's file belongs to that package;
//   * the REPORT's package table adds up to the module's counts;
//   * the budget is spent AGAIN in the next package: with the same one-step
//     budget, the per-package mode enters one function per package and the
//     module-wide mode enters one in the whole module;
//   * the report STATES the rule it followed;
//   * and the mode is a NO-OP when no budget was reached: the two modes then
//     enter the same functions and cost the same steps.
//
// Nothing here carries a constant that could drift: the packages are read
// from the TREE, the counts from the ARTEFACTS, and the budget from the
// SOURCE.
//
// Usage: node scripts/qa/per_package.mjs [--artefacts <dir>]
//
//   --artefacts <dir>  check artefacts that are ALREADY THERE: the report
//                      (`*.md`), the captured output (`metrics.txt`) and the
//                      per-package traces (`*_trace.jsonl`).  The live runs
//                      are skipped; the cross-checks are not.
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

const argValue = (flag) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const ARTIFACTS = argValue('--artefacts');

// ------------------------------------------------------- the tree's packages

/// The package of a FILE of the tree: the nearest directory that holds a
/// `moon.pkg`, counted from the file's own directory upwards.  The module's
/// ROOT package is "", and that is the name of a file that no package
/// directory covers.
///
/// This is the SAME rule the loader uses, and it is measured here rather
/// than carried: a check that carried the package list would be a second
/// source of truth that could drift from the loader it checks.
export function packageOfFile(root, relFile) {
  const parts = relFile.split('/').slice(0, -1);
  for (let i = parts.length; i >= 0; i--) {
    const dir = parts.slice(0, i).join('/');
    if (dir === '' && i > 0) continue;
    if (existsSync(join(root, dir === '' ? '' : dir, 'moon.pkg'))) {
      return dir;
    }
  }
  return '';
}

/// The packages of the tree: every directory that holds a `moon.pkg`.
function treePackages(root) {
  const out = new Set();
  const walk = (dir, rel) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    if (existsSync(join(dir, 'moon.pkg'))) out.add(rel);
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      if (e.name === '_build' || e.name === '.git' || e.name === '.mooncakes' || e.name === '.repos') continue;
      walk(join(dir, e.name), rel === '' ? e.name : `${rel}/${e.name}`);
    }
  };
  walk(root, '');
  return out;
}

// ------------------------------------------------------------ the artefacts

export function parsePackageTable(text) {
  const rows = [];
  let inTable = false;
  for (const raw of text.split(/\r?\n/)) {
    if (/^\|\s*Package\s*\|/.test(raw)) {
      inTable = true;
      continue;
    }
    if (!inTable) continue;
    if (!raw.trim().startsWith('|')) {
      inTable = false;
      continue;
    }
    const cells = raw.split('|').slice(1, -1).map((s) => s.trim());
    if (cells.length < 7) {
      inTable = false;
      continue;
    }
    if (cells[0] === 'Package' || /^-+$/.test(cells[0])) continue;
    rows.push({
      name: cells[0].replace(/^`|`$/g, ''),
      entered: Number(cells[1]),
      skipped: Number(cells[2]),
      steps: Number(cells[3]),
      events: Number(cells[4]),
      findings: Number(cells[5]),
      budget: cells[6],
    });
  }
  return rows;
}

export function parseReportFacts(text) {
  const selection = /^\|\s*Entry selection\s*\|\s*(.*?)\s*\|\s*$/m.exec(text);
  const events = /^\|\s*Trace events\s*\|\s*(\d+)\s*\|\s*$/m.exec(text);
  const steps = /^\|\s*Interpreted steps\s*\|\s*(\d+)\s*\|\s*$/m.exec(text);
  return {
    selection: selection ? selection[1] : null,
    events: events ? Number(events[1]) : null,
    steps: steps ? Number(steps[1]) : null,
  };
}

export function parseMetrics(text, lens) {
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.startsWith('METRICS')) continue;
    const fields = raw.split('\t');
    if (fields[1] !== lens) continue;
    const out = {};
    for (const f of fields.slice(2)) {
      const eq = f.indexOf('=');
      if (eq < 0) continue;
      out[f.slice(0, eq)] = f.slice(eq + 1);
    }
    return out;
  }
  return null;
}

/// The per-package trace files of a directory, each with its events.
function readTraces(dir) {
  const files = readdirSync(dir).filter((f) => f.endsWith('_trace.jsonl'));
  const out = [];
  for (const f of files) {
    const text = readFileSync(join(dir, f), 'utf8');
    const events = [];
    for (const line of text.split('\n')) {
      if (!line.trim()) continue;
      let obj;
      try {
        obj = JSON.parse(line);
      } catch {
        events.push({ file: null, broken: true });
        continue;
      }
      events.push({ file: obj.file, broken: false });
    }
    out.push({ name: f, events, bytes: statSync(join(dir, f)).size });
  }
  return out;
}

// ------------------------------------------------------------- the live runs

function runScan(exe, extraArgs, outDir) {
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  const r = spawnSync(
    exe,
    ['analyze', '--dir', '.', '--out', outDir, '--metrics', ...extraArgs],
    { cwd: ROOT, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (r.status !== 0) {
    console.error(`the scan failed (${r.status}):`);
    console.error(((r.stderr ?? '') + (r.stdout ?? '')).split(/\r?\n/).slice(0, 8).join('\n'));
    return null;
  }
  const text = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const reportFile = readdirSync(outDir).find((f) => f.endsWith('.md'));
  const report = reportFile ? readFileSync(join(outDir, reportFile), 'utf8') : '';
  const traceFiles = readdirSync(outDir).filter((f) => f.endsWith('_trace.jsonl'));
  return { text, report, reportFile, traceFiles, outDir };
}

// ----------------------------------------------------------------- the checks

/// The checks that read ARTEFACTS: they are the same in the live mode and in
/// the `--artefacts` mode, so the falsifier points them at a mutated COPY.
function checkArtefacts(dir, report, metricsText) {
  const table = parsePackageTable(report);
  const facts = parseReportFacts(report);
  const traces = readTraces(dir);
  const metrics = parseMetrics(metricsText, 'funcs');
  const pkgMetrics = parseMetrics(metricsText, 'packages');

  check('the report has a package table', table.length > 0, `${table.length} row(s)`);

  // The table names REAL packages of the tree.
  const real = treePackages(ROOT);
  const unknown = table.filter((r) => r.name !== '' && !real.has(r.name)).map((r) => r.name);
  check(
    'every package the report names is a directory of the tree that holds a moon.pkg',
    unknown.length === 0,
    unknown.length === 0 ? '' : `not in the tree: ${unknown.join(', ')}`,
  );

  // The split LOSES NOTHING: the events of the files add up to the module's
  // event count.
  const traceEvents = traces.reduce((n, t) => n + t.events.length, 0);
  check(
    'the per-package traces hold every event of the module, once',
    facts.events !== null && traceEvents === facts.events,
    `traces ${traceEvents}, report ${facts.events}`,
  );

  // Every event of a package's file BELONGS to that package.
  const seen = new Map();
  let stray = 0;
  for (const t of traces) {
    const pkgs = new Set();
    for (const e of t.events) {
      if (e.broken || typeof e.file !== 'string') {
        stray += 1;
        continue;
      }
      pkgs.add(packageOfFile(ROOT, e.file));
    }
    for (const p of pkgs) {
      if (!seen.has(p)) seen.set(p, []);
      seen.get(p).push(t.name);
    }
    if (pkgs.size > 1) {
      stray += 1;
      console.log(`  NOTE: the trace ${t.name} holds events of ${pkgs.size} packages`);
    }
  }
  check(
    'every event of a package\'s trace file belongs to that package',
    stray === 0,
    stray === 0 ? '' : `${stray} stray event(s) or mixed file(s)`,
  );

  // Every package the trace names is in the table.
  const tableNames = new Set(table.map((r) => r.name));
  const missing = [...seen.keys()].filter((p) => !tableNames.has(p));
  check(
    'every package the traces name is in the report\'s package table',
    missing.length === 0,
    missing.length === 0 ? '' : `missing: ${missing.join(', ')}`,
  );

  // The table ADDS UP to the module.
  const tableEvents = table.reduce((n, r) => n + r.events, 0);
  check(
    'the package table\'s event counts add up to the module\'s',
    facts.events !== null && tableEvents === facts.events,
    `table ${tableEvents}, report ${facts.events}`,
  );
  const tableSteps = table.reduce((n, r) => n + r.steps, 0);
  check(
    'the package table\'s step counts add up to the module\'s',
    facts.steps !== null && tableSteps === facts.steps,
    `table ${tableSteps}, report ${facts.steps}`,
  );

  // The report STATES the rule it followed.
  check(
    'the report states the per-package rule',
    facts.selection !== null && /PACKAGE BY PACKAGE/.test(facts.selection),
    facts.selection ?? '(no row)',
  );

  // The metrics agree with the table about the number of packages.
  if (pkgMetrics) {
    check(
      'the metrics and the table agree about how many packages there are',
      Number(pkgMetrics.packages) === table.length,
      `metrics ${pkgMetrics.packages}, table ${table.length}`,
    );
  }
  if (metrics) {
    const tableEntered = table.reduce((n, r) => n + r.entered, 0);
    check(
      'the metrics and the package table agree about how many functions were entered',
      Number(metrics.entered) === tableEntered,
      `metrics ${metrics.entered}, table ${tableEntered}`,
    );
  }
  return { table, facts, traces, metrics, pkgMetrics };
}

// ------------------------------------------------------------------- the run

if (!ARTIFACTS) {
  {
    const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
      cwd: ROOT,
      encoding: 'utf8',
      timeout: 900000,
      maxBuffer: 32 * 1024 * 1024,
      shell: true,
    });
    if (build.status !== 0) {
      console.error('the CLI build failed, so there is nothing to check:');
      console.error((build.stderr ?? '') + (build.stdout ?? ''));
      process.exit(2);
    }
  }
  const exe = requireCli(ROOT);
  const base = join(ROOT, '_build', 'qa', 'per_package');
  rmSync(base, { recursive: true, force: true });

  const wide = runScan(exe, [], join(base, 'wide'));
  if (!wide) process.exit(2);
  const per = runScan(exe, ['--per-package'], join(base, 'per'));
  if (!per) process.exit(2);
  const tiny = runScan(exe, ['--per-package', '--max-total-steps', '1'], join(base, 'tiny'));
  if (!tiny) process.exit(2);
  const tinyWide = runScan(exe, ['--max-total-steps', '1'], join(base, 'tinywide'));
  if (!tinyWide) process.exit(2);

  // The artefacts of the per-package run, so the falsifier has something to
  // copy.
  const art = join(base, 'artefacts');
  mkdirSync(art, { recursive: true });
  writeFileSync(join(art, per.reportFile), per.report, 'utf8');
  writeFileSync(join(art, 'metrics.txt'), per.text, 'utf8');
  for (const f of per.traceFiles) {
    writeFileSync(join(art, f), readFileSync(join(per.outDir, f), 'utf8'), 'utf8');
  }

  checkArtefacts(art, per.report, per.text);

  // The module-wide mode writes ONE trace file; the per-package mode writes
  // one per package.
  check(
    'the module-wide mode writes one trace file',
    wide.traceFiles.length === 1,
    `${wide.traceFiles.length} file(s)`,
  );
  check(
    'the per-package mode writes one trace file per package',
    per.traceFiles.length === parsePackageTable(per.report).length,
    `${per.traceFiles.length} file(s)`,
  );

  // THE BUDGET IS SPENT AGAIN IN THE NEXT PACKAGE.  The same one-step budget
  // on both sides: the module-wide scan enters ONE function in the whole
  // module, and the per-package scan enters one in each package that has
  // functions.
  const wideTiny = parseMetrics(tinyWide.text, 'funcs');
  const perTiny = parseMetrics(tiny.text, 'funcs');
  const tinyTable = parsePackageTable(tiny.report);
  const withFunctions = tinyTable.filter((r) => r.entered > 0).length;
  check(
    'the per-package mode spends the budget again in the next package',
    wideTiny !== null &&
      perTiny !== null &&
      withFunctions > 1 &&
      Number(perTiny.entered) === withFunctions &&
      Number(perTiny.entered) > Number(wideTiny.entered),
    `module-wide ${wideTiny?.entered}, per-package ${perTiny?.entered}, packages with functions ${withFunctions}`,
  );
  check(
    'the per-package mode says the budget stopped the scan',
    perTiny !== null && perTiny['stopped-by'] === 'budget',
    `stopped-by=${perTiny?.['stopped-by']}`,
  );

  // THE MODE IS A NO-OP WHEN NO BOUND STOPPED THE SCAN.  The two runs then
  // enter the same functions and cost the same steps; if a bound DID stop
  // the scan, the two modes are supposed to differ and the check says so
  // instead of pretending.
  const wideMetrics = parseMetrics(wide.text, 'funcs');
  const perMetrics = parseMetrics(per.text, 'funcs');
  if (wideMetrics && perMetrics && wideMetrics['stopped-by'] === 'none') {
    check(
      'the two modes agree when no budget was reached',
      wideMetrics.entered === perMetrics.entered &&
        wideMetrics.steps === perMetrics.steps &&
        wideMetrics['step-budget'] === perMetrics['step-budget'],
      `entered ${wideMetrics.entered}/${perMetrics.entered}, steps ${wideMetrics.steps}/${perMetrics.steps}`,
    );
  } else {
    console.log('  NOTE: the module-wide scan was stopped by a bound, so the two modes are expected to differ');
  }
} else {
  const dir = resolve(ARTIFACTS);
  const files = readdirSync(dir);
  const reportFile = files.find((f) => f.endsWith('.md'));
  const metricsFile = files.find((f) => f === 'metrics.txt');
  if (!reportFile || !metricsFile) {
    console.error(`the artefacts in ${dir} do not hold a report and a metrics.txt`);
    process.exit(2);
  }
  const report = readFileSync(join(dir, reportFile), 'utf8');
  const metricsText = readFileSync(join(dir, metricsFile), 'utf8');
  checkArtefacts(dir, report, metricsText);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
