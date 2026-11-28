#!/usr/bin/env node
// THE TREE IS STILL THE TREE: THE LAST STEP OF THE GATE.
//
// MEASURED BUG (2026-11-28): the gate came back GREEN with `reports/` GONE
// FROM DISK.  All 28 committed corpus files -- 194,178,849 bytes of
// committed evidence -- had been deleted, and `git status` showed 28
// deleted files.  The gate said "63 passed, 0 failed" because NOTHING IN IT
// LOOKED AT THE WORKING TREE.
//
// The cause was a check of this round's own making: the first version of
// `default_output.mjs` CLEARED the directory it was told to expect
// artefacts in, and its falsifier pointed that at the old default -- which
// IS the committed corpus.  So a check that was supposed to PROTECT the
// corpus DELETED it, and the gate could not see it.
//
// THAT IS THE BLIND SPOT THIS STEP FILLS.  A gate that runs 63 checks and
// then says GREEN has answered one question: "did every check agree with
// what it claimed?"  It has NOT answered "is the tree still the tree?"  The
// two are different questions, and only the second one catches a check
// that destroys what it measures.
//
// WHAT IS ASKED, AND WHY THESE THREE.
//
//   1. Is every TRACKED file still on disk?  `git ls-files --deleted` is
//      git's own answer, and it is empty only when nothing tracked was
//      removed.  This is the question the bug answered "no" to.  It is asked
//      of the WHOLE tree, because the corpus is not the only thing a check
//      could destroy.
//   2. Is the CORPUS byte-identical to the index?  `git diff -- reports/`
//      compares the working tree against the index for that directory.  A
//      check that OVERWRITES the corpus answers this "no" -- and an
//      overwrite is the other half of the same bug: the self-check used to
//      write 13 files over the evidence it was being compared against.
//   3. Did a check leave STRAY files under the corpus?  The corpus is
//      IGNORED on purpose -- the rule that keeps it out of the package --
//      so a stray corpus file is invisible to a plain "untracked" query and
//      visible only to the ignored-files query.  Both are asked, because
//      "stray" and "stray but ignored" are different failures.
//
// WHY THE CORPUS AND NOT THE WHOLE TREE FOR QUESTIONS 2 AND 3.  The corpus
// is COMMITTED EVIDENCE: it is not supposed to change while a gate runs,
// and every byte of it is answerable to the index.  The rest of the tree is
// not: the release preparation edits README.md and moon.mod on purpose, so
// asking "does the whole tree match the index" would go red every single
// time the gate is run before a commit -- a check that is red by
// construction is a check nobody reads.
//
// WHERE THIS STEP RUNS MATTERS.  It is the LAST step of the local gate, on
// purpose: a step that runs early cannot see what a later step did.  A
// check that deletes the corpus is caught by the step that runs after it.
//
// Usage: node scripts/qa/tree_intact.mjs [--root <dir>]
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';

const REPO = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

const argv = process.argv.slice(2);
const flag = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : null;
};

/// The tree under test.  It is a parameter so the falsifier can ask the
/// question about a REPLICA: the question must be asked of a tree the
/// falsifier is allowed to damage.
const ROOT = resolve(flag('--root') ?? REPO);

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

/// Git's own answer, in the tree under test.
function git(args) {
  const r = spawnSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error) return { code: -1, out: '' };
  return { code: r.status, out: r.stdout ?? '' };
}

const lines = (s) => s.split(/\r?\n/).filter((l) => l.length > 0);

// ---------------------------------------------------------------------------
// Is this a git repository at all?  A tree that is not one cannot answer the
// three questions, and saying UNKNOWN is the honest verdict -- reading it
// as a pass would be a check that cannot fail.
// ---------------------------------------------------------------------------
const inside = git(['rev-parse', '--is-inside-work-tree']);
if (inside.code !== 0 || inside.out.trim() !== 'true') {
  unknown(`this is not a git work tree: ${ROOT}`);
}

// ---------------------------------------------------------------------------
// QUESTION 1: is every tracked file still on disk?
// ---------------------------------------------------------------------------
const deleted = lines(git(['ls-files', '--deleted']).out);
check(
  'every tracked file is still on disk',
  deleted.length === 0,
  deleted.length ? `${deleted.length} deleted: ${deleted.slice(0, 5).join(', ')}` : 'none deleted',
);

// ---------------------------------------------------------------------------
// QUESTION 2: is the CORPUS byte-identical to the index?
//
// `git diff` compares the working tree against the index, content and not
// just timestamps.  The name of every file that differs is printed too,
// because "the tree changed" without saying WHICH file is a claim nobody
// can act on.
// ---------------------------------------------------------------------------
const changed = lines(git(['diff', '--name-only', '--', 'reports/']).out);
check(
  'the committed corpus is byte-identical to what is committed',
  changed.length === 0,
  changed.length ? `${changed.length} changed: ${changed.slice(0, 5).join(', ')}` : 'none changed',
);

// ---------------------------------------------------------------------------
// QUESTION 3: did a check leave STRAY files under the corpus?
//
// The corpus is ignored on purpose, so a stray file in it is invisible to
// a plain "untracked" query and visible only to the ignored-files query.
// Both are asked, because "stray" and "stray but ignored" are different
// failures and the second one is the one that actually happens.
// ---------------------------------------------------------------------------
const stray = lines(git(['ls-files', '--others', '--exclude-standard', '--', 'reports/']).out);
const strayIgnored = lines(
  git(['ls-files', '--others', '--ignored', '--exclude-standard', '--', 'reports/']).out,
);
const allStray = [...stray, ...strayIgnored];
check(
  'no stray file was left under the corpus',
  allStray.length === 0,
  allStray.length ? `${allStray.length} stray: ${allStray.slice(0, 5).join(', ')}` : 'none',
);

// ---------------------------------------------------------------------------
// THE CORPUS, COUNTED.  The number is read out of git rather than carried
// here: a check that carried its own constant could not notice the corpus
// changing.
// ---------------------------------------------------------------------------
const trackedCorpus = lines(git(['ls-files', '--cached', '--', 'reports/']).out);
check(
  'the committed corpus is present in the index',
  trackedCorpus.length > 0,
  `${trackedCorpus.length} tracked file(s)`,
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
