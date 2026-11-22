#!/usr/bin/env node
// THE PEER'S VERDICT ON THIS SOURCE.
//
// The peer analyzer -- `riantr/moonbit_static_analysis` -- reads this module
// and says what it finds.  That is a CROSS-CHECK: a second implementation, by
// a different author, over the same tree.  The README documents the
// invocation and `docs/design.md` records what it found; this check makes it
// RE-RUNNABLE, so the answer is a fact about the tree instead of a paragraph
// in a document.
//
// MEASURED (2026-11-22): `moonx riantr/moonbit_static_analysis@latest .` over
// this tree reported 13 actionable findings:
//
//   10 in `src/app/scan.mbt` -- 2 ArgTypeMismatch and 8 UnusedParam
//    3 in `fixtures/eva_demo/lib.mbt`
//
// The ten were REAL, and the MoonBit compiler confirmed every one of them
// independently: the file held TWO definitions of `walk_dir`, one with six
// parameters and one with five, and the five-parameter one was never called
// on any backend (`Unused function 'walk_dir'`).  The three in the fixture
// corpus are the corpus: `fixtures/eva_demo` is DELIBERATELY vulnerable --
// it is what the analyser is tested against -- so a finding there is the
// tool working, not a defect in this project.
//
// So the invariant is narrow and it is about THIS project:
//
//   THE PEER MUST REPORT NO ACTIONABLE FINDING IN THIS PROJECT'S OWN SOURCE.
//
// The fixture corpus is excluded, and the exclusion is printed, because
// "no actionable finding" has to mean something: it means the source that
// ships.  A NOTICE is not a finding: the peer prints a notice per line only
// where it can hide a finding, and its own summary counts them separately.
//
// The peer is a MOVING TARGET: `@latest` is what the README documents and
// what a reader runs.  A newer peer that finds something new in this source
// turns this check RED on purpose -- that is the event it exists to surface.
//
// The check needs the registry, so it can come back with NO VERDICT: exit 2
// means "could not decide", not "the tree is broken".  That is the
// convention the whole harness uses.
//
// Usage:
//   node scripts/qa/peer_scan.mjs [--falsify]
//
//   --falsify   require an actionable finding in this project's own source,
//               so a detector that can no longer see one fails instead of
//               passing quietly

import { spawnSync } from 'node:child_process';

const falsify = process.argv.includes('--falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ---------------------------------------------------------------------------
// The peer, over this tree.
//
// The peer resolves `.repos/` relative to the WORKING DIRECTORY, so it has to
// run from the repository root -- from anywhere else it cannot locate the
// source for the target.
// ---------------------------------------------------------------------------
const run = spawnSync(
  'moonx',
  ['riantr/moonbit_static_analysis@latest', '.', '--exclude', '_build'],
  {
    cwd: process.cwd(),
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 256 * 1024 * 1024,
  },
);

const out = `${run.stdout ?? ''}${run.stderr ?? ''}`;

if (run.error) {
  console.error(`UNKNOWN  the peer could not be started: ${run.error.message}`);
  process.exit(2);
}

const summary = out.match(/^SUMMARY\t.*$/m);
if (!summary) {
  console.error('UNKNOWN  the peer produced no SUMMARY line, so it has no verdict on this tree.');
  const head = out.split(/\r?\n/).filter((l) => l.trim()).slice(0, 6);
  if (head.length > 0) console.error(head.map((l) => `        ${l}`).join('\n'));
  process.exit(2);
}

// ---------------------------------------------------------------------------
// The report.
//
// The peer prints one header line per file, then the rows for that file:
//
//   FOUND   .mbt  defects=0  notices=25  unchecked=51  ./src/app/abs.mbt
//   107:20 - notice: if expression is outside the analyzed subset; ...
//   333:15 - error: too many arguments to 'walk_dir': expected 5, got 6 ...
//
// The last tab-separated field of a header line is the path.  A row that
// starts with `notice:` is a NOTICE; anything else is an actionable finding.
// ---------------------------------------------------------------------------
const STATUS = /^(CLEAN|FOUND|PARTIAL)\t/;
const ROW = /^(\d+):(\d+) - (.*)$/;

let current = '';
const actionable = [];
const notices = [];
const headers = [];

for (const line of out.split(/\r?\n/)) {
  if (STATUS.test(line)) {
    const fields = line.split('\t');
    current = fields[fields.length - 1].trim();
    headers.push({ status: fields[0].trim(), file: current, line });
    continue;
  }
  const m = line.match(ROW);
  if (!m) continue;
  const row = { file: current, line: Number(m[1]), col: Number(m[2]), text: m[3] };
  if (/^notice:/.test(row.text)) notices.push(row);
  else actionable.push(row);
}

// ---------------------------------------------------------------------------
// What is THIS project's source.
//
// The fixture corpus is deliberately vulnerable -- it is the analyser's test
// corpus -- so a finding there is the tool working.  Everything else in the
// tree is this project's own source, and an actionable finding in it is a
// defect to fix.
// ---------------------------------------------------------------------------
const isFixture = (file) => file.replace(/^\.\//, '').startsWith('fixtures/');
const own = actionable.filter((a) => !isFixture(a.file));
const fixtures = actionable.filter((a) => isFixture(a.file));

const notParsed = headers.filter((h) => h.status === 'PARTIAL');

console.log(`peer summary: ${summary[0].replace(/\t/g, '  ')}`);
console.log(`files in the report: ${headers.length}, of which ${notParsed.length} only partly read`);
for (const h of notParsed) {
  const why = h.line.split('\t').filter((f) => f.startsWith('read up to')).join('');
  console.log(`  partly read: ${h.file}${why ? '  (' + why + ')' : ''}`);
}
console.log(`actionable findings: ${actionable.length} in total, ${own.length} in this project's own source, ${fixtures.length} in the fixture corpus`);
for (const a of own) {
  console.log(`  ${a.file}:${a.line}:${a.col}\n    ${a.text}`);
}

if (falsify) {
  check(
    'the detector still sees an actionable finding in this project\'s own source',
    own.length > 0,
    own.length === 0
      ? 'no actionable finding found, so the detector cannot see one any more'
      : `${own.length} found`,
  );
} else {
  check(
    'the peer reports no actionable finding in this project\'s own source',
    own.length === 0,
    own.length === 0
      ? `all ${fixtures.length} actionable findings are in the fixture corpus, which is deliberately vulnerable`
      : `${own.length} actionable finding(s) in the source that ships`,
  );
}

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
