#!/usr/bin/env node
// Dependency-free acceptance checker for LunaFlow reports.
// Usage: node scripts/verify.mjs [reportDir]

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, basename } from 'node:path';

const dir = process.argv[2] ?? 'reports';
const required = [
  'riantr_moonbit_doubleML@latest_0.164.62.md',
  'riantr_moonbit_static_analysis@latest_0.4.43.md',
  'local_module_0.0.0.md',
];

const sections = [
  '## 1. Acquisition and version pinning',
  '## 2. Ingestion statistics',
  '## 3. Proof-strength levels and funnel',
  '## 4. Control-flow analysis',
  '## 5. Data flow and taint',
  '## 6. Value ranges',
  '## 7. Program slicing',
  '## 8. Contracts and verification conditions (L3)',
  '## 9. Method summary',
  '## 10. Reproduction',
];

let failures = 0;
let checks = 0;

function check(name, ok, detail = '') {
  checks += 1;
  if (ok) {
    console.log(`PASS  ${name}${detail ? ' — ' + detail : ''}`);
  } else {
    failures += 1;
    console.log(`FAIL  ${name}${detail ? ' — ' + detail : ''}`);
  }
}

function mermaidBlocks(md) {
  const blocks = [];
  const re = /```mermaid\n([\s\S]*?)```/g;
  let m;
  while ((m = re.exec(md)) !== null) blocks.push(m[1]);
  return blocks;
}

function validateMermaid(src) {
  const issues = [];
  const lines = src.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length === 0) return ['empty diagram'];
  if (!/^(flowchart|graph)\s/.test(lines[0].trim())) issues.push('bad header');
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const quotes = (line.match(/"/g) ?? []).length;
    if (quotes % 2 !== 0) issues.push(`odd quotes on line ${i + 1}`);
    // Mermaid allows brackets inside quoted labels; only the node syntax outside quotes must balance.
    const unquoted = line.replace(/"[^"]*"/g, '""');
    const open = (unquoted.match(/\[/g) ?? []).length;
    const close = (unquoted.match(/\]/g) ?? []).length;
    if (open !== close) issues.push(`unbalanced [] on line ${i + 1}`);
    if (/\n/.test(line)) issues.push(`raw newline on line ${i + 1}`);
  }
  return issues;
}

function summary(file) {
  return JSON.parse(readFileSync(file, 'utf8'));
}

console.log(`LunaFlow acceptance — report dir: ${dir}\n`);

for (const name of required) {
  const path = join(dir, name);
  if (!existsSync(path)) {
    check(`report exists: ${name}`, false, 'missing');
    continue;
  }
  const md = readFileSync(path, 'utf8');
  check(`report exists: ${name}`, true, `${statSync(path).size} B`);

  for (const s of sections) {
    check(`${name}: section "${s}"`, md.includes(s));
  }

  const blocks = mermaidBlocks(md);
  check(`${name}: has CFG + taint + slice diagrams`, blocks.length >= 3, `${blocks.length} blocks`);
  let bad = 0;
  for (const b of blocks) {
    if (validateMermaid(b).length > 0) bad += 1;
  }
  check(`${name}: all Mermaid blocks structurally valid`, bad === 0, `${bad} invalid`);

  const sliceSection = md.split('## 7. Program slicing')[1] ?? '';
  const sliceBlocks = mermaidBlocks(sliceSection);
  check(`${name}: slice section has a Mermaid block`, sliceBlocks.length >= 1);
  const sliceNodes = sliceBlocks.reduce(
    (n, b) => n + b.split(/\r?\n/).filter((l) => /^\s+s\d+\[/.test(l)).length,
    0,
  );
  check(`${name}: slice diagram has ≥ 1 node`, sliceNodes >= 1, `${sliceNodes} nodes`);

  const funnelSection = md.split('## 3. Proof-strength levels and funnel')[1]?.split('## 4.')[0] ?? '';
  check(`${name}: funnel section has a Mermaid diagram`, mermaidBlocks(funnelSection).length >= 1);
  check(
    `${name}: funnel table has L1/L2/L3 rows`,
    funnelSection.includes('| L1 concrete |') &&
      funnelSection.includes('| L2 abstract |') &&
      funnelSection.includes('| L3 contracts |'),
  );

  const pointRows = (md.split('### 6.1 Per-program-point observations')[1] ?? '')
    .split('\n')
    .filter((l) => l.startsWith('| ') && !l.startsWith('| ---')).length;
  check(`${name}: per-program-point table has rows`, pointRows >= 2, `${pointRows} rows`);
}

const summaryExpectations = [
  ['riantr_moonbit_doubleML@latest_0.164.62_summary.json', 40000, 0.95],
  ['riantr_moonbit_static_analysis@latest_0.4.43_summary.json', 7000, 0.95],
  ['local_module_0.0.0_summary.json', 30, 1.0],
];

for (const [file, minStmts, minCoverage] of summaryExpectations) {
  const path = join(dir, file);
  if (!existsSync(path)) {
    check(`summary exists: ${file}`, false, 'missing');
    continue;
  }
  const s = summary(path);
  check(`summary exists: ${file}`, true);
  check(
    `${file}: statements ≥ ${minStmts}`,
    s.statements >= minStmts,
    `${s.statements}`,
  );
  const total = s.statements + s.unsupported_statements;
  const ratio = total === 0 ? 1 : s.statements / total;
  check(
    `${file}: frontend coverage ≥ ${(minCoverage * 100).toFixed(0)}%`,
    ratio >= minCoverage,
    `${(ratio * 100).toFixed(2)}%`,
  );
  check(`${file}: trace events > 0`, s.trace_events > 0, `${s.trace_events}`);
  check(`${file}: taint sinks ≥ 1`, s.taint_sinks >= 1, `${s.taint_sinks}`);
  check(`${file}: dead-code findings ≥ 1`, s.dead_code >= 1, `${s.dead_code}`);
  check(`${file}: slices ≥ 1`, s.slices >= 1, `${s.slices}`);
  check(`${file}: selected level ≥ 1`, s.level >= 1, `L${s.level}`);
  check(`${file}: abstract_findings present`, typeof s.abstract_findings === 'number', `${s.abstract_findings}`);
  check(
    `${file}: VC counters present`,
    typeof s.vcs_proved === 'number' &&
      typeof s.vcs_failed === 'number' &&
      typeof s.vcs_unknown === 'number',
  );
  check(
    `${file}: elapsed_ms ≤ 60000`,
    s.elapsed_ms <= 60000,
    `${s.elapsed_ms} ms`,
  );
}

const reports = readdirSync(dir).filter((f) => f.endsWith('.md'));
console.log(`\n${reports.length} Markdown report(s): ${reports.join(', ')}`);
console.log(`\nRESULT: ${checks - failures}/${checks} checks passed, ${failures} failure(s)`);
if (failures > 0) process.exit(1);