#!/usr/bin/env node
// THE VERSION-PIN CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier runs the real
// check -- `scripts/qa/version_pin.mjs` -- with INJECTED SITUATIONS and
// asserts that it reaches the verdict each situation deserves:
//
//   C   the unmutated run                                    GREEN  (exit 0)
//   F1  a version directory NEWER than the registry's latest   RED    (exit 1)
//   F2  a registry version that cannot be fetched             UNKNOWN (exit 2)
//
// F1 is the sensitivity: the check's claim is "the version the analyser
// analyses for `@latest` is the registry's latest", so a candidate list that
// contains a version which is NOT the registry's latest has to be caught.  The
// check used to have no such case -- it looked at the answer and never asked
// whether the answer could have been a different one.
//
// F2 is the three-state discipline: a check that cannot get its dependency
// says NOTHING about the tree.  It must not report a pass (the tree was never
// looked at) and it must not report a failure (the tree is not known to be
// broken).  Exit 2 is the only honest answer, and this falsifier holds the
// check to it.
//
// The C CONTROL is the ordinary run: nothing injected, the candidate list
// holds the registry's version and a planted decoy that is one day older, and
// the check must stay GREEN.  Without the control, a check that failed on
// every possible input would look like a check that works.
//
// Usage: node scripts/qa/version_pin_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = resolve(ROOT, 'scripts', 'qa', 'version_pin.mjs');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

/// Run the real check with the given arguments.
function run(args) {
  const r = spawnSync(process.execPath, [CHECK, ...args], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { status: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

/// The check must go RED, and say why.
function mustGoRed(name, args, expect) {
  const r = run(args);
  check(`${name}: the check goes red`, r.status === 1, `exit=${r.status}`);
  if (r.status === 1 && expect) {
    check(`${name}: it fails for the right reason`, r.out.includes(expect), expect);
  }
}

/// The check must stay GREEN.
function mustStayGreen(name, args) {
  const r = run(args);
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) {
    console.log(
      r.out
        .split(/\r?\n/)
        .filter((l) => l.startsWith('FAIL') || l.startsWith('UNKNOWN'))
        .join('\n'),
    );
  }
}

/// The check must reach NO VERDICT: exit 2, and neither 0 nor 1.
function mustBeUnknown(name, args) {
  const r = run(args);
  check(`${name}: the check reaches no verdict`, r.status === 2, `exit=${r.status}`);
  check(
    `${name}: it says so in words`,
    r.out.includes('UNKNOWN'),
    r.out.split(/\r?\n/).slice(0, 2).join(' | '),
  );
}

// C -- the CONTROL: the ordinary run.
mustStayGreen('C the unmutated run', []);

// F1 -- a candidate that is NEWER than the registry's latest.
//
// The decoy here is newer, so the analyser's own rule ("the newest of the
// fetched versions") points AT the decoy, and the check's claim -- the
// registry's latest -- is what says no.  A check that only looked at the
// newest candidate would pass here.
mustGoRed(
  'F1 a candidate newer than the registry',
  ['--decoy', '0.9.29991231+ffffffff'],
  "the analysed version is the registry's latest",
);

// F2 -- a registry version that cannot be fetched.
mustBeUnknown('F2 a version that cannot be fetched', ['--registry', '9.9.9+deadbeef']);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
