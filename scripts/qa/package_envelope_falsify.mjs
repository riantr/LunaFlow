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
//   F7  a raw trace that NO ignore rule matches -- `git add -f` would be the
//       wrong advice, so the check must not print it
//
// And then it goes END TO END: the command the check prints is taken from the
// check's OWN output and run against a REPLICA of the tree -- a real git
// repository, carrying this tree's .gitignore and a raw trace on disk that the
// index does not know yet -- and the check must go green after it.  A failure
// that names a command is worth nothing if the command does not work.
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
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
    return out;
  }
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
  }
  return out;
}

/// The lines a failing check offers as the way out.
const remedyLines = (out) => out.split(/\r?\n/).filter((l) => l.startsWith('FIX')).join(' | ');

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
  const report = 'reports/riantr_moonbit_doubleML@latest_0.164.68.md';
  m.artefacts = [...m.artefacts, { path: report }];
  m.packed = m.packed.filter((f) => f.path !== report);
  runModel('F3 a report that is not packed', m, 'every report, sidecar and summary is packed');
}

// F4 -- a raw trace IS packed: the thing that broke the 0.1.35 upload.
{
  const m = clone(TRUTH);
  m.packed = [
    ...m.packed,
    { path: 'reports/riantr_moonbit_doubleML@latest_0.164.68_root_trace.jsonl', bytes: 80_044_077 },
  ];
  runModel('F4 a raw trace in the package', m, 'no raw trace is packed');
}

// F5 -- a raw trace that is not tracked: the evidence is not in the repository.
{
  const m = clone(TRUTH);
  m.traces = m.traces.map((t) => ({ ...t, tracked: false }));
  const out = runModel('F5 a raw trace that is not tracked', m, 'every raw trace is still tracked by git');
  // AND IT MUST NAME THE WAY OUT.  The rule that hides the traces is the same
  // rule that makes a plain `git add` refuse them, so a failure that says only
  // "not tracked" leaves the reader with the fact and no command.
  check(
    'F5: it names the ignore rule and the command that stages the trace',
    /FIX\s+.*git add -f --/.test(out),
    remedyLines(out) || 'no FIX line',
  );
}

// F6 -- NO raw trace at all.  The check must not pass vacuously.
{
  const m = clone(TRUTH);
  m.traces = [];
  runModel('F6 no raw trace at all', m, 'every raw trace is still tracked by git');
}

// F7 -- a trace that is not tracked and that NO ignore rule matches: the rule
// does not apply, so `git add -f` would be the wrong advice, and the check
// must not print it.
{
  const m = clone(TRUTH);
  m.traces = [{ path: 'reports/a_stray_trace.jsonl', tracked: false, ignored: false, ignoredBy: null }];
  const out = runModel('F7 a trace that no ignore rule matches', m, 'every raw trace is still tracked by git');
  check(
    'F7: it says `git add`, not `git add -f` -- no rule matches it',
    /FIX\s+.*git add --/.test(out) && !/git add -f/.test(out),
    remedyLines(out) || 'no FIX line',
  );
}

// E1 -- END TO END: the command the check prints IS the command that works.
//
// The replica is a real git repository, under `_build/`, with this tree's own
// .gitignore and one raw trace on disk that the index does not know yet -- the
// state the 59-step gate was in when it went red on the package envelope.  The
// tracked tree is never touched.
{
  const REPO = join(WORK, 'replica');
  mkdirSync(join(REPO, 'scripts', 'qa'), { recursive: true });
  mkdirSync(join(REPO, 'docs', 'qa'), { recursive: true });
  mkdirSync(join(REPO, 'reports'), { recursive: true });
  copyFileSync(CHECK, join(REPO, 'scripts', 'qa', 'package_envelope.mjs'));
  copyFileSync(join(ROOT, '.gitignore'), join(REPO, '.gitignore'));
  copyFileSync(
    join(ROOT, 'docs', 'qa', 'PUBLISH_ENVELOPE.json'),
    join(REPO, 'docs', 'qa', 'PUBLISH_ENVELOPE.json'),
  );
  writeFileSync(join(REPO, 'moon.mod'), 'name = "replica/demo"\n\nversion = "0.0.1"\n');
  writeFileSync(join(REPO, 'reports', 'x_trace.jsonl'), '{"event":1}\n');

  const git = (args) => spawnSync('git', args, { cwd: REPO, encoding: 'utf8' });
  const init = git(['init', '--quiet']);
  // Windows would rewrite the copied files' line endings and say so, and that
  // noise does not belong in the gate's output.
  git(['config', 'core.autocrlf', 'false']);
  // The trace is NOT named: the ignore rule is what keeps it out of the index.
  const staged = git(['add', '--', 'moon.mod', '.gitignore', 'docs', 'scripts']);
  check(
    'E1: the replica -- a real repository, with this tree\'s ignore rules -- could be prepared',
    init.status === 0 && staged.status === 0,
    init.status !== 0 ? (init.stderr ?? '') : (staged.stderr ?? ''),
  );

  const run = () =>
    spawnSync(process.execPath, [join(REPO, 'scripts', 'qa', 'package_envelope.mjs')], {
      cwd: REPO,
      encoding: 'utf8',
      timeout: 600000,
      maxBuffer: 32 * 1024 * 1024,
    });

  const before = run();
  const beforeOut = `${before.stdout ?? ''}${before.stderr ?? ''}`;
  check(
    'E1: the check goes red on a repository whose index does not know the trace yet',
    before.status === 1,
    `exit=${before.status}`,
  );
  // The command is TAKEN from the output, not written out again here: a second
  // copy of it would be a second source of truth, and this case would prove
  // something about the copy rather than about the check.
  const command = /git add -f -- (\S+)/.exec(beforeOut);
  check(
    'E1: and it prints the command that stages the trace',
    command !== null,
    command ? command[0] : beforeOut.split(/\r?\n/).filter((l) => l.startsWith('FIX')).join(' | '),
  );
  if (command) {
    git(['add', '-f', '--', command[1]]);
    const after = run();
    check(
      'E1: and that very command turns the check green',
      after.status === 0,
      `exit=${after.status}`,
    );
  }
}

// The CONTROL -- one more small file says nothing about the envelope.
{
  const m = clone(TRUTH);
  m.packed = [...m.packed, { path: 'reports/a_small_extra.jsonl', bytes: 1_234 }];
  runModel('control', m, null);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
