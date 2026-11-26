// THE STRUCTURAL DRIFT CHECK: the local gate's step list against CI's.
//
// WHY THIS EXISTS.  `scripts/qa/peer_scan.mjs` was CI step 56 and was NOT one of
// the local gate's steps, so five consecutive commits reported "gate 55/55
// green" while CI was failing on that exact step.  The lists drifted once; this
// check is what makes the second time impossible.
//
// THE INVARIANT IS ONE-DIRECTIONAL, ON PURPOSE:
//
//     EVERY CHECK CI RUNS MUST ALSO BE RUN BY THE LOCAL GATE.
//
// Not equality.  A check the local gate runs and CI does not is harmless: the
// local gate is then STRICTER, and a CI green means only that CI did not measure
// that thing.  The dangerous direction is the other one -- a check that protects
// CI but not the local gate -- and that is what this asserts.
//
// THE UNIT OF COMPARISON IS THE SCRIPT, NOT THE ARGUMENT STRING.  Measured, not
// assumed: CI runs `readme_table.mjs --no-selfscan` and `moon test
// --enable-coverage` where the local gate runs `readme_table.mjs` (the FULL
// mode, which is stricter) and `moon test`.  Comparing whole command strings
// called those drift; they are not -- the same check runs, with different
// arguments.  So the comparison keys on what is invoked, and argument
// differences are REPORTED as notes for a reader to see.
//
// THE COMPARISON IS ALSO NOT A STRING MATCH ON THE RAW FILE: CI CHAINS commands
// (`size_taint && size_taint --no-build --falsify`) and uses `run: |` blocks
// with one command per line.  Both forms are split into single commands first.
//
// Usage:
//   node scripts/qa/gate_parity.mjs [--steps <f>] [--ci <f>] [--falsify]
//
//   --falsify  prove the check can go red, on COPIES -- the tracked files are
//              never touched
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};
const note = (s) => console.log(`note  ${s}`);

const argOf = (flag, dflt) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
};

const STEPS_PATH = argOf('--steps', 'scripts/qa/gate-steps.json');
const CI_PATH = argOf('--ci', '.github/workflows/ci.yml');
const falsify = process.argv.includes('--falsify');

const norm = (s) => s.replace(/\s+/g, ' ').trim();

// What a command INVOKES, independent of its arguments.
//   `node scripts/qa/x.mjs --flag`  ->  scripts/qa/x.mjs
//   `python .github/scripts/y.py`   ->  .github/scripts/y.py
//   `moon test --target wasm`       ->  moon test
//   `typos`                         ->  typos
// A command with no such identity is not a check (`moon update`, `mkdir`, the
// toolchain version probe, `tail`, ...).
function keyOf(cmd) {
  const script = /\b((?:\.github\/)?scripts\/[A-Za-z0-9_./-]+)/.exec(cmd);
  if (script) return script[1];
  const moonVerb = /^moon (check|test|fmt|build)\b/.exec(cmd);
  if (moonVerb) return `moon ${moonVerb[1]}`;
  if (/^typos$/.test(cmd)) return 'typos';
  return null;
}

// ---------------------------------------------------------------------------
function readSteps(path) {
  return JSON.parse(readFileSync(path, 'utf8')).map(norm);
}

