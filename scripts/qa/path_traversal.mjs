#!/usr/bin/env node
// Path-traversal regression test for report output naming.
//
// The report stem is built from the analysed module's `name`/`version` manifest
// fields, so a hostile module can try to steer the output path out of --out.
// `coord_file_stem` replaces "/" with "_"; this test proves whether the other
// separators and `..` chains are neutralised too.
//
// Usage: node scripts/qa/path_traversal.mjs
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readdirSync, statSync, rmSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = requireCli(root);
const base = join(root, '_build', 'qa', 'trav');

const SOURCE = 'pub fn f(x : Int) -> Int {\n  x\n}\n';
const cases = [
  { name: 'version-dots-2', manifest: 'name = "fuzz/demo"\nversion = "../../escaped"\n' },
  { name: 'version-dots-5', manifest: 'name = "fuzz/demo"\nversion = "../../../../../../escaped"\n' },
  { name: 'name-dots-5', manifest: 'name = "../../../../../../escaped"\nversion = "0.1.0"\n' },
  { name: 'name-backslash', manifest: 'name = "..\\\\..\\\\..\\\\..\\\\escaped"\nversion = "0.1.0"\n' },
  { name: 'name-backslash-slash', manifest: 'name = "..\\\\../..\\\\../escaped"\nversion = "0.1.0"\n' },
  { name: 'version-backslash', manifest: 'name = "fuzz/demo"\nversion = "..\\\\..\\\\..\\\\..\\\\escaped"\n' },
  { name: 'abs-path-name', manifest: 'name = "/tmp/pwn"\nversion = "0.1.0"\n' },
];

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

let failures = 0;
if (existsSync(base)) rmSync(base, { recursive: true, force: true });

for (const c of cases) {
  const caseDir = join(base, c.name);
  const work = join(caseDir, 'work');
  mkdirSync(join(work, 'mod'), { recursive: true });
  writeFileSync(join(work, 'mod', 'moon.mod'), c.manifest);
  writeFileSync(join(work, 'mod', 'lib.mbt'), SOURCE);

  const r = spawnSync(exe, ['analyze', '--dir', 'mod', '--out', 'out'], {
    cwd: work,
    encoding: 'utf8',
    timeout: 60000,
    maxBuffer: 32 * 1024 * 1024,
  });

  // every file the run produced, relative to the case root, that is not under work/out
  const produced = walk(caseDir)
    .filter((p) => /\.(md|json|jsonl)$/.test(p))
    .map((p) => relative(caseDir, p).replace(/\\/g, '/'))
    .filter((p) => !p.startsWith('work/out/'));
  const escaped = produced.length > 0;
  if (escaped) failures += 1;
  console.log(
    `${escaped ? 'ESCAPE' : 'OK    '}  ${c.name.padEnd(22)} exit=${String(r.status).padEnd(4)} ` +
      (escaped ? `wrote: ${produced.join(', ')}` : 'artefacts confined to out/'),
  );
  if (escaped) {
    for (const p of produced) {
      const abs = join(caseDir, p);
      console.log(`         -> ${abs}`);
    }
  }
}

console.log(`\nRESULT: ${cases.length - failures}/${cases.length} cases confined, ${failures} escape(s)`);
process.exit(failures === 0 ? 0 : 1);
