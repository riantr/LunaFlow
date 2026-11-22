#!/usr/bin/env node
// THE REGISTER CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier MUTATES COPIES --
// never the tracked register, never the analyser's source -- and asserts that
// the same check `scripts/qa/selfscan_register.mjs` goes RED on each
// mutation.
//
// The mutations are the ways the register could be WRONG while still looking
// fine:
//
//   F1  a claim the analyser makes is dropped from the register -- the
//       register stops being the answer to every claim
//   F2  a count in the register is wrong -- the register answers with a
//       number that was not measured
//   F3  the headline count is stale -- the number the register publishes does
//       not match the rows under it
//   F4  a claim that is NOT made is registered -- the register overstates
//   F5  a family that does not exist is named -- the register answers with a
//       family the analyser has never heard of
//
// It also runs a CONTROL: a change the checker must NOT notice (a rewording
// of the guard text in a row, which says nothing about which claims the
// analyser makes).  Without the control, a checker that failed on every
// possible edit would look like a checker that works.
//
// Usage: node scripts/qa/selfscan_register_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const REGISTER = join(ROOT, 'src', 'app', 'selfscan_guards_wbtest.mbt');
const CHECK = join(ROOT, 'scripts', 'qa', 'selfscan_register.mjs');
const WORK = join(ROOT, '_build', 'qa', 'selfscan_register_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// The binary is BUILT HERE, not assumed.
{
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
}

const exe = requireCli(ROOT);
rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });
const source = join(WORK, 'source');
mkdirSync(source, { recursive: true });
{
  const run = spawnSync(
    exe,
    ['analyze', '--dir', '.', '--out', source, '--funnel', '--counterexamples'],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (run.status !== 0) {
    console.error('the analyser run failed, so there is nothing to falsify:');
    console.error((run.stderr ?? '').split(/\r?\n/).slice(0, 5).join('\n'));
    process.exit(2);
  }
}

const FILES = readdirSync(source).filter((f) => f.endsWith('_findings.jsonl') || f.endsWith('_counterexamples.jsonl'));
if (FILES.length === 0) {
  console.error('the analyser wrote no sidecars to falsify');
  process.exit(2);
}

const REGISTER_TEXT = readFileSync(REGISTER, 'utf8');

/// A fresh copy of the artefacts and of the register, so every mutation
/// starts from the truth.
function copyCase(name, mutate) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const f of FILES) copyFileSync(join(source, f), join(dir, f));
  const text = mutate(REGISTER_TEXT);
  if (text === REGISTER_TEXT) {
    console.error(`the mutation for ${name} changed nothing`);
    process.exit(2);
  }
  const registerFile = join(dir, 'register.mbt');
  writeFileSync(registerFile, text, 'utf8');
  return { dir, registerFile };
}

/// Run the real check against a copy.  It must go RED there.
function mustGoRed(name, dir, registerFile, expect) {
  const r = spawnSync(
    process.execPath,
    [CHECK, '--artefacts', dir, '--register', registerFile],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red && expect) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
  }
  return out;
}

/// Run the real check against a copy.  It must stay GREEN there.
function mustStayGreen(name, dir, registerFile) {
  const r = spawnSync(
    process.execPath,
    [CHECK, '--artefacts', dir, '--register', registerFile],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  return out;
}

// F1 -- a claim the analyser makes is not registered.
{
  const c = copyCase('f1', (t) =>
    t
      .split('\n')
      .filter((l) => !l.includes('rule_dimension_matrix'))
      .join('\n'),
  );
  mustGoRed('F1 an unregistered claim', c.dir, c.registerFile, 'is not registered');
}

// F2 -- a count in the register is not the count that was measured.
{
  const c = copyCase('f2', (t) => t.replace('3 x INDEX-OOB', '2 x INDEX-OOB'));
  mustGoRed('F2 a count that was not measured', c.dir, c.registerFile, 'disagree about how many claims');
}

// F3 -- the headline count is stale.
{
  const c = copyCase('f3', (t) => t.replace('reports 29 findings', 'reports 26 findings'));
  mustGoRed('F3 a stale headline', c.dir, c.registerFile, 'headline');
}

// F4 -- the register states a claim the analyser does not make.
{
  const c = copyCase('f4', (t) =>
    t.replace(
      '///   ffi.mbt       ffi_join                TAINT-INDEX-RANGE `len == 0`',
      '///   ffi.mbt       ffi_join                TAINT-INDEX-RANGE `len == 0`\n///   ffi.mbt       ffi_join                INDEX-OOB         `len == 0`',
    ),
  );
  mustGoRed('F4 a claim that is not made', c.dir, c.registerFile, 'does not make');
}

// F5 -- a family that does not exist.
{
  const c = copyCase('f5', (t) =>
    t.replace(
      '///   ffi.mbt       ffi_join                TAINT-INDEX-RANGE `len == 0`',
      '///   ffi.mbt       ffi_join                TAINT-INDEX-RANGE `len == 0`\n///   ffi.mbt       ffi_join                NOT-A-FAMILY     `len == 0`',
    ),
  );
  mustGoRed('F5 a family the analyser does not have', c.dir, c.registerFile, 'is not a family the analyser has');
}

// The CONTROL -- a rewording of the guard text says nothing about which
// claims the analyser makes, so the check must NOT notice it.
{
  const c = copyCase('control', (t) =>
    t.replace('`split` yields\n', '`split` yields, MEASURED,\n'),
  );
  mustStayGreen('the control', c.dir, c.registerFile);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