function readCiCommands(path) {
  const lines = readFileSync(path, 'utf8').split('\n');
  const raw = [];
  for (let i = 0; i < lines.length; i++) {
    const m = /^(\s*)run:\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    const indent = m[1].length;
    const inline = m[2].trim();
    if (!(inline === '' || /^[|>]/.test(inline))) {
      raw.push(inline);
      continue;
    }
    // A `run: |` block holds ONE COMMAND PER LINE (joining them with spaces
    // produced commands that matched nothing).  A line ending in `&&` or `\`
    // continues onto the next.
    let pending = '';
    for (let j = i + 1; j < lines.length; j++) {
      const l = lines[j];
      if (l.trim() === '') continue;
      if (l.length - l.trimStart().length <= indent) break;
      const t = l.trim();
      if (t.startsWith('#')) continue;
      pending = pending === '' ? t : pending + ' ' + t;
      if (/&&\s*$/.test(pending) || /\\\s*$/.test(pending)) continue;
      raw.push(pending);
      pending = '';
    }
    if (pending !== '') raw.push(pending);
  }
  const out = [];
  for (const entry of raw) {
    for (const part of entry.split(' && ')) {
      const c = norm(part);
      if (c) out.push(c);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
function compare(steps, ciCommands) {
  const localKeys = new Map(); // key -> array of full commands
  for (const s of steps) {
    const k = keyOf(s);
    if (!k) continue;
    if (!localKeys.has(k)) localKeys.set(k, []);
    localKeys.get(k).push(s);
  }
  const ciKeyed = [];
  for (const c of ciCommands) {
    const k = keyOf(c);
    if (k) ciKeyed.push({ cmd: c, key: k });
  }
  const ciKeys = new Set(ciKeyed.map((x) => x.key));

  const missing = [...ciKeys].filter((k) => !localKeys.has(k)).sort();
  const argDiffers = [];
  for (const { cmd, key } of ciKeyed) {
    const locals = localKeys.get(key);
    if (!locals) continue;
    if (!locals.some((l) => l === cmd)) argDiffers.push({ key, ci: cmd, local: locals });
  }
  const localOnly = [...localKeys.keys()].filter((k) => !ciKeys.has(k)).sort();
  return { missing, argDiffers, localOnly, localKeys, ciKeys };
}

// ---------------------------------------------------------------------------
const steps = readSteps(STEPS_PATH);
const ciCommands = readCiCommands(CI_PATH);

console.log(`local gate steps : ${steps.length}   (${STEPS_PATH})`);
console.log(`CI run: commands : ${ciCommands.length}   (${CI_PATH})`);

check('every step in the local list is a non-empty command', steps.every((s) => s.length > 0));

const dupes = steps.filter((s, i) => steps.indexOf(s) !== i);
check(
  'the local list has no duplicate step',
  dupes.length === 0,
  dupes.length ? `duplicated: ${[...new Set(dupes)].join(' | ')}` : `${new Set(steps).size} distinct`,
);

const { missing, argDiffers, localOnly, localKeys, ciKeys } = compare(steps, ciCommands);

// THE INVARIANT.
check(
  'every check CI runs is also run by the local gate',
  missing.length === 0,
  missing.length
    ? `${missing.length} check(s) CI runs are NOT run by the local gate: ${missing.join(' | ')}`
    : `${ciKeys.size} check(s) CI runs, all of them also in the local gate`,
);

if (localOnly.length > 0) {
  note(`${localOnly.length} check(s) the local gate runs that CI does not -- the harmless direction, CI is not protecting something the gate is not:`);
  for (const k of localOnly) note('    ' + k);
}

if (argDiffers.length > 0) {
  note(`${argDiffers.length} check(s) run by BOTH, with different arguments (the check is covered; the arguments are reported so the difference is visible):`);
  for (const d of argDiffers) {
    note('    ' + d.key);
    note('      CI    : ' + d.ci);
    for (const l of d.local) note('      local : ' + l);
  }
}

// The falsification: prove the invariant check can go RED, on copies.
if (falsify) {
  const dir = join(process.cwd(), '_build', 'qa', 'gate_parity_falsify');
  mkdirSync(dir, { recursive: true });

  // CASE 1 -- drop a check the CI side runs; it must be reported as missing.
  const dropped = [...ciKeys][0];
  const stepsWithout = steps.filter((s) => keyOf(s) !== dropped);
  const c1 = compare(stepsWithout, ciCommands);

  // CASE 2 -- a CI check that no longer exists must stop being reported.
  const ciRaw = readFileSync(CI_PATH, 'utf8');
  const victim = [...ciKeys].find((k) => k.includes('scripts/')) ?? dropped;
  const ciMutated = ciRaw
    .split('\n')
    .map((l) => (l.includes(victim) ? l.replace(victim, 'true') : l))
    .join('\n');
  const ciCopy = join(dir, 'ci.yml');
  writeFileSync(ciCopy, ciMutated, 'utf8');
  const c2 = compare(steps, readCiCommands(ciCopy));

  // CASE 3 -- the CONTROL: the unmodified pair reports exactly what the main
  // run reported, so the comparison is not order- or copy-dependent.
  const c3 = compare(readSteps(STEPS_PATH), readCiCommands(CI_PATH));

  check(
    'removing a local step makes the check red',
    c1.missing.includes(dropped),
    `dropped ${dropped} -> reported missing: ${c1.missing.length}`,
  );
  check(
    'a CI check that no longer exists stops being reported',
    !c2.missing.includes(victim),
    victim,
  );
  check(
    'the control: the unmodified lists give the same answer',
    JSON.stringify(c3.missing) === JSON.stringify(missing),
  );
}

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
