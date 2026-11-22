#!/usr/bin/env node
// A SIGNATURE MUST NOT DEPEND ON THE TARGET.
//
// MEASURED: `moonx riantr/moonbit_static_analysis@latest .` -- the peer
// analyzer, over this tree -- reported 2 ArgTypeMismatch findings on
// `src/app/scan.mbt`:
//
//   error: too many arguments to 'walk_dir': expected 5, got 6
//
// Both were TRUE, and the reason was in the file rather than in the peer.
// `src/app/scan.mbt` held TWO definitions of `walk_dir`:
//
//   #cfg(any(target="native", target="wasm"))
//   async fn walk_dir(dir, rel, st, limit, depth, excludes) -> Unit   <- SIX
//
//   #cfg(not(any(target="native", target="wasm")))
//   async fn walk_dir(dir, rel, st, limit, depth) -> Unit              <- FIVE
//
// The two guards are mutually exclusive, so no build ever saw both -- and the
// MoonBit compiler agreed the second one was DEAD: `moon check --target js`
// reported `Unused function 'walk_dir'`.
//
// An analyzer that does not evaluate `#cfg` sees both definitions and reads
// the two CALLS as "too many arguments". It cannot tell a dead definition
// from a live one, and it has no way to know that the two disagree.
//
// So the invariant this check holds is the one the peer could not check:
// WITHIN A PACKAGE, EVERY DEFINITION OF ONE NAME MUST TAKE THE SAME NUMBER OF
// PARAMETERS. A function's shape is part of its published interface, and a
// shape that changes with the target is a defect on every target -- the
// backend that has the smaller one is the one that will not compile.
//
// The check reads the SOURCE, so it needs no build, no network and no
// third-party tool: it is the defect class, made checkable on its own.
//
// Usage:
//   node scripts/qa/cfg_signatures.mjs [--root <dir>] [--falsify]
//
//   --root <dir>   scan another tree (the falsifier points it at a mutated
//                  COPY of this one; the real tree is never modified)
//   --falsify      require a mismatch to EXIST, so a detector that can no
//                  longer see one fails instead of passing quietly
//
// Dependency-free, like the rest of the harness.

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

const rootArg = process.argv.indexOf('--root');
const ROOT = rootArg >= 0 ? resolve(process.argv[rootArg + 1]) : resolve(process.cwd());
const falsify = process.argv.includes('--falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ---------------------------------------------------------------------------
// The source files. A package is a directory: `src/app`, `src/command`, and
// the root. Two packages may each have a private function of the same name;
// the invariant is about ONE package.
// ---------------------------------------------------------------------------
function mbtFiles(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) mbtFiles(full, out);
    else if (entry.name.endsWith('.mbt')) out.push(full);
  }
  return out;
}

const files = [];
if (existsSync(join(ROOT, 'src'))) files.push(...mbtFiles(join(ROOT, 'src')));
if (existsSync(join(ROOT, 'main.mbt'))) files.push(join(ROOT, 'main.mbt'));

