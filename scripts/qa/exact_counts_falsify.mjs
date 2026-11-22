#!/usr/bin/env node
// FALSIFY THE EXACT-COUNTS CHECK.
//
// `scripts/qa/exact_counts.mjs` says the drift detector may not compare a
// published count with a measured count by ORDER. A check that cannot fail
// proves nothing, so this one breaks the drift detector ON A COPY -- under
// `_build/`, so the tracked source is never written -- and asserts that the
// check notices.
//
// It asserts the OTHER direction too, and that is the half that makes the
// first half mean something: a comparison that is only MENTIONED, in a
// comment or in a message, must NOT be flagged. A check that flagged
// everything would satisfy the first case and know nothing.
//
// The cases:
//
//   F1  the count comparison becomes an ordering one -> the check goes RED
//   F2  a COMMENT mentions an ordering comparison      -> the check stays GREEN
//   F3  a MESSAGE mentions an ordering comparison      -> the check stays GREEN
//
// The real `scripts/qa/readme_table.mjs` is never written: its SHA-256 is
// taken before and after, so "the source came back" is measured.
//
// Usage: node scripts/qa/exact_counts_falsify.mjs

import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = join(ROOT, 'scripts', 'qa', 'exact_counts.mjs');
const DETECTOR = join(ROOT, 'scripts', 'qa', 'readme_table.mjs');
const SCRATCH = join(ROOT, '_build', 'qa', 'exact_counts');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

const sha = (b) => createHash('sha256').update(b).digest('hex');

mkdirSync(SCRATCH, { recursive: true });
const COPY = join(SCRATCH, 'readme_table_copy.mjs');
const source = readFileSync(DETECTOR, 'utf8');
const before = sha(readFileSync(DETECTOR));

/// Run the check against a file and report its verdict.
function runCheck(file) {
  const r = spawnSync('node', [CHECK, file], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 120000,
    maxBuffer: 16 * 1024 * 1024,
  });
  return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

// The baseline: the tracked detector is clean, so a red result below is the
// mutation's doing and not the tree's.
const base = runCheck(DETECTOR);
check(
  'the real drift detector passes BEFORE any mutation',
  base.code === 0,
  base.code === 0 ? 'the baseline is green' : `exit ${base.code}`,
);

// --- F1: the count comparison becomes an ordering one -----------------------
const ANCHOR =
  'if (cell !== s[f]) diffs.push(`${h}: README ${cell} vs ${file} ${s[f]}`);';
if (!source.includes(ANCHOR)) {
  check('F1 the count comparison is weakened', false, 'the anchor is not in the source');
} else {
  copyFileSync(DETECTOR, COPY);
  const mutated = source.replace(ANCHOR, ANCHOR.replace('cell !== s[f]', 'cell <= s[f]'));
  writeFileSync(COPY, mutated, 'utf8');
  const r = runCheck(COPY);
  check(
    'F1 a count comparison weakened to an ordering one is caught',
    r.code === 1,
    r.code === 1 ? 'the check went red, as it must' : `exit ${r.code}`,
  );
  // It must name the line it broke -- a check that goes red for the wrong
  // reason is not checking the right thing.
  const named = /readme_table_copy\.mjs:\d+/.test(r.out);
  check(
    'F1 … and it names the line it broke',
    named,
    (r.out.match(/FAIL.*/) ?? ['(no FAIL line)'])[0],
  );
}

// --- F2: a COMMENT mentions an ordering comparison --------------------------
// The check must NOT fire: a comparison that is only described in prose is
// not a comparison.
const commentAnchor = 'function liveTable(md) {';
if (!source.includes(commentAnchor)) {
  check('F2 a comment mentions an ordering comparison', false, 'the anchor is not in the source');
} else {
  copyFileSync(DETECTOR, COPY);
  const mutated = source.replace(
    commentAnchor,
    `${commentAnchor}\n  // the old rule was: cell <= s[f] -- a threshold, and a vacuous one`,
  );
  writeFileSync(COPY, mutated, 'utf8');
  const r = runCheck(COPY);
  check(
    'F2 an ordering comparison mentioned in a COMMENT is not a violation',
    r.code === 0,
    r.code === 0 ? 'the check stayed green, as it must' : `exit ${r.code}`,
  );
}

// --- F3: a MESSAGE mentions an ordering comparison --------------------------
const messageAnchor = 'const num = (cell) => {';
if (!source.includes(messageAnchor)) {
  check('F3 a message mentions an ordering comparison', false, 'the anchor is not in the source');
} else {
  copyFileSync(DETECTOR, COPY);
  const mutated = source.replace(
    messageAnchor,
    `${messageAnchor}\n  const example = 'the old rule was cell <= s[f], a vacuous threshold';`,
  );
  writeFileSync(COPY, mutated, 'utf8');
  const r = runCheck(COPY);
  check(
    'F3 an ordering comparison mentioned in a MESSAGE is not a violation',
    r.code === 0,
    r.code === 0 ? 'the check stayed green, as it must' : `exit ${r.code}`,
  );
}

// The tracked source was never written.
const after = sha(readFileSync(DETECTOR));
check(
  'the tracked drift detector was never touched',
  before === after,
  before.slice(0, 16),
);

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
