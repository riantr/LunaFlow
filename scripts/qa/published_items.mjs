#!/usr/bin/env node
// THE THREE ITEMS, CHECKED IN THE PUBLISHED ARTEFACT.
//
// Every other check in this repository measures the LOCAL build. The registry
// serves a different artefact -- the wasm one, built by CI -- and that is the
// one a consumer actually runs. So this runs the PUBLISHED module over a
// corpus and checks the three items in ITS report:
//
//   1. the findings table is bounded, the count table above it is the whole
//      set, and the sidecar keeps every finding the bound left out;
//   2. D1: the allocation-size rule fires (it was dead code once, and it
//      fired on no input);
//   3. D2: the same finding in two files is two findings (the key had no file
//      in it, and the second was dropped).
//
// And it compares the published report with the LOCAL build's report on the
// same corpus: if the published artefact behaves differently, the release
// does not carry the repair.
//
// `moonx` materialises the module's source into the CURRENT directory's
// .repos/, so this runs from a scratch directory of its own -- never from the
// repository root, whose .repos/ holds the peer corpus.
//
// Usage: node scripts/qa/published_items.mjs [version] [scratch-dir]
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(process.cwd());
const VERSION = process.argv[2] ?? '0.1.30';
const SCRATCH = resolve(process.argv[3] ?? join(root, '_build', 'published_items'));
const CORPUS = join(root, 'fixtures', 'vuln_demo');
const CAP = '3';

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

///|
/// Run the published module's CLI over a directory.
function published(dir, out) {
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  const r = spawnSync(
    'moonx',
    [
      `riantr/LunaFlow@${VERSION}`,
      'analyze',
      '--dir',
      dir,
      '--out',
      out,
      '--funnel',
      '--max-findings',
      CAP,
    ],
    { cwd: SCRATCH, encoding: 'utf8', timeout: 1800000, maxBuffer: 64 * 1024 * 1024, shell: true },
  );
  if (r.status !== 0) {
    console.error(((r.stderr ?? '') + (r.stdout ?? '')).slice(-2000));
    return null;
  }
  const mdFile = readdirSync(out).find((f) => f.endsWith('.md') && !f.includes('summary'));
  const sideFile = readdirSync(out).find((f) => f.endsWith('_findings.jsonl'));
  const lines = readFileSync(join(out, mdFile), 'utf8').split('\n');
  const findings = readFileSync(join(out, sideFile), 'utf8')
    .split('\n')
    .filter((l) => l.trim().length > 0)
    .map((l) => JSON.parse(l));
  const mix = new Map();
  for (const o of findings) {
    const k = o.family ?? o.rule ?? 'unknown';
    mix.set(k, (mix.get(k) ?? 0) + 1);
  }
  return { lines, findings, mix };
}

///|
/// The bounded tables of a report: the marker row, and the count table above
/// it (a "| family | count |" table), which must sum to the whole set.
function boundedTables(lines) {
  const twoCell = (l) => /^\|\s*([^|]+?)\s*\|\s*([\d,]+)\s*\|$/.exec(l);
  const out = [];
  lines.forEach((l, i) => {
    const m = /\(truncated at (\d+) of ([\d,]+) rows?\)/.exec(l);
    if (!m || !l.trim().startsWith('|')) return;
    let j = i - 1;
    while (j >= 0) {
      const t = lines[j].trim();
      const cols = t.startsWith('|') ? t.split('|').length - 2 : 0;
      if (t === '' || cols !== 2) {
        j -= 1;
        continue;
      }
      break;
    }
    const rows = [];
    for (; j >= 0; j -= 1) {
      const c = twoCell(lines[j]);
      if (!c) break;
      rows.push({ family: c[1].trim(), count: Number(c[2].replace(/,/g, '')) });
    }
    out.push({
      cap: Number(m[1]),
      whole: Number(m[2].replace(/,/g, '')),
      sum: rows.reduce((a, x) => a + x.count, 0),
    });
  });
  return out;
}

rmSync(SCRATCH, { recursive: true, force: true });
mkdirSync(SCRATCH, { recursive: true });

