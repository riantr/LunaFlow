#!/usr/bin/env node
// E2E + determinism harness for the LunaFlow CLI (acceptance A3, A4, A10-A13, A17, A18).
//
// Runs the built binary against the fixture and the two validation modules,
// twice for the fixture, and asserts artefacts, thresholds and determinism.
//
// Usage: node scripts/qa/e2e.mjs [--out <dir>] [--skip-modules]
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync, statSync, readdirSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = resolveCli(root);
const outRoot = resolve(root, process.argv.includes('--out') ? process.argv[process.argv.indexOf('--out') + 1] : '_build/qa/e2e');
const skipModules = process.argv.includes('--skip-modules');

if (!existsSync(exe)) {
  console.error(`missing binary: ${exe}\nrun: moon build src/cli --target native`);
  process.exit(2);
}

// THE BINARY UNDER TEST IS BUILT HERE, not assumed. This harness measures
// the PRODUCT's behaviour -- its findings, its counts, its wall time -- and a
// binary left over from an earlier build measures the product as it WAS. That
// is not a hypothetical: the abstract layer's scope change was measured
// against a stale binary here and reported the OLD scope, because the
// harness ran whatever `cli.exe` was on disk.
//
// The build is incremental, so on a warm tree it costs a second and prints
// "no work to do"; on a cold one it is the build the CI step would have done
// anyway. It happens BEFORE any timed run, so it never lands inside a
// measurement.
{
  const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 32 * 1024 * 1024,
    shell: true,
  });
  if (build.status !== 0) {
    console.error('the CLI build failed, so there is nothing to test:');
    console.error((build.stderr ?? '') + (build.stdout ?? ''));
    process.exit(2);
  }
}

let checks = 0;
let failures = 0;
const rows = [];
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

