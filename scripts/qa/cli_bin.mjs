// Resolve the built CLI executable, on any platform.
//
// The executable is named after the package it comes from (`src/cli`), with a
// `.exe` suffix on Windows and no suffix elsewhere. The harness used to
// hard-code `cli.exe`, which made every script in this directory unusable on
// a Linux CI runner -- and the name is resolved by looking at what the
// toolchain actually produced rather than by guessing it.
//
// Dependency-free, like the rest of the harness.

import { existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

export function resolveCli(root = process.cwd()) {
  const dir = join(root, '_build', 'native', 'debug', 'build', 'src', 'cli');
  const preferred = process.platform === 'win32' ? ['cli.exe'] : ['cli'];
  for (const name of preferred) {
    const p = join(dir, name);
    if (existsSync(p) && statSync(p).isFile()) return p;
  }
  // Fall back to whatever the toolchain produced, for a layout this file has
  // not seen: a file without an extension is the executable.
  if (existsSync(dir)) {
    for (const name of readdirSync(dir).sort()) {
      const p = join(dir, name);
      if (statSync(p).isFile() && !name.includes('.')) return p;
    }
  }
  return join(dir, preferred[0]);
}
