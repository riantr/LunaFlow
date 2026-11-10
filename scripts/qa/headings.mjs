#!/usr/bin/env node
// Print the heading skeleton of a markdown file, so a README can be compared
// against a reference document section by section.
//
// Usage: node scripts/qa/headings.mjs <file.md> [--max N]
import { readFileSync } from 'node:fs';

const file = process.argv[2];
const maxIdx = process.argv.indexOf('--max');
const max = maxIdx >= 0 ? Number(process.argv[maxIdx + 1]) : Infinity;
const lines = readFileSync(file, 'utf8').split(/\r?\n/);
let n = 0;
for (const line of lines) {
  const m = /^(#{1,4})\s+(.*)$/.exec(line);
  if (!m) continue;
  n += 1;
  if (n > max) break;
  console.log(`${m[1].length}  ${m[2]}`);
}
