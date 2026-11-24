#!/usr/bin/env node
// MEASURE (A) THE ANALYSIS CAP and (B) THE PUBLISH CEILING.
//
// (A) Does the per-package mode get past the module-wide step budget?  On
//     three corpora, in three modes:
//
//       wide  the default: one budget for the whole module
//       per   --per-package: one budget PER PACKAGE
//       free  --per-function: no budget at all -- the ceiling of what the
//             analyser can do, and the reference the other two are read
//             against
//
// (B) Does the per-package mode get past the publish ceiling?  The ceiling
//     is the envelope the registry has ALREADY accepted, read from
//     `docs/qa/PUBLISH_ENVELOPE.json`: the total unpacked size and the
//     largest single entry.  The per-package mode splits the TRACE into one
//     file per package, so the question is what the split does to those two
//     numbers.
//
// Every number here is MEASURED: the counts come from the analyser's own
// metrics, the sizes from the files on disk, and the ceiling from the
// record -- never from a constant written here.
//
// THE RESULT IS TRACKED, at `docs/qa/PER_PACKAGE_MEASUREMENTS.json`, because
// the README publishes these numbers: a published measurement whose driver
// lives only in a scratch directory cannot be re-derived by a reader, and a
// published measurement that cannot be re-derived is a claim.
//
// The corpora are the ones the registry serves, fetched into `.repos/`.  A
// pinned version is used when it is there; otherwise the newest version that
// IS there is used, and the version that was actually measured is recorded in
// the artefact -- so a re-run on a newer corpus says so instead of silently
// reporting the old numbers.
//
// Usage: node scripts/qa/measure_per_package.mjs [--out <file>] [--skip-free]
//
//   --out <file>    write the artefact somewhere else
//   --skip-free     skip the uncapped runs (they are the slow ones)
//
// This is NOT a gate step: it needs the corpora fetched and it measures
// three uncapped runs over them.  It is the command that produced the
// numbers the README publishes.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const EXE = requireCli(ROOT);
const WORK = join(ROOT, '_build', 'qa', 'per_package_measure');

const argValue = (flag) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const OUT = argValue('--out') ?? join(ROOT, 'docs', 'qa', 'PER_PACKAGE_MEASUREMENTS.json');
const SKIP_FREE = process.argv.includes('--skip-free');

// The ceiling, read from the record the release published.
const ENVELOPE = JSON.parse(readFileSync(join(ROOT, 'docs', 'qa', 'PUBLISH_ENVELOPE.json'), 'utf8'));
const MAX_TOTAL = ENVELOPE.reference_unpacked_bytes;
const MAX_ENTRY = ENVELOPE.reference_largest_entry_bytes;

// --- the corpora ------------------------------------------------------------
//
// The version is PINNED, and the pin is the version the published numbers
// were measured on.  When the pinned one is not there, the newest one that is
// there is used and the artefact records which -- so the numbers always name
// the corpus they came from.

///|
/// Compare two dotted version strings numerically, part by part.
function compareVersions(a, b) {
  const pa = a.split('.').map((x) => Number(x) || 0);
  const pb = b.split('.').map((x) => Number(x) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

///|
/// The directory of a fetched corpus, and the version that was really there.
///
/// The path is written with FORWARD slashes, so the tracked artefact reads
/// the same on every platform; the analyser takes a forward-slash path on
/// Windows as well.
function resolveCorpus(moduleName, pinnedVersion) {
  const base = join(ROOT, '.repos', 'riantr', moduleName);
  const pinned = join(base, pinnedVersion);
  if (existsSync(pinned)) {
    return { dir: `.repos/riantr/${moduleName}/${pinnedVersion}`, version: pinnedVersion };
  }
  if (!existsSync(base)) return null;
  const versions = readdirSync(base)
    .filter((v) => statSync(join(base, v)).isDirectory())
    .sort(compareVersions);
  if (versions.length === 0) return null;
  const v = versions[versions.length - 1];
  return { dir: `.repos/riantr/${moduleName}/${v}`, version: v };
}

///|
/// One field of `moon.mod`.  The manifest is NOT json -- it is `key = "value"`
/// lines with `//` comments -- so it is read as what it is.
function manifestField(key) {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*"([^"]*)"`);
  for (const line of readFileSync(join(ROOT, 'moon.mod'), 'utf8').split(/\r?\n/)) {
    const m = re.exec(line);
    if (m) return m[1];
  }
  return null;
}

