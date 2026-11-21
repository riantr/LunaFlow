// FALSIFY THE PHASE-3 REPAIR, IN THE REPOSITORY.
//
// MUTATES THE SOURCE TREE. This is a MANUAL, LOCAL tool -- it is NOT a gate
// step and it is deliberately NOT wired into CI. It refuses to run on a dirty
// tree, and it restores the source BYTE for BYTE (and proves it).
//
// A check that cannot fail proves nothing. Each case below breaks the repair
// ON PURPOSE, runs the test suite, and asserts that the assertions the repair
// is supposed to pin actually FAIL -- and that every OTHER assertion, the
// 274 that are not about this phase, still passes. Then the source is
// restored and compared by SHA-256, so "the source came back" is measured, not
// asserted.
//
//   F1  the change is reverted entirely (the published tree before it)
//   F2  the count's taint inherits the CONTENTS' again
//   F3  the count is dropped (the count falls back to the unknown range and
//       the size's taint to the contents')
//   F4  the count's taint is dropped (the count is clean)
//
// The rule every case is held to: the set of assertions that FAIL is exactly
// the set the case is expected to break. A failure outside that set -- in the
// other 274 assertions -- is a failure of this tool's expectation, and it is
// reported as one.
//
// Usage:
//   node scripts/qa/plus_size_falsify.mjs [--base <ref>]
//
//   --base <ref>  the tree F1 reverts to. Default: v0.1.31 -- the last
//                 release BEFORE the repair, so "the change is reverted" is
//                 anchored to a published tree rather than to a commit id.

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const ABS = 'src/app/abs.mbt';

const baseArg = process.argv.indexOf('--base');
const BASE = baseArg >= 0 ? process.argv[baseArg + 1] : 'v0.1.31';

const sha = (b) => createHash('sha256').update(b).digest('hex');
const git = (...a) => execFileSync('git', a, { encoding: 'utf8' }).trim();

// The twelve assertions of src/app/plus_size_wbtest.mbt.
const COUNT_SUM = 'phase3: the count of a `+`-built array is the sum of the two counts';
const COUNT_TWO = "phase3: the count of a `+`-built array of two caller's arrays is the sum of both";
const COUNT_CONST = 'phase3: the count of a `+`-built array of two literals is a constant';
const SIZE_ONE = "phase3: the size's taint of a `+`-built array names the COUNT's sources and not the element's";
const SIZE_EVERY = "phase3: the size's taint of a `+`-built array names every source that decides the COUNT";
const SIZE_EMPTY = "phase3: the size's taint of a `+`-built array of two literals is empty";
const SELF_LIT = "phase3: the count of a `+`-built array of literals is not the element's taint";
const SELF_BOUND = "phase3: the count of a `+`-built array of literals is not the element's taint through a binding";
const LABEL_ONE = "phase3: a `+`-built array's size claim names the COUNT's sources and not the element's";
const LABEL_EVERY = "phase3: a `+`-built array's size claim names every source that decides the COUNT";
const EVIDENCE = "phase3: the claim's evidence carries the sum of the two counts";
const ELEMENT = "phase3: a size that is the ELEMENT of a `+`-built array still claims";

// The concatenation's own line in the repaired source: the anchor every case
// but F1 mutates.
const BUILT = 'AbsCell::new(AArr(lo, hi, srcs_union(asz, bsz)), t)';

const CASES = [
  {
    id: 'F1',
    name: 'the change is reverted entirely',
    revert: true,
    expect:
      "the count is gone, the self-refuting claim returns, and the label names the ELEMENT again",
    mustFail: [
      COUNT_SUM,
      COUNT_TWO,
      COUNT_CONST,
      SIZE_ONE,
      SIZE_EVERY,
      SIZE_EMPTY,
      SELF_LIT,
      SELF_BOUND,
      LABEL_ONE,
      LABEL_EVERY,
      EVIDENCE,
    ],
  },
  {
    id: 'F2',
    name: "the count's taint inherits the CONTENTS' again",
    edits: [[ABS, BUILT, 'AbsCell::new(AArr(lo, hi, t), t)']],
    expect: "the label names the ELEMENT again -- and the count is still the sum",
    mustFail: [SIZE_ONE, SIZE_EVERY, SIZE_EMPTY, LABEL_ONE, LABEL_EVERY],
  },
  {
    id: 'F3',
    name: 'the count is dropped (it falls back to the unknown range, and the size\'s taint to the contents\')',
    edits: [[ABS, BUILT, 'AbsCell::new(AArr(0, 64, t), t)']],
    expect:
      'the count is not the sum any more, and the two self-refuting claims return',
    mustFail: [
      COUNT_SUM,
      COUNT_TWO,
      COUNT_CONST,
      SIZE_ONE,
      SIZE_EVERY,
      SIZE_EMPTY,
      SELF_LIT,
      SELF_BOUND,
      LABEL_ONE,
      LABEL_EVERY,
      EVIDENCE,
    ],
  },
  {
    id: 'F4',
    name: "the count's taint is dropped (the count is clean)",
    edits: [[ABS, BUILT, 'AbsCell::new(AArr(lo, hi, []), t)']],
    expect: 'the positive claims stop firing',
    mustFail: [SIZE_ONE, SIZE_EVERY, LABEL_ONE, LABEL_EVERY, EVIDENCE],
  },
];

// --- refuse to run on a dirty tree: this tool rewrites tracked files ---------
// Only TRACKED files are looked at: untracked scratch files cannot be damaged
// by this tool, and the tool itself is untracked the first time it runs.
const dirty = git('status', '--porcelain', '--untracked-files=no');
if (dirty !== '') {
  console.error('REFUSED: a tracked file is modified. This tool rewrites tracked');
  console.error('files, so it will not run on top of uncommitted work:\n' + dirty);
  process.exit(2);
}

