#!/usr/bin/env node
// Sweep nesting depth and report how the parser degrades, so the MAX_PARSE_DEPTH
// guard's real behaviour is measured instead of assumed.
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = requireCli(root);
const base = join(root, '_build', 'qa', 'sweep');
if (existsSync(base)) rmSync(base, { recursive: true, force: true });
mkdirSync(join(base, 'mod'), { recursive: true });
writeFileSync(join(base, 'mod', 'moon.mod'), 'name = "sweep/demo"\nversion = "0.1.0"\n');

const rows = [];
for (const n of [10, 50, 100, 250, 256, 300, 500, 1000, 2000, 5000]) {
  const src = 'pub fn f(x : Int) -> Int {\n' + 'if x > 0 { '.repeat(n) + 'x' + ' }'.repeat(n) + '\n}\n';
  writeFileSync(join(base, 'mod', 'lib.mbt'), src);
  const r = spawnSync(exe, ['analyze', '--dir', 'mod', '--out', 'out'], { cwd: base, encoding: 'utf8', timeout: 60000 });
  const md = existsSync(join(base, 'out', 'sweep_demo_0.1.0.md'))
    ? readFileSync(join(base, 'out', 'sweep_demo_0.1.0.md'), 'utf8')
    : '';
  const num = (label) => {
    const m = md.match(new RegExp(`\\| ${label} \\| (\\d+)`));
    return m ? Number(m[1]) : -1;
  };
  rows.push({ depth: n, exit: r.status, stmts: num('Statements understood'), unsupported: num('Statements unsupported'), issues: num('Parse issues') });
}
console.log('| nest depth | exit | stmts | unsupported | parse issues |');
console.log('| ---: | ---: | ---: | ---: | ---: |');
for (const r of rows) console.log(`| ${r.depth} | ${r.exit} | ${r.stmts} | ${r.unsupported} | ${r.issues} |`);
