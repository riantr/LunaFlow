#!/usr/bin/env node
// Regression: the harness must find the built CLI under either name.
//
// The MoonBit native target names the executable `cli.exe` on EVERY platform,
// including Linux, where the file is an ELF binary with a Windows extension:
//
//     riantr/LunaFlow/src/cli  native  .../build/src/cli/cli.exe
//
// The resolver used to pick the name by platform -- `cli.exe` on Windows and
// `cli` elsewhere -- so on a Linux CI runner it looked for a file that the
// toolchain never produced. The CLI never ran, and the harness failed later
// on a missing output file: a symptom, three steps away from the cause.
//
// This test builds the two directory layouts a toolchain could leave behind
// and asserts that the resolver finds the executable in both, and that it
// does NOT claim a binary that is not there.
//
// Usage: node scripts/qa/cli_resolver.mjs

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { resolveCli, requireCli } from './cli_bin.mjs';

const root = process.cwd();
const dir = join(root, '_build', 'qa', 'cli_resolver');
const exeDir = join(dir, '_build', 'native', 'debug', 'build', 'src', 'cli');

let failures = 0;
function check(name, ok, detail = '') {
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

rmSync(dir, { recursive: true, force: true });
mkdirSync(exeDir, { recursive: true });

// Layout 1: the toolchain's actual output -- `cli.exe` on every platform.
writeFileSync(join(exeDir, 'cli.exe'), 'binary');
let found = resolveCli(dir);
check('finds the executable named cli.exe', existsSync(found) && found.endsWith('cli.exe'), found);

// Layout 2: a toolchain that emits a plain `cli`.
rmSync(join(exeDir, 'cli.exe'), { force: true });
writeFileSync(join(exeDir, 'cli'), 'binary');
found = resolveCli(dir);
check('finds the executable named cli', existsSync(found) && found.endsWith('cli'), found);

// Layout 3: nothing built at all -- the resolver must not claim a binary.
rmSync(join(exeDir, 'cli'), { force: true });
found = resolveCli(dir);
check('reports no binary when nothing is built', !existsSync(found), found);

// And the OTHER half of the resolver's contract: a harness that needs the
// binary must not go on to fail somewhere else when it is not there.  It must
// stop with exit 2 -- "no verdict" -- and NAME the cause, because a missing
// binary says nothing about the tree, and a harness that reports it as a
// failed check accuses the tree of being broken.
//
// `requireCli` calls process.exit, so it is driven in a CHILD: the code is
// passed as an argument, with no shell in between, and the URL of the module
// is built with pathToFileURL so a Windows path is not mistaken for one.
const moduleUrl = pathToFileURL(join(root, 'scripts', 'qa', 'cli_bin.mjs')).href;
const call = (fn) =>
  spawnSync(
    process.execPath,
    ['--input-type=module', '-e', `import { ${fn} } from '${moduleUrl}'; ${fn}(${JSON.stringify(dir)});`],
    { encoding: 'utf8', timeout: 120000 },
  );
const missing = call('requireCli');
check(
  'requireCli exits 2 when the binary is not there -- no verdict, not a failure',
  missing.status === 2,
  `exit=${missing.status}`,
);
check(
  '  and it names the cause and the way to get it',
  /missing CLI binary/.test(missing.stderr ?? '') &&
    /moon build src\/cli/.test(missing.stderr ?? ''),
  (missing.stderr ?? '').split(/\r?\n/).filter(Boolean)[0] ?? '',
);

// With the binary there, the same call returns it and says nothing.
writeFileSync(join(exeDir, 'cli.exe'), 'binary');
const present = call('requireCli');
check(
  'requireCli returns the binary when it is there',
  present.status === 0,
  `exit=${present.status}`,
);

rmSync(dir, { recursive: true, force: true });

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
