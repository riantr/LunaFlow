#!/usr/bin/env node
// THE DEFAULT OUTPUT DIRECTORY, AND THE CORPUS IT MUST NOT TOUCH.
//
// MEASURED BUG (2026-11-28): a bare `moonx riantr/LunaFlow@latest` wrote 13
// files into `reports/`.  In THIS repository `reports/` is the COMMITTED
// CORPUS -- the report, the sidecar and the summary of the two corpora and
// of the fixture -- so the self-check OVERWROTE the evidence it was supposed
// to be compared against, and the overwrite read as a change in the
// analysis.
//
// MEASURED BUG IN THIS VERY CHECK (2026-11-28): the first version of this
// check CLEARED the directory it was told to expect artefacts in --
// `rmSync(join(ROOT, EXPECT))` -- and the falsifier pointed that at the OLD
// default, which IS the committed corpus.  So the check DELETED the corpus
// it was measuring.  The 63-step gate came back GREEN with `reports/` gone
// from disk: `git status` showed 28 deleted files, and the check that was
// supposed to protect the corpus had deleted it.  A check that destroys the
// thing it measures is not a check, and a gate that cannot see that is not a
// gate.
//
// TWO RULES, AND THEY ARE THE POINT OF THIS REWRITE.
//
//   1. THE EXPECTATION IS DERIVED, NOT CARRIED.  The default the tool uses is
//      read out of the tool's OWN source -- `Opts::default()` in
//      `src/command/command.mbt` -- and the run is MEASURED: the artefacts
//      are found where they landed, not assumed to be where the check hoped.
//      A check that carries the answer it is looking for cannot tell a fix
//      from a coincidence, and it cannot notice a change to the declaration.
//
//   2. THE CHECK MAY ONLY CLEAR A DISPOSABLE DIRECTORY.  Clearing is what
//      tells "the run wrote this" from "this was already here" -- the
//      artefacts are deterministic, so a leftover would answer the question
//      wrongly.  So the check clears the expected directory, and ONLY when
//      that directory is inside the build tree.  The corpus is not in the
//      build tree, and the corpus is not cleared.  Ever.
//
// THE CLAIM, IN THREE PARTS.
//
//   1. A run with no `--out` writes into the DEFAULT output directory, and
//      into nothing else: not into the working directory, and not into
//      `reports/`.
//   2. That default directory is DISPOSABLE -- the repository's own ignore
//      rules exclude it, and the repository tracks NOTHING under it.  The
//      corpus fails the second half of that test, which is exactly why it
//      cannot be the default.
//   3. In the tree under test, a run with no `--out` leaves the committed
//      corpus BYTE-IDENTICAL -- the same files, the same sizes, the same
//      contents -- and the README's `--out` row names the default the tool
//      declares.
//
// Part 3 is the one the bug is about, and it is measured on the repository's
// OWN corpus rather than on a copy: the claim is that the committed evidence
// survives a self-check.
//
// `--expect <dir>` asks a different question -- "what if the default were
// this?" -- and the falsifier uses it to point the check at the OLD default
// (`reports`).  The check must then go red, AND the corpus must still be
// there afterwards.
//
// Usage:
//   node scripts/qa/default_output.mjs [--expect <dir>] [--corpus <dir>] [--root <dir>]
//
//   --expect <dir>   where the artefacts are supposed to land.
//                    Default: the default the tool DECLARES.
//   --corpus <dir>   the directory whose byte-identity is measured.
//                    Default: reports
//   --root <dir>     the tree the self-check runs in.
//                    Default: this repository
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const REPO = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

const argv = process.argv.slice(2);
const flag = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : null;
};

/// The tree the self-check runs in, and the two directories it measures.
const ROOT = resolve(flag('--root') ?? REPO);
const CORPUS = flag('--corpus') ?? 'reports';
const EXPECT_OVERRIDE = flag('--expect');
/// The file the DECLARATION is read out of.  It is a parameter so the
/// falsifier can hand the check a source that declares something else: a
/// check that carried its own constant would not notice, and a check that
/// reads the declaration would go red.
const SOURCE = flag('--source');

/// A path, resolved against the tree under test.
const at = (root, p) => (isAbsolute(p) ? p : join(root, p));

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};
const unknown = (why) => {
  console.error(`UNKNOWN  ${why}`);
  process.exit(2);
};

