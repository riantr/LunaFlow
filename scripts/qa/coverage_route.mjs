#!/usr/bin/env node
// The coverage route gate.
//
// `moon coverage analyze` failed on this tree for two reasons, and NEITHER of
// them was a defect in the analyser:
//
//   1. The coverage reporter's LEXER reserves identifiers that the MoonBit
//      compiler accepts (`method`, `abstract`, ...). The default report
//      format (`simp_caret`) is the only one that PARSES the covered sources,
//      so a file using one of those identifiers makes the whole coverage
//      route fail with "cannot parse source file '...': N lexical error(s)".
//      MEASURED: `src/app/eva.mbt` (a parameter named `method`),
//      `src/app/report.mbt` (the `abstract` field of `ReportInput`) and
//      `src/command/command.mbt` (the same field in a struct literal) were
//      the three files the reporter could not read.
//
//   2. The reporter discovers trace sources RECURSIVELY from the current
//      directory, so a STALE `.trace.source` under the repository -- a build
//      tree from before the module was renamed -- makes every report fail
//      with "invalid source range in 'src/cli/main.mbt'". `moon coverage
//      clean` does not remove them; the tree has to be moved out.
//
// Both are checked here, statically and fast: no build, no network.
//
// Usage: node scripts/qa/coverage_route.mjs
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const root = process.cwd();

// The reserved words of `moonbitlang/lexer@0.4.4` (the version
// `moon_cove@0.3.6` pins). MEASURED against the reporter, not guessed: every
// one of them, used as an identifier, is a lexical error for the coverage
// tooling -- and the compiler accepts all of them.
const RESERVED = [
  'module', 'move', 'ref', 'static', 'super', 'unsafe', 'use', 'await', 'dyn',
  'abstract', 'do', 'final', 'macro', 'override', 'typeof', 'virtual', 'yield',
  'local', 'method', 'alias', 'assert',
];

const SOURCE_DIRS = ['src', 'fixtures'];
const SOURCE_EXT = '.mbt';

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith(SOURCE_EXT)) out.push(p);
  }
  return out;
}

// Remove comments and string literals, keeping the line structure so a hit
// can be located. The scanner is a state machine, not a regex sweep: a `//`
// inside a string is not a comment, and a string inside a comment is not a
// string.
//
// THE MULTI-LINE STRING, AND THE BLIND SPOT IT CAUSED.  MoonBit's multi-line
// string has NO TERMINATOR: the literal opens with `#|`, EVERY content line
// carries the `#|` prefix, and the literal ends at the first line that does
// NOT carry it -- the module's own `src/app/lexer.mbt` states this, and
// `src/app/block_string_test.mbt` pins it.  A bare `#|` line is an EMPTY
// line of the literal, not the end of it.
//
// This scanner used to look for a `|#` closer, which never comes -- and a
// closer that is never found blanks THE REST OF THE FILE.  MEASURED, by
// evaluating the stripper out of THIS file: the check read 20,964 code lines
// of the tree before the repair and reads 24,321 after it -- 3,357 more, 16.0
// % more.  `src/command/command.mbt` was the worst case: its 65-line usage
// text is one multi-line literal, and the 1,158 code lines after it were
// invisible.  A reserved identifier planted after that literal left the check
// GREEN.  `scripts/qa/coverage_route_falsify.mjs` is the proof, and it runs
// on COPIES.
//
// The rule now: a `#|` whose line carries nothing before it is a literal
// CONTENT line, and the whole line is blanked.  A `#|` anywhere else is
// inside a comment or a normal string, which the earlier branches already
// consumed; if one is ever left over, the REST OF THE LINE is blanked -- which
// cannot swallow the file, and is the failure mode worth avoiding.
function stripNonCode(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  const blank = (text) => text.replace(/[^\n]/g, ' ');
  // Is the position at the start of a line, ignoring the indentation?
  const atLineStart = (at) => {
    let j = at - 1;
    while (j >= 0 && (src[j] === ' ' || src[j] === '\t')) j -= 1;
    return j < 0 || src[j] === '\n';
  };
  while (i < n) {
    const two = src.slice(i, i + 2);
    if (two === '//') {
      const end = src.indexOf('\n', i);
      const stop = end === -1 ? n : end;
      out += blank(src.slice(i, stop));
      i = stop;
      continue;
    }
    if (two === '/*') {
      const end = src.indexOf('*/', i + 2);
      const stop = end === -1 ? n : end + 2;
      out += blank(src.slice(i, stop));
      i = stop;
      continue;
    }
    if (two === '#|') {
      const end = src.indexOf('\n', i);
      const stop = end === -1 ? n : end;
      if (atLineStart(i)) {
        // A literal CONTENT line: the whole line is string content.
        out += blank(src.slice(i, stop));
        i = stop;
        continue;
      }
      // Not a content line, so it is inside a comment or a normal string --
      // both of which the branches above consume.  If one is ever left over,
      // the REST OF THE LINE is string content: that cannot swallow the file.
      out += blank(src.slice(i, stop));
      i = stop;
      continue;
    }
    if (src[i] === '"') {
      let j = i + 1;
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue; }
        if (src[j] === '"') { j++; break; }
        j++;
      }
      out += blank(src.slice(i, j));
      i = j;
      continue;
    }
    out += src[i];
    i++;
  }
  return out;
}