const MODULE_NAME = manifestField('name');
const MODULE_VERSION = manifestField('version');

const CORPORA = [
  { key: 'this tree', module: MODULE_NAME, version: MODULE_VERSION, dir: '.', pinned: null },
  {
    key: 'static_analysis',
    module: 'riantr/moonbit_static_analysis',
    version: null,
    dir: null,
    pinned: '0.5.4',
  },
  {
    key: 'doubleML',
    module: 'riantr/moonbit_doubleML',
    version: null,
    dir: null,
    // The version the REGISTRY serves: it moved 0.164.64 -> 0.164.66, and the
    // committed artefact was regenerated against the corpus the registry
    // serves now, so the measurement must describe the same corpus.
    pinned: '0.164.66',
  },
];

for (const c of CORPORA) {
  if (c.pinned === null) continue;
  const found = resolveCorpus(c.module.replace('riantr/', ''), c.pinned);
  if (!found) {
    console.error(`the corpus ${c.module} is not fetched: ${join('.repos', 'riantr', c.module.replace('riantr/', ''))}`);
    console.error('fetch it first:  moon add ' + c.module);
    process.exit(2);
  }
  c.dir = found.dir;
  c.version = found.version;
}

const MODES = [
  // The MODULE-WIDE mode is asked for by NAME: it used to be what a scan with
  // no flags did, and it is not any more.
  { name: 'wide', args: ['--module-wide'] },
  // The per-package mode is asked for by name too, even though it is now the
  // DEFAULT: a measurement that named the mode it measured could not be
  // confused with a measurement of the default.
  { name: 'per', args: ['--per-package'] },
  { name: 'free', args: ['--per-function'] },
];

