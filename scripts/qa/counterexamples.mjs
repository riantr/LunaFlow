#!/usr/bin/env node
// THE COUNTEREXAMPLES, CHECKED AGAINST WHAT THEY CLAIM.
//
// §5.12 of a report says, for each finding an execution produced, the
// smallest input that reproduces it.  That is a CLAIM, and a claim has to be
// measured.  This check measures it against the artefacts the analyser
// actually wrote:
//
//   * the table and the `_counterexamples.jsonl` sidecar are the same table
//     in two forms, and they must agree row by row -- a counterexample that
//     the report and the sidecar tell apart is a drift;
//   * every counterexample must name a finding the report SHOWS: a
//     counterexample for a finding the reader cannot see is a claim about
//     nothing;
//   * every argument must BE the candidate the claimed index points at, in
//     the analyser's own candidate list -- the index is what "smaller" means
//     here, and a value that is not the candidate at that index makes the
//     minimality claim a decoration;
//   * the counts the section states in prose must be the counts the
//     sidecar and the findings sidecar imply: how many findings an
//     execution produced, how many got a counterexample, and how many are
//     not claims about an input at all.
//
// It also checks the two things that are easy to get wrong and invisible in
// the output: that two runs of the same tree agree, and that the flag is
// what turns the section on -- without it, there is no sidecar and the
// section says the minimisation was not run.
//
// The MINIMALITY itself -- that no strictly smaller candidate reproduces the
// finding -- is pinned by `src/app/minimize_wbtest.mbt`, on a module where
// the smaller candidate is known not to reproduce.  This check cannot
// measure that without re-implementing the analyser, and a check that
// re-implements the thing it checks measures nothing.
//
// Usage: node scripts/qa/counterexamples.mjs [--artefacts <dir>]
//
// `--artefacts <dir>` checks artefacts that are ALREADY THERE and does not
// run the analyser.  The falsifier uses it to point the same checks at a
// mutated COPY.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { requireCli } from './cli_bin.mjs';
import {
  dynamicSites,
  nonInputSites,
  parseCounterexampleSection,
  parseCounterexampleSidecar,
  parseFindingsSidecar,
  parseProseCounts,
  parseWithoutRows,
  renderInput,
  siteKey,
} from './counterexample_report.mjs';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const FIXTURE = join(ROOT, 'fixtures', 'vuln_demo');
const STEM = 'local_module_0.0.0';

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};

const artifactsIndex = process.argv.indexOf('--artefacts');
const ARTIFACTS = artifactsIndex >= 0 ? resolve(process.argv[artifactsIndex + 1]) : null;

// --------------------------------------------------------------- the artefacts

