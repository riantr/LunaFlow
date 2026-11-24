#!/usr/bin/env node
// THE DEFAULT SCAN'S COVERAGE RULE, MEASURED.
//
// The default scan enters EVERY function.  The bound that stops it is a WORK
// budget -- the module-wide step budget -- and not a count of functions.  The
// count was the wrong shape for a bound: the same 150 functions cost 3,011
// steps on this tree and 47,835 on `riantr/moonbit_doubleML@0.164.64`, and
// because it was taken in file order it took whole DIRECTORIES and left whole
// directories uninterpreted (8 of 64 files on this tree).
//
// This check states that rule and then MEASURES it, on four readings:
//
//   * the DEFAULT run is not truncated by any bound -- `stopped-by=none` -- so
//     every function in the module's entry universe was entered;
//   * the STEP BUDGET is a real bound: with `--max-total-steps 1` the scan
//     stops, and it says the BUDGET stopped it;
//   * the COUNT cap is still a real bound: with `--max-functions 3` the scan
//     stops, and it says the COUNT stopped it;
//   * the budget the default run used is the budget the SOURCE declares.
//
// And it cross-checks the two artefacts that state the coverage -- the
// metrics block and the report's "Entry selection" row -- against EACH
// OTHER.  A report that claims a coverage the metrics do not show is a
// failure, not a sentence: the two are written by different code, and only
// their agreement says that the coverage a reader is told about is the
// coverage that was measured.
//
// Usage: node scripts/qa/l1_coverage.mjs [--artefacts <dir>]
//
//   --artefacts <dir>  check artefacts that are ALREADY THERE: the report
//                      (`*.md`) and the captured metrics (`metrics.txt`).
//                      The live runs are skipped; the cross-check is not.
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
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

// --------------------------------------------------------------- the source

/// The step budget the SOURCE declares, read from the source rather than
/// carried here: a constant in this file would be a second source of truth
/// that could drift from the one the analyser actually uses.
function declaredBudget() {
  const path = join(ROOT, 'src', 'app', 'interp.mbt');
  if (!existsSync(path)) return null;
  const m = /pub const DEFAULT_MAX_TOTAL_STEPS\s*:\s*Int32\s*=\s*(\d+)/.exec(
    readFileSync(path, 'utf8'),
  );
  return m ? Number(m[1]) : null;
}

// -------------------------------------------------------------- the metrics

/// The `METRICS funcs` line, read as the fields it carries.
export function parseFuncsMetrics(text) {
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.startsWith('METRICS')) continue;
    const fields = raw.split('\t');
    if (fields[1] !== 'funcs') continue;
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

/// The report's coverage rows, read from the rendered report.
export function parseReportCoverage(text) {
  const observed = /^\|\s*Observed functions\s*\|\s*(\d+)\s*\|\s*$/m.exec(text);
  const selection = /^\|\s*Entry selection\s*\|\s*(.*?)\s*\|\s*$/m.exec(text);
  // The ABSTRACT LAYER's scope line, which names the module's ANALYSABLE
  // universe -- the number of functions that have a body. The dynamic layer
  // walks the same list, so the two numbers are comparable, and the comparison
  // is the strong form of "every function was entered": the functions the
  // dynamic layer entered PLUS the ones it skipped must be exactly the
  // universe the abstract layer names. A proxy ("the scan entered a lot of
  // functions") cannot fail; this can.
  const scope = /The abstract layer analysed (\d+) of (\d+)/.exec(text);
  return {
    observed: observed ? Number(observed[1]) : null,
    selection: selection ? selection[1] : null,
    l2Analysed: scope ? Number(scope[1]) : null,
    universe: scope ? Number(scope[2]) : null,
  };
}

// -------------------------------------------------------------- the runs

