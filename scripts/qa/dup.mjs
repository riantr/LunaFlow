#!/usr/bin/env node
// Clone detection (CPD-style) for MoonBit sources.
//
// Token-normalised, line-based sliding window with greedy extension: a clone is
// >= 6 consecutive non-trivial code lines that appear verbatim (whitespace and
// trailing comments normalised) in at least two places. Reports the duplication
// ratio and the largest clusters.
//
// Usage: node scripts/qa/dup.mjs [--min-lines 6] [--top 12]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = process.cwd();
const argOf = (name, dflt) => (process.argv.includes(name) ? Number(process.argv[process.argv.indexOf(name) + 1]) : dflt);
const MIN = argOf('--min-lines', 6);
const TOP = argOf('--top', 12);

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith('.mbt')) out.push(p);
  }
  return out;
}

const files = [...walk(join(root, 'src')), ...walk(join(root, 'fixtures'))];
const corpus = [];
let totalCodeLines = 0;

for (const f of files) {
  const rel = relative(root, f).replace(/\\/g, '/');
  const raw = readFileSync(f, 'utf8').split(/\r?\n/);
  const lines = [];
  raw.forEach((line, idx) => {
    const t = line.trim();
    if (t === '' || t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) return;
    if (t === '///|') return;
    lines.push({ no: idx + 1, norm: t.replace(/\s+/g, ' ').replace(/\s*\/\/.*$/, '') });
  });
  totalCodeLines += lines.length;
  corpus.push({ file: rel, lines, isTest: rel.endsWith('_test.mbt') });
}

const index = new Map();
for (const doc of corpus) {
  for (let i = 0; i + MIN <= doc.lines.length; i += 1) {
    const key = doc.lines.slice(i, i + MIN).map((l) => l.norm).join('\u0001');
    if (!index.has(key)) index.set(key, []);
    index.get(key).push({ doc, i });
  }
}

const groups = [...index.entries()].filter(([, occ]) => new Set(occ.map((o) => o.doc.file + ':' + o.i)).size >= 2);
const covered = new Map(); // file -> Set(lineNo)
const clusters = [];

for (const [key, occ] of groups) {
  const a = occ[0];
  const b = occ.find((o) => o.doc.file !== a.doc.file || o.i !== a.i);
  if (!b) continue;
  // greedy extension
  let len = MIN;
  while (
    a.i + len < a.doc.lines.length &&
    b.i + len < b.doc.lines.length &&
    a.doc.lines[a.i + len].norm === b.doc.lines[b.i + len].norm
  ) {
    len += 1;
  }
  const aStart = a.doc.lines[a.i].no;
  const bStart = b.doc.lines[b.i].no;
  const signature = `${a.doc.file}:${aStart}+${len}|${b.doc.file}:${bStart}+${len}`;
  clusters.push({
    len,
    occurrences: occ.length,
    signature,
    sample: a.doc.lines.slice(a.i, a.i + Math.min(len, 3)).map((l) => l.norm).join(' ⏎ ').slice(0, 150),
    files: [...new Set(occ.map((o) => o.doc.file))],
    inTests: a.doc.isTest && b.doc.isTest,
  });
  for (const o of occ) {
    const set = covered.get(o.doc.file) ?? new Set();
    for (let k = 0; k < len; k += 1) {
      const line = o.doc.lines[o.i + k];
      if (line) set.add(line.no);
    }
    covered.set(o.doc.file, set);
  }
}

// keep one entry per (file pair, start) signature
const seen = new Set();
const uniq = clusters.filter((c) => (seen.has(c.signature) ? false : (seen.add(c.signature), true)));
const coveredLines = [...covered.values()].reduce((a, s) => a + s.size, 0);

console.log(`clone detection — window ${MIN} lines, ${corpus.length} files, ${totalCodeLines} code lines\n`);
console.log(`duplicated lines: ${coveredLines} / ${totalCodeLines} = **${((100 * coveredLines) / totalCodeLines).toFixed(1)}%**`);
console.log(`clone clusters (≥2 occurrences): ${uniq.length}\n`);
console.log('| lines | occurrences | files | sample |');
console.log('| ---: | ---: | --- | --- |');
for (const c of uniq.sort((x, y) => y.len * y.occurrences - x.len * x.occurrences).slice(0, TOP)) {
  console.log(`| ${c.len} | ${c.occurrences} | ${c.files.join(', ').replace(/^src\/app\//, '')} | ${c.sample.replace(/\|/g, '\\|')} |`);
}