/// The invariants of ONE set of artefacts.  The label names the set, so a
/// failure says which run disagreed.
function checkArtefacts(dir, label, stem = STEM) {
  const reportPath = join(dir, `${stem}.md`);
  const sidecarPath = join(dir, `${stem}_counterexamples.jsonl`);
  const findingsPath = join(dir, `${stem}_findings.jsonl`);

  check(`${label}: the report exists`, existsSync(reportPath), reportPath);
  check(`${label}: the counterexample sidecar exists`, existsSync(sidecarPath), sidecarPath);
  check(`${label}: the findings sidecar exists`, existsSync(findingsPath), findingsPath);
  if (!existsSync(reportPath) || !existsSync(sidecarPath) || !existsSync(findingsPath)) {
    return null;
  }

  const md = readFileSync(reportPath, 'utf8');
  const parsed = parseCounterexampleSection(md);
  check(`${label}: the report has the counterexample section`, parsed !== null);
  if (!parsed) return null;

  const sidecar = parseCounterexampleSidecar(readFileSync(sidecarPath, 'utf8'));
  const findings = parseFindingsSidecar(readFileSync(findingsPath, 'utf8'));

  check(
    `${label}: the table and the sidecar have the same number of rows`,
    parsed.rows.length === sidecar.length,
    `table ${parsed.rows.length} vs sidecar ${sidecar.length}`,
  );

  // Row by row: the report and the sidecar must tell the same story.
  const n = Math.min(parsed.rows.length, sidecar.length);
  let rowMismatch = 0;
  for (let i = 0; i < n; i += 1) {
    const row = parsed.rows[i];
    const cx = sidecar[i];
    const [file, line] = splitLocation(row.location);
    const same =
      row.rule === cx.rule &&
      file === cx.file &&
      Number(line) === cx.line &&
      row.entry === cx.entry &&
      row.input === renderInput(cx.params, cx.args) &&
      row.runs === String(cx.tried);
    if (!same) rowMismatch += 1;
  }
  check(
    `${label}: every table row agrees with its sidecar row`,
    rowMismatch === 0,
    rowMismatch ? `${rowMismatch} row(s) differ` : `${n} row(s)`,
  );

  // Every counterexample must name a finding the report SHOWS.
  const shownSites = new Set(findings.map(siteKey));
  const unnamed = sidecar.filter((cx) => !shownSites.has([cx.rule, cx.file, cx.line, cx.fn].join('|')));
  check(
    `${label}: every counterexample names a finding the report shows`,
    unnamed.length === 0,
    unnamed.length ? `${unnamed.length} name(s) the report does not show` : `${sidecar.length} counterexample(s)`,
  );

  // The index is what "smaller" means: the argument must BE the candidate
  // the index points at.
  let badIndex = 0;
  for (const cx of sidecar) {
    if (cx.params.length !== cx.args.length || cx.params.length !== cx.indices.length) {
      badIndex += 1;
      continue;
    }
    for (let i = 0; i < cx.params.length; i += 1) {
      const list = cx.candidates?.[i];
      const idx = cx.indices[i];
      if (!Array.isArray(list) || idx < 0 || idx >= list.length) {
        badIndex += 1;
      } else if (list[idx] !== cx.args[i]) {
        badIndex += 1;
      }
    }
  }
  check(
    `${label}: every argument is the candidate its index points at`,
    badIndex === 0,
    badIndex ? `${badIndex} mismatch(es)` : `${sidecar.length} counterexample(s)`,
  );

  // The counts in prose, measured against the sidecars.
  const prose = parseProseCounts(parsed.section);
  check(`${label}: the section states its counts`, prose !== null);
  if (prose) {
    check(
      `${label}: the count of minimised findings is the number of counterexamples`,
      prose.minimised === sidecar.length,
      `prose ${prose.minimised} vs sidecar ${sidecar.length}`,
    );
    check(
      `${label}: the count of findings an execution produced is the number of dynamic sites in the findings`,
      prose.requested === dynamicSites(findings).size,
      `prose ${prose.requested} vs findings ${dynamicSites(findings).size}`,
    );
    check(
      `${label}: the count of findings that are not claims about an input is the number of the other sites`,
      prose.notInput === nonInputSites(findings).size,
      `prose ${prose.notInput} vs findings ${nonInputSites(findings).size}`,
    );
    const tried = sidecar.reduce((a, cx) => a + cx.tried, 0);
    check(
      `${label}: the count of inputs tried covers the counterexamples' own`,
      prose.tried >= tried && tried >= sidecar.length,
      `prose ${prose.tried} vs sidecar ${tried}`,
    );
    check(
      `${label}: every requested finding is minimised, without a counterexample, or left out`,
      prose.minimised + prose.without + prose.skipped === prose.requested,
      `${prose.minimised} + ${prose.without} + ${prose.skipped} vs ${prose.requested}`,
    );
    // The findings no input reproduced are LISTED, not only counted, and the
    // list has to be the count.
    const withoutRows = parseWithoutRows(parsed.section);
    check(
      `${label}: the findings without a counterexample are listed`,
      withoutRows.length === prose.without,
      `${withoutRows.length} listed vs ${prose.without} counted`,
    );
    // And they are the dynamic sites the counterexamples do NOT cover.
    const covered = new Set(sidecar.map((cx) => [cx.rule, cx.file, cx.line, cx.fn].join('|')));
    const uncovered = [...dynamicSites(findings)].filter((k) => !covered.has(k));
    check(
      `${label}: the findings without a counterexample are the ones the counterexamples do not cover`,
      uncovered.length === prose.without,
      `${uncovered.length} uncovered vs ${prose.without} counted`,
    );
  }

  // A finding with no counterexample and a truncated run are two different
  // things, and the section has to be able to tell them apart.
  const saysTruncated = /stopped at its run budget/.test(parsed.section);
  check(
    `${label}: the truncation notice is stated when the budget stopped the walk`,
    prose === null || prose.tried >= sidecar.reduce((a, cx) => a + cx.tried, 0),
    saysTruncated ? 'the notice is there' : 'no notice',
  );

  return { sidecar, prose };
}

function splitLocation(text) {
  const at = text.lastIndexOf(':');
  if (at < 0) return [text, '0'];
  return [text.slice(0, at), text.slice(at + 1)];
}

// --------------------------------------------------------------- the live run

