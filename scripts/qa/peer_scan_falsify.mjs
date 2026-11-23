#!/usr/bin/env node
// THE PEER-SCAN CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier breaks COPIES --
// never the tracked ledger, never the analyser's source -- and asserts that
// the same check `scripts/qa/peer_scan.mjs` goes RED on each mutation.
//
// The mutations are the ways the peer's verdict could be WRONG while still
// looking fine:
//
//   F1  a file the peer did not fully parse is DROPPED from the ledger -- the
//       coverage would shrink silently, and the claim would cover less than
//       it says
//   F2  a file the peer DID fully parse is added to the ledger -- the ledger
//       would claim a gap that is not one
//   F3  a construct's error kind is changed -- the ledger would name a gap
//       the peer does not report
//   F4  the PEER'S OWN REPORT says it withheld a finding -- the claim would
//       hide something the peer knew about and could not report
//
// It also runs a CONTROL: a change the checker must NOT notice (a rewording
// of a construct's note, which says nothing about which files the peer read
// only up to a parse error).  Without the control, a checker that failed on
// every possible edit would look like a checker that works.
//
// The peer is run ONCE and its report is captured: it takes ~10 s, and a
// falsifier that ran it once per mutation would pay that four times.  The
// tracked ledger is never written.
//
// Usage: node scripts/qa/peer_scan_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const LEDGER = join(ROOT, 'docs', 'qa', 'PEER_PARSE_GAPS.json');
const CHECK = join(ROOT, 'scripts', 'qa', 'peer_scan.mjs');
const WORK = join(ROOT, '_build', 'qa', 'peer_scan_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });

// --- the peer's report, captured ONCE ----------------------------------------
const PEER_TEXT = (() => {
  const run = spawnSync(
    'moonx',
    ['riantr/moonbit_static_analysis@latest', '.', '--exclude', '_build'],
    { cwd: ROOT, encoding: 'utf8', timeout: 900000, maxBuffer: 256 * 1024 * 1024 },
  );
  const text = `${run.stdout ?? ''}${run.stderr ?? ''}`;
  if (run.error || !/^SUMMARY\t/m.test(text)) {
    console.error('the peer produced no report, so there is nothing to falsify:');
    console.error(text.split(/\r?\n/).slice(0, 6).join('\n'));
    process.exit(2);
  }
  return text;
})();

const LEDGER_TEXT = readFileSync(LEDGER, 'utf8');

/// A fresh copy of the ledger, so every mutation starts from the truth.
function copyLedger(name, mutate) {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const ledger = JSON.parse(LEDGER_TEXT);
  const before = JSON.stringify(ledger);
  const mutated = mutate(ledger);
  if (JSON.stringify(mutated) === before) {
    console.error(`the mutation for ${name} changed nothing`);
    process.exit(2);
  }
  const file = join(dir, 'PEER_PARSE_GAPS.json');
  writeFileSync(file, JSON.stringify(mutated, null, 2), 'utf8');
  return file;
}

/// A fresh copy of the peer's report, so the mutation starts from the truth.
function copyPeer(name, mutate) {
  const file = join(WORK, `${name}-peer.txt`);
  const mutated = mutate(PEER_TEXT);
  if (mutated === PEER_TEXT) {
    console.error(`the mutation for ${name} changed nothing`);
    process.exit(2);
  }
  writeFileSync(file, mutated, 'utf8');
  return file;
}

/// Run the real check.  It must go RED.
function mustGoRed(name, ledgerFile, peerFile, expect) {
  const r = spawnSync(
    process.execPath,
    [CHECK, '--peer-output', peerFile, '--ledger', ledgerFile],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red && expect) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
  }
}

/// Run the real check.  It must stay GREEN.
function mustStayGreen(name, ledgerFile, peerFile) {
  const r = spawnSync(
    process.execPath,
    [CHECK, '--peer-output', peerFile, '--ledger', ledgerFile],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 32 * 1024 * 1024 },
  );
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) console.log(out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
}

// The truth, written straight out: the mutating helpers refuse to make a
// copy that changes nothing, and the truth IS the unchanged thing.
const peerTruth = join(WORK, 'truth-peer.txt');
writeFileSync(peerTruth, PEER_TEXT, 'utf8');
const ledgerTruth = join(WORK, 'truth-ledger.json');
writeFileSync(ledgerTruth, LEDGER_TEXT, 'utf8');

// The truth has to PASS, or every mutation below would "go red" for the wrong
// reason: a falsifier that starts from a broken baseline proves nothing.
mustStayGreen('the unmutated copies', ledgerTruth, peerTruth);

// F1 -- a file the peer did not fully parse is dropped from the ledger.
{
  const file = copyLedger('f1', (l) => {
    // The first gap -- `src/command/command.mbt` -- is no longer recorded.
    l.constructs = l.constructs.slice(1);
    return l;
  });
  mustGoRed('F1 a gap that is not recorded', file, peerTruth, 'exactly the known gaps');
}

// F2 -- a file the peer DID fully parse is added to the ledger.
{
  const file = copyLedger('f2', (l) => {
    l.constructs[0].files = [...l.constructs[0].files, 'src/app/util.mbt'];
    return l;
  });
  mustGoRed('F2 a gap that does not exist', file, peerTruth, 'exactly the known gaps');
}

// F3 -- a construct's error kind is changed.
{
  const file = copyLedger('f3', (l) => {
    l.constructs[0].peer_error = 'expected a semicolon';
    return l;
  });
  mustGoRed('F3 an error kind the peer does not report', file, peerTruth, 'gap names');
}

// F4 -- the PEER'S OWN REPORT says it withheld a finding.
{
  const file = copyPeer('f4', (t) =>
    t
      .replace(/^NOTPARSE\t(\d+) files?, (\d+) finding\(s\) withheld/m, 'NOTPARSE\t$1 files?, 1 finding(s) withheld')
      .replace(/(\bwithheld=)(\d+)/, '$11'),
  );
  mustGoRed('F4 a finding the peer withheld', ledgerTruth, file, 'withheld no finding');
}

// The CONTROL -- a rewording of a construct's note says nothing about which
// files the peer read only up to a parse error.
{
  const file = copyLedger('control', (l) => {
    l.constructs[0].note = `${l.constructs[0].note} (reworded, nothing else changed)`;
    return l;
  });
  mustStayGreen('the control', file, peerTruth);
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
