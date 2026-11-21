// FALSIFY THE PHASE-2 REPAIR, IN THE REPOSITORY.
//
// MUTATES THE SOURCE TREE. This is a MANUAL, LOCAL tool -- it is NOT a gate
// step and it is deliberately NOT wired into CI. It refuses to run on a dirty
// tree, and it restores the source BYTE for BYTE (and proves it).
//
// A check that cannot fail proves nothing. Each case below breaks the repair
// ON PURPOSE, runs the test suite, and asserts that the assertions the repair
// is supposed to pin actually FAIL -- and that the ones it is NOT supposed to
// break still pass. Then the source is restored and compared by SHA-256, so
// "the source came back" is measured, not asserted.
//
//   F1  the change is reverted entirely (the published tree before it)
//   F2  the size's taint inherits the CONTENTS' again
//   F3  the contents' taint inherits the SIZE's again
//   F4  every size is clean (the size's taint is dropped where it is made)
//
// Usage:
//   node scripts/qa/size_taint_falsify.mjs [--base <ref>]
//
//   --base <ref>  the tree F1 reverts to. Default: v0.1.30 -- the last
//                 release BEFORE the repair, so "the change is reverted" is
//                 anchored to a published tree rather than to a commit id.

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const ABS = 'src/app/abs.mbt';
const REL = 'src/app/relation.mbt';

const baseArg = process.argv.indexOf('--base');
const BASE = baseArg >= 0 ? process.argv[baseArg + 1] : 'v0.1.30';

const sha = (b) => createHash('sha256').update(b).digest('hex');
const git = (...a) => execFileSync('git', a, { encoding: 'utf8' }).trim();

// The nine assertions of src/app/size_taint_wbtest.mbt.
const LIT = [
  'the length of a container whose ELEMENTS are tainted is not a tainted size',
  'the same holds through a binding',
  'the same holds after a push',
];
const ELEM = "the ELEMENTS of a sized array do not carry the size's taint";
const LABEL = 'the claim names only the sources that decide the SIZE';
const COUNT = "the length of a sized array names only the sources that decide the COUNT";
const POS = [
  'a size that is a parameter is still a size untrusted input chose',
  'the length of an array PARAMETER is still a size untrusted input chose',
  'the length of a string PARAMETER is still a size untrusted input chose',
  'the length of a string BUILT from untrusted input is still a size untrusted input chose',
];