// The source the cases start from is the COMMITTED one, and the hash the
// report ends with is the COMMITTED tree's -- not the working tree's, which
// `moon fmt` may still rewrite. Phase 2 shipped a hash that matched no
// commit for exactly that reason.
const original = readFileSync(ABS);
const originalHash = sha(original);
const committed = execFileSync('git', ['show', `HEAD:${ABS}`]);
const committedHash = sha(committed);
if (committedHash !== originalHash) {
  console.error('REFUSED: the working tree differs from the committed one.');
  console.error(`  committed  ${committedHash}`);
  console.error(`  working    ${originalHash}`);
  process.exit(2);
}
const baseAbs = execFileSync('git', ['show', `${BASE}:${ABS}`]);

const restore = () => {
  writeFileSync(ABS, original);
};

// Which of the assertions failed in a test run's output?
//
// The suite prints one line per failure:
//   [riantr/LunaFlow] test src/app/plus_size_wbtest.mbt:71 ("<name>") failed
const failedTests = (out) => {
  const failed = new Set();
  for (const line of out.split('\n')) {
    const m = line.match(/\("(.+?)"\)\s*failed/);
    if (m) failed.add(m[1]);
  }
  return failed;
};

const runTests = () => {
  const r = spawnSync('moon', ['test', 'src/app', '--target', 'native'], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
};

let allOk = true;
console.log('=== FALSIFYING THE PHASE-3 REPAIR ===');
console.log(`base for F1: ${BASE}`);
console.log(`committed ${ABS} sha256: ${committedHash}\n`);

try {
  for (const c of CASES) {
    console.log(`--- ${c.id}: ${c.name}`);
    try {
      if (c.revert) {
        writeFileSync(ABS, baseAbs);
      } else {
        let text = original.toString('utf8');
        for (const [file, from, to] of c.edits) {
          if (file !== ABS) throw new Error(`unexpected file ${file}`);
          const n = text.split(from).length - 1;
          if (n !== 1) throw new Error(`the anchor occurs ${n} times, not once:\n${from}`);
          text = text.replace(from, to);
        }
        writeFileSync(ABS, Buffer.from(text, 'utf8'));
      }
    } catch (e) {
      console.log(`    SETUP FAILED: ${e.message}`);
      allOk = false;
      restore();
      continue;
    }

    const { code, out } = runTests();
    const failed = failedTests(out);
    const totals = (out.match(/Total tests: \d+, passed: \d+, failed: \d+\./) || ['(no totals)'])[0];

    // A run that produced no totals did not reach the assertions -- it failed
    // to build, or the toolchain refused it. Say so, and show why.
    if (totals === '(no totals)') {
      console.log('    !! the suite did not reach the assertions. The toolchain said:');
      const lines = out.split('\n');
      const hits = [];
      lines.forEach((l, i) => {
        if (/error/i.test(l)) hits.push(i);
      });
      if (hits.length === 0) {
        console.log('      (no line mentions an error; the last 20 lines:)');
        console.log(lines.slice(-20).map((l) => '      | ' + l).join('\n'));
      } else {
        const first = Math.max(0, hits[0] - 4);
        const last = Math.min(lines.length, hits[0] + 40);
        console.log(
          lines
            .slice(first, last)
            .map((l) => '      | ' + l)
            .join('\n'),
        );
      }
    }

    const missingFail = c.mustFail.filter((t) => !failed.has(t));
    // Every failure has to be one the case expects: a failure in one of the
    // other 274 assertions is a defect in this tool's expectation, not in the
    // repair.
    const unexpectedFail = [...failed].filter((t) => !c.mustFail.includes(t));

    console.log(`    expect: ${c.expect}`);
    console.log(`    suite:  ${totals}  (exit ${code})`);
    console.log(
      `    failed: ${failed.size ? [...failed].map((t) => `\n      - ${t}`).join('') : '(none)'}`,
    );
    const ok = code !== 0 && missingFail.length === 0 && unexpectedFail.length === 0;
    if (!ok) {
      allOk = false;
      if (code === 0) console.log('    !! the suite PASSED with the repair broken -- the assertions are vacuous');
      if (missingFail.length) console.log(`    !! should have failed and did not: ${missingFail.join(' | ')}`);
      if (unexpectedFail.length) console.log(`    !! failed but should not have: ${unexpectedFail.join(' | ')}`);
    } else {
      console.log('    OK: the repair is falsifiable, and nothing else broke.');
    }
    console.log('');

    // The source comes back BEFORE the next case: each case must start from
    // the tree as it is, not from the previous case's wreckage.
    restore();
  }
} finally {
  restore();
}

const backHash = sha(readFileSync(ABS));
const identical = backHash === committedHash;
console.log(`source restored byte-identically: ${identical ? 'YES' : 'NO'}`);
console.log(`  ${ABS} ${backHash}`);
console.log(`  committed             ${committedHash}`);
if (!identical) allOk = false;

// The strongest form of "the source came back": the TREE is what it was.
const clean = git('status', '--porcelain', '--untracked-files=no');
console.log(`no tracked file changed: ${clean === '' ? 'YES' : 'NO'}`);
if (clean !== '') {
  console.log(clean);
  allOk = false;
}

console.log(
  `\n${allOk ? 'ALL FALSIFICATIONS BEHAVED AS REQUIRED' : 'A FALSIFICATION DID NOT BEHAVE AS REQUIRED'}`,
);
process.exit(allOk ? 0 : 1);
