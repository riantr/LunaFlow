#!/usr/bin/env node
// Print the heading skeleton of a markdown file, so a README can be compared
// against a reference document section by section.
//
// Usage: node scripts/qa/headings.mjs <file.md> [--max N]
//
// FENCED CODE BLOCKS ARE SKIPPED. A shell comment inside a fenced block
// starts with `#`, and a line like `# the full funnel, with a slice on a
// variable` is a COMMENT, not a heading. Reading those as headings made the
// skeleton of a README with code examples look like it had six extra
// top-level sections, and the comparison this script exists for -- against
// `riantr/moonbit_static_analysis`, whose README has no `#` comments in its
// code blocks -- then reported a difference that was not one.
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/qa/headings.mjs <file.md> [--max N]');
  process.exit(2);
}
const maxIdx = process.argv.indexOf('--max');
const max = maxIdx >= 0 ? Number(process.argv[maxIdx + 1]) : Infinity;
const lines = readFileSync(file, 'utf8').split(/\r?\n/);
let n = 0;
let inFence = false;
for (const line of lines) {
  // A fence opens with ``` or ~~~ and closes with the same marker. The
  // closing fence may carry trailing whitespace, and nothing else does.
  const fence = /^\s*(```+|~~~+)/.exec(line);
  if (fence) {
    inFence = !inFence;
    continue;
  }
  if (inFence) continue;
  const m = /^(#{1,4})\s+(.*)$/.exec(line);
  if (!m) continue;
  n += 1;
  if (n > max) break;
  console.log(`${m[1].length}  ${m[2]}`);
}
