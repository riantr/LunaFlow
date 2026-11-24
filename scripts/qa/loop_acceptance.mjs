#!/usr/bin/env node
// THE LOOP'S THREE ITEMS, CHECKED BY RUNNING THEM.
//
//   1. Bound the findings table
//   2. D1 (five dead rules) + D2
//   3. Phase 1 (L2-IFDS)
//
// Every item is checked by EXECUTING the thing it claims, never by reading a
// document that says so. A document can be right about a tree that has moved;
// a run cannot.
//
// What each item is checked against:
//
//   1. a live run with `--max-findings 3`: every findings table must carry a
//      marker row that names the cap and the whole set, the count table above
//      it must SUM to that whole set, and the `_findings.jsonl` sidecar must
//      hold every family the count tables name -- the bound may cost the
//      reader a row, never a finding. The same two facts are checked on the
//      COMMITTED doubleML artefact, which is the one the registry serves.
//
//   2. D1: the analyser must report a tainted allocation size at all (the rule
//      that says so was DEAD once, and it fired on no input), for both the
//      parser's spelling and the qualified one. D2: the same finding in TWO
//      files must be TWO findings -- the de-duplication key had no file in it,
//      so the second was dropped -- and the same finding twice in ONE file
//      must still be one.
//
//   3. the Phase-1 spike: M1 (no lost sink), M2 (the blanket rule's
//      contribution) and M3 (the model's coverage) over the fixture corpus,
//      plus the harness's own falsification mode, which breaks each check on
//      purpose and requires it to fail.
//
// The binary under test is BUILT here, not assumed: a binary left over from
// an earlier build measures the product as it WAS.
//
// Usage: node scripts/qa/loop_acceptance.mjs [--no-build]
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';
import { committedArtefactStem } from './committed_artefact.mjs';

const root = resolve(process.cwd());
const work = join(root, '_build', 'qa', 'loop_acceptance');
const skipBuild = process.argv.includes('--no-build');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

// The harness runs commands through a shell, so an argument with spaces in it
// has to carry its own quotes -- otherwise the shell splits it.
const run = (cmd, args, cwd = root) =>
  spawnSync(cmd, args, {
    cwd,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
    shell: true,
  });

const runQuoted = (cmd, args, cwd = root) =>
  run(
    cmd,
    args.map((a) => (/\s/.test(a) ? `"${a}"` : a)),
    cwd,
  );

///|
/// A two-column table row: "| family | count |".
const twoCell = (l) => /^\|\s*([^|]+?)\s*\|\s*([\d,]+)\s*\|$/.exec(l);

///|
/// The count tables of a report, each paired with the marker row of the
/// findings table it describes.
//
// A count table is a "| Family | Findings |" header, a separator, and then
/// one "| family | count |" row per family. The findings table follows it, and
/// -- when the table is bounded -- ends with the marker row that names the
/// cap and the whole set.
function countTables(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    if (!/^\|\s*Family\s*\|\s*Findings\s*\|/.test(lines[i])) continue;
    let j = i + 1;
    // the separator
    if (j < lines.length && /^\|[\s|:-]+\|$/.test(lines[j].trim())) j += 1;
    const rows = [];
    for (; j < lines.length; j++) {
      const m = twoCell(lines[j]);
      if (!m) break;
      rows.push({ family: m[1].trim(), count: Number(m[2].replace(/,/g, '')) });
    }
    // the marker row of the table this count table describes
    let marker = null;
    for (let k = j; k < lines.length; k++) {
      const mm = /\(truncated at (\d+) of ([\d,]+) rows?\)/.exec(lines[k]);
      if (mm && lines[k].trim().startsWith('|')) {
        marker = { index: k, cap: Number(mm[1]), whole: Number(mm[2].replace(/,/g, '')) };
        break;
      }
    }
    out.push({
      headerIndex: i,
      rows,
      sum: rows.reduce((a, r) => a + r.count, 0),
      marker,
    });
  }
  return out;
}

