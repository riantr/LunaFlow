// THE COMMITTED ARTEFACT, FOUND RATHER THAN NAMED.
//
// The corpus version is part of the artefact's file name, and the REGISTRY
// moves it: `riantr/moonbit_doubleML` went 0.164.64 -> 0.164.66 while this
// repository was working on other things.  A checker that carried the
// version in its own source would stop finding the artefact the day the
// registry moved -- and it would then compare NOTHING, which looks exactly
// like a pass.
//
// So the file is FOUND in the tree's own reports directory, by its prefix.
//
// The same rule the registry's own reader follows: the LAST match wins, so a
// newer version of the same corpus is preferred over an older one that is
// still lying in the directory.

import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

///|
/// The committed artefact with the given prefix and suffix, or null.
export function committedArtefact(root, prefix, suffix) {
  const dir = join(root, 'reports');
  if (!existsSync(dir)) return null;
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(prefix) && f.endsWith(suffix))
    .sort();
  return files.length > 0 ? join(dir, files[files.length - 1]) : null;
}

///|
/// The STEM of the committed artefact -- the path without its suffix -- so a
/// caller can reach the report, the sidecar and the summary that share it.
export function committedArtefactStem(root, prefix) {
  const dir = join(root, 'reports');
  if (!existsSync(dir)) return null;
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(prefix) && f.endsWith('.md'))
    .sort();
  return files.length > 0 ? join(dir, files[files.length - 1].slice(0, -'.md'.length)) : null;
}

// Dependency-free, like the rest of the harness.
