#!/usr/bin/env node
// THE VERSION `@latest` RESOLVES TO, and the one it must NOT resolve to.
//
// MEASURED BUG (2026-11-28): `moonx riantr/LunaFlow@latest moonbitlang/core@latest`
// analysed `moonbitlang/core` 0.1.20261102+97801ee1b -- the OLDEST of the three
// versions the fetch had written -- while the registry's latest was
// 0.1.20261126+3c0520448, twenty-four days newer.  The report named the older
// tree in its title, and every number in it described that older tree.
//
// WHY IT HAPPENED.  A toolchain module's version carries a build hash:
// "0.1.20261126+3c0520448".  The third segment is the NUMBER 20261126 and the
// hash is not part of it, but the comparison read the whole segment as a
// number, so every toolchain version degraded to [0, 1, 0], compared EQUAL to
// every other toolchain version, and the first directory in the list won.  The
// list is sorted, so the OLDEST won.
//
// THE CLAIM, AND WHY IT NEEDS A CONTROL.
//
//   The version the analyser analyses for `@latest` is the registry's latest,
//   and it is the NEWEST of the version directories the fetch wrote.
//
// The second half is the one with teeth, and it needs a CONTROL to be worth
// anything: a candidate list of ONE version cannot be ordered, so a check that
// only looks at the answer would pass on a list where the answer is the only
// possibility.  So this harness PLANTS A DECOY -- a version directory that is
// OLDER than the registry's latest, and that the analyser is therefore free to
// pick -- and then asserts that it did NOT pick it.  With the decoy in place
// the candidate list has a wrong answer in it, and the check says which one
// was taken.
//
// The decoy is planted in a PROBE, not in the repository's own `.repos/`: the
// probe is a scratch project under `_build/`, so nothing here can disturb the
// versions a user has already fetched, and the check's candidate list is
// exactly what the harness put there.
//
// THE ORACLE IS A SECOND IMPLEMENTATION.  The expected answer is computed by
// the ordering rule written again, here, in JavaScript -- not by calling the
// analyser's own code, which would make the check a tautology.  Two
// implementations of one rule, in two languages, that agree on the answer.
//
// The check needs the registry, so it can come back with NO VERDICT: exit 2
// means "could not decide", not "the tree is broken".  That is the convention
// the whole harness uses.
//
// Usage:
//   node scripts/qa/version_pin.mjs [--registry <version>] [--decoy <name>|none]
//
//   --registry <version>  the registry's latest version.  The default reads it
//                         from the registry's own JSON API.  A falsifier
//                         passes a version that cannot be fetched to prove the
//                         harness says UNKNOWN there and not PASS.
//   --decoy <name>        the version directory to plant.  The default is one
//                         derived from the registry's version: the same shape,
//                         one day older.  There is no mode without it: a
//                         candidate list of ONE version cannot be ordered, so
//                         a run without a control has nothing to decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const SCRATCH = join(ROOT, '_build', 'qa', 'version_pin');
const PROBE = join(SCRATCH, 'probe');
const OUT = join(SCRATCH, 'out');
const MODULE = 'moonbitlang/core';
const REGISTRY_API = 'https://mooncakes.io/api/v0/modules/moonbitlang/core';

const argv = process.argv.slice(2);
const option = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
};

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};
/// No verdict at all: the tree is NOT known to be broken.
const unknown = (why) => {
  console.error(`UNKNOWN  ${why}`);
  process.exit(2);
};

// ---------------------------------------------------------------------------
// THE ORDERING RULE, WRITTEN AGAIN, IN JAVASCRIPT.
//
// This is the ORACLE: it must not be the analyser's own code, or the check
// would be comparing the analyser with itself.  A version segment is read as
// its LEADING NUMBER -- "20261126+3c0520448" is the number 20261126 -- and the
// segments are compared as numbers, with the whole string as the tie-break.
// ---------------------------------------------------------------------------
function leadingInt(text) {
  const s = String(text).trim();
  let value = 0;
  for (const ch of s) {
    if (ch < '0' || ch > '9') break;
    value = value * 10 + (ch.charCodeAt(0) - 48);
  }
  return value;
}

function versionParts(version) {
  const parts = String(version).split('.').map(leadingInt);
  while (parts.length < 3) parts.push(0);
  return parts;
}

function compareVersions(a, b) {
  const pa = versionParts(a);
  const pb = versionParts(b);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i += 1) {
    const x = i < pa.length ? pa[i] : 0;
    const y = i < pb.length ? pb[i] : 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

function pinVersion(versions) {
  let best = '';
  for (const v of versions) {
    if (best === '' || compareVersions(v, best) > 0) best = v;
  }
  return best;
}

/// A version that is strictly OLDER than `version` and has the same shape.
function olderVersion(version) {
  const parts = String(version).split('.');
  const last = parts[parts.length - 1] ?? '0';
  const digits = /^(\d+)/.exec(last);
  const n = digits ? Number(digits[1]) : 0;
  const older = Math.max(0, n - 1);
  const head = parts.slice(0, -1).concat([String(older)]).join('.');
  return `${head}+000000000`;
}

// ---------------------------------------------------------------------------
// THE REGISTRY'S LATEST VERSION.
//
// The registry's own JSON API, the same source `core_compat.mjs` reads: it
// NAMES the version, so nothing has to be parsed out of a log line.
// ---------------------------------------------------------------------------
async function registryLatest() {
  const given = option('--registry', '');
  if (given !== '') return given;
  // The registry query is retried: a network blip is not a verdict about the
  // tree, and a gate that blocks on a blip is a gate nobody trusts. MEASURED
  // 2026-11-28: the first query after the pre-fix run failed with
  // "fetch failed" and the retry answered.
  let last = '';
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    let res;
    try {
      res = await fetch(REGISTRY_API);
    } catch (e) {
      last = `the registry could not be reached: ${e && e.message ? e.message : e}`;
      continue;
    }
    if (!res.ok) {
      last = `the registry query failed: HTTP ${res.status}`;
      continue;
    }
    let body;
    try {
      body = await res.json();
    } catch (e) {
      last = `the registry's answer was not JSON: ${e && e.message ? e.message : e}`;
      continue;
    }
    const version = body && body.latest_version;
    if (!version) {
      last = 'the registry named no latest_version for ' + MODULE;
      continue;
    }
    return version;
  }
  unknown(last);
}

