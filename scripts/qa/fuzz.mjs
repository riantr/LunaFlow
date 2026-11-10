#!/usr/bin/env node
// Fuzz / robustness harness for the LunaFlow CLI.
//
// Each case runs the native binary with cwd=<case>/work and --out out, so any
// write that escapes the intended report directory lands inside <case>/ and is
// detected as an OUT-OF-DIR artifact. Cases cover mutated sources, hostile
// manifests, pathological syntax, invalid encodings and malformed CLI args.
//
// Usage: node scripts/qa/fuzz.mjs [--seed N] [--limit K] [--keep]
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, copyFileSync,
} from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { requireCli } from './cli_bin.mjs';

const root = process.cwd();
const exe = requireCli(root);
if (!exists(exe)) {
  console.error('missing CLI binary; run: moon build src/cli --target native');
  process.exit(2);
}
function exists(p) {
  try {
    statSync(p);
    return true;
  } catch {
    return false;
  }
}

const seedArg = process.argv.includes('--seed') ? Number(process.argv[process.argv.indexOf('--seed') + 1]) : 20261110;
const limitArg = process.argv.includes('--limit') ? Number(process.argv[process.argv.indexOf('--limit') + 1]) : Infinity;
const keep = process.argv.includes('--keep');
const TIMEOUT_MS = 30000;

function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(seedArg);
const pick = (xs) => xs[Math.floor(rnd() * xs.length) % xs.length];

const fixtureSrc = readFileSync(join(root, 'fixtures', 'vuln_demo', 'lib.mbt'), 'utf8');

// ---------------------------------------------------------------- corpus ---
const cases = []; // {name, files: [[relpath, Buffer|string]], args}
const F = 'lib.mbt';
const MOD = 'moon.mod';
const good = (text) => [[MOD, 'name = "fuzz/demo"\nversion = "0.1.0"\n'], [F, text]];