const CASES = [
  {
    id: 'F1',
    name: 'the change is reverted entirely',
    revert: true,
    expect:
      "the element shape's false claim returns, and the size's label names the ELEMENT as well",
    mustFail: [ELEM, COUNT],
    mustPass: [...LIT, ...POS, LABEL],
  },
  {
    id: 'F2',
    name: "the size's taint inherits the CONTENTS' again",
    edits: [
      [
        ABS,
        'AArr(l, h, sz) => AbsCell::new(AInt(l, h), sz)',
        'AArr(l, h, _) => AbsCell::new(AInt(l, h), t)',
      ],
    ],
    expect: "the size's label names the ELEMENT again",
    mustFail: [COUNT],
    mustPass: [...LIT, ELEM, ...POS, LABEL],
  },
  {
    id: 'F3',
    name: "the contents' taint inherits the SIZE's again",
    edits: [
      [
        ABS,
        '          let contents_taint = if cells.length() > 1 {\n' +
          '            cells[1].srcs\n' +
          '          } else {\n' +
          '            []\n' +
          '          }',
        '          let contents_taint = size.srcs',
      ],
    ],
    expect: "the `Array::make(n, 0)` element shape's false claim returns",
    mustFail: [ELEM],
    mustPass: [...LIT, ...POS, LABEL, COUNT],
  },
  {
    id: 'F4',
    name: "every size is clean (the size's taint is dropped where it is made)",
    edits: [
      [
        ABS,
        'AArr(l, h, sz) => AbsCell::new(AInt(l, h), sz)',
        'AArr(l, h, _) => AbsCell::new(AInt(l, h), [])',
      ],
      [
        ABS,
        '                AArr(\n' +
          '                  if l < 0 {\n' +
          '                    0\n' +
          '                  } else {\n' +
          '                    l\n' +
          '                  },\n' +
          '                  if h < 0 {\n' +
          '                    0\n' +
          '                  } else {\n' +
          '                    h\n' +
          '                  },\n' +
          '                  size.srcs,\n' +
          '                ),',
        '                AArr(\n' +
          '                  if l < 0 {\n' +
          '                    0\n' +
          '                  } else {\n' +
          '                    l\n' +
          '                  },\n' +
          '                  if h < 0 {\n' +
          '                    0\n' +
          '                  } else {\n' +
          '                    h\n' +
          '                  },\n' +
          '                  [],\n' +
          '                ),',
      ],
      [ABS, 'AbsCell::new(AArr(0, 64, srcs), srcs)', 'AbsCell::new(AArr(0, 64, []), srcs)'],
      [
        ABS,
        '              AbsCell::new(AInt(lo, hi), t)\n' +
          '            }\n' +
          '            _ => AbsCell::new(ATop, t)',
        '              AbsCell::new(AInt(lo, hi), [])\n' +
          '            }\n' +
          '            _ => AbsCell::new(ATop, t)',
      ],
    ],
    expect: 'the true claims that go through a SIZE stop firing',
    mustFail: [
      COUNT,
      'the length of an array PARAMETER is still a size untrusted input chose',
      'the length of a string PARAMETER is still a size untrusted input chose',
      'the length of a string BUILT from untrusted input is still a size untrusted input chose',
    ],
    mustPass: [...LIT, ELEM, LABEL, 'a size that is a parameter is still a size untrusted input chose'],
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

const original = { abs: readFileSync(ABS), rel: readFileSync(REL) };
const originalHash = { abs: sha(original.abs), rel: sha(original.rel) };
const baseAbs = execFileSync('git', ['show', `${BASE}:${ABS}`]);
const baseRel = execFileSync('git', ['show', `${BASE}:${REL}`]);

const restore = () => {
  writeFileSync(ABS, original.abs);
  writeFileSync(REL, original.rel);
};

// Which of the nine assertions failed in a test run's output?
//
// The suite prints one line per failure:
//   [riantr/LunaFlow] test src/app/size_taint_wbtest.mbt:71 ("<name>") failed
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
console.log('=== FALSIFYING THE PHASE-2 REPAIR ===');
console.log(`base for F1: ${BASE}\n`);

try {
  for (const c of CASES) {
    console.log(`--- ${c.id}: ${c.name}`);
    try {
      if (c.revert) {
        writeFileSync(ABS, baseAbs);
        writeFileSync(REL, baseRel);
      } else {
        let text = original.abs.toString('utf8');
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
    const wronglyFailed = c.mustPass.filter((t) => failed.has(t));

    console.log(`    expect: ${c.expect}`);
    console.log(`    suite:  ${totals}  (exit ${code})`);
    console.log(
      `    failed: ${failed.size ? [...failed].map((t) => `\n      - ${t}`).join('') : '(none)'}`,
    );
    const ok = code !== 0 && missingFail.length === 0 && wronglyFailed.length === 0;
    if (!ok) {
      allOk = false;
      if (code === 0) console.log('    !! the suite PASSED with the repair broken -- the assertions are vacuous');
      if (missingFail.length) console.log(`    !! should have failed and did not: ${missingFail.join(' | ')}`);
      if (wronglyFailed.length) console.log(`    !! failed but should not have: ${wronglyFailed.join(' | ')}`);
    } else {
      console.log('    OK: the repair is falsifiable.');
    }
    console.log('');

    // The source comes back BEFORE the next case: each case must start from
    // the tree as it is, not from the previous case's wreckage.
    restore();
  }
} finally {
  restore();
}

const backAbs = sha(readFileSync(ABS));
const backRel = sha(readFileSync(REL));
const identical = backAbs === originalHash.abs && backRel === originalHash.rel;
console.log(`source restored byte-identically: ${identical ? 'YES' : 'NO'}`);
console.log(`  ${ABS} ${backAbs}`);
console.log(`  ${REL} ${backRel}`);
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