function runCli(label, args, timeoutMs = 180000) {
  const t0 = process.hrtime.bigint();
  const r = spawnSync(exe, args, { cwd: root, encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const stdout = r.stdout ?? '';
  const stderr = r.stderr ?? '';
  rows.push({ label, exit: r.status, ms: Math.round(ms), timedOut: r.error?.code === 'ETIMEDOUT' });
  check(`${label}: completed without timeout`, r.error?.code !== 'ETIMEDOUT', `${Math.round(ms)} ms`);
  check(`${label}: exit code 0`, r.status === 0, `exit=${r.status}${r.error ? ' ' + r.error.code : ''}`);
  if (r.status !== 0 && (stdout + stderr).trim() !== '') {
    console.log(`      stderr: ${(stdout + stderr).trim().split(/\r?\n/).slice(0, 3).join(' | ')}`);
  }
  return { stdout, stderr, ms };
}

const summaryOf = (dir, stem) => JSON.parse(readFileSync(join(dir, `${stem}_summary.json`), 'utf8'));
const strip = (s) => {
  const { elapsed_ms, ...rest } = s;
  return JSON.stringify(rest, Object.keys(rest).sort());
};
const sliceNodes = (md) => {
  const sec = md.split('## 7. Program slicing')[1] ?? '';
  return (sec.match(/^\s+s\d+\[/gm) ?? []).length;
};

function assertArtefacts(label, dir, stem) {
  for (const suffix of ['.md', '_summary.json', '_trace.jsonl', '_findings.jsonl']) {
    check(`${label}: artefact ${stem}${suffix}`, existsSync(join(dir, stem + suffix)));
  }
}

// The findings tables are BOUNDED, so the report no longer holds every
// finding: the `_findings.jsonl` sidecar does. These two read the two
// artefacts and check they agree -- every finding the report SHOWS must be
// in the sidecar -- because a sidecar that disagreed with the report would
// be worse than no sidecar at all.
//
// A findings row is a seven-column table row whose first column is a family
// code and whose fourth is `file:line`. The count table above a truncated
// table is two columns, the header and the separator are not family codes,
// and the truncation marker starts with `...`, so none of them is mistaken
// for a finding.
function findingsRows(md) {
  const rows = [];
  for (const line of md.split('\n')) {
    if (!line.startsWith('| ')) continue;
    const cells = line.slice(1, -1).split('|').map((c) => c.trim());
    if (cells.length !== 7) continue;
    if (!/^[A-Z][A-Z-]+$/.test(cells[0])) continue;
    const at = /^(.+):(\d+)$/.exec(cells[3]);
    if (!at) continue;
    rows.push({ rule: cells[0], fn: cells[2], file: at[1], line: Number(at[2]) });
  }
  return rows;
}

function sidecarEntries(dir, stem) {
  const p = join(dir, `${stem}_findings.jsonl`);
  if (!existsSync(p)) return [];
  return readFileSync(p, 'utf8')
    .split('\n')
    .filter((l) => l.trim() !== '')
    .map((l) => JSON.parse(l));
}

function checkSidecar(label, dir, stem, md, summary) {
  const rows = findingsRows(md);
  const entries = sidecarEntries(dir, stem);
  const key = (r) => `${r.rule}|${r.fn}|${r.file}|${r.line}`;
  const have = new Set(entries.map((e) => `${e.rule}|${e.fn}|${e.file}|${e.line}`));
  const missing = rows.filter((r) => !have.has(key(r)));
  check(
    `${label}: every finding the report shows is in the findings sidecar`,
    missing.length === 0,
    missing.length ? `${missing.length} missing, first: ${key(missing[0])}` : `${rows.length} rows, ${entries.length} entries`,
  );
  check(
    `${label}: the sidecar's count agrees with the summary`,
    summary.findings === entries.length,
    `summary ${summary.findings} vs sidecar ${entries.length}`,
  );
  check(
    `${label}: every sidecar entry names a family and a location`,
    entries.every((e) => typeof e.rule === 'string' && e.rule !== '' && typeof e.file === 'string' && Number.isInteger(e.line)),
    `${entries.length} entries`,
  );
}

// --- fixture, twice into the same dir, for determinism -------------------
const f1 = join(outRoot, 'det');
const f2 = join(outRoot, 'det');
runCli('fixture run1', ['analyze', '--dir', 'fixtures/vuln_demo', '--out', f1, '--funnel', '--slice', 'i@copy_prefix']);

const stem = 'local_module_0.0.0';
assertArtefacts('fixture', f1, stem);
const detSummary1 = existsSync(join(f1, `${stem}_summary.json`))
  ? readFileSync(join(f1, `${stem}_summary.json`), 'utf8')
  : '';
const detReport1 = existsSync(join(f1, `${stem}.md`)) ? readFileSync(join(f1, `${stem}.md`), 'utf8') : '';
const detTrace1 = existsSync(join(f1, `${stem}_trace.jsonl`))
  ? readFileSync(join(f1, `${stem}_trace.jsonl`), 'utf8')
  : '';

runCli('fixture run2', ['analyze', '--dir', 'fixtures/vuln_demo', '--out', f2, '--funnel', '--slice', 'i@copy_prefix']);

if (existsSync(join(f1, `${stem}_summary.json`))) {
  const detSummary2 = readFileSync(join(f1, `${stem}_summary.json`), 'utf8');
  const detReport2 = readFileSync(join(f1, `${stem}.md`), 'utf8');
  const detTrace2 = readFileSync(join(f1, `${stem}_trace.jsonl`), 'utf8');
  const s1 = JSON.parse(detSummary1);
  const s2 = JSON.parse(detSummary2);
  check('A13 determinism: summaries identical except elapsed_ms', strip(s1) === strip(s2), `elapsed ${s1.elapsed_ms} vs ${s2.elapsed_ms} ms`);
  check('A13 determinism: trace JSONL byte-identical', detTrace1 === detTrace2, `${detTrace1.length} B`);
  const mdNormalized = (md) => md.replace(/\d+(?:\.\d+)?\s*ms/g, '<ms>');
  check('A13 determinism: report identical except timing figures', mdNormalized(detReport1) === mdNormalized(detReport2));
  check('A6 dead code == 3', s1.dead_code === 3, `${s1.dead_code}`);
  check('A6 unreachable == 1', s1.unreachable === 1, `${s1.unreachable}`);
  check('A7 infinite loop >= 1', s1.infinite_loop >= 1, `${s1.infinite_loop}`);
  check('A8 taint sinks >= 1', s1.taint_sinks >= 1, `${s1.taint_sinks}`);
  check('A15 abstract findings >= 1', s1.abstract_findings >= 1, `${s1.abstract_findings}`);
  check('A16 L3 proved >= 1', s1.vcs_proved >= 1, `${s1.vcs_proved}`);
  check('A16 L3 failed >= 1', s1.vcs_failed >= 1, `${s1.vcs_failed}`);
  check('A18 funnel implies level 3', s1.level === 3, `L${s1.level}`);
  check('A4 frontend coverage >= 95%', s1.statements / (s1.statements + s1.unsupported_statements) >= 0.95);
  checkSidecar('fixture', f1, stem, detReport1, s1);
}
const fixtureMd = join(f1, `${stem}.md`);
if (existsSync(fixtureMd)) {
  const md = readFileSync(fixtureMd, 'utf8');
  check('A10 fixture slice has >= 1 node', sliceNodes(md) >= 1, `${sliceNodes(md)}`);
  check('A17 funnel diagram present', /flowchart LR[\s\S]*L1\[/.test(md));
  const ten = ['## 1.', '## 2.', '## 3.', '## 4.', '## 5.', '## 6.', '## 7.', '## 8.', '## 9.', '## 10.'];
  check('report has all ten sections', ten.every((h) => md.includes(h)));
  check('A12 fixture report <= 512 KB', statSync(fixtureMd).size <= 512 * 1024, `${statSync(fixtureMd).size} B`);
}

// --- registry modules ----------------------------------------------------
const modules = skipModules
  ? []
  : [
      {
        label: 'doubleML',
        coord: 'riantr/moonbit_doubleML@latest',
        stemPrefix: 'riantr_moonbit_doubleML@latest_',
        slice: 'theta_hat@aggregate_coef_se',
        minSlice: 4,
        // The statement count used to be 43822, and that number was wrong
        // twice over: the parser shredded every construct it did not model
        // into one statement per fragment, and a shredded fragment ate the
        // closing brace of its function, so whole function bodies were
        // truncated. Both are fixed, and the honest count for 0.164.64 is
        // 29853. The floor stays a scale check, not a count check.
        minStmts: 25000,
      },
      {
        label: 'static_analysis',
        coord: 'riantr/moonbit_static_analysis@latest',
        stemPrefix: 'riantr_moonbit_static_analysis@latest_',
        slice: 'buf@render_reports',
        minSlice: 1,
        // A scale check, not a count check: the statement count used to be
        // 43822 for doubleML, and that number was wrong twice over -- the
        // parser shredded every construct it did not model into one statement
        // per fragment, and a shredded fragment ate the closing brace of its
        // function, so whole function bodies were truncated. Both are fixed.
        //
        // The floor moves with the module's own releases: this module's
        // statement count was 11,750 at 0.4.45 and 17,428 at 0.5.0. The floor
        // is set low enough that it survives a release, because what it is
        // really testing is that the analyser READ the module at all.
        minStmts: 7000,
      },
    ];

for (const mod of modules) {
  const dir = join(outRoot, mod.label);
  // THE OUTPUT DIRECTORY IS EMPTIED BEFORE THE RUN. The artefact names carry
  // the resolved version, so a directory that has been used before holds one
  // set of files PER VERSION, and `readdirSync().find()` returns the first
  // match -- which is the OLDEST one, not the one this run just wrote.
  //
  // MEASURED: on 2026-11-19 the run wrote `..._0.5.0.md` and the harness
  // measured `..._0.4.45.md`, dated nine days earlier, because that file
  // sorted first. Every count the harness reported for this module -- the
  // statement count, the report size, the L2 finding count, even the
  // "resolved version" -- was a week-old number, and the run still passed.
  // A clean directory makes the only files present the ones this run wrote.
  rmSync(dir, { recursive: true, force: true });
  const { ms } = runCli(mod.label, [
    'analyze',
    mod.coord,
    '--out',
    dir,
    '--funnel',
    '--slice',
    mod.slice,
    '--function',
    mod.slice.split('@')[1],
  ]);
  if (!existsSync(dir)) continue;
  const mdName = readdirSync(dir).find((f) => f.startsWith(mod.stemPrefix) && f.endsWith('.md'));
  if (!mdName) {
    check(`${mod.label}: report written`, false, 'no .md produced');
    continue;
  }
  const version = mdName.slice(mod.stemPrefix.length, -3);
  const summary = summaryOf(dir, mdName.slice(0, -3));
  const md = readFileSync(join(dir, mdName), 'utf8');
  check(`${mod.label} A3: resolved version recorded`, summary.version === version, version);
  check(`${mod.label} A4: frontend coverage >= 95%`, summary.statements / (summary.statements + summary.unsupported_statements) >= 0.95, `${((100 * summary.statements) / (summary.statements + summary.unsupported_statements)).toFixed(2)}%`);
  check(`${mod.label}: statements >= ${mod.minStmts}`, summary.statements >= mod.minStmts, `${summary.statements}`);
  check(`${mod.label} A10: slice nodes >= ${mod.minSlice}`, sliceNodes(md) >= mod.minSlice, `${sliceNodes(md)}`);
  check(`${mod.label} A11: wall time <= 60 s`, ms <= 60000, `${Math.round(ms)} ms`);
  check(`${mod.label} A12: report <= 512 KB`, statSync(join(dir, mdName)).size <= 512 * 1024, `${statSync(join(dir, mdName)).size} B`);
  const trace = readdirSync(dir).find((f) => f.endsWith('_trace.jsonl'));
  const traceBytes = trace ? statSync(join(dir, trace)).size : 0;
  check(`${mod.label} A12: trace <= 64 MB`, traceBytes <= 64 * 1024 * 1024, `${(traceBytes / 1024 / 1024).toFixed(1)} MB`);
  check(`${mod.label} A15: abstract findings >= 1`, summary.abstract_findings >= 1, `${summary.abstract_findings}`);
  check(`${mod.label} A17: funnel diagram present`, /flowchart LR[\s\S]*L1\[/.test(md));
  check(`${mod.label} A9: per-point table non-empty`, /### 6\.1 Per-program-point observations[\s\S]*?\n\| /.test(md));
  checkSidecar(mod.label, dir, mdName.slice(0, -3), md, summary);
}

// --- full-size run (no --function): A11/A12 at documented scale ----------
if (!skipModules) {
  const full = join(outRoot, 'doubleML-full');
  // The same reason as the module runs above: the directory accumulates one
  // set of files per resolved version, and only this run's files may be read.
  rmSync(full, { recursive: true, force: true });
  const { ms } = runCli('doubleML full', [
    'analyze',
    'riantr/moonbit_doubleML@latest',
    '--out',
    full,
    '--funnel',
    '--slice',
    'theta_hat@aggregate_coef_se',
  ]);
  if (existsSync(full)) {
    const mdName = readdirSync(full).find((f) => f.endsWith('.md'));
    if (mdName) {
      const summary = summaryOf(full, mdName.slice(0, -3));
      const mdBytes = statSync(join(full, mdName)).size;
      const trace = readdirSync(full).find((f) => f.endsWith('_trace.jsonl'));
      const traceBytes = trace ? statSync(join(full, trace)).size : 0;
      check('doubleML full A11: wall time <= 60 s', ms <= 60000, `${Math.round(ms)} ms`);
      check('doubleML full A12: report <= 512 KB', mdBytes <= 512 * 1024, `${mdBytes} B`);
      // The trace grew because the analyzer now understands more of the
      // module: 350906 events and 59.2 MB became 387638 events and 70.3 MB.
      // The cap moves with it, and the headroom is for a future release of
      // the module.
      check('doubleML full A12: trace <= 96 MB', traceBytes <= 96 * 1024 * 1024, `${(traceBytes / 1024 / 1024).toFixed(1)} MB`);
      check('doubleML full: trace events > 100k', summary.trace_events > 100000, `${summary.trace_events}`);
      // doubleML has no unreachable statements, and the analyzer now says so.
      // The floor it used to carry -- 100 findings -- was the shredding bug:
      // every fragment that followed a `return` was one row, and the module
      // produced 137 of them. The check is a ceiling now, and it is the
      // regression guard for the shredding.
      check('doubleML full: dead code findings <= 5', summary.dead_code <= 5, `${summary.dead_code}`);
      check('doubleML full: taint sinks >= 100', summary.taint_sinks >= 100, `${summary.taint_sinks}`);
      // The L2 count moved from 127 to 204 for the same reason: the abstract
      // interpreter sees the code now. It moved again, from 187 to 1282, when
      // the abstract layer's scope stopped being the interpreter's entry-point
      // cap and became the WHOLE module: the committed artefact is the
      // full-scope run, and 1282 is its number.
      //
      // And it moved AGAIN, from 1282 to 3316, when two defects were
      // repaired: the allocation rules matched only the `::` spelling while
      // the parser renders a qualified path with a DOT, so the
      // allocation-size family could not fire at all (it appeared ZERO times
      // in the committed artefacts); and the de-duplication key had no file
      // in it, so a finding in one file could be dropped as a duplicate of
      // one in another. Both were measured, and the count is the number the
      // repaired tree produces.
      //
      // And it moved AGAIN, from 3316 to 3305, when the blanket loop rule was
      // removed: the rule tainted every number a tainted loop condition read,
      // and the counter is not one of the tainted values -- the BOUND is. The
      // 11 findings the rule alone carried were false, and at every one of
      // their sites the layer already reported the honest claim, an index
      // out of bounds. See `docs/qa/IFDS_PHASE1.md`.
      //
      // And once more, from 3305 to 3321, when the value domain was repaired:
      // a boolean LITERAL was modelled as a value that can be NEITHER true nor
      // false, and the contradiction pruned the branches it guarded -- so the
      // allocation sites inside a pruned loop body were never seen. The repair
      // brought 16 findings back, and took 3 false positives away; the net is
      // the number the repaired tree produces.
      check('doubleML full: L2 findings within 50% of documented 3321', Math.abs(summary.abstract_findings - 3321) <= 1661, `${summary.abstract_findings}`);
      checkSidecar('doubleML full', full, mdName.slice(0, -3), readFileSync(join(full, mdName), 'utf8'), summary);
    }
  }
}

console.log('\n| run | exit | ms |');
console.log('| --- | ---: | ---: |');
for (const r of rows) console.log(`| ${r.label} | ${r.exit} | ${r.ms} |`);
console.log(`\nRESULT: ${checks - failures}/${checks} checks passed, ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
