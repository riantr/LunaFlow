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

import { mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

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

rmSync(dir, { recursive: true, force: true });

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
