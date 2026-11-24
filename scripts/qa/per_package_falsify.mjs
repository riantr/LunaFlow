#!/usr/bin/env node
// THE PER-PACKAGE CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier breaks COPIES --
// never the tracked sources, never the analyser -- and asserts that the same
// check `scripts/qa/per_package.mjs` goes RED on each mutation.
//
// The mutations are the ways the per-package artefacts could be WRONG while
// still looking fine:
//
//   F1  a package's trace file holds an event of ANOTHER package -- the
//       split put an event in the wrong place
//   F2  a trace file lost an event -- the split DROPPED evidence
//   F3  the report's package table does not add up to the module's counts --
//       the table states a coverage that was not measured
//   F4  the report states the MODULE-WIDE rule while the artefacts are the
//       per-package ones -- the report states a rule that is not the rule
//       that was followed
//   F5  the metrics do not carry the packages line -- the artefacts are not
//       the per-package ones, which is what a MODULE-WIDE run looks like
//
// It also runs a CONTROL: a change that says nothing about which coverage
// was measured (the budget's NUMBER), which the checker must NOT notice.
// Without the control, a checker that failed on every possible edit would
// look like a checker that works.
//
// The scan is run ONCE -- with NO mode flag, because the per-package mode is
// the DEFAULT now, so the artefacts are the ones the tool ships -- and its
// artefacts are captured: the falsifier copies them, and the tracked tree is
// never written.
//
// Usage: node scripts/qa/per_package_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = join(ROOT, 'scripts', 'qa', 'per_package.mjs');
const WORK = join(ROOT, '_build', 'qa', 'per_package_falsify');

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

const ARTEFACTS = (() => {
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
  const run = spawnSync(exe, ['analyze', '--dir', '.', '--out', out, '--metrics'], {
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
  const traces = readdirSync(out).filter((f) => f.endsWith('_trace.jsonl'));
  if (traces.length < 2) {
    console.error(`the per-package scan wrote ${traces.length} trace file(s); the falsifier needs two`);
    process.exit(2);
  }
  const art = join(WORK, 'artefacts');
  mkdirSync(art, { recursive: true });
  writeFileSync(join(art, reportFile), readFileSync(join(out, reportFile), 'utf8'), 'utf8');
  writeFileSync(join(art, 'metrics.txt'), `${run.stdout ?? ''}${run.stderr ?? ''}`, 'utf8');
  for (const f of traces) {
    writeFileSync(join(art, f), readFileSync(join(out, f), 'utf8'), 'utf8');
  }
  return { dir: art, reportFile, traces };
})();

/// A fresh copy of the artefacts, so every mutation starts from the truth.
function copyArtefacts(name, mutate) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const f of readdirSync(ARTEFACTS.dir)) {
    writeFileSync(join(dir, f), readFileSync(join(ARTEFACTS.dir, f), 'utf8'), 'utf8');
  }
  const touched = mutate(dir);
  if (!touched) {
    console.error(`the mutation for ${name} changed nothing`);
    process.exit(2);
  }
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
rmSync(truth, { recursive: true, force: true });
mkdirSync(truth, { recursive: true });
for (const f of readdirSync(ARTEFACTS.dir)) {
  writeFileSync(join(truth, f), readFileSync(join(ARTEFACTS.dir, f), 'utf8'), 'utf8');
}

// The truth has to PASS, or every mutation below would "go red" for the wrong
// reason: a falsifier that starts from a broken baseline proves nothing.
mustStayGreen('the unmutated copies', truth);

// F1 -- a package's trace file holds an event of ANOTHER package.
{
  const dir = copyArtefacts('f1', (d) => {
    const traces = readdirSync(d).filter((f) => f.endsWith('_trace.jsonl'));
    const a = join(d, traces[0]);
    const b = join(d, traces[1]);
    const linesA = readFileSync(a, 'utf8').split('\n').filter((l) => l.trim());
    const linesB = readFileSync(b, 'utf8').split('\n').filter((l) => l.trim());
    if (linesA.length === 0 || linesB.length === 0) return false;
    const moved = linesA[0];
    writeFileSync(a, linesA.slice(1).join('\n') + '\n', 'utf8');
    writeFileSync(b, linesB.join('\n') + '\n' + moved + '\n', 'utf8');
    return true;
  });
  mustGoRed('F1 an event in the wrong package\'s trace', dir, "belongs to that package");
}

// F2 -- a trace file lost an event.
{
  const dir = copyArtefacts('f2', (d) => {
    const traces = readdirSync(d).filter((f) => f.endsWith('_trace.jsonl'));
    const a = join(d, traces[0]);
    const lines = readFileSync(a, 'utf8').split('\n').filter((l) => l.trim());
    if (lines.length === 0) return false;
    writeFileSync(a, lines.slice(1).join('\n') + '\n', 'utf8');
    return true;
  });
  mustGoRed('F2 a trace that lost an event', dir, 'hold every event of the module');
}

// F3 -- the report's package table does not add up.
{
  const dir = copyArtefacts('f3', (d) => {
    const reportFile = readdirSync(d).find((f) => f.endsWith('.md'));
    const p = join(d, reportFile);
    const text = readFileSync(p, 'utf8');
    // The first row of the package table: change its event count.
    const at = text.search(/^\|\s*`[^`]+`\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|/m);
    if (at < 0) return false;
    const line = text.slice(at).split('\n')[0];
    const changed = line.replace(/(\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*)(\d+)(\s*\|)/, (m, a, n, b) => `${a}${Number(n) + 1}${b}`);
    if (changed === line) return false;
    writeFileSync(p, text.slice(0, at) + changed + text.slice(at + line.length), 'utf8');
    return true;
  });
  mustGoRed('F3 a package table that does not add up', dir, 'event counts add up to the module');
}

// F4 -- the report states the MODULE-WIDE rule.
{
  const dir = copyArtefacts('f4', (d) => {
    const reportFile = readdirSync(d).find((f) => f.endsWith('.md'));
    const p = join(d, reportFile);
    const text = readFileSync(p, 'utf8');
    const changed = text.replace(
      /^\|\s*Entry selection\s*\|.*$/m,
      "| Entry selection | every function was entered (862); the step budget (100000 steps) was not reached |",
    );
    if (changed === text) return false;
    writeFileSync(p, changed, 'utf8');
    return true;
  });
  mustGoRed('F4 a rule the artefacts do not show', dir, 'states the per-package rule');
}

// F5 -- the metrics do not carry the packages line: the artefacts are not the
// per-package ones.
{
  const dir = copyArtefacts('f5', (d) => {
    const p = join(d, 'metrics.txt');
    const text = readFileSync(p, 'utf8');
    const lines = text.split(/\r?\n/);
    const kept = lines.filter((l) => !/^METRICS\tpackages\t/.test(l));
    if (kept.length === lines.length) return false;
    writeFileSync(p, kept.join('\n'), 'utf8');
    return true;
  });
  mustGoRed('F5 artefacts that are not the per-package ones', dir, 'the metrics say the scan was the per-package one');
}

// The CONTROL -- the budget's NUMBER says nothing about which coverage was
// measured.
{
  const dir = copyArtefacts('control', (d) => {
    const p = join(d, 'metrics.txt');
    const text = readFileSync(p, 'utf8');
    const changed = text.replace(/(\tstep-budget=)(\d+)/, (m, a, n) => `${a}${Number(n) + 1}`);
    if (changed === text) return false;
    writeFileSync(p, changed, 'utf8');
    return true;
  });
  mustStayGreen('the control', dir);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
