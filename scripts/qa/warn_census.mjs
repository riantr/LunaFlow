#!/usr/bin/env node
// SAST warning census: runs `moon check --target native` and aggregates every
// compiler warning by category and by file, so gate noise is measurable instead
// of eyeballed. Emits a Markdown table.
//
// Usage: node scripts/qa/warn_census.mjs [--json]
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const asJson = process.argv.includes('--json');

const r = spawnSync('moon check --target native', {
  cwd: root,
  encoding: 'utf8',
  maxBuffer: 256 * 1024 * 1024,
  shell: true,
});
const text = (r.stdout || '') + '\n' + (r.stderr || '');

const recs = [];
let currentFile = null;
let currentLine = null;
for (const raw of text.split(/\r?\n/)) {
  const loc = raw.match(/╭─\[\s*(.*?):(\d+):\d+\s*\]/);
  if (loc) {
    currentFile = loc[1].replace(/\\/g, '/').replace(/^.*?moonbit_LunaFlow\//, '');
    currentLine = Number(loc[2]);
    continue;
  }
  const w = raw.match(/Warning \(([a-z_]+)\)/);
  if (w) {
    recs.push({ file: currentFile ?? '(toolchain)', line: currentLine, kind: w[1] });
    continue;
  }
  const e = raw.match(/Error \(([a-z_]+)\)/);
  if (e) {
    recs.push({ file: currentFile ?? '(toolchain)', line: currentLine, kind: 'error:' + e[1] });
  }
}

const byKind = new Map();
const byFile = new Map();
for (const rec of recs) {
  byKind.set(rec.kind, (byKind.get(rec.kind) ?? 0) + 1);
  const key = rec.file;
  if (!byFile.has(key)) byFile.set(key, new Map());
  const m = byFile.get(key);
  m.set(rec.kind, (m.get(rec.kind) ?? 0) + 1);
}

const summaryLine = (text.match(/Finished\. moon:.*|Error:.*|failed.*/g) ?? []).pop() ?? '';

const sortedKinds = [...byKind.entries()].sort((a, b) => b[1] - a[1]);

if (asJson) {
  process.stdout.write(
    JSON.stringify(
      { exit: r.status, total: recs.length, kinds: Object.fromEntries(sortedKinds), records: recs },
      null,
      2,
    ) + '\n',
  );
} else {
  console.log(`moon check exit=${r.status}  total warnings/errors=${recs.length}`);
  console.log(`tail: ${summaryLine}`);
  console.log('\n| category | count |');
  console.log('| --- | ---: |');
  for (const [k, v] of sortedKinds) console.log(`| ${k} | ${v} |`);
  console.log('\n| file | warnings | detail |');
  console.log('| --- | ---: | --- |');
  const files = [...byFile.entries()]
    .map(([f, m]) => ({ f, n: [...m.values()].reduce((a, b) => a + b, 0), m }))
    .sort((a, b) => b.n - a.n);
  for (const { f, n, m } of files) {
    const detail = [...m.entries()].sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(', ');
    console.log(`| ${f} | ${n} | ${detail} |`);
  }
}