function runScan(exe, extraArgs, outDir) {
  mkdirSync(outDir, { recursive: true });
  // `--funnel` is here for the REPORT, not for the scan: it is what makes the
  // report carry the abstract layer's scope line -- the module's analysable
  // universe -- which is the number this check compares the dynamic layer's
  // entered+skipped count against. The dynamic layer's own behaviour does not
  // depend on it.
  const r = spawnSync(
    exe,
    ['analyze', '--dir', '.', '--out', outDir, '--metrics', '--funnel', ...extraArgs],
    { cwd: ROOT, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (r.status !== 0) {
    console.error(`the scan failed (${r.status}):`);
    console.error(((r.stderr ?? '') + (r.stdout ?? '')).split(/\r?\n/).slice(0, 8).join('\n'));
    return null;
  }
  const text = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const metrics = parseFuncsMetrics(text);
  if (!metrics) {
    console.error('the scan printed no `METRICS funcs` line');
    return null;
  }
  const reportFile = readdirSync(outDir).find((f) => f.endsWith('.md'));
  const report = reportFile ? readFileSync(join(outDir, reportFile), 'utf8') : '';
  return { metrics, report, text };
}

// ------------------------------------------------------------- the checks

if (!ARTIFACTS) {
  // The binary under test is BUILT HERE, not assumed: a binary left over from
  // an earlier build measures the product as it WAS.
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
  const base = join(ROOT, '_build', 'qa', 'l1_coverage');
  rmSync(base, { recursive: true, force: true });

  const def = runScan(exe, [], join(base, 'default'));
  if (!def) process.exit(2);
  const budget = runScan(exe, ['--max-total-steps', '1'], join(base, 'budget'));
  if (!budget) process.exit(2);
  const count = runScan(exe, ['--max-functions', '3'], join(base, 'count'));
  if (!count) process.exit(2);

  // The artefacts of the DEFAULT run, so the cross-check below has something
  // to read and the falsifier has something to copy.
  const art = join(base, 'artefacts');
  mkdirSync(art, { recursive: true });
  const reportFile = readdirSync(join(base, 'default')).find((f) => f.endsWith('.md'));
  writeFileSync(join(art, reportFile), def.report, 'utf8');
  writeFileSync(join(art, 'metrics.txt'), def.text, 'utf8');

  check(
    'the default scan was not truncated by a bound',
    def.metrics['stopped-by'] === 'none',
    `stopped-by=${def.metrics['stopped-by']}`,
  );
  check(
    'the default scan entered every function',
    Number(def.metrics.entered) > 0 && Number(def.metrics.skipped) <= 1,
    `entered=${def.metrics.entered} skipped=${def.metrics.skipped}`,
  );
  // The STRONG form of the claim above: the dynamic layer entered EXACTLY the
  // module's analysable universe -- the number the abstract layer's own scope
  // line names. Both layers walk the same list of functions, and the abstract
  // layer's universe counts the functions that HAVE A BODY, which is exactly
  // what the dynamic layer enters (the ones without a body are skipped, and
  // they are not in that universe). The two numbers are written by different
  // code, so their agreement is evidence and not a tautology.
  const defCoverage = parseReportCoverage(def.report);
  check(
    "the default scan entered exactly the module's analysable universe",
    defCoverage.universe !== null && Number(def.metrics.entered) === defCoverage.universe,
    `entered ${def.metrics.entered} vs the universe ${defCoverage.universe}`,
  );
  check(
    'the step budget stopped the scan when it was made small',
    budget.metrics['stopped-by'] === 'budget',
    `stopped-by=${budget.metrics['stopped-by']}`,
  );
  check(
    'the count cap stopped the scan when it was made small',
    count.metrics['stopped-by'] === 'count',
    `stopped-by=${count.metrics['stopped-by']}`,
  );
  const declared = declaredBudget();
  if (declared === null) {
    check('the source declares a step budget', false, 'DEFAULT_MAX_TOTAL_STEPS was not found');
  } else {
    check(
      'the default scan used the budget the source declares',
      Number(def.metrics['step-budget']) === declared,
      `run ${def.metrics['step-budget']}, source ${declared}`,
    );
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
  const metrics = parseFuncsMetrics(metricsText);
  if (!metrics) {
    console.error('the metrics hold no `METRICS funcs` line');
    process.exit(2);
  }
  const coverage = parseReportCoverage(report);

  check(
    'the report and the metrics agree about how many functions were entered',
    coverage.observed !== null && coverage.observed === Number(metrics.entered),
    `report ${coverage.observed}, metrics ${metrics.entered}`,
  );
  const stopped = metrics['stopped-by'];
  const row = coverage.selection ?? '';
  if (stopped === 'none') {
    // The row states the claim in the MODE's own words.  The module-wide mode
    // says "the step budget (100000 steps) was not reached"; the per-package
    // mode -- the DEFAULT since 0.1.37 -- says "each of the 10 packages had its
    // own step budget (100000 steps) and none of them was reached".  The CLAIM
    // is the same in both: every function was entered, and no bound was
    // reached.  The wording belongs to the tool, so the check accepts both
    // wordings of the one claim; it does not accept a third.
    check(
      'the report says every function was entered when no bound stopped the scan',
      /every function was entered/.test(row) &&
        /(was not reached|none of them was reached)/.test(row) &&
        !/cap applies/.test(row),
      row,
    );
    check(
      "the scan entered exactly the module's analysable universe",
      coverage.universe !== null && Number(metrics.entered) === coverage.universe,
      `entered ${metrics.entered} vs the universe ${coverage.universe}`,
    );
  } else if (stopped === 'budget') {
    check(
      'the report says the step budget stopped the scan when the budget stopped it',
      /step budget/.test(row) && /was spent/.test(row),
      row,
    );
  } else if (stopped === 'count') {
    check(
      'the report names the count cap when the count stopped the scan',
      /--max-functions/.test(row),
      row,
    );
  } else {
    check('the metrics name a bound that stopped the scan', false, `stopped-by=${stopped}`);
  }
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
