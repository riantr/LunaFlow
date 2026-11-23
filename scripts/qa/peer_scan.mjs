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
// AND THE CLAIM CARRIES ITS COVERAGE.  The peer does not parse every file
// it reads: it stops at the first parse error in some of them, and for
// those files it has NO verdict.  So the claim above is true over the files
// the peer UNDERSTOOD, and the boundary is measured rather than left
// implicit: the peer must WITHHOLD no finding (the findings it knew about
// in a file it could not parse), and the set of files it did not fully
// parse must be exactly the set recorded in
// `docs/qa/PEER_PARSE_GAPS.json`.  A change in either direction turns this
// check red on purpose: the published claim has to be written again.
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
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const falsify = process.argv.includes('--falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ---------------------------------------------------------------------------
// THE LEDGER: the files the peer does not fully understand.
//
// It carries the construct, the peer's OWN error kind and the file, so the
// comparison below is between the peer's words and a recorded fact.
// ---------------------------------------------------------------------------
// The ledger can be pointed at a COPY, so a falsifier can break it without
// touching the tracked file.
const ledgerArg = process.argv.indexOf('--ledger');
const LEDGER_PATH =
  ledgerArg >= 0 && process.argv[ledgerArg + 1]
    ? process.argv[ledgerArg + 1]
    : join(process.cwd(), 'docs', 'qa', 'PEER_PARSE_GAPS.json');
let ledger = null;
try {
  ledger = JSON.parse(readFileSync(LEDGER_PATH, 'utf8'));
} catch (e) {
  console.error(`UNKNOWN  the peer-parse-gap ledger could not be read: ${LEDGER_PATH}`);
  console.error(String(e && e.message ? e.message : e));
  process.exit(2);
}
const ledgerFiles = () => ledger.constructs.flatMap((c) => c.files).sort();

// ---------------------------------------------------------------------------
// The peer's NOTPARSE block: the error kind per file, and how many findings
// it WITHHELD -- the findings it knew about in a file it could not parse.
// ---------------------------------------------------------------------------
function parseNotParse(text) {
  const kinds = new Map();
  let withheld = null;
  let current = null;
  for (const line of text.split(/\r?\n/)) {
    const head = /^NOTPARSE\t(\d+) files?, (\d+) finding\(s\) withheld/.exec(line);
    if (head) {
      withheld = Number(head[2]);
      continue;
    }
    const kind = /^\s+\d+x\s+(.+)$/.exec(line);
    if (kind) {
      current = kind[1].trim();
      continue;
    }
    const eg = /^\s+e\.g\.\s+(\S+)\s*$/.exec(line);
    if (eg && current) {
      const list = kinds.get(current) ?? [];
      list.push(eg[1]);
      kinds.set(current, list);
      current = null;
    }
  }
  return { kinds, withheld };
}

// ---------------------------------------------------------------------------
// The peer's SUMMARY, read as the counts it states.
// ---------------------------------------------------------------------------
function parseSummaryFields(text) {
  const m = /^SUMMARY\t(.*)$/m.exec(text);
  if (!m) return {};
  const fields = {};
  for (const f of m[1].split('\t')) {
    const kv = /^(\w+)=(.*)$/.exec(f);
    if (kv) fields[kv[1]] = kv[2];
  }
  return fields;
}

// ---------------------------------------------------------------------------
// The peer, over this tree.
//
// The peer resolves `.repos/` relative to the WORKING DIRECTORY, so it has to
// run from the repository root -- from anywhere else it cannot locate the
// source for the target.
// ---------------------------------------------------------------------------
// The peer takes ~10 s to run, and a falsifier that has to run it once per
// mutation would pay that four times.  `--peer-output <file>` reads a
// report that was already captured, so the mutations are what cost.
const peerOutArg = process.argv.indexOf('--peer-output');
const fromFile = peerOutArg >= 0 && process.argv[peerOutArg + 1];

let out = '';
if (fromFile) {
  try {
    out = readFileSync(process.argv[peerOutArg + 1], 'utf8');
  } catch (e) {
    console.error(`UNKNOWN  the peer's report could not be read: ${process.argv[peerOutArg + 1]}`);
    console.error(String(e && e.message ? e.message : e));
    process.exit(2);
  }
} else {
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

  out = `${run.stdout ?? ''}${run.stderr ?? ''}`;

  if (run.error) {
    console.error(`UNKNOWN  the peer could not be started: ${run.error.message}`);
    process.exit(2);
  }
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

// --- the COVERAGE of the claim ---------------------------------------------
//
// The peer's own report says how much of the tree it UNDERSTOOD: the
// PARTIAL rows name the files it read only up to their first parse error,
// and the NOTPARSE block says how many findings it WITHHELD.  The claim
// above holds over the files it understood, and these checks pin that
// boundary so it cannot change silently.
const notParse = parseNotParse(out);
const summaryFields = parseSummaryFields(out);
const partlyRead = notParsed.map((h) => h.file.replace(/^\.\//, '')).sort();
const known = ledgerFiles();

console.log(
  `the peer's coverage: ${headers.length - notParsed.length} of ${headers.length} file(s) fully understood; ` +
    `the ${notParsed.length} it did not are the known gaps in docs/qa/PEER_PARSE_GAPS.json` +
    (partlyRead.length > 0 ? ` (${partlyRead.join(', ')})` : ''),
);

check(
  'the peer withheld no finding: the claim hides nothing the peer knew',
  notParse.withheld === 0 && Number(summaryFields.withheld) === 0,
  `the NOTPARSE block says ${notParse.withheld}, the SUMMARY says ${summaryFields.withheld}`,
);
check(
  'the files the peer did not fully parse are exactly the known gaps',
  JSON.stringify(partlyRead) === JSON.stringify(known),
  `the peer: ${partlyRead.join(', ') || '(none)'} | the ledger: ${known.join(', ') || '(none)'}`,
);
for (const c of ledger.constructs) {
  const files = notParse.kinds.get(c.peer_error);
  // The peer prints its paths with a `./` prefix and the ledger stores them
  // without one, so both sides are normalised before they are compared.
  const named = Array.isArray(files) ? files.map((f) => f.replace(/^\.\//, '')) : null;
  check(
    `the peer's "${c.peer_error}" gap names ${c.files.join(', ')}`,
    named !== null && c.files.every((f) => named.includes(f)),
    named ? named.join(', ') : 'the peer reported no such gap',
  );
}
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
