#!/usr/bin/env node
// THE PACKAGE ENVELOPE CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier feeds
// `scripts/qa/package_envelope.mjs` a MODEL -- the file set the check builds
// for itself -- and asserts that the same check goes RED on each mutation.
// The tracked tree is never written: every model is a JSON file under
// `_build/`.
//
// The model the mutations start from is the one the CHECK measured
// (`--dump-model`), not a hand-written copy: a second copy of the rule would
// be a second source of truth, and the falsifier would be proving something
// about its own copy.
//
// The mutations are the ways the package could be wrong while still looking
// fine:
//
//   F1  the package carries more unpacked bytes than the registry has accepted
//   F2  the package carries ONE file bigger than the registry has accepted
//   F3  a report, a sidecar or a summary is not packed at all
//   F4  a raw trace IS packed -- the thing that broke the 0.1.35 upload
//   F5  a raw trace is not tracked, so the evidence is not in the repository
//   F6  there is NO raw trace at all -- the check must not pass vacuously
//
// It also runs a CONTROL: a model that differs from the truth in a way that
// says nothing about the envelope (one more small file), which the checker
// must NOT notice.  Without the control, a checker that failed on every
// possible edit would look like a checker that works.
//
// Usage: node scripts/qa/package_envelope_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = join(ROOT, 'scripts', 'qa', 'package_envelope.mjs');
const WORK = join(ROOT, '_build', 'qa', 'package_envelope_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });

// --- the truth, measured by the check itself --------------------------------

const truthFile = join(WORK, 'truth.json');
{
  const r = spawnSync(process.execPath, [CHECK, '--dump-model', truthFile], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (r.status !== 0 || !existsSync(truthFile)) {
    console.error('the model could not be measured, so there is nothing to falsify:');
    console.error((r.stderr ?? '') + (r.stdout ?? ''));
    process.exit(2);
  }
}
const TRUTH = JSON.parse(readFileSync(truthFile, 'utf8'));

/// Write a model and run the real check on it.
function runModel(name, model, expect) {
  const file = join(WORK, `${name}.json`);
  writeFileSync(file, JSON.stringify(model, null, 2), 'utf8');
  const r = spawnSync(process.execPath, [CHECK, '--packed', file], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 600000,
    maxBuffer: 32 * 1024 * 1024,
  });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  if (expect === null) {
    const green = r.status === 0;
    check(`${name}: the check stays green`, green, `exit=${r.status}`);
    if (!green) console.log(out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
    return;
  }
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
  }
}

const clone = (model) => JSON.parse(JSON.stringify(model));

// The truth has to PASS, or every mutation below would "go red" for the wrong
// reason: a falsifier that starts from a broken baseline proves nothing.
runModel('truth', clone(TRUTH), null);

// F1 -- the package carries more unpacked bytes than the registry accepted.
{
  const m = clone(TRUTH);
  m.packed = [...m.packed, { path: 'reports/a_big_trace.jsonl', bytes: 50_000_000 }];
  runModel('F1 a package over the unpacked ceiling', m, 'unpacked bytes');
}

// F2 -- one file bigger than the largest entry the registry accepted.
{
  const m = clone(TRUTH);
  m.packed = [...m.packed, { path: 'reports/a_big_trace.jsonl', bytes: 40_000_000 }];
  runModel('F2 a package with one entry over the ceiling', m, 'largest entry');
}

// F3 -- a report that is not packed at all.
{
  const m = clone(TRUTH);
  const report = 'reports/riantr_moonbit_doubleML@latest_0.164.64.md';
  m.artefacts = [...m.artefacts, { path: report }];
  m.packed = m.packed.filter((f) => f.path !== report);
  runModel('F3 a report that is not packed', m, 'every report, sidecar and summary is packed');
}

// F4 -- a raw trace IS packed: the thing that broke the 0.1.35 upload.
{
  const m = clone(TRUTH);
  m.packed = [
    ...m.packed,
    { path: 'reports/riantr_moonbit_doubleML@latest_0.164.64_trace.jsonl', bytes: 80_863_997 },
  ];
  runModel('F4 a raw trace in the package', m, 'no raw trace is packed');
}

// F5 -- a raw trace that is not tracked: the evidence is not in the repository.
{
  const m = clone(TRUTH);
  m.traces = m.traces.map((t) => ({ ...t, tracked: false }));
  runModel('F5 a raw trace that is not tracked', m, 'every raw trace is still tracked by git');
}

// F6 -- NO raw trace at all.  The check must not pass vacuously.
{
  const m = clone(TRUTH);
  m.traces = [];
  runModel('F6 no raw trace at all', m, 'every raw trace is still tracked by git');
}

// The CONTROL -- one more small file says nothing about the envelope.
{
  const m = clone(TRUTH);
  m.packed = [...m.packed, { path: 'reports/a_small_extra.jsonl', bytes: 1_234 }];
  runModel('control', m, null);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
