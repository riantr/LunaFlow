#!/usr/bin/env node
// Spot check: after the MAX_PARSE_DEPTH guard, pathologically nested input must
// degrade to a *recorded gap* (parse issue in the report), never a crash and
// never a silently empty analysis.
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = resolveCli(root);
const base = join(root, '_build', 'qa', 'deep');
if (existsSync(base)) rmSync(base, { recursive: true, force: true });
mkdirSync(join(base, 'mod'), { recursive: true });
writeFileSync(join(base, 'mod', 'moon.mod'), 'name = "deep/demo"\nversion = "0.1.0"\n');

const bodies = {
  'nest-if-5000': 'pub fn f(x : Int) -> Int {\n' + 'if x > 0 { '.repeat(5000) + 'x' + ' }'.repeat(5000) + '\n}\n',
  'nest-paren-2000': 'pub fn g(x : Int) -> Int {\n  let y = ' + '('.repeat(2000) + 'x' + ')'.repeat(2000) + '\n  y\n}\n',
};

let bad = 0;
for (const [name, src] of Object.entries(bodies)) {
  writeFileSync(join(base, 'mod', 'lib.mbt'), src);
  const r = spawnSync(exe, ['analyze', '--dir', 'mod', '--out', 'out'], {
    cwd: base,
    encoding: 'utf8',
    timeout: 60000,
  });
  const mdPath = join(base, 'out', 'deep_demo_0.1.0.md');
  const md = existsSync(mdPath) ? readFileSync(mdPath, 'utf8') : '';
  const issuesRow = md.match(/\| Parse issues \| (\d+) \|/);
  const gaps = issuesRow ? Number(issuesRow[1]) : -1;
  const summary = existsSync(join(base, 'out', 'deep_demo_0.1.0_summary.json'))
    ? JSON.parse(readFileSync(join(base, 'out', 'deep_demo_0.1.0_summary.json'), 'utf8'))
    : null;
  const ok = r.status === 0 && gaps >= 1 && summary !== null && summary.functions >= 1;
  if (!ok) bad += 1;
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(16)} exit=${r.status} nesting-gaps=${gaps} ` +
      `funcs=${summary ? summary.functions : 'n/a'} stmts=${summary ? summary.statements : 'n/a'} ` +
      `unsupported=${summary ? summary.unsupported_statements : 'n/a'}`,
  );
}
console.log(`\nRESULT: ${Object.keys(bodies).length - bad}/${Object.keys(bodies).length} degrade-to-gap`);
process.exit(bad === 0 ? 0 : 1);
