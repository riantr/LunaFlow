#!/usr/bin/env node
// Load and resource measurement: peak working set per run, and parallel
// throughput against sequential for the same unit of work.
//
// There is no server in this project, so "load" means: N concurrent analyzer
// processes competing for CPU and disk, plus the peak memory of the heaviest
// documented run.
//
// Usage: node scripts/qa/load.mjs [--parallel 4] [--skip-modules]
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = resolveCli(root);
const outRoot = join(root, '_build', 'qa', 'load');
mkdirSync(outRoot, { recursive: true });
const parIdx = process.argv.indexOf('--parallel');
const PAR = parIdx >= 0 ? Number(process.argv[parIdx + 1]) : 4;
const skipModules = process.argv.includes('--skip-modules');

if (!existsSync(exe)) {
  console.error('missing CLI binary; run: moon build src/cli --target native');
  process.exit(2);
}

// --- peak working set via a PowerShell wrapper ------------------------------
// Start-Process -Wait loses the counters once the child exits (PeakWorkingSet64
// reads back as 0), so sample WorkingSet64 while the process is alive and keep
// the maximum. Child stdout is redirected so it cannot pollute the measurement.
function peakMemoryMb(args, cwd = root, logName = 'mem') {
  const log = join(outRoot, `${logName}.log`);
  const argList = args.map((a) => `'${a.replace(/'/g, "''")}'`).join(',');
  const ps = [
    "$ErrorActionPreference='Stop'",
    `$p = Start-Process -FilePath '${exe}' -ArgumentList @(${argList}) -WorkingDirectory '${cwd}' -PassThru -NoNewWindow -RedirectStandardOutput '${log}' -RedirectStandardError '${log}.err'`,
    `$max = 0`,
    `while (-not $p.HasExited) { $p.Refresh(); if ($p.WorkingSet64 -gt $max) { $max = $p.WorkingSet64 }; Start-Sleep -Milliseconds 40 }`,
    `[math]::Round($max/1MB,1)`,
  ].join('; ');
  const r = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command', ps], {
    encoding: 'utf8',
    timeout: 300000,
  });
  const mb = Number((r.stdout ?? '').trim());
  return Number.isFinite(mb) && mb > 0 ? mb : NaN;
}

function runOnce(args, cwd = root) {
  const t0 = process.hrtime.bigint();
  const r = spawnSync(exe, args, { cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024 });
  return { ms: Number(process.hrtime.bigint() - t0) / 1e6, ok: r.status === 0 };
}

function runMany(argsList) {
  const t0 = process.hrtime.bigint();
  return Promise.all(
    argsList.map(
      (args) =>
        new Promise((resolve) => {
          const p = spawn(exe, args, { cwd: root });
          let err = '';
          p.stderr.on('data', (d) => (err += d));
          p.on('close', (code) => resolve({ ok: code === 0, err }));
        }),
    ),
  ).then((rs) => ({ ms: Number(process.hrtime.bigint() - t0) / 1e6, results: rs }));
}

const report = [];

// --- memory ----------------------------------------------------------------
if (!skipModules) {
  const memArgs = ['analyze', 'riantr/moonbit_doubleML@latest', '--out', join(outRoot, 'mem'), '--funnel'];
  const mb = peakMemoryMb(memArgs);
  report.push({ what: 'doubleML full run', peakMb: mb });
  console.log(`peak working set, doubleML full run: ${mb} MB`);
}
const memFixture = peakMemoryMb(['analyze', '--dir', 'fixtures/vuln_demo', '--out', join(outRoot, 'memfix'), '--funnel']);
console.log(`peak working set, fixture run: ${memFixture} MB`);
report.push({ what: 'fixture run', peakMb: memFixture });

// --- parallel vs sequential ------------------------------------------------
if (!skipModules) {
  const unit = (i) => [
    'analyze',
    'riantr/moonbit_doubleML@latest',
    '--function',
    'aggregate_coef_se',
    '--out',
    join(outRoot, `par${i}`),
  ];
  const seq = [];
  for (let i = 0; i < PAR; i += 1) seq.push(runOnce(unit(i)));
  const seqMs = seq.reduce((a, x) => a + x.ms, 0);
  const par = await runMany(Array.from({ length: PAR }, (_, i) => unit(i)));
  const allOk = par.results.every((r) => r.ok) && seq.every((r) => r.ok);
  console.log(`\nsequential ${PAR} × 1.4 s runs: ${Math.round(seqMs)} ms (sum of wall times)`);
  console.log(`parallel  ${PAR} concurrent runs: ${Math.round(par.ms)} ms`);
  console.log(`speedup: ${(seqMs / par.ms).toFixed(2)}×  all runs ok: ${allOk}`);
  report.push({ what: `parallel ${PAR}`, seqMs: Math.round(seqMs), parMs: Math.round(par.ms), allOk });
}

const summary = readFileSync(join(root, '_build', 'qa', 'fuzz_results.json'), 'utf8');
console.log(`\nfuzz corpus reference: ${JSON.parse(summary).cases.length} cases on record`);
console.log('\n| measurement | value |');
console.log('| --- | --- |');
for (const r of report) {
  if (r.peakMb !== undefined) console.log(`| ${r.what}: peak working set | ${r.peakMb} MB |`);
  else console.log(`| ${r.what}: sequential vs parallel | ${r.seqMs} ms → ${r.parMs} ms (${(r.seqMs / r.parMs).toFixed(2)}×) |`);
}