// ---------------------------------------------------------------------------
// THE DECLARATION, READ OUT OF THE TOOL'S OWN SOURCE.
//
// The check must not carry the answer it is looking for: if it hard-coded
// `_build/qa/lunaflow`, then a change to the source that breaks the default
// would be invisible to it -- the check would compare the tool against
// itself and find nothing.  So the declaration is PARSED, and the run is
// measured against it.
// ---------------------------------------------------------------------------
function declaredDefault() {
  const src = SOURCE
    ? resolve(SOURCE)
    : join(REPO, 'src', 'command', 'command.mbt');
  if (!existsSync(src)) return null;
  const text = readFileSync(src, 'utf8');
  const body = /fn\s+Opts::default\(\)\s*->\s*Opts\s*\{([\s\S]*?)\n\}/.exec(text);
  if (!body) return null;
  const field = /^\s*out\s*:\s*"([^"]+)"/m.exec(body[1]);
  return field ? field[1] : null;
}

const DECLARED = declaredDefault();
if (!DECLARED) {
  unknown(
    `the default output directory could not be read out of ${
      SOURCE ? resolve(SOURCE) : join(REPO, 'src', 'command', 'command.mbt')
    }`,
  );
}
const EXPECT = EXPECT_OVERRIDE ?? DECLARED;

// ---------------------------------------------------------------------------
// THE BUILD TREE, AND WHAT MAY BE CLEARED.
//
// The build tree is the repository's own: the directory the ignore rules
// exclude, which is what "disposable" means here.  Only a directory INSIDE
// it may be cleared by this check.  The corpus is not in it, and the corpus
// is not cleared.
// ---------------------------------------------------------------------------
const BUILD = join(ROOT, '_build');
const isDisposable = (dir) => dir === BUILD || dir.startsWith(BUILD + sep);

/// The artefacts a run writes, recognised by their shape rather than by name.
const isArtefact = (name) => /\.(md|json|jsonl)$/.test(name);

/// The files in a directory, with their sizes and a digest of their contents.
function snapshot(dir) {
  if (!existsSync(dir)) return [];
  const rows = [];
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (!statSync(p).isFile()) continue;
    const bytes = readFileSync(p);
    rows.push(`${name}:${bytes.length}:${createHash('sha256').update(bytes).digest('hex')}`);
  }
  return rows;
}

/// Every file under `dir`, recursively, as a path relative to `dir`.
function walk(dir, base = dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, base, out);
    else if (statSync(p).isFile()) out.push(relative(base, p).split(sep).join('/'));
  }
  return out;
}

/// Git's own answer, twice: does an ignore rule match this path, and does the
/// index track anything under it?  A build directory is disposable because
/// the repository ignores it AND tracks nothing in it; the corpus fails the
/// second half, which is why it cannot be the default.
function gitOut(args) {
  const r = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  return { code: r.status, out: r.stdout ?? '' };
}
const ignoredByRepo = (relPath) => gitOut(['check-ignore', '--quiet', '--', relPath]).code === 0;
const trackedUnder = (relPath) =>
  gitOut(['ls-files', '--', relPath]).out.split(/\r?\n/).filter(Boolean);

const exe = requireCli(REPO);

// ---------------------------------------------------------------------------
// PART 1 -- the default, measured in a scratch directory.
//
// The scratch directory is the CLI's working directory, so the default path
// is resolved against IT, not against the repository.
// ---------------------------------------------------------------------------
const scratch = join(ROOT, '_build', 'qa', 'default_output', 'scratch');
rmSync(scratch, { recursive: true, force: true });
mkdirSync(join(scratch, 'mod', 'src'), { recursive: true });
writeFileSync(
  join(scratch, 'mod', 'moon.mod'),
  'name = "default_output/probe"\n\nversion = "0.1.0"\n',
);
writeFileSync(
  join(scratch, 'mod', 'src', 'lib.mbt'),
  '///|\npub fn probe(x : Int) -> Int {\n  x + 1\n}\n',
);

const run = spawnSync(exe, ['analyze', '--dir', 'mod', '--quiet'], {
  cwd: scratch,
  encoding: 'utf8',
  timeout: 120000,
  maxBuffer: 16 * 1024 * 1024,
});
if (run.status !== 0) {
  unknown(`the analyser did not run: exit ${run.status}\n${run.stdout ?? ''}\n${run.stderr ?? ''}`);
}

