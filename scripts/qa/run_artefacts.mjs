#!/usr/bin/env node
// THE TRACE FILES A RUN WRITES, FOUND BY WHAT THEY ARE.
//
// A scan writes ONE TRACE FILE PER PACKAGE since 0.1.37 -- the per-package mode
// is the DEFAULT -- so a run's trace is `<stem>_<package>_trace.jsonl` and there
// is no single file name to state.  A check that names one (`<stem>_trace.jsonl`)
// finds nothing the day the mode splits the trace, and then compares an empty
// string with an empty string: that looks exactly like a pass.
//
// And naming one is not the only way to measure nothing.  A check that takes the
// FIRST `*_trace.jsonl` in the directory measures ONE PACKAGE and calls it the
// run's trace -- and a directory that has been used before holds the files of an
// EARLIER run too, because the artefact names carry the resolved version and the
// per-package names carry the package.  The e2e harness hit exactly that: it
// read a leftover `..._trace.jsonl` from a run before the default flip, compared
// it with itself, and passed.
//
// So the trace is FOUND: every `*_trace.jsonl` in the directory, sorted by name,
// and their bytes SUMMED.  The total is what the publish envelope is about, and
// it is what a size ceiling has to be measured against.
//
// Dependency-free, like the rest of the harness.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

/// The trace files in an output directory, sorted by name.
export function traceFiles(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith('_trace.jsonl'))
    .sort();
}

/// The trace files' bodies, joined in name order.
export function traceBody(dir, files = traceFiles(dir)) {
  return files.map((f) => readFileSync(join(dir, f), 'utf8')).join('');
}

/// The trace files' total size in bytes.
export function traceBytes(dir, files = traceFiles(dir)) {
  return files.reduce((sum, f) => sum + statSync(join(dir, f)).size, 0);
}
