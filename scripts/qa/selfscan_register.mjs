#!/usr/bin/env node
// THE SELF-SCAN'S REGISTER, CHECKED AGAINST THE ANALYSER THAT WROTE IT.
//
// `src/app/selfscan_guards_wbtest.mbt` holds THE REGISTER: every claim the
// analyser makes about its OWN source, and the guard that answers it.  The
// register says of itself that "a claim that is NOT registered is a claim
// nobody has answered, and that is the kind that hides a real defect" -- and
// it had drifted.  It was measured on 2026-11-22 against 26 claims; the tree
// makes 29.  Three of them were in a function that was added afterwards, and
// nobody had answered them.
//
// So the register is re-measured here.  The analyser runs over this module's
// own source and what it says NOW is compared with what the register says:
//
//   * every claim the analyser makes about this source is REGISTERED, with
//     the count the analyser measured -- a claim nobody answered is the kind
//     that hides a defect;
//   * every claim the register states is STILL MADE -- a register that
//     overstates has gone stale in the other direction;
//   * the register's headline count is the count that was measured, and the
//     register's own rows add up to that headline;
//   * every family the register names is a family the analyser HAS (read
//     from `src/app/model.mbt`, not from a list this file carries), and
//     every site it names is a site that is still in the source.
//
// The comparison is between two measurements OF THE SAME TREE, so it does not
// depend on the toolchain: the claims come from this module's OWN parser
// (`src/app/parser.mbt`) reading this module's OWN source, so a newer
// MoonBit does not move them.  A difference means the TREE changed -- which
// is exactly when the register has to be written again.
//
// The counterexamples come along for the ride: every claim an execution
// produced, except the one about the analyser's own step budget (which is not
// a claim about an input at all), must have a counterexample -- an input that
// reproduces it.  A registered claim with no reproducing input has been
// LISTED, not looked at.
//
// Usage: node scripts/qa/selfscan_register.mjs [--artefacts <dir>] [--register <file>]
//
// `--artefacts <dir>` checks artefacts that are ALREADY THERE and does not
// run the analyser.  `--register <file>` reads the register from THAT file
// instead of the tracked one.  The falsifier uses both to point these same
// checks at a mutated COPY.
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const REGISTER_PATH = join(ROOT, 'src', 'app', 'selfscan_guards_wbtest.mbt');
const MODEL_PATH = join(ROOT, 'src', 'app', 'model.mbt');
const SRC = join(ROOT, 'src');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

const argValue = (flag) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const ARTIFACTS = argValue('--artefacts');
const REGISTER_FILE = argValue('--register') ? resolve(argValue('--register')) : REGISTER_PATH;

// --------------------------------------------------------------- the register

/// The register's table, parsed.
///
/// The format is the one the register itself uses: a row names the file, the
/// function and then the CLAIMS -- `INDEX-OOB`, `3 x INDEX-OOB` -- and after
/// that the guard, which is the part in backticks.  The claims column is cut
/// at the first backtick, so the guard's own words are never read as claims.
export function parseRegister(text) {
  const rows = [];
  let headline = null;
  let inTable = false;
  let current = null;

  const close = () => {
    if (current) {
      rows.push(current);
      current = null;
    }
  };

  for (const raw of text.split(/\r?\n/)) {
    const h = /reports (\d+) findings/.exec(raw);
    if (h) headline = Number(h[1]);
    if (!raw.startsWith('///')) {
      inTable = false;
      close();
      continue;
    }
    const line = raw.replace(/^\/\/\/\s?/, '');
    if (/^\s*site\s+claims\s+the guard\s*$/.test(line)) {
      inTable = true;
      continue;
    }
    if (!inTable) continue;
    if (line.trim() === '') {
      inTable = false;
      close();
      continue;
    }
    const content = line.trim();
    const row = /^(\S+\.mbt)\s+(\S+)\s*(.*)$/.exec(content);
    if (row) {
      close();
      current = { file: row[1], fn: row[2], claims: row[3].split('`')[0] };
      continue;
    }
    if (current) current.claims += ' ' + content.split('`')[0];
  }
  close();

  for (const r of rows) {
    r.families = new Map();
    const re = /(?:(\d+)\s*x\s*)?\b([A-Z][A-Z-]*)\b/g;
    let m;
    while ((m = re.exec(r.claims)) !== null) {
      const count = m[1] ? Number(m[1]) : 1;
      r.families.set(m[2], (r.families.get(m[2]) ?? 0) + count);
    }
  }
  return { headline, rows };
}