// WHERE THE ARTEFACTS LANDED -- found, not assumed.
const artefacts = walk(scratch).filter((rel) => isArtefact(rel) && !rel.startsWith('mod/'));
const landed = [...new Set(artefacts.map((rel) => rel.split('/').slice(0, -1).join('/')))].sort();
const expectedRel = EXPECT.split(sep).join('/').replace(/^\.\//, '');

check(
  'the artefacts land in the default output directory',
  landed.length === 1 && landed[0] === expectedRel,
  landed.length ? `landed in ${landed.join(', ')}; expected ${expectedRel}` : 'no artefact was written anywhere',
);

const rootArtefacts = artefacts.filter((rel) => !rel.includes('/'));
check(
  'nothing is written into the working directory',
  rootArtefacts.length === 0,
  rootArtefacts.join(', '),
);

const corpusArtefacts = artefacts.filter((rel) => rel.startsWith('reports/'));
check(
  'nothing is written into reports/',
  corpusArtefacts.length === 0,
  corpusArtefacts.join(', '),
);

// The DISPOSABILITY of the directory the tool is supposed to use.  Two
// halves, both measured: the repository's own ignore rules, and the
// repository's own index.  The corpus is ignored too -- the rule that keeps
// it out of the package -- but the index TRACKS it, and that is the half
// that says "not disposable".
const expectedTracked = trackedUnder(expectedRel);
check(
  'the default output directory is disposable',
  ignoredByRepo(expectedRel) && expectedTracked.length === 0,
  [
    ignoredByRepo(expectedRel) ? 'ignored' : 'NOT ignored',
    `${expectedTracked.length} tracked file(s) under it`,
  ].join(', '),
);

// ---------------------------------------------------------------------------
// PART 2 -- the committed corpus, measured on the tree under test.
//
// This is the claim the bug is about: a self-check leaves the committed
// evidence alone.  The corpus is snapshotted BEFORE and AFTER, and the two
// snapshots must be identical.
// ---------------------------------------------------------------------------
const corpusDir = at(ROOT, CORPUS);
if (!existsSync(corpusDir)) {
  unknown(`the corpus directory is not there: ${corpusDir}`);
}
const before = snapshot(corpusDir);

const expectDir = at(ROOT, EXPECT);
const cleared = isDisposable(expectDir);
let expectBefore;
if (cleared) {
  // The expected directory is disposable: it is cleared so that "the run
  // wrote this" can be told from "this was already here".
  rmSync(expectDir, { recursive: true, force: true });
  expectBefore = [];
} else {
  // It is NOT disposable, so it is not cleared.  The files that were there
  // before the run are remembered instead, and the artefacts the run ADDED
  // are what the check looks for -- which is the same question, asked
  // without destroying anything.
  expectBefore = snapshot(expectDir);
  console.log(`NOTE  ${expectDir} is not inside the build tree; it was NOT cleared`);
}

const selfRun = spawnSync(exe, ['analyze', '--dir', '.', '--quiet'], {
  cwd: ROOT,
  encoding: 'utf8',
  timeout: 600000,
  maxBuffer: 64 * 1024 * 1024,
});
if (selfRun.status !== 0) {
  unknown(`the self-scan did not run: exit ${selfRun.status}\n${selfRun.stderr ?? ''}`);
}

const after = snapshot(corpusDir);
const expectAfter = snapshot(expectDir);

const added = after.filter((r) => !before.includes(r));
const removed = before.filter((r) => !after.includes(r));
const changed = before.filter(
  (r) => after.includes(r) && r !== after.find((x) => x.split(':')[0] === r.split(':')[0]),
);
check(
  'the committed corpus is byte-identical after a self-check',
  added.length === 0 && removed.length === 0 && changed.length === 0,
  [
    added.length ? `added: ${added.join(', ')}` : '',
    removed.length ? `removed: ${removed.join(', ')}` : '',
    changed.length ? `changed: ${changed.join(', ')}` : '',
  ]
    .filter(Boolean)
    .join('; ') || `${before.length} file(s) unchanged`,
);

// The self-check's own artefacts went to the expected directory -- measured as
// the files that appeared there, so the question is asked the same way
// whether or not the directory could be cleared.
const addedArtefacts = expectAfter
  .filter((r) => !expectBefore.includes(r))
  .filter((r) => isArtefact(r.split(':')[0]));
check(
  "the self-check's artefacts went to the default output directory",
  addedArtefacts.length > 0,
  `${addedArtefacts.length} new artefact(s) in ${EXPECT}`,
);

// ---------------------------------------------------------------------------
// PART 3 -- the documentation names the declaration.
//
// The README is what a reader acts on.  If the source declares a default and
// the README documents another one, the reader is told to expect something
// the tool does not do.
// ---------------------------------------------------------------------------
const readmePath = join(REPO, 'README.md');
if (!existsSync(readmePath)) {
  unknown(`the README is not there: ${readmePath}`);
}
const outRow = readFileSync(readmePath, 'utf8')
  .split(/\r?\n/)
  .find((line) => line.includes('`--out <dir>`'));
check(
  "the README's --out row names the declared default",
  outRow !== undefined && outRow.includes(DECLARED),
  outRow ? outRow.trim() : 'no --out row in the README',
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
