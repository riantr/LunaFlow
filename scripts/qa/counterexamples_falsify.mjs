#!/usr/bin/env node
// THE COUNTEREXAMPLE CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier MUTATES COPIES of
// the artefacts -- never the tracked files, never the analyser's source --
// and asserts that the same check `scripts/qa/counterexamples.mjs` goes RED
// on each mutation.
//
// The mutations are the ways the feature could be WRONG while still looking
// fine:
//
//   F1  an argument that is not the candidate its index points at -- the
//       minimality claim becomes a decoration
//   F2  a counterexample that names a finding the report does not show --
//       the claim is about nothing
//   F3  a report row that disagrees with the sidecar row -- the two
//       renderings drift apart
//   F4  a count in the prose that the sidecar does not support -- the
//       numbers drift
//   F5  a counterexample whose rule does not match the report's row -- the
//       table and the sidecar name different families
//
// It also runs a CONTROL: a change the checker must NOT notice (a rewording
// of the paragraph that states what "minimal" means).  Without the control,
// a checker that failed on every possible edit would look like a checker
// that works.
//
// Usage: node scripts/qa/counterexamples_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const FIXTURE = join(ROOT, 'fixtures', 'vuln_demo');
const STEM = 'local_module_0.0.0';
const WORK = join(ROOT, '_build', 'qa', 'counterexamples_falsify');

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
    ['analyze', '--dir', FIXTURE, '--out', source, '--counterexamples'],
    { cwd: ROOT, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (run.status !== 0) {
    console.error('the analyser run failed, so there is nothing to falsify:');
    console.error((run.stderr ?? '').split(/\r?\n/).slice(0, 5).join('\n'));
    process.exit(2);
  }
}

const FILES = [`${STEM}.md`, `${STEM}_counterexamples.jsonl`, `${STEM}_findings.jsonl`];
for (const f of FILES) {
  if (!existsSync(join(source, f))) {
    console.error(`missing artefact: ${f}`);
    process.exit(2);
  }
}

/// A fresh copy of the artefacts, so every mutation starts from the truth.
function copyArtefacts(name) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const f of FILES) copyFileSync(join(source, f), join(dir, f));
  return dir;
}

/// Run the real check against a directory of artefacts.  It must FAIL there.
function mustGoRed(name, dir, expect) {
  const r = spawnSync(
    process.execPath,
    [join(ROOT, 'scripts', 'qa', 'counterexamples.mjs'), '--artefacts', dir],
    { cwd: ROOT, encoding: 'utf8', timeout: 300000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  const red = r.status !== 0;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  check(
    `${name}: the check names the reason`,
    expect.test(out),
    expect.detail(out),
  );
}

/// The control: the check must stay GREEN.
function mustStayGreen(name, dir) {
  const r = spawnSync(
    process.execPath,
    [join(ROOT, 'scripts', 'qa', 'counterexamples.mjs'), '--artefacts', dir],
    { cwd: ROOT, encoding: 'utf8', timeout: 300000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) console.log(out.split(/\r?\n/).slice(-12).join('\n'));
}

// --- F1: an argument that is not the candidate its index points at --------
{
  const dir = copyArtefacts('f1');
  const p = join(dir, `${STEM}_counterexamples.jsonl`);
  const lines = readFileSync(p, 'utf8').split(/\r?\n/).filter((l) => l.trim() !== '');
  const rows = lines.map((l) => JSON.parse(l));
  const withArgs = rows.find((cx) => cx.args.length > 0);
  withArgs.args[0] = '999999';
  writeFileSync(p, rows.map((cx) => JSON.stringify(cx)).join('\n') + '\n', 'utf8');
  mustGoRed('F1 argument not at its candidate index', dir, {
    test: (out) => /every argument is the candidate its index points at/.test(out),
    detail: () => 'the index check',
  });
}

// --- F2: a counterexample that names a finding the report does not show ---
{
  const dir = copyArtefacts('f2');
  const p = join(dir, `${STEM}_counterexamples.jsonl`);
  const lines = readFileSync(p, 'utf8').split(/\r?\n/).filter((l) => l.trim() !== '');
  const rows = lines.map((l) => JSON.parse(l));
  rows[0].line = 4242;
  writeFileSync(p, rows.map((cx) => JSON.stringify(cx)).join('\n') + '\n', 'utf8');
  mustGoRed('F2 counterexample naming an unshown finding', dir, {
    test: (out) => /every counterexample names a finding the report shows/.test(out),
    detail: () => 'the naming check',
  });
}

// --- F3: a report row that disagrees with the sidecar ----------------------
{
  const dir = copyArtefacts('f3');
  const p = join(dir, `${STEM}.md`);
  const md = readFileSync(p, 'utf8');
  // The first counterexample row: change its re-run count.
  const written = md.replace(/(\| `[^`]+` \| [^|]+ \| `[^`]+` \| [^|]+ \| )(\d+)(\s*\|)/, '$199999$3');
  check('F3: the report row was changed', written !== md);
  writeFileSync(p, written, 'utf8');
  mustGoRed('F3 report row disagreeing with the sidecar', dir, {
    test: (out) => /every table row agrees with its sidecar row/.test(out),
    detail: () => 'the row-agreement check',
  });
}

// --- F4: a count in the prose the sidecar does not support ----------------
{
  const dir = copyArtefacts('f4');
  const p = join(dir, `${STEM}.md`);
  const md = readFileSync(p, 'utf8');
  const written = md.replace(
    /The minimisation covered \*\*(\d+)\*\* of the \*\*(\d+)\*\* findings/,
    (m, a, b) => `The minimisation covered **${Number(a) + 1}** of the **${b}** findings`,
  );
  check('F4: the prose count was changed', written !== md);
  writeFileSync(p, written, 'utf8');
  mustGoRed('F4 prose count the sidecar does not support', dir, {
    test: (out) => /the count of minimised findings is the number of counterexamples/.test(out),
    detail: () => 'the count check',
  });
}

// --- F5: a counterexample whose rule does not match the report's row ------
{
  const dir = copyArtefacts('f5');
  const p = join(dir, `${STEM}_counterexamples.jsonl`);
  const lines = readFileSync(p, 'utf8').split(/\r?\n/).filter((l) => l.trim() !== '');
  const rows = lines.map((l) => JSON.parse(l));
  rows[0].rule = 'NO-SUCH-FAMILY';
  writeFileSync(p, rows.map((cx) => JSON.stringify(cx)).join('\n') + '\n', 'utf8');
  mustGoRed('F5 sidecar family disagreeing with the report', dir, {
    test: (out) =>
      /every table row agrees with its sidecar row/.test(out) ||
      /every counterexample names a finding the report shows/.test(out),
    detail: () => 'the row-agreement or the naming check',
  });
}

// --- the control: a rewording the checker must NOT notice ------------------
{
  const dir = copyArtefacts('control');
  const p = join(dir, `${STEM}.md`);
  const md = readFileSync(p, 'utf8');
  const written = md.replace(
    'This is not a globally minimal program and not a minimal source',
    'This is not a globally minimal PROGRAM and not a minimal source',
  );
  check('control: the prose was reworded', written !== md);
  writeFileSync(p, written, 'utf8');
  mustStayGreen('control a rewording of the prose', dir);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