function moduleName() {
  const text = readFileSync(join(root, 'moon.mod'), 'utf8');
  const m = text.match(/^\s*name\s*=\s*"([^"]+)"/m);
  return m ? m[1] : null;
}

let failures = 0;
const fail = (msg) => { failures++; console.log(`FAIL  ${msg}`); };
const pass = (msg) => console.log(`PASS  ${msg}`);

// --- 1. reserved identifiers -------------------------------------------------
const sources = [];
for (const dir of SOURCE_DIRS) sources.push(...walk(join(root, dir)));
sources.push(join(root, 'main.mbt'));

const hits = [];
for (const file of sources) {
  if (!existsSync(file)) continue;
  const code = stripNonCode(readFileSync(file, 'utf8'));
  const lines = code.split('\n');
  lines.forEach((line, idx) => {
    for (const word of RESERVED) {
      // A word after `.` is a FIELD name and a word after `@` is a PACKAGE
      // name (`@ref.Ref(0)`): neither is an identifier the lexer reserves.
      const re = new RegExp(`(?<![\\w.$@])${word}(?![\\w])`);
      if (re.test(line)) {
        hits.push(`${relative(root, file).split(sep).join('/')}:${idx + 1}  '${word}'`);
      }
    }
  });
}

if (hits.length) {
  fail(`${hits.length} reserved identifier(s) in the sources -- the coverage reporter cannot read them:`);
  for (const h of hits) console.log(`      ${h}`);
  console.log('      The reporter reserves these words; the compiler accepts them.');
  console.log('      Rename them (for a public field, the name the QA report asks for).');
} else {
  pass(`no reserved identifier in ${sources.length} source file(s)`);
}

// --- 2. stale trace trees ----------------------------------------------------
const module = moduleName();
const traces = [];
(function findTraces(dir) {
  if (!existsSync(dir)) return;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) {
      if (name === '.git' || name === '.repos') continue;
      findTraces(p);
    } else if (name.endsWith('.trace.source')) {
      traces.push(p);
    }
  }
})(root);

const stale = [];
for (const trace of traces) {
  const text = readFileSync(trace, 'latin1');
  if (!module) continue;
  // The trace names its module. A trace that does NOT name the CURRENT module
  // was written for another one -- a tree from before the module was renamed
  // -- and every report that reads it fails with "invalid source range".
  if (!text.includes(module)) {
    stale.push(`${relative(root, trace).split(sep).join('/')}  ->  was written for another module (the module is now '${module}')`);
    continue;
  }
  // The package paths are the text between the module name and the `$` that
  // ends the id. They are DIRECTORIES of this repository (`src/app`,
  // `fixtures/conc_demo`, ...), so they are what has to still exist.
  let pos = 0;
  while (pos < text.length) {
    const at = text.indexOf(module, pos);
    if (at === -1) break;
    pos = at + module.length;
    const dollar = text.indexOf('$', pos);
    if (dollar === -1) continue;
    const path = text.slice(pos, dollar);
    if (path === '' || !/^[A-Za-z0-9_.\-\/]+$/.test(path)) continue;
    if (!existsSync(join(root, path))) {
      stale.push(`${relative(root, trace).split(sep).join('/')}  ->  package path '${path}' does not exist`);
    }
  }
}

if (stale.length) {
  fail(`${stale.length} stale coverage trace reference(s) -- they make EVERY report fail with 'invalid source range':`);
  for (const s of stale.slice(0, 12)) console.log(`      ${s}`);
  console.log('      `moon coverage clean` does not remove them. Move the build tree OUT of the repository.');
} else {
  pass(`no stale coverage trace in ${traces.length} trace file(s)`);
}

console.log(`\n${failures === 0 ? 'RESULT: coverage route OK' : `RESULT: ${failures} failure(s)`}`);
process.exit(failures === 0 ? 0 : 1);