///|
/// The sidecar's family mix.
function sidecarFamilies(path) {
  const mix = new Map();
  const lines = readFileSync(path, 'utf8')
    .split('\n')
    .filter((l) => l.trim().length > 0);
  for (const l of lines) {
    const o = JSON.parse(l);
    const k = o.family ?? o.rule ?? 'unknown';
    mix.set(k, (mix.get(k) ?? 0) + 1);
  }
  return { mix, count: lines.length };
}

///|
/// The findings of one report directory: its markdown, its sidecar and its
/// summary.
function readArtefacts(dir) {
  const mdFile = readdirSync(dir).find((f) => f.endsWith('.md') && !f.includes('summary'));
  const sideFile = readdirSync(dir).find((f) => f.endsWith('_findings.jsonl'));
  const sumFile = readdirSync(dir).find((f) => f.endsWith('_summary.json'));
  const md = readFileSync(join(dir, mdFile), 'utf8');
  return {
    md,
    lines: md.split('\n'),
    side: join(dir, sideFile),
    summary: JSON.parse(readFileSync(join(dir, sumFile), 'utf8')),
  };
}

// ---------------------------------------------------------------- the build --
if (!skipBuild) {
  const b = run('moon', ['build', 'src/cli', '--target', 'native']);
  if (b.status !== 0) {
    console.error('the CLI build failed, so there is nothing to measure:');
    console.error((b.stderr ?? '') + (b.stdout ?? ''));
    process.exit(2);
  }
}
const cli = resolveCli(root);
if (!existsSync(cli)) {
  console.error('missing CLI binary:', cli);
  process.exit(2);
}

// ============================ 1. Bound the findings table ====================
console.log('\n-- 1. Bound the findings table --');

