#!/usr/bin/env node
// THE TREE-INTACT CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier asks the real
// check -- `scripts/qa/tree_intact.mjs` -- about trees it is ALLOWED to
// damage: a small git repository of its own, under `_build/`.
//
//   C   an intact tree                                       GREEN  (exit 0)
//   F1  a tracked file DELETED                               RED    (exit 1)
//   F2  a corpus file OVERWRITTEN                            RED    (exit 1)
//   F3  a STRAY file left under the corpus                   RED    (exit 1)
//
// F1 is the case this whole step exists for: MEASURED 2026-11-28, the gate
// came back GREEN with all 28 corpus files deleted from disk, and `git
// status` showed 28 deleted files.  Nothing in the gate was looking.
//
// F2 is the other half of the same bug: the self-check used to write 13
// files OVER the evidence it was being compared against, and an overwrite
// leaves the file present -- only the CONTENT changes.  A check that only
// looked for missing files would miss it.
//
// F3 is what a run that writes into the corpus leaves behind: the files are
// IGNORED (the rule that keeps the corpus out of the package), so they are
// invisible to a plain "untracked" query.
//
// THE C CONTROL is the ordinary case: nothing damaged, and the check must
// stay GREEN.  Without the control, a check that failed on every possible
// input would look like a check that works.
//
// EVERY CASE RUNS AGAINST A REPLICA.  The real corpus of this repository is
// never the thing at risk -- the 2026-11-28 bug deleted it, and the reason
// this falsifier exists is that nothing stopped that from happening.
//
// Usage: node scripts/qa/tree_intact_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import {
  copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync,
} from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = resolve(ROOT, 'scripts', 'qa', 'tree_intact.mjs');
const WORK = join(ROOT, '_build', 'qa', 'tree_intact_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

/// Run the real check against the given tree.
function run(root) {
  const r = spawnSync(process.execPath, [CHECK, '--root', root], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 300000,
    maxBuffer: 32 * 1024 * 1024,
  });
  return { status: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

/// The check must go RED, and say why.
function mustGoRed(name, root, expect) {
  const r = run(root);
  check(`${name}: the check goes red`, r.status === 1, `exit=${r.status}`);
  if (r.status === 1 && expect) {
    check(`${name}: it fails for the right reason`, r.out.includes(expect), expect);
  }
  if (r.status !== 1 && r.status !== 2) {
    console.log(r.out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
  }
}

/// The check must stay GREEN.
function mustStayGreen(name, root) {
  const r = run(root);
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) {
    console.log(
      r.out
        .split(/\r?\n/)
        .filter((l) => l.startsWith('FAIL') || l.startsWith('UNKNOWN'))
        .join('\n'),
    );
  }
}

// ---------------------------------------------------------------------------
// THE REPLICA.
//
// A git repository of its own: a tracked source file, a tracked corpus, and
// the ignore rule that keeps the corpus out of the package -- the same rule
// this repository uses, so the stray-file case is the real one.
// ---------------------------------------------------------------------------
function buildReplica() {
  const dir = join(WORK, 'replica');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, 'src'), { recursive: true });
  mkdirSync(join(dir, 'reports'), { recursive: true });
  writeFileSync(join(dir, 'src', 'lib.mbt'), '///|\npub fn f(x : Int) -> Int {\n  x\n}\n');
  writeFileSync(join(dir, 'reports', 'corpus.md'), '# the corpus\n');
  writeFileSync(join(dir, 'reports', 'corpus_summary.json'), '{"module":"replica"}\n');
  writeFileSync(
    join(dir, '.gitignore'),
    '# THE CORPUS STAYS IN THE REPOSITORY; THE PACKAGE DOES NOT CARRY IT.\n/reports/\n',
  );
  const git = (args) =>
    spawnSync('git', args, { cwd: dir, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  git(['init', '-q']);
  git(['config', 'user.email', 'qa@example.invalid']);
  git(['config', 'user.name', 'qa']);
  git(['add', '-f', 'src/lib.mbt', 'reports/corpus.md', 'reports/corpus_summary.json', '.gitignore']);
  git(['commit', '-q', '-m', 'the replica']);
  return dir;
}

/// A FRESH copy of the replica, so every case starts from the truth.
function freshReplica() {
  const source = buildReplica();
  const dir = join(WORK, 'case');
  rmSync(dir, { recursive: true, force: true });
  // `git clone` into a path that does NOT exist yet: cloning into an
  // existing directory is refused, and a case that cannot be built is a
  // case that silently does not run.
  const cp = spawnSync('git', ['clone', '-q', source, dir], { encoding: 'utf8' });
  if (cp.status !== 0) {
    console.error(`UNKNOWN  the replica could not be cloned: ${cp.stderr ?? ''}`);
    process.exit(2);
  }
  return dir;
}

// ---------------------------------------------------------------------------
// C -- the CONTROL: an intact tree.
// ---------------------------------------------------------------------------
mustStayGreen('C the intact tree', freshReplica());

// ---------------------------------------------------------------------------
// F1 -- a tracked file DELETED.
//
// This is the 2026-11-28 case: all 28 corpus files gone, and the gate
// green.  The corpus file is deleted here, and the check must notice.
// ---------------------------------------------------------------------------
{
  const dir = freshReplica();
  rmSync(join(dir, 'reports', 'corpus.md'));
  mustGoRed('F1 a tracked file deleted', dir, 'every tracked file is still on disk');
}

// ---------------------------------------------------------------------------
// F2 -- a corpus file OVERWRITTEN.
//
// The file is still there; only its CONTENT changed.  A check that looked
// for missing files would miss this -- and an overwrite is exactly what the
// self-check used to do to the corpus it was being compared against.
// ---------------------------------------------------------------------------
{
  const dir = freshReplica();
  writeFileSync(join(dir, 'reports', 'corpus.md'), '# the corpus, OVERWRITTEN\n');
  mustGoRed('F2 a corpus file overwritten', dir, 'byte-identical');
}

// ---------------------------------------------------------------------------
// F3 -- a STRAY file left under the corpus.
//
// The corpus is ignored, so a stray file in it is invisible to a plain
// "untracked" query.  This is what a run that writes into the corpus
// leaves behind.
// ---------------------------------------------------------------------------
{
  const dir = freshReplica();
  writeFileSync(join(dir, 'reports', 'stray.md'), '# a stray file\n');
  mustGoRed('F3 a stray file under the corpus', dir, 'no stray file was left under the corpus');
}

// ---------------------------------------------------------------------------
// THE REAL TREE, LAST: it must be exactly as it was.
// ---------------------------------------------------------------------------
const realCorpus = join(ROOT, 'reports');
const realCount = existsSync(realCorpus)
  ? spawnSync('git', ['ls-files', '--cached', '--', 'reports/'], { cwd: ROOT, encoding: 'utf8' })
      .stdout.split(/\r?\n/)
      .filter(Boolean).length
  : 0;
check(
  "this repository's corpus is intact",
  realCount === 28,
  `${realCount} tracked file(s)`,
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