/// The family codes the analyser HAS, read from its own source: the arms of
/// `FindingKind::code`.  A list in this file would be a second source of
/// truth that could drift from the analyser it checks.
export function extractFamilyCodes(modelText) {
  const codes = new Set();
  const re = /^\s*F\w+\s*=>\s*"([A-Z][A-Z-]*)"/gm;
  let m;
  while ((m = re.exec(modelText)) !== null) codes.add(m[1]);
  return codes;
}

/// The claims the analyser makes about THIS module's own source.
export function ownSourceClaims(findings) {
  return findings
    .filter((f) => typeof f.file === 'string' && f.file.replace(/\\/g, '/').startsWith('src/'))
    .map((f) => ({
      file: f.file.replace(/\\/g, '/'),
      base: basename(f.file.replace(/\\/g, '/')),
      fn: f.fn,
      family: f.rule,
      method: f.method,
      line: f.line,
    }));
}

/// The registered rows that could answer a claim: the same file, a function
/// name that is a prefix of the measured one (the register writes
/// `ffi_check_signature_...` where the name is longer), and the family.
function rowsFor(rows, claim) {
  return rows.filter(
    (r) =>
      r.file === claim.base &&
      r.fn.replace(/\.+$/, '').length > 0 &&
      claim.fn.startsWith(r.fn.replace(/\.+$/, '')) &&
      r.families.has(claim.family),
  );
}

/// The comparison itself: the register against the measured claims.  It
/// returns the problems it finds, and an empty list means the register is
/// exactly what the analyser says.
export function compareRegister(register, claims, familyCodes) {
  const problems = [];

  // Every family the register names is one the analyser HAS.
  for (const r of register.rows) {
    for (const family of r.families.keys()) {
      if (!familyCodes.has(family)) {
        problems.push({
          name: 'a family the register names is not a family the analyser has',
          detail: `${r.file} ${r.fn}: ${family}`,
        });
      }
    }
  }

  // Every measured claim is registered, with the count that was measured.
  const measuredCounts = new Map();
  for (const c of claims) {
    const key = `${c.base}|${c.fn}|${c.family}`;
    measuredCounts.set(key, (measuredCounts.get(key) ?? 0) + 1);
  }
  for (const c of claims) {
    const hits = rowsFor(register.rows, c);
    const key = `${c.base}|${c.fn}|${c.family}`;
    const count = measuredCounts.get(key);
    if (hits.length === 0) {
      problems.push({
        name: 'a claim the analyser makes about this source is not registered',
        detail: `${c.family} at ${c.base}:${c.line} (${c.fn})`,
      });
      continue;
    }
    if (hits.length > 1) {
      problems.push({
        name: 'a claim is answered by more than one registered row',
        detail: `${c.family} at ${c.base}:${c.line} (${c.fn})`,
      });
      continue;
    }
    const registered = hits[0].families.get(c.family);
    if (registered !== count) {
      problems.push({
        name: 'the register and the analyser disagree about how many claims a site has',
        detail: `${c.base} ${c.fn} ${c.family}: register ${registered}, analyser ${count}`,
      });
    }
  }

  // Every registered claim is still made.
  for (const r of register.rows) {
    for (const [family, count] of r.families) {
      const matched = claims.filter(
        (c) =>
          c.base === r.file &&
          c.family === family &&
          c.fn.startsWith(r.fn.replace(/\.+$/, '')),
      );
      const got = matched.length;
      if (got !== count) {
        problems.push({
          name: 'the register states a claim the analyser does not make',
          detail: `${r.file} ${r.fn} ${family}: register ${count}, analyser ${got}`,
        });
      }
    }
  }

  // The headline, and the rows' own sum.
  const measuredTotal = claims.length;
  let registeredTotal = 0;
  for (const r of register.rows) {
    for (const count of r.families.values()) registeredTotal += count;
  }
  if (register.headline === null) {
    problems.push({ name: 'the register states no headline count', detail: '' });
  } else if (register.headline !== measuredTotal) {
    problems.push({
      name: "the register's headline count is not the count that was measured",
      detail: `register ${register.headline}, analyser ${measuredTotal}`,
    });
  }
  if (register.headline !== null && registeredTotal !== register.headline) {
    problems.push({
      name: "the register's rows do not add up to its own headline",
      detail: `rows ${registeredTotal}, headline ${register.headline}`,
    });
  }

  return problems;
}

// --------------------------------------------------------------- the source

/// Every `.mbt` file under `src/`, by base name.
function sourceFiles(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) sourceFiles(p, out);
    else if (entry.name.endsWith('.mbt')) out.push(p);
  }
  return out;
}