// 1a. a LIVE run with the cap at 3
const fixtureOut = join(work, 'fixture');
rmSync(fixtureOut, { recursive: true, force: true });
mkdirSync(fixtureOut, { recursive: true });
const scan = run(cli, ['analyze', '--dir', join(root, 'fixtures', 'vuln_demo'), '--out', fixtureOut, '--funnel', '--max-findings', '3']);
check('the fixture scan with --max-findings 3 ran', scan.status === 0, `exit ${scan.status}`);
if (scan.status === 0) {
  const art = readArtefacts(fixtureOut);
  const tables = countTables(art.lines);
  const bounded = tables.filter((t) => t.marker);
  check('every count table has a bounded findings table', bounded.length > 0 && bounded.length === tables.length, `${bounded.length} of ${tables.length}`);
  for (const t of bounded) {
    check(
      `a findings table is capped at 3 and names a whole set larger than the cap`,
      t.marker.cap === 3 && t.marker.whole > 3,
      `cap ${t.marker.cap} of ${t.marker.whole}`,
    );
    check(
      `the count table above it sums to the whole set it names`,
      t.sum === t.marker.whole,
      `the table sums to ${t.sum}, the marker says ${t.marker.whole}`,
    );
  }
  const note = art.lines.find((l) => /every finding.*sidecar|_findings\.jsonl` sidecar/.test(l));
  check('a note says the sidecar holds every finding the table does not show', !!note);
  const side = sidecarFamilies(art.side);
  const wanted = new Map();
  for (const t of tables) {
    for (const r of t.rows) wanted.set(r.family, (wanted.get(r.family) ?? 0) + r.count);
  }
  const short = [...wanted].filter(([f, n]) => (side.mix.get(f) ?? 0) < n);
  check(
    'the sidecar holds every finding the count tables name',
    short.length === 0,
    short.length === 0
      ? `${side.count} findings in ${side.mix.size} families`
      : short.map(([f, n]) => `${f}: ${n} named, ${side.mix.get(f) ?? 0} in the sidecar`).join('; '),
  );
}

// 1b. the COMMITTED doubleML artefact -- the one the registry serves.
//
// The corpus version is part of the file name and the REGISTRY moves it (it
// went 0.164.64 -> 0.164.66), so the artefact is FOUND in the tree's own
// reports directory rather than NAMED here: a checker that carried the
// version would stop finding the artefact the day the registry moved, and
// would then quietly check nothing.
const stem = committedArtefactStem(root, 'riantr_moonbit_doubleML@latest_');
if (!stem) {
  check('the committed doubleML artefact is present', false, join(root, 'reports'));
}
if (stem && existsSync(stem + '.md') && existsSync(stem + '_findings.jsonl')) {
  const lines = readFileSync(stem + '.md', 'utf8').split('\n');
  const tables = countTables(lines);
  const l2 = tables.find((t) => t.marker && t.marker.whole > 1000);
  check('the committed artefact has a bounded findings table', !!l2, l2 ? `of ${l2.marker.whole} rows` : 'none found');
  if (l2) {
    check(
      "the committed artefact's count table sums to the whole set its marker names",
      l2.sum === l2.marker.whole,
      `the table sums to ${l2.sum}, the marker says ${l2.marker.whole}`,
    );
    check(
      'the committed artefact states the cap it used',
      l2.marker.cap > 0 && l2.marker.cap < l2.marker.whole,
      `cap ${l2.marker.cap} of ${l2.marker.whole}`,
    );
  }
  const side = sidecarFamilies(stem + '_findings.jsonl');
  const wanted = new Map();
  for (const t of tables) {
    for (const r of t.rows) wanted.set(r.family, (wanted.get(r.family) ?? 0) + r.count);
  }
  const short = [...wanted].filter(([f, n]) => (side.mix.get(f) ?? 0) < n);
  check('the committed sidecar holds every finding the count tables name', short.length === 0, `${side.count} findings in the sidecar`);
  check(
    'the committed sidecar holds more than the bounded table shows',
    side.count > (l2 ? l2.marker.cap : 0),
    `${side.count} findings in the sidecar`,
  );
} else {
  check('the committed doubleML artefact is present', false, stem);
}

// ============================= 2. D1 + D2 ====================================
console.log('\n-- 2. D1 (five dead rules) + D2 --');

// 2a. D1, behaviourally: the rule fires at all.
const sideFile = readdirSync(fixtureOut).find((f) => f.endsWith('_findings.jsonl'));
const side = sidecarFamilies(join(fixtureOut, sideFile));
check(
  'D1: the analyser reports a tainted allocation size (the rule was dead code)',
  (side.mix.get('TAINT-ALLOC') ?? 0) > 0,
  `${side.mix.get('TAINT-ALLOC') ?? 0} TAINT-ALLOC finding(s)`,
);

// 2b. D1, for both spellings -- the unit assertions that name them.
const spell = runQuoted('moon', ['test', 'src/app', '--target', 'native', '-f', 'a tainted allocation size is reported*']);
const spellText = (spell.stdout ?? '') + (spell.stderr ?? '');
const spellTotal = /Total tests:\s*(\d+), passed: (\d+), failed: (\d+)/.exec(spellText);
check(
  "D1: the allocation-size rule fires for the parser's spelling and the qualified one",
  spell.status === 0 && spellTotal !== null && spellTotal[1] === '2' && spellTotal[3] === '0',
  spellTotal ? `${spellTotal[1]} matched, ${spellTotal[3]} failed (exit ${spell.status})` : `exit ${spell.status}`,
);

// 2c. D2, black box: the same finding in two files is two findings.
const d2dir = join(work, 'd2');
rmSync(d2dir, { recursive: true, force: true });
mkdirSync(d2dir, { recursive: true });
const SAME = `pub fn f(n : Int) -> Array[Int] {
  Array::make(n, 0)
}
`;
writeFileSync(join(d2dir, 'a.mbt'), SAME, 'utf8');
writeFileSync(join(d2dir, 'b.mbt'), SAME.replace('pub fn f', 'pub fn g'), 'utf8');
const d2out = join(work, 'd2out');
rmSync(d2out, { recursive: true, force: true });
mkdirSync(d2out, { recursive: true });
const d2run = run(cli, ['analyze', '--dir', d2dir, '--out', d2out, '--funnel']);
check('the two-file module was analysed', d2run.status === 0, `exit ${d2run.status}`);
if (d2run.status === 0) {
  const d2side = readdirSync(d2out).find((f) => f.endsWith('_findings.jsonl'));
  const all = readFileSync(join(d2out, d2side), 'utf8')
    .split('\n')
    .filter((l) => l.trim().length > 0)
    .map((l) => JSON.parse(l));
  // The L2's own findings: the dynamic layer reports the same claim about the
  // same line, so the L2's ones are the ones the de-duplication key governs.
  const l2alloc = all.filter(
    (o) => (o.family ?? o.rule) === 'TAINT-ALLOC' && o.method === 'L2-abstract',
  );
  check(
    'D2: the same finding in two files is two findings',
    l2alloc.length === 2,
    `${l2alloc.length} L2 TAINT-ALLOC finding(s)`,
  );
  const files = [...new Set(l2alloc.map((o) => o.file))].sort();
  check(
    'D2: and the two findings name the two files',
    files.length === 2 && files.some((f) => f.includes('a.mbt')) && files.some((f) => f.includes('b.mbt')),
    files.join(', '),
  );
}

// 2d. D2, the other direction: the de-duplication is still exact within a file.
const dedup = runQuoted('moon', ['test', 'src/app', '--target', 'native', '-f', 'the same finding twice in one file*']);
const dedupText = (dedup.stdout ?? '') + (dedup.stderr ?? '');
check(
  'D2: the same finding twice in one file is still one finding',
  dedup.status === 0 && /Total tests:\s*1, passed: 1, failed: 0/.test(dedupText),
  `exit ${dedup.status}`,
);

// 2e. D2, the unit assertion that names the two files.
const twoFiles = runQuoted('moon', ['test', 'src/app', '--target', 'native', '-f', 'two findings in two files are two findings']);
const twoFilesText = (twoFiles.stdout ?? '') + (twoFiles.stderr ?? '');
check(
  'D2: the unit assertion "two findings in two files are two findings" passes',
  twoFiles.status === 0 && /Total tests:\s*1, passed: 1, failed: 0/.test(twoFilesText),
  `exit ${twoFiles.status}`,
);

// ============================ 3. Phase 1 (L2-IFDS) ===========================
console.log('\n-- 3. Phase 1 (L2-IFDS) --');

const spike = run('node', ['scripts/qa/ifds_spike.mjs', '--corpus', 'fixtures', '--label', 'fixtures']);
const spikeOut = (spike.stdout ?? '') + (spike.stderr ?? '');
check(
  'the Phase-1 spike passes M1, M2 and M3 over the fixture corpus',
  spike.status === 0 && /RESULT: ifds spike OK/.test(spikeOut),
  `exit ${spike.status}`,
);
for (const m of ['M1', 'M2', 'M3']) {
  const line = spikeOut.split('\n').find((l) => l.startsWith(`PASS  ${m}:`));
  check(`  ${m} is reported as PASS`, !!line, line ? line.slice(0, 100) : 'no line');
}
const falsify = run('node', ['scripts/qa/ifds_spike.mjs', '--corpus', 'fixtures', '--label', 'fixtures-falsify', '--falsify']);
const falsifyOut = (falsify.stdout ?? '') + (falsify.stderr ?? '');
check(
  "the spike's falsification mode passes: each check breaks on purpose and has to fail",
  falsify.status === 0 && /RESULT: ifds spike OK/.test(falsifyOut),
  `exit ${falsify.status}`,
);

console.log('');
console.log(
  failures === 0
    ? `LOOP ACCEPTANCE: all ${checks} checks pass -- the three items hold on this tree.`
    : `LOOP ACCEPTANCE: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