console.log(`-- the PUBLISHED riantr/LunaFlow@${VERSION} over ${CORPUS} --`);
const art = published(CORPUS, join(SCRATCH, 'out'));
if (!art) {
  console.error('the published run failed');
  process.exit(2);
}
console.log(`   the scratch directory: ${SCRATCH}\n`);

// --- 1. the table is bounded, the sidecar is lossless ------------------------
const tables = boundedTables(art.lines);
check('the published report bounds its findings tables', tables.length > 0, `${tables.length} bounded table(s)`);
for (const t of tables) {
  check(
    `a published table is capped at ${t.cap} and its count table sums to the whole set it names`,
    t.cap > 0 && t.cap < t.whole && t.sum === t.whole,
    `cap ${t.cap} of ${t.whole}, the count table sums to ${t.sum}`,
  );
}
const shown = tables.reduce((a, t) => a + t.cap, 0);
check(
  'the published sidecar holds every finding the tables did not show',
  art.findings.length > shown,
  `${art.findings.length} findings in the sidecar, ${shown} shown`,
);
check(
  'the published report says the sidecar keeps every finding',
  art.lines.some((l) => /every finding.*sidecar|_findings\.jsonl` sidecar/.test(l)),
);

// --- 2. D1: the allocation-size rule fires ----------------------------------
check(
  'D1: the published analyser reports a tainted allocation size',
  (art.mix.get('TAINT-ALLOC') ?? 0) > 0,
  `${art.mix.get('TAINT-ALLOC') ?? 0} TAINT-ALLOC finding(s)`,
);

// --- 3. D2: the same finding in two files is two findings -------------------
const d2dir = join(SCRATCH, 'd2');
rmSync(d2dir, { recursive: true, force: true });
mkdirSync(d2dir, { recursive: true });
const SAME = `pub fn f(n : Int) -> Array[Int] {
  Array::make(n, 0)
}
`;
writeFileSync(join(d2dir, 'a.mbt'), SAME, 'utf8');
writeFileSync(join(d2dir, 'b.mbt'), SAME.replace('pub fn f', 'pub fn g'), 'utf8');
const d2 = published(d2dir, join(SCRATCH, 'd2out'));
if (!d2) {
  check('the published analyser ran on the two-file module', false);
} else {
  const alloc = d2.findings.filter(
    (o) => (o.family ?? o.rule) === 'TAINT-ALLOC' && o.method === 'L2-abstract',
  );
  check('D2: the same finding in two files is two findings', alloc.length === 2, `${alloc.length} L2 finding(s)`);
  const files = [...new Set(alloc.map((o) => o.file))].sort();
  check(
    'D2: and the two findings name the two files',
    files.length === 2 && files.some((f) => f.includes('a.mbt')) && files.some((f) => f.includes('b.mbt')),
    files.join(', '),
  );
}

// --- the published report matches the local build ----------------------------
const localDir = join(root, '_build', 'qa', 'loop_acceptance', 'fixture');
let same = false;
let localCount = null;
if (existsSync(localDir)) {
  const lf = readdirSync(localDir).find((f) => f.endsWith('_findings.jsonl'));
  if (lf) {
    const local = readFileSync(join(localDir, lf), 'utf8')
      .split('\n')
      .filter((l) => l.trim().length > 0)
      .map((l) => JSON.parse(l));
    localCount = local.length;
    const localMix = new Map();
    for (const o of local) {
      const k = o.family ?? o.rule ?? 'unknown';
      localMix.set(k, (localMix.get(k) ?? 0) + 1);
    }
    same = local.length === art.findings.length && [...localMix].every(([k, v]) => (art.mix.get(k) ?? 0) === v);
  }
}
check(
  'the published report matches the local build on the same corpus',
  same,
  localCount === null ? 'no local reference run' : `local ${localCount} findings vs published ${art.findings.length}`,
);

console.log('');
console.log(
  failures === 0
    ? `PUBLISHED ${VERSION}: all ${checks} checks pass -- the registry serves the three items.`
    : `PUBLISHED ${VERSION}: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
