#!/usr/bin/env node
// FALSIFY THE SIGNATURE CHECK, ON A COPY.
//
// A check that cannot fail proves nothing.  This one breaks the INVARIANT on
// purpose and asserts that the check notices -- and that it notices the right
// thing.
//
// It does NOT touch this repository's source.  It copies the tree into
// `_build/`, mutates the COPY, and runs the check against the copy with
// `--root`.  The real `src/` is never written, so there is nothing to restore
// and nothing that can be left behind.
//
// The mutation is the defect the peer analyzer found, in the shape it had:
//
//   #cfg(not(any(target="native", target="wasm")))
//   async fn walk_dir(dir, rel, st, limit, depth) -> Unit    <- FIVE
//
// beside the live one, which takes SIX.  MEASURED: `moonx
// riantr/moonbit_static_analysis@latest .` reported 2 ArgTypeMismatch
// findings on `src/app/scan.mbt` for exactly that shape, and the MoonBit
// compiler reported the stub itself as `Unused function 'walk_dir'`.
//
// Usage: node scripts/qa/cfg_signatures_falsify.mjs

import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(process.cwd());
const work = join(root, '_build', 'qa', 'cfg_signatures_falsify');
const tree = join(work, 'tree');
const check = join(root, 'scripts', 'qa', 'cfg_signatures.mjs');

const STUB = `
///|
#cfg(not(any(target="native", target="wasm")))
async fn walk_dir(
  dir : String,
  rel : String,
  st : WalkState,
  limit : Int32,
  depth : Int32,
) -> Unit {

}
`;

let checks = 0;
let failures = 0;
const check_ = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

const run = (...args) => {
  const r = spawnSync(process.execPath, [check, ...args], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status ?? -1, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
};

// ---------------------------------------------------------------------------
// The copy.
// ---------------------------------------------------------------------------
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });
cpSync(join(root, 'src'), join(tree, 'src'), { recursive: true });
if (existsSync(join(root, 'main.mbt'))) {
  cpSync(join(root, 'main.mbt'), join(tree, 'main.mbt'));
}

const scan = join(tree, 'src', 'app', 'scan.mbt');
const original = readFileSync(scan, 'utf8');

// F1: the copy, untouched, is GREEN.  A detector that is red on a good tree
// would be a detector nobody trusts.
const before = run('--root', tree);
check_(
  'the copied tree is green before the mutation',
  before.code === 0,
  before.code === 0 ? 'the copy has the same shape as the tree it came from' : before.out.trim().split('\n').slice(-3).join(' | '),
);

// F2: the mutation -- a second `walk_dir`, with FIVE parameters beside the
// live one that takes SIX.
writeFileSync(scan, original + STUB, 'utf8');
const after = run('--root', tree);
check_(
  'the mutated tree is red',
  after.code === 1,
  after.code === 1 ? 'the check exits 1 on a signature that depends on the target' : `exit ${after.code}`,
);

// F3: and it is red for the RIGHT REASON: it names `walk_dir` and shows both
// shapes.  A detector that goes red for another reason is not a detector.
const namesWalkDir = /walk_dir/.test(after.out);
const showsBothShapes = /\b5 parameter\(s\)/.test(after.out) && /\b6 parameter\(s\)/.test(after.out);
check_(
  'the red check names the function and shows both shapes',
  namesWalkDir && showsBothShapes,
  namesWalkDir && showsBothShapes
    ? 'walk_dir is reported with 5 and with 6 parameters'
    : after.out.trim().split('\n').slice(-4).join(' | '),
);

// F4: the `--falsify` mode of the check sees the same mismatch, so the
// inversion is not a different detector.
const falsified = run('--root', tree, '--falsify');
check_(
  "the check's own --falsify mode sees the mutation",
  falsified.code === 0,
  falsified.code === 0 ? 'the inverted expectation is satisfied by the mutation' : falsified.out.trim().split('\n').slice(-3).join(' | '),
);

// The real tree was never written.
const real = readFileSync(join(root, 'src', 'app', 'scan.mbt'), 'utf8');
check_('this repository\'s source was not touched', real === original);

rmSync(work, { recursive: true, force: true });

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
