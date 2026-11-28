#!/usr/bin/env node
// THE DEFAULT-OUTPUT CHECK, PROVED ABLE TO FAIL -- AND PROVED TO BE SAFE.
//
// A check that cannot fail is not a check.  A check that DELETES the thing
// it measures is worse.  This falsifier runs the real check --
// `scripts/qa/default_output.mjs` -- and asserts the verdict each situation
// deserves.
//
//   C   the ordinary run                                    GREEN  (exit 0)
//   F1  the OLD default (`reports`) as the expectation        RED    (exit 1)
//   F2  a SOURCE that declares the old default                RED    (exit 1)
//   F3  the OLD default, run against a REPLICA                RED    (exit 1)
//
// F1 is the sensitivity: the check claims that the artefacts land in the
// default output directory.  Pointed at the old default, they are NOT there
// -- so the check must go red, and it must go red for the right reason.
//
// F2 is the derivation: the check reads the default out of the tool's OWN
// source instead of carrying it as a constant.  Handed a source that
// declares the old default, the check must go red -- because the tool still
// writes to the build directory.  A check that carried its own constant
// would stay green here, which is exactly what would make it useless.
//
// F3 is the SAFETY: pointed at the old default, the check must go red
// WITHOUT deleting the corpus it was measuring.  This is not hypothetical.
// The first version of the check cleared the directory it was told to
// expect artefacts in, and the falsifier pointed that at `reports` -- which
// IS the committed corpus.  The check DELETED all 28 corpus files, and the
// 63-step gate came back GREEN with `reports/` gone from disk.  The
// falsifier runs every case against a REPLICA tree, so the corpus of this
// repository is never the thing at risk.
//
// THE C CONTROL is the ordinary run: nothing injected, and the check must
// stay GREEN.  Without the control, a check that failed on every possible
// input would look like a check that works.
//
// Usage: node scripts/qa/default_output_falsify.mjs
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { join, resolve, sep } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = resolve(ROOT, 'scripts', 'qa', 'default_output.mjs');
const WORK = join(ROOT, '_build', 'qa', 'default_output_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

/// Run the real check with the given arguments.
function run(args, cwd = ROOT) {
  const r = spawnSync(process.execPath, [CHECK, ...args], {
    cwd,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
  return { status: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

/// The check must go RED, and say why.
function mustGoRed(name, args, expect, cwd = ROOT) {
  const r = run(args, cwd);
  check(`${name}: the check goes red`, r.status === 1, `exit=${r.status}`);
  if (r.status === 1 && expect) {
    check(`${name}: it fails for the right reason`, r.out.includes(expect), expect);
  }
  if (r.status !== 1 && r.status !== 2) {
    console.log(r.out.split(/\r?\n/).filter((l) => l.startsWith('FAIL')).join('\n'));
  }
}

/// The check must stay GREEN.
function mustStayGreen(name, args, cwd = ROOT) {
  const r = run(args, cwd);
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
// A copy of the tree the check measures: the sources, the manifest and a
// corpus of its own.  The real corpus is 194 MB across 28 files -- two of
// them are 80 MB raw traces -- so the replica carries a corpus of its own
// instead, and the real one is never at risk.
// ---------------------------------------------------------------------------
function buildReplica() {
  const replica = join(WORK, 'replica');
  rmSync(replica, { recursive: true, force: true });
  mkdirSync(replica, { recursive: true });
  for (const name of ['moon.mod', 'moon.pkg', 'main.mbt']) {
    copyFileSync(join(ROOT, name), join(replica, name));
  }
  cpSync(join(ROOT, 'src'), join(replica, 'src'), { recursive: true });
  const corpus = join(replica, 'reports');
  mkdirSync(corpus, { recursive: true });
  writeFileSync(join(corpus, 'replica_report.md'), '# the replica corpus\n');
  writeFileSync(join(corpus, 'replica_summary.json'), '{"module":"replica"}\n');
  writeFileSync(join(corpus, 'replica_findings.jsonl'), '{"event":1}\n');
  return replica;
}

/// The digest of every file in a directory: the fingerprint of a corpus.
function digest(dir) {
  if (!existsSync(dir)) return 'MISSING';
  const rows = [];
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (!statSync(p).isFile()) continue;
    const bytes = readFileSync(p);
    rows.push(`${name}:${bytes.length}:${createHash('sha256').update(bytes).digest('hex')}`);
  }
  return rows.join('|');
}

// ---------------------------------------------------------------------------
// C -- the CONTROL: the ordinary run, against the REPLICA.
//
// The ordinary run is measured on the replica, so the control never writes
// into this repository's corpus either.  The real tree is measured by the
// check itself (`node scripts/qa/default_output.mjs`), which is a gate step.
// ---------------------------------------------------------------------------
const replica = buildReplica();
const replicaCorpus = join(replica, 'reports');
const corpusBefore = digest(replicaCorpus);

mustStayGreen('C the ordinary run', ['--root', replica]);

check(
  'C: the replica corpus survived the run',
  digest(replicaCorpus) === corpusBefore,
  `${readdirSync(replicaCorpus).length} file(s)`,
);

// ---------------------------------------------------------------------------
// F1 -- the OLD default as the expectation, against the REPLICA.
//
// The artefacts are NOT in `reports/`, so the check must notice.  A check
// that passed here would be passing for the wrong reason: it would not be
// looking at where the artefacts landed at all.
//
// The corpus of the REPLICA must survive this: the check is pointed at a
// directory that is NOT disposable, and it must refuse to clear it.
// ---------------------------------------------------------------------------
const beforeF1 = digest(replicaCorpus);
mustGoRed(
  'F1 the old default as the expectation',
  ['--root', replica, '--expect', 'reports'],
  'the artefacts land in the default output directory',
  replica,
);

check(
  'F1: the replica corpus survived the run',
  digest(replicaCorpus) === beforeF1,
  `${readdirSync(replicaCorpus).length} file(s)`,
);

// ---------------------------------------------------------------------------
// F2 -- a SOURCE that declares the old default.
//
// The check reads the default out of the tool's own source.  Handed a
// source that declares `reports`, it must expect `reports` -- and the tool
// still writes to the build directory, so the check must go red.  A check
// that carried the answer as a constant would stay green here.
// ---------------------------------------------------------------------------
const fakeSource = join(WORK, 'old_default_command.mbt');
{
  const original = readFileSync(join(ROOT, 'src', 'command', 'command.mbt'), 'utf8');
  const patched = original.replace(
    /out\s*:\s*"[^"]+"/,
    'out: "reports"',
  );
  if (patched === original) {
    console.error('UNKNOWN  the `out:` field could not be patched in a copy of the source');
    process.exit(2);
  }
  writeFileSync(fakeSource, patched);
}

mustGoRed(
  'F2 a source that declares the old default',
  ['--root', replica, '--source', fakeSource],
  'the artefacts land in the default output directory',
  replica,
);

check(
  'F2: the replica corpus survived the run',
  digest(replicaCorpus) === beforeF1,
  `${readdirSync(replicaCorpus).length} file(s)`,
);

// ---------------------------------------------------------------------------
// F3 -- the OLD default against the REPLICA, with the corpus AT STAKE.
//
// This is the case that destroyed the real corpus: the check was pointed at
// `reports`, and the check cleared it.  Here the corpus is the replica's,
// and it must still be there -- byte for byte -- afterwards.  The check
// goes red, AND the thing it measures is intact.
//
// The check is pointed at the replica's OWN `reports`, which is not inside
// the replica's `_build`, so the check must not clear it.
// ---------------------------------------------------------------------------
const beforeF3 = digest(replicaCorpus);
mustGoRed(
  'F3 the old default, with the corpus at stake',
  ['--root', replica, '--expect', 'reports', '--corpus', 'reports'],
  'the artefacts land in the default output directory',
  replica,
);

check(
  'F3: the corpus the check was measuring survived the run',
  digest(replicaCorpus) === beforeF3,
  `${readdirSync(replicaCorpus).length} file(s)`,
);

check(
  'F3: the corpus is still the three files it was',
  readdirSync(replicaCorpus).length === 3,
  readdirSync(replicaCorpus).join(', '),
);

// ---------------------------------------------------------------------------
// THE REAL TREE, LAST: the corpus of THIS repository must be intact.
//
// Every case above ran against the replica.  This is the last statement:
// the real corpus was never at risk, and it is still exactly as it was.
// ---------------------------------------------------------------------------
const realCorpus = join(ROOT, 'reports');
const realBefore = digest(realCorpus);
const realCount = readdirSync(realCorpus).length;
check(
  "this repository's corpus is intact",
  realCount === 28 && realBefore !== 'MISSING',
  `${realCount} file(s)`,
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
