#!/usr/bin/env node
// THE DRIFT DETECTOR MUST COMPARE COUNTS EXACTLY.
//
// `scripts/qa/readme_table.mjs` is what keeps the README's published numbers
// true: it compares every published count with the count that was MEASURED,
// and the only way such a comparison passes is for the two to BE the same.
// That is what makes a published number falsifiable -- the drift detector is
// the check that fails when the tree moves.
//
// An ORDERING comparison is the one shape that can pass VACUOUSLY. "The
// README's count must be at most the measured count" is satisfied by a README
// that UNDER-states the tree, so the check goes green while the tree gets
// worse, and nothing in the run says so. So the drift detector may not
// compare a published count with a measured count by ORDER: `<`, `<=`, `>`
// and `>=` between two values are all forbidden, and only `===` and `!==`
// are allowed.
//
// WHY A LEXER AND NOT A GREP. The detector mentions comparisons in its
// comments and in the messages it prints ("README 7,208 vs the tree 7,223"),
// and its arrow functions carry a `>` that is not a comparison at all. A
// search for the characters would flag all three. So the source is stripped
// of comments and string literals FIRST, and only what is left -- actual
// code -- is read for comparisons.
//
// WHY THE SENTINEL IS EXEMPT. The detector asks "was the index found?" with
// `start < 0` and `i < 0`. That is a POSITION check, not a count check: one
// side is the literal zero, and no published count is compared with a
// measured count through it. A comparison is a violation only when BOTH
// sides are values -- so `cell <= s[f]` is caught and `i < 0` is not.
//
// WHAT THIS DOES NOT PROVE. It catches the weakening that a rewrite would
// use -- an ordering comparison where an equality belongs. A rewriting that
// KEEPS `===` but changes what it compares (`Math.min(cell, s[f]) === cell`)
// is a review question, not a syntax question, and this check does not claim
// to settle it.
//
// Exit codes: 0 the discipline holds; 1 it does not; 2 the detector could
// not be read, so there is NO VERDICT -- never a false accusation.
//
// Usage: node scripts/qa/exact_counts.mjs [file-to-check]

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const target = process.argv[2] ?? 'scripts/qa/readme_table.mjs';

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

// ------------------------------------------------------- the lexer
//
// The source with its comments and string literals REMOVED, one entry per
// line, so a comparison that is only mentioned in prose is not a comparison,
// and so a violation can be reported with the line it is on.
//
// The four things that can hold text that is not code: a line comment, a
// block comment, a quoted string, and a template literal. A template's
// `${...}` interpolation IS code, so it is kept; only the literal text
// between the backticks is dropped.
//
// A `/` starts a REGEX when the last significant character is one that
// cannot end an expression -- `=`, `(`, `,`, `:` and friends. That is the
// usual heuristic, and it is enough here: the detector's regexes carry no
// ordering character, but a `/` that starts a division must not be read as
// the start of a literal.

const CODE = 0;
const TEMPLATE = 1;
const INTERP = 2;

function codeOnly(text) {
  const lines = [''];
  let i = 0;
  let last = '';
  const stack = [CODE];
  const push = (c) => {
    if (c === '\n') lines.push('');
    else lines[lines.length - 1] += c;
    if (!/\s/.test(c)) last = c;
  };
  while (i < text.length) {
    const c = text[i];
    const n = text[i + 1];
    const mode = stack[stack.length - 1];
    if (mode === CODE) {
      if (c === '/' && n === '/') {
        while (i < text.length && text[i] !== '\n') i += 1;
        continue;
      }
      if (c === '/' && n === '*') {
        i += 2;
        while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) {
          if (text[i] === '\n') lines.push('');
          i += 1;
        }
        i += 2;
        continue;
      }
      if (c === '"' || c === "'") {
        i += 1;
        while (i < text.length && text[i] !== c) {
          if (text[i] === '\\') i += 1;
          i += 1;
        }
        i += 1;
        continue;
      }
      if (c === '`') {
        stack.push(TEMPLATE);
        i += 1;
        continue;
      }
      if (c === '/' && '=(,:[!&|?{;+-'.includes(last)) {
        // A REGEX literal: skip to its closing slash.
        i += 1;
        let inClass = false;
        while (i < text.length) {
          if (text[i] === '\\') {
            i += 2;
            continue;
          }
          if (text[i] === '[') inClass = true;
          else if (text[i] === ']') inClass = false;
          else if (text[i] === '/' && !inClass) break;
          else if (text[i] === '\n') break;
          i += 1;
        }
        i += 1;
        continue;
      }
      if (c === '{' && stack.length > 1 && stack[stack.length - 2] === TEMPLATE) {
        stack.push(INTERP);
        push(c);
        i += 1;
        continue;
      }
      if (c === '}' && mode === INTERP) {
        stack.pop();
        push(c);
        i += 1;
        continue;
      }
      push(c);
      i += 1;
      continue;
    }
    if (mode === TEMPLATE) {
      if (c === '\\') {
        i += 2;
        continue;
      }
      if (c === '`') {
        stack.pop();
        i += 1;
        continue;
      }
      if (c === '$' && n === '{') {
        stack.push(INTERP);
        i += 2;
        continue;
      }
      if (c === '\n') lines.push('');
      i += 1;
      continue;
    }
    // INTERP: code, but a `}` returns to the template.
    if (c === '}') {
      stack.pop();
      i += 1;
      continue;
    }
    push(c);
    i += 1;
  }
  return lines;
}

