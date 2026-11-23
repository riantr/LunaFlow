#!/usr/bin/env node
// THE PUBLISHED-ARTEFACT CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier points
// `scripts/qa/published_items.mjs` at a MUTATED COPY of the local artefacts
// and asserts that the byte-identity comparison goes RED -- because a
// published tool that computed a DIFFERENT minimal input than the tree would
// be a different analyser wearing the same version number, and that is
// exactly what the comparison exists to catch.
//
// The published side is real: the check runs the registry's own artefact, so
// this needs the registry and exits 2 when it cannot be reached -- "could not
// decide", never "the tree is broken".
//
// It also runs a CONTROL: the UNMUTATED copies, which have to stay green --
// a falsifier that starts from a broken baseline proves nothing.
//
// The tracked files are never written: the mutation is made in a scratch
// directory of its own.
//
// Usage: node scripts/qa/published_items_falsify.mjs [version]
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const VERSION = process.argv[2] ?? '0.1.34';
const CHECK = join(ROOT, 'scripts', 'qa', 'published_items.mjs');
const WORK = join(ROOT, '_build', 'qa', 'published_items_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });

/// Run the check against a given local-artefacts directory.  It must go RED
/// when `expect` is set, and stay GREEN when it is not.
///
/// The check takes the version and then an OPTIONAL scratch directory, so
/// the flag has to come AFTER both: putting `--local-artefacts` in the
/// scratch-directory's place would make the check scratch into a directory
/// named after the flag -- in the repository root.
function runCheck(name, localDir, expect) {
  const args = [CHECK, VERSION, join(WORK, 'scratch')];
  if (localDir) args.push('--local-artefacts', localDir);
  const r = spawnSync(process.execPath, args, {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  if (r.status === 2) {
    console.error('UNKNOWN  the check could not decide -- the registry is unreachable.');
    console.error(out.split(/\r?\n/).slice(0, 6).join('\n'));
    process.exit(2);
  }
  if (expect) {
    const red = r.status === 1;
    check(`${name}: the check goes red`, red, `exit=${r.status}`);
    if (red) {
      check(`${name}: it fails for the right reason`, out.includes(expect), expect);
    }
  } else {
    check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
    if (r.status !== 0) {
      console.log(out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
    }
  }
  return out;
}

// The first run does the work: it runs the published CLI and the local
// build, and it leaves the LOCAL artefacts in the check's own scratch
// directory, which is what the mutation needs.
const SCRATCH = join(ROOT, '_build', 'published_items');
console.log('-- the first run produces the artefacts the mutation needs --');
const first = runCheck('the first run', null, null);
if (!existsSync(join(SCRATCH, 'local'))) {
  console.error('the first run left no local artefacts to mutate');
  process.exit(2);
}

/// A fresh copy of the local artefacts, so every mutation starts from the
/// truth.
function copyLocal(name) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const f of readdirSync(join(SCRATCH, 'local'))) {
    copyFileSync(join(SCRATCH, 'local', f), join(dir, f));
  }
  return dir;
}

// The CONTROL -- the unmutated copies have to stay green.
{
  const dir = copyLocal('control');
  runCheck('the control', dir, null);
}

// F1 -- one byte of the local counterexample sidecar is changed: the
// published tool and the tree disagree about the minimal input.
{
  const dir = copyLocal('f1');
  const file = join(dir, readdirSync(dir).find((f) => f.endsWith('_counterexamples.jsonl')));
  const text = readFileSync(file, 'utf8');
  const at = text.indexOf('"tried":');
  const mutated = at >= 0 ? text.slice(0, at + 8) + '9' + text.slice(at + 9) : text.replace('"tried":1', '"tried":9');
  if (mutated === text) {
    console.error('the mutation for F1 changed nothing');
    process.exit(2);
  }
  writeFileSync(file, mutated, 'utf8');
  runCheck('F1 a different minimal input', dir, 'byte-identical to the local build');
}

// F2 -- the local counterexample sidecar is REMOVED: the local build has no
// counterexamples at all, which is a different analyser too.
{
  const dir = copyLocal('f2');
  const file = join(dir, readdirSync(dir).find((f) => f.endsWith('_counterexamples.jsonl')));
  rmSync(file, { force: true });
  runCheck('F2 no local counterexamples at all', dir, 'byte-identical to the local build');
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