const registryVersion = await registryLatest();

// ---------------------------------------------------------------------------
// THE PROBE: a scratch project with its own `.repos/`.
//
// The manifest is BARE on purpose: a probe that imports `moonbitlang/core`
// makes the toolchain see two versions of the stdlib core, and it refuses.
// ---------------------------------------------------------------------------
mkdirSync(PROBE, { recursive: true });
writeFileSync(
  join(PROBE, 'moon.mod'),
  'name = "probe/version_pin"\n\nversion = "0.1.0"\n',
  'utf8',
);

const fetched = spawnSync('moon', ['-C', PROBE, 'fetch', `${MODULE}@${registryVersion}`], {
  cwd: ROOT,
  encoding: 'utf8',
  timeout: 900000,
  maxBuffer: 64 * 1024 * 1024,
});
if (fetched.status !== 0) {
  unknown(
    `moon fetch ${MODULE}@${registryVersion} failed (exit ${fetched.status}):\n` +
      `${fetched.stdout ?? ''}\n${fetched.stderr ?? ''}`,
  );
}

const base = join(PROBE, '.repos', 'moonbitlang', 'core');
const realDir = join(base, registryVersion);
if (!existsSync(realDir)) {
  unknown(`the fetch reported success but ${realDir} does not exist`);
}

// The candidate list is EXACTLY what the harness puts there: a version the
// registry no longer serves would otherwise sit in the probe and be ordered
// against the new one, which is a different question.
for (const name of readdirSync(base)) {
  if (name !== registryVersion) rmSync(join(base, name), { recursive: true, force: true });
}

// ---------------------------------------------------------------------------
// THE DECOY: a version directory that is OLDER, and free to be picked.
// ---------------------------------------------------------------------------
const decoyArg = option('--decoy', 'auto');
const decoyName = decoyArg === 'auto' ? olderVersion(registryVersion) : decoyArg;
const decoyDir = join(base, decoyName);
// The decoy is removed on the way out, INCLUDING on the paths that end the run
// early: `process.exit` does not unwind a `finally` block, so a cleanup
// written there would leave the decoy behind whenever the run could not
// decide.
process.on('exit', () => {
  if (existsSync(decoyDir)) rmSync(decoyDir, { recursive: true, force: true });
});
{
  mkdirSync(decoyDir, { recursive: true });
  writeFileSync(
    join(decoyDir, 'moon.mod'),
    `name = "moonbitlang/core"\n\nversion = "${decoyName}"\n`,
    'utf8',
  );
  writeFileSync(
    join(decoyDir, 'decoy.mbt'),
    '///|\npub fn decoy_marker() -> Int32 {\n  7\n}\n',
    'utf8',
  );
}

const candidates = readdirSync(base).sort();

{ // the run, in a block of its own
  // The candidate list must hold a WRONG answer, or the check is vacuous:
  // with one candidate there is nothing to choose between, and "it chose the
  // only one" proves nothing about how it chooses.
  if (candidates.length < 2) {
    unknown(
      `the candidate list holds ${candidates.length} version(s) (${candidates.join(', ')}), ` +
        'so there is nothing to choose between and the check would pass vacuously',
    );
  }

  const exe = requireCli(ROOT);
  // The output directory is cleared first: a report left over from an earlier
  // run would answer "the report names the analysed version" for a run that
  // wrote no report at all.
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  const run = spawnSync(
    exe,
    [
      'analyze',
      `${MODULE}@latest`,
      '--out',
      OUT,
      // The budget is cut so the run is a PINNING check and not a second
      // analysis of the whole standard library: the file count, which is what
      // says which tree was read, is measured before the budget applies.
      '--max-functions',
      '1',
      '--max-total-steps',
      '200',
    ],
    { cwd: PROBE, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
  );
  const text = `${run.stdout ?? ''}${run.stderr ?? ''}`;

  const moduleLine = /^module\t(.+)$/m.exec(text);
  if (!moduleLine) {
    unknown(
      `the analyser named no version:\n${text.split(/\r?\n/).slice(0, 8).join('\n')}`,
    );
  }
  const reported = moduleLine[1].split('@').pop();
  const filesLine = /^files\t(\d+)$/m.exec(text);
  const files = filesLine ? Number(filesLine[1]) : -1;
  const expected = pinVersion(candidates);

  check(
    'the analysed version is the registry\'s latest',
    reported === registryVersion,
    `analysed ${reported}, registry says ${registryVersion}`,
  );
  check(
    'the analysed version is the newest of the fetched versions',
    reported === expected,
    `analysed ${reported}, newest of ${candidates.join(', ')} is ${expected}`,
  );
  check(
    'the planted older version was not analysed',
    reported !== decoyName,
    `decoy ${decoyName}, analysed ${reported}`,
  );
  check(
    'the tree that was read is the module, not the planted decoy',
    files > 100,
    `files=${files}`,
  );
  const reports = readdirSync(OUT).filter((f) => f.endsWith('.md'));
  check(
    'the report names the analysed version',
    reports.length === 1 && reports[0].includes(reported.replace(/\+/g, '_')),
    reports.join(', ').slice(0, 200),
  );
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