// ------------------------------------------------- the comparisons

// A comparison is ORDERING when it asks "is one side above the other?", and
// EXACT when it asks "are these two the same?". Only the second can be the
// comparison of a published count with a measured count.
const ORDER_OPS = ['<=', '>=', '<', '>'];
const EXACT_OPS = ['===', '!==', '==', '!='];

// The literal that a comparison may have on one side: a number, a quoted
// string, or one of the four words that stand for a value.
const LITERAL = /^[0-9]|^['"`]|^(true|false|null|undefined)\b/;

// The operand next to an operator: the last (or first) significant token,
// which is enough to tell a VALUE from a LITERAL.
function operandAt(line, from, step) {
  let i = from;
  for (;;) {
    if (i < 0 || i >= line.length) return '';
    const c = line[i];
    if (!/\s/.test(c)) {
      if (/[A-Za-z_$]/.test(c)) {
        if (step < 0) {
          let start = i;
          while (start > 0 && /[A-Za-z0-9_$]/.test(line[start - 1])) start -= 1;
          return line.slice(start, i + 1);
        }
        let end = i;
        while (end < line.length && /[A-Za-z0-9_$]/.test(line[end])) end += 1;
        return line.slice(i, end);
      }
      return c;
    }
    i += step;
  }
}

function comparisonsIn(lines) {
  const found = [];
  lines.forEach((line, index) => {
    for (let i = 0; i < line.length; i += 1) {
      const c = line[i];
      if (c !== '<' && c !== '>' && c !== '=' && c !== '!') continue;
      // `=>` is an arrow, not a comparison; `!` alone is not one either.
      if (c === '>' && line.slice(0, i).trimEnd().endsWith('=')) continue;
      if (c === '=' && line[i + 1] === '>') continue;
      if (c === '!' && line[i + 1] !== '=') continue;
      if (c === '=' && line[i + 1] !== '=') continue;
      const two = line.slice(i, i + 2);
      const op = ORDER_OPS.includes(two) || EXACT_OPS.includes(two) ? two : c;
      if (!ORDER_OPS.includes(op) && !EXACT_OPS.includes(op)) continue;
      const width = op.length;
      const left = operandAt(line, i - 1, -1);
      const right = operandAt(line, i + width, +1);
      found.push({
        line: index + 1,
        op,
        kind: ORDER_OPS.includes(op) ? 'order' : 'exact',
        text: line.trim(),
        left,
        right,
        bothValues: !LITERAL.test(left) && !LITERAL.test(right),
      });
      i += width - 1;
    }
  });
  return found;
}

// ------------------------------------------------------------ the check

const path = resolve(ROOT, target);
let source;
try {
  source = readFileSync(path, 'utf8');
} catch (e) {
  console.error(`the detector could not be read, so there is NO VERDICT: ${path}`);
  console.error(e instanceof Error ? e.message : String(e));
  process.exit(2);
}

check(
  'the drift detector could be read',
  true,
  `${target} (${source.split(/\r?\n/).length} lines)`,
);

const code = codeOnly(source);
const comparisons = comparisonsIn(code);
const orderings = comparisons.filter((c) => c.kind === 'order');
const violations = orderings.filter((c) => c.bothValues);

check(
  'the drift detector compares no two values by ORDER',
  violations.length === 0,
  violations.length
    ? violations.map((v) => `${target}:${v.line} ${v.op} (${v.left} ${v.op} ${v.right})`).join('; ')
    : `${orderings.length} ordering comparison(s), all of them a position check against a literal`,
);

// The exemptions are reported, so a reader can see what the rule allows.
const exempt = orderings.filter((c) => !c.bothValues);
console.log(
  `      ${exempt.length} position check(s) against a literal are allowed: ` +
    exempt.map((c) => `${target}:${c.line} ${c.left} ${c.op} ${c.right}`).join(', '),
);

// And the rule is not satisfied by a detector that compares NOTHING: the
// exact comparisons between two values are what the drift detector is made
// of, so their absence has to be a failure too.
const exactOnValues = comparisons.filter((c) => c.kind === 'exact' && c.bothValues);
check(
  'the drift detector does compare counts, by EXACT equality',
  exactOnValues.length > 0,
  `${exactOnValues.length} exact comparison(s) between two values`,
);

console.log(
  `\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks - failures} passed, ${failures} failure(s))`,
);
process.exit(failures === 0 ? 0 : 1);