// A. truncations
for (const k of [1, 5, 40, 150, 600, 1200]) cases.push({ name: `trunc@${k}`, files: good(fixtureSrc.slice(0, k)), args: base() });
// B. byte flips
for (let i = 0; i < 12; i += 1) {
  const at = Math.floor(rnd() * fixtureSrc.length);
  const c = String.fromCharCode(32 + Math.floor(rnd() * 95));
  cases.push({ name: `flip@${at}->${c}`, files: good(fixtureSrc.slice(0, at) + c + fixtureSrc.slice(at + 1)), args: base() });
}
// C. token insertion
const toks = ['{', '}', '[', ']', '(', ')', 'match', '=>', '->', '::', '@', '#|', '///|', '"', "'", '`', '\\', 'fn', 'let', 'while', '@env.args(', '//@ requires', '//@ ensures \\result', '//@ invariant', '//@ assigns nothing', 'impl', 'for', 'loop'];
for (let i = 0; i < 24; i += 1) {
  const at = Math.floor(rnd() * (fixtureSrc.length + 1));
  const t = pick(toks);
  cases.push({ name: `ins@${at}:${t.replace(/\n/g, '\\n')}`, files: good(fixtureSrc.slice(0, at) + t + fixtureSrc.slice(at)), args: base() });
}
// D. unbalanced closers
for (const [n, body] of [['open-brace', fixtureSrc + '{'.repeat(50)], ['close-brace', fixtureSrc + '}'.repeat(50)], ['open-brack', fixtureSrc + '['.repeat(50)], ['stray-string', fixtureSrc + '\nlet s = "unterminated\n'], ['block-comment', fixtureSrc + '\n/* unterminated\n'], ['backtick', fixtureSrc + '\nlet x = `a` + \n']]) cases.push({ name: `unbal:${n}`, files: good(body), args: base() });
// E. pathological syntax
cases.push({ name: 'huge-line-200k', files: good('// ' + 'a'.repeat(200000)), args: base() });
cases.push({ name: 'huge-string-1M', files: good('pub fn f() -> String {\n  "' + 'x'.repeat(1000000) + '"\n}\n'), args: base() });
for (const n of [100, 1000, 5000]) cases.push({ name: `nest-if-${n}`, files: good('pub fn f(x : Int) -> Int {\n' + 'if x > 0 { '.repeat(n) + 'x' + ' }'.repeat(n) + '\n}\n'), args: base() });
for (const n of [100, 2000]) cases.push({ name: `nest-paren-${n}`, files: good('pub fn f(x : Int) -> Int {\n  let y = ' + '('.repeat(n) + 'x' + ')'.repeat(n) + '\n  y\n}\n'), args: base() });
cases.push({ name: 'nest-index-500', files: good('pub fn f(a : Array[Int], i : Int) -> Int {\n  ' + 'a[i]'.repeat(1) + ' = ' + 'a[a['.repeat(250) + 'i' + ']]'.repeat(250) + '\n  i\n}\n'), args: base() });
cases.push({ name: 'many-functions-2000', files: good(Array.from({ length: 2000 }, (_, i) => `pub fn f${i}(x : Int) -> Int {\n  x + ${i}\n}`).join('\n')), args: base() });
cases.push({ name: 'deep-dirs-40', files: [[join(...Array.from({ length: 40 }, () => 'd'), F), fixtureSrc], [MOD, 'name = "fuzz/demo"\nversion = "0.1.0"\n']], args: base() });
// F. encodings
cases.push({ name: 'invalid-utf8', files: good(Buffer.from([0xff, 0xfe, 0x41, 0x00, 0x80, 0x81, 0xbf])), args: base() });
cases.push({ name: 'nul-bytes', files: good('pub fn f() -> Int {\n  1\n}\n\u0000garbage\u0000\n'), args: base() });
cases.push({ name: 'bom-crlf', files: good('\ufeffpub fn f() -> Int {\r\n  1\r\n}\r\n'), args: base() });
cases.push({ name: 'unicode-idents', files: good('pub fn 函数(x : Int) -> Int {\n  let ünïcode = x\n  ünïcode\n}\n'), args: base() });
cases.push({ name: 'empty-file', files: good(''), args: base() });
cases.push({ name: 'comments-only', files: good('/// doc\n// line\n/** block */\n'), args: base() });
cases.push({ name: 'whitespace-only', files: good('   \n\t\n  '), args: base() });
cases.push({ name: 'no-manifest', files: [[F, fixtureSrc]], args: base() });
// G. hostile manifests (path traversal via module name)
const MANIFEST_HOSTILE = [
  ['name-traversal', 'name = "../../escaped"\nversion = "0.1.0"\n'],
  ['name-slashes', 'name = "a/b/../c"\nversion = "0.1.0"\n'],
  ['name-quotes-pipe', 'name = "q\\"uote|pipe"\nversion = "0.1.0"\n'],
  ['version-traversal', 'name = "fuzz/demo"\nversion = "../../evil"\n'],
  ['manifest-garbage', 'this is not = a valid manifest {{{ [\n'],
  ['name-empty', 'name = ""\nversion = "0.1.0"\n'],
  ['name-control-chars', 'name = "a\u0001\u0002b"\nversion = "0.1.0"\n'],
];
for (const [n, mod] of MANIFEST_HOSTILE) cases.push({ name: `manifest:${n}`, files: [[MOD, mod], [F, fixtureSrc]], args: base() });
// H. contract fuzz inside fixture
for (let i = 0; i < 8; i += 1) {
  const spec = pick([
    '//@ requires ;',
    '//@ ensures',
    '//@ requires n >= ;',
    '//@ invariant x = = 1;',
    '//@ assigns nothing extra;',
    '//@ requires n < values.length(); //@ ensures \\result > 0;',
    '//@ requires (n + 1) * 2 > 0 && !(n < 0);',
    '//@ requires unknown_var == 0;',
  ]);
  cases.push({ name: `spec:${spec.slice(6, 22).replace(/[^\w]/g, '_')}`, files: good(spec + '\n' + fixtureSrc), args: base('--funnel') });
}
// I. CLI arg fuzz on a clean fixture copy
const ARGS = [
  [], ['--level', 'abc'], ['--level', '99'], ['--level', '-2'], ['--trials', '0'], ['--trials', '-5'],
  ['--trials', '999999'], ['--trials', 'abc'], ['--max-functions', '-3'], ['--max-cfg', '0'], ['--max-cfg', '-1'],
  ['--slice', '@'], ['--slice', 'x@'], ['--slice', '@y'], ['--slice', 'a@b@c'], ['--slice', 'theta_hat@nonexistent'],
  ['--function', 'no_such_fn'], ['--coverage', 'no_such.xml'], ['--coverage'], ['--out'], ['--dir'],
  ['--unknown-flag', 'x'], ['--max-slice', '0'], ['--max-taint', '-9'], ['--forward'], ['--backward', '--forward'],
];
for (const extra of ARGS) cases.push({ name: `args:${extra.join('_') || 'none'}`, files: good(fixtureSrc), args: base(...extra) });
// J. directory failures
cases.push({ name: 'dir-missing', files: good(fixtureSrc), args: ['analyze', '--dir', 'no/such/dir', '--out', 'out'] });
cases.push({ name: 'dir-is-file', files: good(fixtureSrc), args: ['analyze', '--dir', 'moon.mod', '--out', 'out'] });
cases.push({ name: 'coord-garbage', files: good(fixtureSrc), args: ['analyze', 'not-a-coordinate', '--out', 'out'] });

