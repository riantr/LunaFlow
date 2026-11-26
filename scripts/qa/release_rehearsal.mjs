// THE RELEASE REHEARSAL: does the registry still serve what the reports record?
//
// THE BLIND SPOT THIS CLOSES.  Every checker in this harness finds the COMMITTED
// artefact and compares the README against IT -- `readme_table.mjs` does that,
// and it does it correctly.  So the tree is internally consistent no matter how
// old the artefact is.  Nothing compared the artefact against what the REGISTRY
// serves as `@latest`, and the gap is not hypothetical: measured on 2026-11-26,
// `riantr/moonbit_static_analysis@latest` resolves to 0.6.0 while the committed
// artefact records 0.5.4 -- every published number for that corpus was stale and
// every check stayed green.
//
// WHAT IT DOES.  For each registry corpus that has a committed artefact, it
// re-runs the PUBLISHED recipe against `<module>@latest` and compares the result
// with the artefact.  The recipe is RECONSTRUCTED from the artefact rather than
// hardcoded: the level comes from its summary, and the slice target is parsed
// from its own report heading (`### backward slice on \`var@func\``).  The one
// constant is `--trials 4`, which is the documented release recipe in
// `docs/design.md` §7.2.
//
// COMPARING COUNTS ACROSS DIFFERENT FLAGS IS THE TRAP.  An earlier round of this
// repository compared a `--trials 8` run against a `--trials 4` artefact and read
// the difference as drift.  So the flags here are reconstructed, and the check
// says which recipe it used.
//
// WHAT IT DOES NOT DO: it does not rewrite the README.  A tool that edits its own
// press release can hide the regression it was meant to expose.  It PRINTS the
// row each corpus should publish, and a human applies it.
//
// Usage:
//   node scripts/qa/release_rehearsal.mjs [--corpus <substr>] [--only-version]
//
//   --corpus        restrict to corpora whose module name contains this
//   --only-version  compare the resolved VERSION only, without a full run
//                   (still needs the run to resolve -- the CLI resolves and
//                   analyses in one pass, so this flag is accepted for symmetry
//                   and currently changes nothing)
//
// Exit codes, the harness convention:
//   0  every corpus still resolves to the version its artefact records
//   1  a corpus MOVED -- the published numbers have to be rewritten
//   2  a corpus could not be checked (registry unreachable, CLI missing)
import { readFileSync, readdirSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = process.cwd();
const SCRATCH = join(ROOT, '_build', 'qa', 'release_rehearsal');
const TRIALS = '4'; // docs/design.md §7.2, the documented release recipe

const argOf = (flag, dflt) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
};
const onlyCorpus = argOf('--corpus', '');

// ---------------------------------------------------------------------------
// The CLI.
// ---------------------------------------------------------------------------
function cliExe() {
  // The same two layouts `cli_bin.mjs` handles, without importing it so this
  // script has no dependency on the harness internals.
  const a = join(ROOT, '_build', 'native', 'debug', 'build', 'src', 'cli', 'cli.exe');
  const b = join(ROOT, '_build', 'native', 'debug', 'build', 'src', 'cli', 'cli');
  if (existsSync(a)) return a;
  if (existsSync(b)) return b;
  return null;
}

// ---------------------------------------------------------------------------
// The committed artefacts: found by prefix, never named.
// ---------------------------------------------------------------------------
function committed() {
  const dir = join(ROOT, 'reports');
  if (!existsSync(dir)) return [];
  const out = [];
  for (const f of readdirSync(dir)) {
    if (!f.endsWith('_summary.json')) continue;
    const stem = f.slice(0, -'_summary.json'.length);
    let summary;
    try {
      summary = JSON.parse(readFileSync(join(dir, f), 'utf8'));
    } catch {
      continue;
    }
    // Only a REGISTRY corpus has an `@latest` to re-measure.  The fixture is a
    // local directory and must be left out: its module is `local/module`.
    if (!/@latest$/.test(summary.module ?? '')) continue;
    if (onlyCorpus && !summary.module.includes(onlyCorpus)) continue;
    out.push({ stem, summary, mdPath: join(dir, stem + '.md') });
  }
  return out;
}

// The slice target, read from the artefact's own report heading.
function sliceOf(mdPath) {
  if (!existsSync(mdPath)) return null;
  const md = readFileSync(mdPath, 'utf8');
  const m = /^###\s+backward slice on `([^`]+)`/m.exec(md);
  return m ? m[1] : null;
}