if (files.length === 0) {
  console.error(`UNKNOWN  no MoonBit source under ${ROOT}`);
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Reading the source without being fooled by it.
//
// A `fn` inside a comment, inside a doc comment, inside a string or inside a
// BLOCK STRING is not a definition, and a comma inside a string is not a
// parameter separator. All of them are blanked out -- with the LENGTH
// preserved, so the line numbers stay right.
//
// The block string matters most here: the test files carry whole MoonBit
// modules as `#| ... |#` fixtures, and those fixtures define functions of
// their own. Read as code, they look like a hundred conflicting definitions.
//
// MoonBit's block string has NO terminator. `#|` opens it, the text after the
// marker is its first chunk, and every following line whose first non-blank
// characters are `#|` is one more chunk; the literal ends before the first
// line that is not one. The rule is the one this module's own lexer
// implements (`src/app/lexer.mbt`, `lex_block_string`), measured by value
// against the toolchain.
//
// The raw string (`#" ... "#`) is handled as well. A `#` that FOLLOWS a quote
// is inside a string already, so it never reaches this branch: `t.text == "#"`
// is a string, not the start of a raw one.
// ---------------------------------------------------------------------------
function blank(text) {
  const lines = text.split('\n');
  const out = [];
  let inBlockComment = false;
  let inBlockString = false;

  for (const line of lines) {
    if (inBlockString) {
      const trimmed = line.replace(/^[ \t]+/, '');
      // A blank line is skipped, and a chunk line is content. Either way the
      // literal carries on.
      if (trimmed === '' || trimmed.startsWith('#|')) {
        out.push(' '.repeat(line.length));
        continue;
      }
      // The first line that is not a chunk line ends the literal, and this
      // line is CODE.
      inBlockString = false;
    }

    let res = '';
    let i = 0;
    while (i < line.length) {
      const c = line[i];
      const d = i + 1 < line.length ? line[i + 1] : '';
      if (inBlockComment) {
        if (c === '*' && d === '/') { res += '  '; i += 2; inBlockComment = false; continue; }
        res += ' '; i += 1; continue;
      }
      if (c === '/' && d === '/') { res += ' '.repeat(line.length - i); break; }
      if (c === '/' && d === '*') { res += '  '; i += 2; inBlockComment = true; continue; }
      if (c === '#' && d === '|') {
        // The rest of this line is the first chunk, and the literal may carry
        // on into the lines below.
        res += '  ' + ' '.repeat(Math.max(0, line.length - i - 2));
        i = line.length;
        inBlockString = true;
        continue;
      }
      if (c === '#' && d === '"') {
        res += '  '; i += 2;
        while (i < line.length) {
          if (line[i] === '"' && line[i + 1] === '#') { res += '  '; i += 2; break; }
          res += ' '; i += 1;
        }
        continue;
      }
      if (c === '"') {
        res += ' '; i += 1;
        while (i < line.length) {
          if (line[i] === '\\') { res += '  '; i += 2; continue; }
          if (line[i] === '"') { res += ' '; i += 1; break; }
          res += ' '; i += 1;
        }
        continue;
      }
      if (c === "'") {
        res += ' '; i += 1;
        while (i < line.length) {
          if (line[i] === '\\') { res += '  '; i += 2; continue; }
          if (line[i] === "'") { res += ' '; i += 1; break; }
          res += ' '; i += 1;
        }
        continue;
      }
      res += c; i += 1;
    }
    out.push(res);
  }
  return out.join('\n');
}

// ---------------------------------------------------------------------------
// The definitions: a name, the number of parameters, and the line.
// ---------------------------------------------------------------------------
const FN = /\bfn\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*\(/g;

function closing(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    const c = text[i];
    if (c === '(' || c === '[' || c === '{') depth += 1;
    else if (c === ')' || c === ']' || c === '}') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function countParams(inner) {
  let depth = 0;
  const segments = [];
  let current = '';
  for (const c of inner) {
    if (c === '(' || c === '[' || c === '{') depth += 1;
    else if (c === ')' || c === ']' || c === '}') depth -= 1;
    if (c === ',' && depth === 0) { segments.push(current); current = ''; continue; }
    current += c;
  }
  segments.push(current);
  // A trailing comma leaves an empty segment, and an empty list is no
  // parameters at all.
  return segments.filter((s) => s.trim() !== '').length;
}

function definitions(text) {
  const clean = blank(text);
  const out = [];
  let m;
  FN.lastIndex = 0;
  while ((m = FN.exec(clean)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = closing(clean, open);
    if (close < 0) continue;
    const line = clean.slice(0, m.index).split('\n').length;
    out.push({ name: m[1], arity: countParams(clean.slice(open + 1, close)), line });
    FN.lastIndex = close;
  }
  return out;
}

// ---------------------------------------------------------------------------
// The comparison.
//
// The unit is a COMPILATION UNIT, not a directory: the files in a directory
// that are not blackbox tests are one package (the whitebox tests are part
// of it), and the blackbox test files are a second one. Two packages may
// each have a private function of the same name; the invariant is about one
// unit.
// ---------------------------------------------------------------------------
const groups = new Map();
let total = 0;
for (const file of files) {
  const rel = relative(ROOT, file).split(sep).join('/');
  const dir = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '.';
  const name = rel.slice(rel.lastIndexOf('/') + 1);
  const unit = name.endsWith('_test.mbt') ? `${dir} (blackbox tests)` : dir;
  for (const def of definitions(readFileSync(file, 'utf8'))) {
    total += 1;
    const key = `${unit}::${def.name}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ ...def, file: rel });
  }
}

const mismatches = [];
const repeated = [];
for (const [key, list] of groups) {
  if (list.length < 2) continue;
  repeated.push(`${key} (${list.length})`);
  const arities = [...new Set(list.map((d) => d.arity))];
  if (arities.length > 1) mismatches.push({ key, list });
}

if (falsify) {
  check(
    'the detector still sees a signature that depends on the target',
    mismatches.length > 0,
    mismatches.length === 0
      ? 'no mismatch found, so the detector cannot see one any more'
      : `${mismatches.length} mismatch(es) found`,
  );
} else {
  check(
    'every name in a compilation unit takes the same number of parameters on every target',
    mismatches.length === 0,
    mismatches.length === 0
      ? `${total} definitions, ${repeated.length} name(s) defined more than once, every one of them the same shape`
      : `${mismatches.length} name(s) disagree`,
  );
  for (const m of mismatches) {
    console.log(`      ${m.key}`);
    for (const d of m.list) {
      console.log(`        ${d.file}:${d.line}  ${d.name}(${d.arity} parameter(s))`);
    }
  }
  if (repeated.length > 0 && mismatches.length === 0) {
    console.log(`      the names defined more than once: ${repeated.join(', ')}`);
  }
}

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