function base(...extra) {
  return ['analyze', '--dir', 'mod', '--out', 'out', ...extra];
}

// ------------------------------------------------------------------ run ----
const results = [];
const started = Date.now();
const used = cases.slice(0, limitArg);
console.log(`fuzz: ${used.length} cases, seed=${seedArg}, timeout=${TIMEOUT_MS}ms`);
let i = 0;
for (const c of used) {
  i += 1;
  const caseDir = mkdtempSync(join(tmpdir(), `lunafuzz-${i}-`));
  const work = join(caseDir, 'work');
  mkdirSync(work, { recursive: true });
  for (const [rel, body] of c.files) {
    const p = join(work, 'mod', rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  }
  const args = c.args;
  const r = spawnSync(exe, args, { cwd: work, encoding: 'utf8', timeout: TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 });
  const crashed = r.status !== 0 && r.status !== null;
  const timedOut = r.error && r.error.code === 'ETIMEDOUT';
  const stderr = (r.stderr ?? '') + (r.stdout ?? '');
  const panic = /panic|access violation|stack overflow|STATUS_|segfault|index out of bounds/i.test(stderr);
  // escape scan: any artefact outside work/out
  const strays = [];
  (function scan(dir, depth) {
    if (depth > 4) return;
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      const st = statSync(p);
      if (st.isDirectory()) {
        if (p !== join(work, 'out') && !(p === join(work, 'out'))) scan(p, depth + 1);
      } else if (/\.(md|jsonl|json)$/.test(name) && !p.startsWith(join(work, 'out'))) {
        if (!c.files.some(([rel]) => p === join(work, 'mod', rel))) strays.push(relative(work, p));
      }
    }
  })(work, 0);
  const verdict = timedOut ? 'HANG' : crashed ? `EXIT ${r.status}` : panic ? 'PANIC' : strays.length ? 'ESCAPE' : 'ok';
  results.push({ name: c.name, verdict, ms: Date.now() - started, exit: r.status, strays, tail: stderr.trim().split(/\r?\n/).slice(-3).join(' | ').slice(0, 300) });
  if (verdict !== 'ok') console.log(`${verdict.padEnd(7)}  ${c.name}${strays.length ? '  stray=' + strays.join(',') : ''}\n        ${results[results.length - 1].tail}`);
  if (!keep) rmSync(caseDir, { recursive: true, force: true });
}
const tally = {};
for (const x of results) tally[x.verdict] = (tally[x.verdict] ?? 0) + 1;
console.log('\nverdict tally:', JSON.stringify(tally));
writeFileSync(join(root, '_build', 'qa', 'fuzz_results.json'), JSON.stringify({ seed: seedArg, cases: results }, null, 2));
console.log(`total cases: ${results.length}, wall: ${((Date.now() - started) / 1000).toFixed(1)} s -> _build/qa/fuzz_results.json`);
const bad = results.filter((x) => x.verdict !== 'ok');
process.exit(bad.length === 0 ? 0 : 1);