function metrics(text, lens) {
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

function line(text, label) {
  for (const raw of text.split(/\r?\n/)) {
    if (raw.startsWith(label + '\t')) return raw.slice(label.length + 1);
  }
  return null;
}

function reportFact(report, label) {
  const m = new RegExp(`^\\|\\s*${label}\\s*\\|\\s*(.*?)\\s*\\|\\s*$`, 'm').exec(report);
  return m ? m[1] : null;
}

function run(corpus, mode, trials) {
  const out = join(WORK, corpus.key.replace(/[^A-Za-z0-9]+/g, '_'), mode.name);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  const started = Date.now();
  const r = spawnSync(
    EXE,
    ['analyze', '--dir', corpus.dir, '--out', out, '--trials', String(trials), '--metrics', ...mode.args],
    { cwd: ROOT, encoding: 'utf8', timeout: 1800000, maxBuffer: 64 * 1024 * 1024 },
  );
  const wall = Date.now() - started;
  if (r.status !== 0) {
    console.error(`the ${corpus.key} ${mode.name} run failed (${r.status}):`);
    console.error(((r.stderr ?? '') + (r.stdout ?? '')).split(/\r?\n/).slice(0, 6).join('\n'));
    return null;
  }
  const text = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const reportFile = readdirSync(out).find((f) => f.endsWith('.md'));
  const report = reportFile ? readFileSync(join(out, reportFile), 'utf8') : '';

  // The traces: their number, their total size, their largest, and how many
  // DISTINCT FILES they name -- the file coverage, measured from the trace
  // itself.
  const traces = readdirSync(out).filter((f) => f.endsWith('_trace.jsonl'));
  let totalBytes = 0;
  let largest = { name: '', bytes: 0 };
  const files = new Set();
  for (const f of traces) {
    const bytes = statSync(join(out, f)).size;
    totalBytes += bytes;
    if (bytes > largest.bytes) largest = { name: f, bytes };
    const body = readFileSync(join(out, f), 'utf8');
    for (const l of body.split('\n')) {
      if (!l.trim()) continue;
      try {
        const o = JSON.parse(l);
        if (typeof o.file === 'string') files.add(o.file);
      } catch {
        /* a line that is not JSON is not a file name */
      }
    }
  }

  const funcs = metrics(text, 'funcs');
  const pkgs = metrics(text, 'packages');
  const filesParsed = Number(reportFact(report, 'Source files parsed'));
  return {
    mode: mode.name,
    wall_ms: wall,
    functions: funcs ? Number(funcs.functions) : null,
    entered: funcs ? Number(funcs.entered) : null,
    skipped: funcs ? Number(funcs.skipped) : null,
    step_budget: funcs ? Number(funcs['step-budget']) : null,
    steps: funcs ? Number(funcs.steps) : null,
    stopped_by: funcs ? funcs['stopped-by'] : null,
    packages: pkgs ? Number(pkgs.packages) : null,
    packages_budget_spent: pkgs ? Number(pkgs['budget-spent']) : null,
    events: Number(line(text, 'trace_events') ?? 0),
    taint_sinks: Number(line(text, 'taint_sinks') ?? 0),
    findings_total: metrics(text, 'findings') ? Number(metrics(text, 'findings').total) : null,
    files_parsed: filesParsed,
    files_interpreted: files.size,
    file_coverage: filesParsed ? files.size / filesParsed : null,
    trace_files: traces.length,
    trace_total_bytes: totalBytes,
    trace_largest_bytes: largest.bytes,
    trace_largest_name: largest.name,
  };
}

const results = [];
for (const corpus of CORPORA) {
  for (const mode of MODES) {
    if (mode.name === 'free' && SKIP_FREE) continue;
    console.error(`--- ${corpus.key}@${corpus.version} :: ${mode.name}`);
    const r = run(corpus, mode, 4);
    if (!r) process.exit(2);
    results.push({
      corpus: corpus.key,
      module: corpus.module,
      version: corpus.version,
      dir: corpus.dir,
      ...r,
    });
    console.error(
      `    entered=${r.entered} steps=${r.steps} events=${r.events} files=${r.files_interpreted}/${r.files_parsed} packages=${r.packages} traces=${r.trace_files} bytes=${r.trace_total_bytes} largest=${r.trace_largest_bytes}`,
    );
  }
}

// The toolchain that measured it: the numbers belong to a parser, and the
// parser has a version.
const moonVersion = (() => {
  // The command is a STRING, with no argument array: passing an array with
  // `shell: true` makes node concatenate the arguments without escaping
  // them, and it says so.
  const r = spawnSync('moon version', { encoding: 'utf8', shell: true });
  return (r.stdout ?? '').trim() || null;
})();

const summary = {
  // The LOCAL date, not the UTC one: this project's dates are the reader's
  // local dates, and a run made after midnight local must not be stamped with
  // yesterday.
  measured_at: (() => {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, '0');
    const d = String(now.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  })(),
  moon_version: moonVersion,
  envelope: {
    max_total_unpacked_bytes: MAX_TOTAL,
    max_largest_entry_bytes: MAX_ENTRY,
    source: 'docs/qa/PUBLISH_ENVELOPE.json',
  },
  corpora: CORPORA.map((c) => ({
    key: c.key,
    module: c.module,
    version: c.version,
    dir: c.dir,
  })),
  results,
};
mkdirSync(join(ROOT, 'docs', 'qa'), { recursive: true });
writeFileSync(OUT, JSON.stringify(summary, null, 2), 'utf8');

console.log('');
console.log('corpus                   mode   entered    steps     events  files     packages  traces  total bytes  largest entry');
for (const r of results) {
  console.log(
    `${r.corpus.padEnd(24)} ${r.mode.padEnd(6)} ${String(r.entered).padStart(7)} ${String(r.steps).padStart(9)} ${String(r.events).padStart(10)}  ${String(r.files_interpreted + '/' + r.files_parsed).padStart(8)} ${String(r.packages ?? '-').padStart(8)} ${String(r.trace_files).padStart(7)} ${String(r.trace_total_bytes).padStart(12)} ${String(r.trace_largest_bytes).padStart(14)}`,
  );
}
console.log('');
console.log(`the ceiling: total <= ${MAX_TOTAL} bytes, largest entry <= ${MAX_ENTRY} bytes`);
for (const r of results) {
  console.log(
    `${r.corpus} ${r.mode}: total ${r.trace_total_bytes <= MAX_TOTAL ? 'WITHIN' : 'OVER'} the ceiling, largest entry ${r.trace_largest_bytes <= MAX_ENTRY ? 'WITHIN' : 'OVER'} it`,
  );
}
console.log('');
console.log(`written to ${OUT}`);
