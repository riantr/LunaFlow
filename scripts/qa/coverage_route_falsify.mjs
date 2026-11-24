#!/usr/bin/env node
// THE COVERAGE-ROUTE CHECK, PROVED ABLE TO FAIL.
//
// A check that cannot fail is not a check.  This falsifier runs the REAL
// `scripts/qa/coverage_route.mjs` on COPIES of the tree -- never a tracked
// file -- and asserts that it goes RED on the ways the published claim could
// be WRONG while still looking fine.
//
// THE DEFECT THIS WAS WRITTEN FOR.  The check strips comments and string
// literals before it looks for the identifiers the coverage reporter's lexer
// reserves.  Its stripper used to treat a `#|` as the start of a block string
// closed by `|#` -- and MoonBit's multi-line string has NO TERMINATOR, so the
// closer was never found and the stripper blanked THE REST OF THE FILE.
// MEASURED, by evaluating the stripper out of the tracked file: the check
// read 20,964 code lines of the tree before the repair and reads 24,321 after
// it -- 3,357 more, 16.0 % more.  `src/command/command.mbt` was the worst
// case: its 65-line usage text is one multi-line literal, and the 1,158 code
// lines after it were invisible.  A reserved identifier planted after that
// literal left the check GREEN -- it measured nothing about the code after
// the literal and said OK.
//
// THE CASES.
//
//   F1  a reserved identifier in a file that holds a multi-line literal --
//       APPENDED, so it lands after the literal, which is exactly where the
//       old stripper stopped seeing code.
//   F2  a reserved identifier appended to a file with NO literal at all --
//       the case that always worked, kept so a regression there is caught.
//   F3  the same reserved identifier, in the MIDDLE of a file, before any
//       literal -- it must be caught there too.
//
// THE CONTROL.  An identifier that is NOT reserved, appended to the same file
// F1 used: the check must NOT notice it.  Without the control, a checker that
// failed on every possible edit would look like a checker that works.
//
// The check reads the tree it is pointed at, so each case runs it with the
// COPY as the working directory.
//
// Usage: node scripts/qa/coverage_route_falsify.mjs
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import {
  cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { join, relative, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const CHECK = join(ROOT, 'scripts', 'qa', 'coverage_route.mjs');
const WORK = join(ROOT, '_build', 'qa', 'coverage_route_falsify');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`);
};

// --- the tree, copied -------------------------------------------------------

/// The files the check reads: the sources, the fixtures, the manifest and the
/// root entry point.  Copied whole, so the copy is a tree the check can run
/// against.
const COPIED = ['src', 'fixtures', 'moon.mod', 'main.mbt'];

function copyTree(dir) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const item of COPIED) {
    const from = join(ROOT, item);
    if (!existsSync(from)) continue;
    cpSync(from, join(dir, item), { recursive: true });
  }
  return dir;
}

/// Every source file under a directory, recursively.
function sourceFiles(dir) {
  const out = [];
  const walk = (d) => {
    if (!existsSync(d)) return;
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (p.endsWith('.mbt')) out.push(p);
    }
  };
  walk(dir);
  out.sort();
  return out;
}

/// A source file that holds a multi-line literal -- the shape the old stripper
/// got wrong.  Found at RUN TIME, not named: a named file is a file that stops
/// existing the day the tree moves.
function fileWithLiteral(dir) {
  for (const p of sourceFiles(join(dir, 'src'))) {
    if (/^\s*#\|/m.test(readFileSync(p, 'utf8'))) return p;
  }
  return null;
}

/// A source file with NO literal at all, so a mutation in it cannot be
/// explained by the literal handling.
function fileWithoutLiteral(dir) {
  for (const p of sourceFiles(join(dir, 'src'))) {
    if (!/^\s*#\|/m.test(readFileSync(p, 'utf8'))) return p;
  }
  return null;
}

/// The path the check PRINTS: relative to the copy it ran in, with forward
/// slashes -- the check normalises the separator, because its output is read
/// by a reader and by CI on Linux.
function printedPath(caseDir, file) {
  return relative(caseDir, file).split(/[\\/]/).join('/');
}

/// Run the real check against a copy.  It must go red.
function mustGoRed(name, dir, expect, plantedIn) {
  const r = spawnSync(process.execPath, [CHECK], { cwd: dir, encoding: 'utf8', timeout: 300000 });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  const red = r.status === 1;
  check(`${name}: the check goes red`, red, `exit=${r.status}`);
  if (red) {
    check(`${name}: it fails for the right reason`, out.includes(expect), expect);
    if (plantedIn) {
      check(
        `${name}: it names the file the identifier was planted in`,
        out.includes(plantedIn),
        plantedIn,
      );
    }
  }
}

/// Run the real check against a copy.  It must stay green.
function mustStayGreen(name, dir) {
  const r = spawnSync(process.execPath, [CHECK], { cwd: dir, encoding: 'utf8', timeout: 300000 });
  const out = (r.stdout ?? '') + (r.stderr ?? '');
  check(`${name}: the check stays green`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) {
    for (const l of out.split(/\r?\n/).filter((x) => x.startsWith('FAIL')).slice(0, 4)) console.log(`        ${l}`);
  }
}

/// Append a line to a file, and say so.  A mutation that changes nothing is
/// not a mutation, and a falsifier that accepts one proves nothing.
function appendLine(file, line) {
  const before = readFileSync(file, 'utf8');
  const after = before.endsWith('\n') ? before + line + '\n' : before + '\n' + line + '\n';
  if (after === before) throw new Error(`the mutation for ${file} changed nothing`);
  writeFileSync(file, after, 'utf8');
  return after;
}

// --- the truth --------------------------------------------------------------

const truth = copyTree(join(WORK, 'truth'));
mustStayGreen('the unmodified copy', truth);

// --- F1: a reserved identifier AFTER a multi-line literal --------------------

{
  const dir = copyTree(join(WORK, 'f1'));
  const target = fileWithLiteral(dir);
  if (!target) {
    check('F1: the copy holds a file with a multi-line literal', false);
  } else {
    // `method` is one of the reporter's reserved words.  It is APPENDED, so it
    // lands after the literal -- exactly where the old stripper stopped seeing
    // code and the check went green.
    appendLine(target, 'let method = 1');
    mustGoRed(
      'F1 a reserved identifier after a multi-line literal',
      dir,
      'reserved identifier',
      printedPath(dir, target),
    );
  }
}

// --- F2: a reserved identifier in a file with NO literal ---------------------

{
  const dir = copyTree(join(WORK, 'f2'));
  const target = fileWithoutLiteral(dir);
  if (!target) {
    check('F2: the copy holds a file with no literal', false);
  } else {
    appendLine(target, 'let method = 1');
    mustGoRed(
      'F2 a reserved identifier in a file with no literal',
      dir,
      'reserved identifier',
      printedPath(dir, target),
    );
  }
}

// --- F3: a reserved identifier in the MIDDLE of a file ------------------------

{
  const dir = copyTree(join(WORK, 'f3'));
  const target = fileWithLiteral(dir);
  if (!target) {
    check('F3: the copy holds a file with a multi-line literal', false);
  } else {
    const before = readFileSync(target, 'utf8');
    // Before the FIRST literal: the case that always worked, kept so a
    // regression there is caught too.
    const at = before.search(/^\s*#\|/m);
    if (at < 0) {
      check('F3: the copy holds a literal to plant before', false);
    } else {
      const lineStart = before.lastIndexOf('\n', at) + 1;
      const after = before.slice(0, lineStart) + 'let method = 1\n' + before.slice(lineStart);
      writeFileSync(target, after, 'utf8');
      mustGoRed(
        'F3 a reserved identifier before any literal',
        dir,
        'reserved identifier',
        printedPath(dir, target),
      );
    }
  }
}

// --- the CONTROL: an identifier that is NOT reserved -------------------------

{
  const dir = copyTree(join(WORK, 'control'));
  const target = fileWithLiteral(dir);
  if (!target) {
    check('the control: the copy holds a file with a multi-line literal', false);
  } else {
    // Same place, same shape, a word the reporter does NOT reserve.
    appendLine(target, 'let helper_name = 1');
    mustStayGreen('the control', dir);
  }
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
