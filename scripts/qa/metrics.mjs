#!/usr/bin/env node
// Metrics for the LunaFlow sources: size, function shape, cyclomatic estimate,
// comment/test ratio, and per-file line coverage from the Cobertura report that
// `moon coverage report -f cobertura` produces.
//
// Usage: node scripts/qa/metrics.mjs [--coverage _build/qa/coverage.xml]
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = process.cwd();
const covArgIdx = process.argv.indexOf('--coverage');
const covPath = join(root, covArgIdx >= 0 ? process.argv[covArgIdx + 1] : '_build/qa/coverage.xml');

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith('.mbt')) out.push(p);
  }
  return out;
}

const files = [...walk(join(root, 'src')), ...walk(join(root, 'fixtures'))];
const perFile = [];
let totals = { lines: 0, code: 0, comment: 0, blank: 0, funcs: 0, decisions: 0, tests: 0, todos: 0, longest: 0 };
const longFuncs = [];

for (const f of files) {
  const rel = relative(root, f).replace(/\\/g, '/');
  const text = readFileSync(f, 'utf8');
  const lines = text.split(/\r?\n/);
  let code = 0;
  let comment = 0;
  let blank = 0;
  let longest = 0;
  let todos = 0;
  for (const line of lines) {
    const t = line.trim();
    if (t === '') blank += 1;
    else if (t.startsWith('//') || t.startsWith('///|') || t.startsWith('/*') || t.startsWith('*')) comment += 1;
    else code += 1;
    if (/TODO|FIXME|XXX|HACK/.test(line)) todos += 1;
    longest = Math.max(longest, line.length);
  }
  // functions: top-level `fn name(` at column 0, plus `pub fn`, `async fn`, methods
  const fnRe = /^(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)/;
  const fns = [];
  let cur = null;
  let depth = 0;
  lines.forEach((line, idx) => {
    const m = fnRe.exec(line);
    if (m && depth === 0) {
      cur = { name: m[1], start: idx + 1, lines: 0, decisions: 0 };
      fns.push(cur);
    }
    for (const ch of line) {
      if (ch === '{') depth += 1;
      else if (ch === '}') depth = Math.max(0, depth - 1);
    }
    if (cur) {
      cur.lines += 1;
      cur.decisions += (line.match(/\b(if|else if|while|for|match)\b/g) ?? []).length;
      cur.decisions += (line.match(/&&|\|\|/g) ?? []).length;
    }
  });
  const decisions = fns.reduce((a, x) => a + x.decisions, 0);
  for (const fn of fns) {
    if (fn.lines >= 60) longFuncs.push({ file: rel, name: fn.name, lines: fn.lines, decisions: fn.decisions });
  }
  perFile.push({
    file: rel,
    lines: lines.length,
    code,
    comment,
    blank,
    funcs: fns.length,
    decisions,
    tests: (text.match(/^test\s+"/gm) ?? []).length,
    todos,
    longest,
    avgFunc: fns.length ? Math.round((code / fns.length) * 10) / 10 : 0,
  });
  totals.lines += lines.length;
  totals.code += code;
  totals.comment += comment;
  totals.blank += blank;
  totals.funcs += fns.length;
  totals.decisions += decisions;
  totals.tests += (text.match(/^test\s+"/gm) ?? []).length;
  totals.todos += todos;
  totals.longest = Math.max(totals.longest, longest);
}

// coverage
let cov = null;
if (existsSync(covPath)) {
  const xml = readFileSync(covPath, 'utf8');
  const classes = [];
  const classRe = /<class name="([^"]+)" filename="([^"]+)" line-rate="([\d.]+)"[^>]*>([\s\S]*?)<\/class>/g;
  let m;
  while ((m = classRe.exec(xml)) !== null) {
    const body = m[4];
    const entries = [...body.matchAll(/<line number="(\d+)" hits="(\d+)"/g)];
    const valid = entries.length;
    const covered = entries.filter((e) => Number(e[2]) > 0).length;
    classes.push({ file: m[2].replace(/\\/g, '/'), rate: Number(m[3]), valid, covered });
  }
  const rate = Number((xml.match(/line-rate="([\d.]+)"/) ?? [])[1] ?? 0);
  cov = { rate, classes };
}

const srcFiles = perFile.filter((f) => f.file.startsWith('src/'));
const testFiles = srcFiles.filter((f) => f.file.endsWith('_test.mbt'));
const prodFiles = srcFiles.filter((f) => !f.file.endsWith('_test.mbt'));
const sum = (xs, k) => xs.reduce((a, x) => a + x[k], 0);

console.log('## Size and shape\n');
console.log('| scope | files | lines | code | comment | blank | comment % | functions | decisions | avg code lines/fn | tests | TODO |');
console.log('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
const row = (label, fs) => {
  const code = sum(fs, 'code');
  const comment = sum(fs, 'comment');
  const funcs = sum(fs, 'funcs');
  console.log(
    `| ${label} | ${fs.length} | ${sum(fs, 'lines')} | ${code} | ${comment} | ${sum(fs, 'blank')} | ` +
      `${code + comment ? ((100 * comment) / (code + comment)).toFixed(1) : '0.0'}% | ${funcs} | ${sum(fs, 'decisions')} | ` +
      `${funcs ? (code / funcs).toFixed(1) : '0.0'} | ${sum(fs, 'tests')} | ${sum(fs, 'todos')} |`,
  );
};
row('all src', srcFiles);
row('production', prodFiles);
row('tests', testFiles);
row('fixtures', perFile.filter((f) => f.file.startsWith('fixtures/')));

console.log('\n## Per-file\n');
console.log('| file | lines | code | funcs | decisions | tests | coverage |');
console.log('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
const covFor = (file) => {
  if (!cov) return 'n/a';
  const hit = cov.classes.find((c) => c.file.endsWith(file.replace(/^src\//, '')) || c.file === file);
  if (!hit || hit.valid === 0) return 'n/a';
  return `${(100 * hit.rate).toFixed(0)}%`;
};
for (const f of perFile.sort((a, b) => b.lines - a.lines)) {
  console.log(`| ${f.file} | ${f.lines} | ${f.code} | ${f.funcs} | ${f.decisions} | ${f.tests} | ${covFor(f.file)} |`);
}

if (cov) {
  console.log(`\n## Line coverage (moon coverage, src/app)\n`);
  console.log(`overall: **${(100 * cov.rate).toFixed(2)}%**`);
  const worst = cov.classes.filter((c) => c.valid >= 20).sort((a, b) => a.rate - b.rate).slice(0, 8);
  console.log('\n| file | covered/valid | rate |');
  console.log('| --- | ---: | ---: |');
  for (const c of worst) console.log(`| ${c.file} | ${c.covered}/${c.valid} | ${(100 * c.rate).toFixed(1)}% |`);
}

if (longFuncs.length) {
  console.log('\n## Functions ≥ 60 lines\n');
  console.log('| file | function | lines | decisions |');
  console.log('| --- | --- | ---: | ---: |');
  for (const f of longFuncs.sort((a, b) => b.lines - a.lines).slice(0, 15)) {
    console.log(`| ${f.file} | \`${f.name}\` | ${f.lines} | ${f.decisions} |`);
  }
}
