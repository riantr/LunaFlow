#!/usr/bin/env node
// Regression: a `--dir` scan must not ingest vendored or build trees.
//
// The source walker skips `_build`, `.git`, `.mooncakes`, `.repos`, `target`
// and `node_modules` by directory name. `.mooncakes` was missing from that
// list, and it is where the toolchain vendors a module's dependencies: a
// self-scan of LunaFlow's own workspace reported 384 parsed files, of which
// 362 came from the vendored `moonbitlang/async` module. Every finding and
// every number in that report then described a third party's code.
//
// WHAT IS ASSERTED, AND WHY IT IS NOT THE OBVIOUS THING.
//
// The obvious assertion -- "the report does not contain the string
// `_build/`" -- is wrong, and it failed on the Linux CI runner. The report
// records the analysed ROOT, and the scratch directory this harness builds
// lives under `_build/`, so the report names `_build/` in the root path
// without having ingested anything from it.
//
// So the assertions are about INGESTED CONTENT, not about path strings: the
// foreign file has a name and a function that the module's own file does not
// have, and neither may appear in the report.
//
// Usage: node scripts/qa/vendor_isolation.mjs

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = resolveCli(root);

if (!existsSync(exe)) {
  console.error(`FAIL  binary missing: ${exe}\n       run: moon build src/cli --target native`);
  process.exit(1);
}

const work = resolve(root, '_build', 'qa', 'vendor_isolation', 'work');
const out = resolve(root, '_build', 'qa', 'vendor_isolation', 'out');

rmSync(work, { recursive: true, force: true });
rmSync(out, { recursive: true, force: true });

// The module's own source.
const own = `///|
pub fn own_source_marker(x : Int32) -> Int32 {
  x + 1
}
`;

// The foreign source: the name and the function are the markers.
const foreign = `///|
pub fn foreign_source_marker() -> Int32 {
  42
}
`;

const FOREIGN_FILE = 'foreign_dep.mbt';
const FOREIGN_FN = 'foreign_source_marker';
const OWN_FN = 'own_source_marker';

// One real source file, plus one file behind every skipped directory name.
mkdirSync(join(work, 'src'), { recursive: true });
writeFileSync(join(work, 'moon.mod'), 'name = "test/vendor_isolation"\n\nversion = "0.0.0"\n');
writeFileSync(join(work, 'src', 'app.mbt'), own);

const skipDirs = ['.mooncakes', '.repos', '.git', '_build', 'target', 'node_modules'];
for (const d of skipDirs) {
  const dir = join(work, d, 'dep', 'src');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, FOREIGN_FILE), foreign);
}

const r = spawnSync(
  exe,
  ['analyze', '--dir', work, '--out', out, '--quiet'],
  { cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 32 * 1024 * 1024 },
);

let failures = 0;
function check(name, ok, detail = '') {
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

check('exit code 0', r.status === 0, `exit=${r.status} ${r.stderr ?? ''}`.trim());

const summaries = readdirSync(out).filter((f) => f.endsWith('_summary.json'));
check('one summary written', summaries.length === 1, summaries.join(', '));

if (summaries.length === 1) {
  const s = JSON.parse(readFileSync(join(out, summaries[0]), 'utf8'));
  check('only the module source is parsed', s.files === 1, `files=${s.files}`);
}

const md = readdirSync(out).find((f) => f.endsWith('.md'));
check('one report written', Boolean(md), md ?? '');
if (md) {
  const text = readFileSync(join(out, md), 'utf8');
  // The foreign file was not ingested.
  check('report does not contain the foreign file name', !text.includes(FOREIGN_FILE), '');
  check('report does not contain the foreign function', !text.includes(FOREIGN_FN), '');
  // The module's own source WAS ingested, so the run is not a no-op.
  check('report contains the module own function', text.includes(OWN_FN), '');
  // Every skipped directory is a directory the walker must not descend into.
  for (const d of skipDirs) {
    check(
      `report does not contain a file under ${d}/`,
      !text.includes(`${d}/${FOREIGN_FILE}`),
      '',
    );
  }
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
