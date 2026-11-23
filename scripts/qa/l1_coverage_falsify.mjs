#!/usr/bin/env node
// THE COVERAGE CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier breaks COPIES --
// never the tracked sources, never the analyser -- and asserts that the same
// check `scripts/qa/l1_coverage.mjs` goes RED on each mutation.
//
// The mutations are the ways the published coverage could be WRONG while
// still looking fine:
//
//   F1  the metrics and the report disagree about HOW MANY functions were
//       entered -- one of them is stale, and a reader is told a coverage that
//       was not measured
//   F2  the metrics say the STEP BUDGET stopped the scan while the report
//       still says every function was entered -- the scan was truncated and
//       the report does not say so
//   F3  the report says the old count cap applies while the metrics say no
//       bound stopped the scan -- the report states a rule that is not the
//       rule that was followed
//
// It also runs a CONTROL: a change that says nothing about which coverage was
// measured (the budget's NUMBER), which the checker must NOT notice.
// Without the control, a checker that failed on every possible edit would
// look like a checker that works.
//
// The scan is run ONCE and its artefacts are captured: the falsifier copies
// them, and the tracked tree is never written.
//
// Usage: node scripts/qa/l1_coverage_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = join(ROOT, 'scripts', 'qa', 'l1_coverage.mjs');
const WORK = join(ROOT, '_build', 'qa', 'l1_coverage_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// --- the artefacts, captured ONCE --------------------------------------------

rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });

const REPORT_TEXT = (() => {
  const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 32 * 1024 * 1024,
    shell: true,
  });
  if (build.status !== 0) {
    console.error('the CLI build failed, so there is nothing to falsify:');
    console.error((build.stderr ?? '') + (build.stdout ?? ''));
    process.exit(2);
  }
  const exe = requireCli(ROOT);
  const out = join(WORK, 'scan');
  mkdirSync(out, { recursive: true });
  // `--funnel` so the captured report carries the abstract layer's scope line:
  // the check compares the dynamic layer's entered+skipped count against that
  // universe, and a report without the line cannot be compared.
  const run = spawnSync(exe, ['analyze', '--dir', '.', '--out', out, '--metrics', '--funnel'], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (run.status !== 0) {
    console.error('the scan failed, so there is nothing to falsify:');
    console.error(((run.stderr ?? '') + (run.stdout ?? '')).split(/\r?\n/).slice(0, 6).join('\n'));
    process.exit(2);
  }
  const reportFile = readdirSync(out).find((f) => f.endsWith('.md'));
  if (!reportFile) {
    console.error('the scan wrote no report, so there is nothing to falsify');
    process.exit(2);
  }
  return {
    report: readFileSync(join(out, reportFile), 'utf8'),
    metrics: `${run.stdout ?? ''}${run.stderr ?? ''}`,
    reportName: reportFile,
  };
})();

/// A fresh copy of the artefacts, so every mutation starts from the truth.
function copyArtefacts(name, mutate) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const report = mutate.report(REPORT_TEXT.report);
  const metrics = mutate.metrics(REPORT_TEXT.metrics);
  if (report === REPORT_TEXT.report && metrics === REPORT_TEXT.metrics) {
    console.error(`the mutation for ${name} changed nothing`);
    process.exit(2);
  }
  writeFileSync(join(dir, REPORT_TEXT.reportName), report, 'utf8');
  writeFileSync(join(dir, 'metrics.txt'), metrics, 'utf8');
  return dir;
}

/// Run the real check.  It must go RED.
function mustGoRed(name, dir, expect) {
  const r = spawnSync(process.execPath, [CHECK, '--artefacts', dir], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 32 * 1024 * 1024,
  });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red && expect) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
  }
}

/// Run the real check.  It must stay GREEN.
function mustStayGreen(name, dir) {
  const r = spawnSync(process.execPath, [CHECK, '--artefacts', dir], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 32 * 1024 * 1024,
  });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) console.log(out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
}

// The truth, written straight out: the mutating helper refuses to make a copy
// that changes nothing, and the truth IS the unchanged thing.
const truth = join(WORK, 'truth');
mkdirSync(truth, { recursive: true });
writeFileSync(join(truth, REPORT_TEXT.reportName), REPORT_TEXT.report, 'utf8');
writeFileSync(join(truth, 'metrics.txt'), REPORT_TEXT.metrics, 'utf8');

// The truth has to PASS, or every mutation below would "go red" for the wrong
// reason: a falsifier that starts from a broken baseline proves nothing.
mustStayGreen('the unmutated copies', truth);

// F1 -- the metrics and the report disagree about how many functions were
// entered.
{
  const dir = copyArtefacts('f1', {
    report: (t) => t,
    metrics: (t) => t.replace(/(\tentered=)(\d+)/, (m, a, n) => `${a}${Number(n) - 1}`),
  });
  mustGoRed('F1 a stale count of entered functions', dir, 'agree about how many functions were entered');
}

// F2 -- the metrics say the budget stopped the scan; the report does not say
// so.
{
  const dir = copyArtefacts('f2', {
    report: (t) => t,
    metrics: (t) => t.replace(/(\tstopped-by=)([a-z]+)/, '$1budget'),
  });
  mustGoRed('F2 a truncation the report does not state', dir, 'the step budget stopped the scan');
}

// F3 -- the report states the OLD rule while the metrics say no bound stopped
// the scan.
{
  const dir = copyArtefacts('f3', {
    report: (t) =>
      t.replace(
        /^\|\s*Entry selection\s*\|.*$/m,
        '| Entry selection | the first 150 functions in file order (the `--max-functions` cap applies) |',
      ),
    metrics: (t) => t,
  });
  mustGoRed('F3 a rule the metrics do not show', dir, 'says every function was entered');
}

// The CONTROL -- the budget's NUMBER says nothing about which coverage was
// measured.
{
  const dir = copyArtefacts('control', {
    report: (t) => t,
    metrics: (t) => t.replace(/(\tstep-budget=)(\d+)/, (m, a, n) => `${a}${Number(n) + 1}`),
  });
  mustStayGreen('the control', dir);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