// --------------------------------------------------------------- the run

function readSidecar(dir, suffix) {
  const file = readdirSync(dir).find((f) => f.endsWith(suffix));
  if (!file) return null;
  return readFileSync(join(dir, file), 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.trim().length > 0)
    .map((l) => JSON.parse(l));
}

let findings = [];
let counterexamples = [];

if (ARTIFACTS) {
  const f = readSidecar(ARTIFACTS, '_findings.jsonl');
  const c = readSidecar(ARTIFACTS, '_counterexamples.jsonl');
  if (!f) {
    console.error(`no findings sidecar in ${ARTIFACTS}`);
    process.exit(2);
  }
  findings = f;
  counterexamples = c ?? [];
} else {
  // The binary under test is BUILT HERE, not assumed: a binary left over from
  // an earlier build measures the product as it WAS.
  {
    const build = spawnSync('moon', ['build', 'src/cli', '--target', 'native'], {
      cwd: ROOT,
      encoding: 'utf8',
      timeout: 900000,
      maxBuffer: 32 * 1024 * 1024,
      shell: true,
    });
    if (build.status !== 0) {
      console.error('the CLI build failed, so there is nothing to check:');
      console.error((build.stderr ?? '') + (build.stdout ?? ''));
      process.exit(2);
    }
  }
  const exe = requireCli(ROOT);
  const out = join(ROOT, '_build', 'qa', 'selfscan_register');
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  const run = spawnSync(
    exe,
    ['analyze', '--dir', '.', '--out', out, '--funnel', '--counterexamples'],
    { cwd: ROOT, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (run.status !== 0) {
    console.error('the self-scan failed, so there is nothing to check:');
    console.error((run.stderr ?? '').split(/\r?\n/).slice(0, 5).join('\n'));
    process.exit(2);
  }
  const f = readSidecar(out, '_findings.jsonl');
  if (!f) {
    console.error('the self-scan wrote no findings sidecar');
    process.exit(2);
  }
  findings = f;
  counterexamples = readSidecar(out, '_counterexamples.jsonl') ?? [];
}

const claims = ownSourceClaims(findings);
check('the self-scan made claims about this module\'s own source', claims.length > 0, `${claims.length} claim(s)`);
if (claims.length === 0) {
  console.log('\nRESULT: UNKNOWN (the analyser made no claim about its own source)');
  process.exit(2);
}

const registerText = readFileSync(REGISTER_FILE, 'utf8');
const register = parseRegister(registerText);
const familyCodes = extractFamilyCodes(readFileSync(MODEL_PATH, 'utf8'));

check('the register has a headline count', register.headline !== null, String(register.headline));
check('the register has rows', register.rows.length > 0, `${register.rows.length} row(s)`);
check(
  'the analyser has the families the register names',
  familyCodes.size > 0,
  `${familyCodes.size} family code(s)`,
);

const problems = compareRegister(register, claims, familyCodes);
for (const p of problems) {
  check(p.name, false, p.detail);
}
check(
  'the register and the analyser agree about every claim',
  problems.length === 0,
  problems.length === 0 ? '' : `${problems.length} problem(s)`,
);

// Every site the register names is still in the source.
const files = sourceFiles(SRC);
for (const r of register.rows) {
  const hits = files.filter((f) => basename(f) === r.file);
  check(`the register's file ${r.file} is still in the source`, hits.length > 0, `${hits.length} match(es)`);
  if (hits.length === 0) continue;
  const wanted = `fn ${r.fn.replace(/\.+$/, '')}`;
  const found = hits.some((f) => readFileSync(f, 'utf8').includes(wanted));
  check(`the register's function ${r.fn} is still in ${r.file}`, found, wanted);
}

// The counterexamples: every claim an execution produced, except the one
// about the analyser's own step budget, has an input that reproduces it.
const missingCx = [];
for (const c of claims) {
  if (!String(c.method).startsWith('dynamic')) continue;
  if (c.family === 'BUDGET-EXCEEDED') continue;
  const hit = counterexamples.some(
    (cx) =>
      cx.rule === c.family &&
      basename(String(cx.file).replace(/\\/g, '/')) === c.base &&
      cx.fn === c.fn,
  );
  if (!hit) missingCx.push(`${c.family} at ${c.base}:${c.line} (${c.fn})`);
}
check(
  'every claim an execution produced has a counterexample',
  missingCx.length === 0,
  missingCx.length === 0 ? '' : missingCx.join('; '),
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