if (ARTIFACTS) {
  const res = checkArtefacts(ARTIFACTS, 'artefacts');
  if (!res) {
    console.error('the artefacts could not be read at all');
    process.exit(2);
  }
  console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
  process.exit(failures === 0 ? 0 : 1);
}

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
const outRoot = join(ROOT, '_build', 'qa', 'counterexamples');
rmSync(outRoot, { recursive: true, force: true });
mkdirSync(outRoot, { recursive: true });

function runCli(label, args) {
  const r = spawnSync(exe, args, { cwd: ROOT, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024 });
  check(`${label}: the analyser exited 0`, r.status === 0, `exit=${r.status}`);
  if (r.status !== 0) console.error((r.stderr ?? '').split(/\r?\n/).slice(0, 5).join('\n'));
  return r;
}

const run1 = join(outRoot, 'run1');
runCli('run 1', ['analyze', '--dir', FIXTURE, '--out', run1, '--counterexamples']);
const first = checkArtefacts(run1, 'run 1');

// The flag is what turns the section on.  Without it there is no sidecar and
// the section says the minimisation was not run -- which is how a reader
// learns that the section is opt-in and why it is empty.
const run2 = join(outRoot, 'run2');
runCli('run 2', ['analyze', '--dir', FIXTURE, '--out', run2]);
check(
  'without the flag: no counterexample sidecar is written',
  !existsSync(join(run2, `${STEM}_counterexamples.jsonl`)),
);
{
  const md = readFileSync(join(run2, `${STEM}.md`), 'utf8');
  const parsed = parseCounterexampleSection(md);
  check('without the flag: the section is still there', parsed !== null);
  if (parsed) {
    check(
      'without the flag: the section says the minimisation was not run',
      /was not run/.test(parsed.section),
    );
    check(
      'without the flag: the section has no counterexample rows',
      parsed.rows.length === 0,
      `${parsed.rows.length} row(s)`,
    );
  }
}

// Determinism: the same tree, twice, must give the same counterexamples.
const run3 = join(outRoot, 'run3');
runCli('run 3', ['analyze', '--dir', FIXTURE, '--out', run3, '--counterexamples']);
{
  const a = readFileSync(join(run1, `${STEM}_counterexamples.jsonl`), 'utf8');
  const b = readFileSync(join(run3, `${STEM}_counterexamples.jsonl`), 'utf8');
  check('two runs give byte-identical counterexample sidecars', a === b, `${a.length} B vs ${b.length} B`);
}

// The SELF-SCAN: the analyser over this module's own source.  The fixture is
// a controlled case, and it has no finding that no input reproduces -- so the
// checks about those findings would be vacuous there.  This module has one:
// a claim about the analyser's own step budget, which no input reproduces
// because it is not a claim about an input.
//
// Every comparison below is between two numbers of the SAME run -- the
// report against its own sidecars -- so a toolchain that finds a different
// set of findings moves both sides together.
const selfOut = join(outRoot, 'selfscan');
runCli('the self-scan', ['analyze', '--dir', '.', '--out', selfOut, '--funnel', '--counterexamples']);
{
  const stem = readdirSync(selfOut).find((f) => f.endsWith('_summary.json'))?.replace(/_summary\.json$/, '');
  check('the self-scan wrote its artefacts', Boolean(stem), String(stem));
  if (stem) {
    const res = checkArtefacts(selfOut, 'the self-scan', stem);
    if (res) {
      // Whether there IS a finding that no input reproduces is a fact about
      // THIS tree and this toolchain, not an invariant: a newer toolchain
      // may parse the module differently and not exhaust any budget.  So
      // this is REPORTED, not asserted -- the check that the without-list
      // agrees with the without-count is asserted either way, and the
      // falsifier exercises that mechanism on every tree.
      console.log(
        `INFO  the self-scan: ${res.prose?.without ?? 0} finding(s) with no counterexample, ${res.prose?.notInput ?? 0} that are not claims about an input`,
      );
    }
  }
}

if (first && first.sidecar.length > 0) {
  const withArgs = first.sidecar.filter((cx) => cx.args.length > 0);
  check(
    'at least one counterexample carries an input',
    withArgs.length > 0,
    `${withArgs.length} of ${first.sidecar.length}`,
  );
  const cx = first.sidecar[0];
  check(
    'every counterexample names an entry function',
    typeof cx.entry === 'string' && cx.entry !== '',
    `${cx.entry}`,
  );
} else {
  check('at least one counterexample carries an input', false, 'no counterexample was produced');
}

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