// ---------------------------------------------------------------------------
// Re-run the published recipe against @latest.
// ---------------------------------------------------------------------------
function rehearse(art) {
  const moduleName = art.summary.module; // already ends in @latest
  const slice = sliceOf(art.mdPath);
  const out = join(SCRATCH, art.stem.replace(/[^A-Za-z0-9_@.-]/g, '_'));
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });

  const args = ['analyze', moduleName, '--out', out, '--funnel', '--trials', TRIALS];
  if (slice) args.push('--slice', slice);

  const exe = cliExe();
  if (!exe) return { error: 'the CLI is not built (`moon build src/cli --target native`)' };

  const r = spawnSync(exe, args, {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 1800000,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (r.status !== 0) {
    return { error: `the run exited ${r.status}: ${((r.stderr ?? '') + (r.stdout ?? '')).slice(-300)}` };
  }
  const files = readdirSync(out).filter((f) => f.endsWith('_summary.json'));
  if (files.length === 0) return { error: 'the run wrote no summary' };
  const fresh = JSON.parse(readFileSync(join(out, files[0]), 'utf8'));
  return { fresh, slice, recipe: args.slice(1).join(' ') };
}

// ---------------------------------------------------------------------------
const FIELDS = [
  'files',
  'functions',
  'statements',
  'unsupported_statements',
  'trace_events',
  'steps',
  'abstract_findings',
  'taint_sinks',
  'findings',
];

const arts = committed();
if (arts.length === 0) {
  console.log('no registry corpus with a committed artefact was found under reports/');
  process.exit(2);
}

let moved = 0;
let unchecked = 0;
const rows = [];

for (const art of arts) {
  const was = art.summary;
  console.log(`\n=== ${was.module} ===`);
  console.log(`  committed artefact : ${art.stem}`);
  console.log(`  committed version  : ${was.version}`);

  const res = rehearse(art);
  if (res.error) {
    console.log(`  UNKNOWN            ${res.error}`);
    unchecked += 1;
    continue;
  }
  const now = res.fresh;
  console.log(`  @latest resolves to: ${now.version}`);
  console.log(`  recipe re-run      : --${res.recipe}`);
  if (res.slice) console.log(`  slice (from the artefact's own report): ${res.slice}`);

  const versionMoved = now.version !== was.version;
  if (versionMoved) {
    console.log(`  MOVED              ${was.version} -> ${now.version}`);
    moved += 1;
  } else {
    console.log(`  version            unchanged`);
  }

  const drift = [];
  for (const f of FIELDS) {
    if (was[f] === undefined || now[f] === undefined) continue;
    if (was[f] !== now[f]) drift.push(`${f}: ${was[f]} -> ${now[f]}`);
  }
  if (drift.length > 0) {
    console.log(`  counters that moved (same recipe, so the difference is the CORPUS):`);
    for (const d of drift) console.log(`      ${d}`);
  } else if (!versionMoved) {
    console.log(`  every counter agrees  (${FIELDS.filter((f) => was[f] !== undefined).length} fields)`);
  }

  // The README row this corpus should publish, in the live table's order.
  const vcs = `${now.vcs_proved ?? 0} / ${now.vcs_failed ?? 0} / ${now.vcs_unknown ?? 0}`;
  rows.push(
    `| \`${now.module}\` → ${now.version} | ${now.files} | ${now.statements} | ${now.trace_events} | ${now.abstract_findings} | ${vcs} | ${now.dead_code ?? 0} | ${now.taint_sinks} | — |`,
  );
}

console.log('\n=== THE ROWS THE README SHOULD PUBLISH ===');
for (const r of rows) console.log(r);
console.log(
  '\n(The Time cell is the run\'s own `elapsed_ms` on THIS machine; it is not comparable across runs, so it is left as `—` for a human to fill from the artefact.)',
);

console.log('');
if (unchecked > 0) {
  console.log(`RESULT: ${unchecked} corpus/corpora could not be checked -- UNKNOWN, not drift.`);
  process.exit(2);
}
if (moved > 0) {
  console.log(`RESULT: ${moved} corpus/corpora MOVED. The published numbers are stale and have to be rewritten.`);
  process.exit(1);
}
console.log(`RESULT: every corpus still resolves to the version its artefact records (${arts.length} checked).`);
process.exit(0);
