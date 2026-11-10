// Resolve the built CLI executable, on any platform.
//
// The executable is named after the package it comes from (`src/cli`), and
// the toolchain names it `cli.exe` on EVERY platform -- including Linux, where
// the file is an ELF binary with a Windows extension. That is not a typo in
// the MoonBit build output; it is what `moon build src/cli --target native`
// prints on the runner:
//
//     riantr/LunaFlow/src/cli  native  .../build/src/cli/cli.exe
//
// The harness used to hard-code that path, which was right on Windows and
// wrong on a Linux CI runner, where the resolver looked for a file named
// `cli` and found nothing. The failure surfaced as a downstream ENOENT on a
// summary file that was never written, which names the symptom and not the
// cause.
//
// So the resolver tries the names the toolchain actually produces, in the
// order it produces them.
//
// Dependency-free, like the rest of the harness.

import { existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const CANDIDATES = ['cli.exe', 'cli'];

export function resolveCli(root = process.cwd()) {
  const dir = join(root, '_build', 'native', 'debug', 'build', 'src', 'cli');
  for (const name of CANDIDATES) {
    const p = join(dir, name);
    if (existsSync(p) && statSync(p).isFile()) return p;
  }
  // Fall back to whatever the toolchain produced, for a layout this file has
  // not seen: the executable is the file the runner can start.
  if (existsSync(dir)) {
    for (const name of readdirSync(dir).sort()) {
      const p = join(dir, name);
      if (statSync(p).isFile() && CANDIDATES.includes(name)) return p;
    }
  }
  return join(dir, CANDIDATES[0]);
}

///|
/// Resolve the CLI, or stop with a message that names the cause.
///
/// A missing binary is not an error the harness should discover three steps
/// later as a missing output file: that names the symptom and not the cause.
/// Every harness that runs the CLI goes through this, so the message is the
/// same everywhere.
export function requireCli(root = process.cwd()) {
  const exe = resolveCli(root);
  if (!existsSync(exe)) {
    console.error(`missing CLI binary: ${exe}`);
    console.error('build it first: moon build src/cli --target native');
    process.exit(2);
  }
  return exe;
}
