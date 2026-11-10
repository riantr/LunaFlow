#!/usr/bin/env node
// Dependency-free Gherkin runner for features/*.feature.
//
// Only the subset the acceptance scenarios need is implemented: Feature,
// Scenario and Given/When/Then/And/But lines, executed in order against a small
// step table. Unknown steps fail loudly instead of being skipped, so the feature
// files cannot silently drift away from the code.
//
// Usage: node scripts/qa/gherkin.mjs [features-dir]
import { spawnSync } from 'node:child_process';
import {
  readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync, rmSync, statSync,
} from 'node:fs';
import { join, relative } from 'node:path';
import { resolveCli } from './cli_bin.mjs';

const root = process.cwd();
const featuresDir = join(root, process.argv[2] ?? 'features');
const exe = resolveCli(root);
const work = join(root, '_build', 'qa', 'gherkin');

const CLI = (args, cwd = root) =>
  spawnSync(exe, args, { cwd, encoding: 'utf8', timeout: 180000, maxBuffer: 64 * 1024 * 1024 });

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const walk = (dir, out = []) => {
  if (!existsSync(dir)) return out;
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
};
const mermaidBlocks = (md) => [...md.matchAll(/```mermaid\n([\s\S]*?)```/g)].map((m) => m[1]);

function freshDir(p) {
  if (existsSync(p)) rmSync(p, { recursive: true, force: true });
  mkdirSync(p, { recursive: true });
  return p;
}

function writeModule(dir, { manifest, source }) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'moon.mod'), manifest);
  writeFileSync(join(dir, 'lib.mbt'), source);
}

const FIXTURE_STEM = 'local_module_0.0.0';

// ------------------------------------------------------------- step table ---
const steps = [
  // Given
  [/^the built CLI binary$/, (ctx) => {
    if (!existsSync(exe)) return { ok: false, detail: `missing ${exe}` };
    ctx.cli = exe;
    return { ok: true };
  }],
  [/^the project working tree$/, () => ({ ok: true })],

  // When
  [/^I analyze the demo fixture with the funnel and a slice$/, (ctx) => {
    const dir = freshDir(join(work, 'fixture'));
    const r = CLI(['analyze', '--dir', 'fixtures/vuln_demo', '--out', dir, '--funnel', '--slice', 'i@copy_prefix']);
    ctx.run = r;
    ctx.summaryPath = join(dir, `${FIXTURE_STEM}_summary.json`);
    ctx.mdPath = join(dir, `${FIXTURE_STEM}.md`);
    ctx.mdDir = dir;
    return { ok: true, detail: `exit=${r.status}` };
  }],
  [/^I analyze the demo fixture twice into the same directory$/, (ctx) => {
    const dir = freshDir(join(work, 'determinism'));
    const args = ['analyze', '--dir', 'fixtures/vuln_demo', '--out', dir, '--funnel', '--slice', 'i@copy_prefix'];
    CLI(args);
    const s1 = readFileSync(join(dir, `${FIXTURE_STEM}_summary.json`), 'utf8');
    const t1 = readFileSync(join(dir, `${FIXTURE_STEM}_trace.jsonl`), 'utf8');
    CLI(args);
    ctx.summaryA = s1;
    ctx.summaryB = readFileSync(join(dir, `${FIXTURE_STEM}_summary.json`), 'utf8');
    ctx.traceA = t1;
    ctx.traceB = readFileSync(join(dir, `${FIXTURE_STEM}_trace.jsonl`), 'utf8');
    return { ok: true };
  }],
  [/^I analyze a module with (\d+) nested if statements$/, (ctx, m) => {
    const depth = Number(m[1]);
    const dir = freshDir(join(work, 'nest'));
    writeModule(join(dir, 'mod'), {
      manifest: 'name = "gherkin/nest"\nversion = "0.1.0"\n',
      source: 'pub fn f(x : Int) -> Int {\n' + 'if x > 0 { '.repeat(depth) + 'x' + ' }'.repeat(depth) + '\n}\n',
    });
    const r = CLI(['analyze', '--dir', 'mod', '--out', 'out'], join(dir, 'mod', '..'));
    ctx.run = r;
    ctx.mdPath = join(dir, 'out', 'gherkin_nest_0.1.0.md');
    ctx.summaryPath = join(dir, 'out', 'gherkin_nest_0.1.0_summary.json');
    return { ok: true, detail: `exit=${r.status}` };
  }],
  [/^I analyze a module whose version field tries to escape the output directory$/, (ctx) => {
    const dir = freshDir(join(work, 'escape'));
    const caseDir = join(dir, 'work');
    writeModule(join(caseDir, 'mod'), {
      manifest: 'name = "gherkin/escape"\nversion = "..\\\\..\\\\..\\\\..\\\\escaped"\n',
      source: 'pub fn f(x : Int) -> Int {\n  x\n}\n',
    });
    const r = CLI(['analyze', '--dir', 'mod', '--out', 'out'], caseDir);
    ctx.run = r;
    ctx.strays = walk(dir)
      .filter((p) => /\.(md|json|jsonl)$/.test(p))
      .map((p) => relative(caseDir, p).replace(/\\/g, '/'))
      .filter((p) => !p.startsWith('out/'));
    return { ok: true, detail: `exit=${r.status}` };
  }],
  [/^I pass --out with no value$/, (ctx) => {
    const dir = freshDir(join(work, 'outfallback'));
    writeModule(join(dir, 'mod'), {
      manifest: 'name = "gherkin/outfallback"\nversion = "0.1.0"\n',
      source: 'pub fn f(x : Int) -> Int {\n  x\n}\n',
    });
    const r = CLI(['analyze', '--dir', 'mod', '--out'], dir);
    ctx.run = r;
    ctx.cwdRootArtifacts = readdirSync(dir).filter((n) => /\.(md|jsonl)$/.test(n));
    ctx.defaultDirArtifacts = existsSync(join(dir, 'reports'))
      ? readdirSync(join(dir, 'reports')).filter((n) => /\.(md|jsonl)$/.test(n))
      : [];
    return { ok: true, detail: `exit=${r.status}` };
  }],

  // Then
  [/^the run exits successfully$/, (ctx) => ({
    ok: ctx.run && ctx.run.status === 0,
    detail: `exit=${ctx.run ? ctx.run.status : 'n/a'}`,
  })],
  [/^the summary reports (\d+) dead code findings$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return { ok: s.dead_code === Number(m[1]), detail: `dead_code=${s.dead_code}` };
  }],
  [/^the summary reports (\d+) unreachable statement$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return { ok: s.unreachable === Number(m[1]), detail: `unreachable=${s.unreachable}` };
  }],
  [/^the summary reports at least (\d+) infinite loop$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return { ok: s.infinite_loop >= Number(m[1]), detail: `infinite_loop=${s.infinite_loop}` };
  }],
  [/^the summary reports at least (\d+) taint sink$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return { ok: s.taint_sinks >= Number(m[1]), detail: `taint_sinks=${s.taint_sinks}` };
  }],
  [/^the summary reports at least (\d+) abstract finding$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return { ok: s.abstract_findings >= Number(m[1]), detail: `abstract_findings=${s.abstract_findings}` };
  }],
  [/^at least (\d+) contract is proved and at least (\d+) fails$/, (ctx, m) => {
    const s = readJson(ctx.summaryPath);
    return {
      ok: s.vcs_proved >= Number(m[1]) && s.vcs_failed >= Number(m[2]),
      detail: `proved=${s.vcs_proved} failed=${s.vcs_failed} unknown=${s.vcs_unknown}`,
    };
  }],
  [/^the report has all ten sections$/, (ctx) => {
    const md = readFileSync(ctx.mdPath, 'utf8');
    const missing = ['## 1.', '## 2.', '## 3.', '## 4.', '## 5.', '## 6.', '## 7.', '## 8.', '## 9.', '## 10.']
      .filter((h) => !md.includes(h));
    return { ok: missing.length === 0, detail: missing.length ? `missing ${missing.join(',')}` : '10/10' };
  }],
  [/^the report contains a funnel diagram$/, (ctx) => {
    const md = readFileSync(ctx.mdPath, 'utf8');
    // full heading, because '## 3.' is a substring of the '### 3.2' subheading
    const sec = md.split('## 3. Proof-strength levels and funnel')[1]?.split('## 4.')[0] ?? '';
    return { ok: /flowchart LR/.test(sec), detail: `section ${sec.length} chars` };
  }],
  [/^the report contains a valid slice diagram$/, (ctx) => {
    const md = readFileSync(ctx.mdPath, 'utf8');
    const sec = md.split('## 7. Program slicing')[1] ?? '';
    const nodes = (sec.match(/^\s+s\d+\[/gm) ?? []).length;
    const blocks = mermaidBlocks(sec).length;
    return { ok: nodes >= 1 && blocks >= 1, detail: `${blocks} block(s), ${nodes} node(s)` };
  }],
  [/^the report stays under (\d+) KB$/, (ctx, m) => {
    const size = statSync(ctx.mdPath).size;
    return { ok: size <= Number(m[1]) * 1024, detail: `${size} B` };
  }],
  [/^the two summaries are identical except the elapsed time$/, (ctx) => {
    const strip = (s) => {
      const { elapsed_ms, ...rest } = JSON.parse(s);
      return JSON.stringify(rest, Object.keys(rest).sort());
    };
    return {
      ok: strip(ctx.summaryA) === strip(ctx.summaryB),
      detail: `elapsed ${JSON.parse(ctx.summaryA).elapsed_ms} vs ${JSON.parse(ctx.summaryB).elapsed_ms} ms`,
    };
  }],
  [/^the two traces are byte identical$/, (ctx) => ({
    ok: ctx.traceA === ctx.traceB,
    detail: `${ctx.traceA.length} B`,
  })],
  [/^the report records a parse gap$/, (ctx) => {
    const md = readFileSync(ctx.mdPath, 'utf8');
    const m = md.match(/\| Parse issues \| (\d+) \|/);
    const n = m ? Number(m[1]) : 0;
    return { ok: n >= 1, detail: `parse issues=${n}` };
  }],
  [/^the summary does not claim the skipped region as understood code$/, (ctx) => {
    const s = readJson(ctx.summaryPath);
    const total = s.statements + s.unsupported_statements;
    return {
      ok: s.unsupported_statements >= 1 && s.statements < 600,
      detail: `statements=${s.statements} unsupported=${s.unsupported_statements} total=${total}`,
    };
  }],
  [/^no artifact is written outside the output directory$/, (ctx) => ({
    ok: ctx.strays.length === 0,
    detail: ctx.strays.length ? ctx.strays.join(', ') : 'none',
  })],
  [/^no artifact is written into the working directory$/, (ctx) => ({
    ok: ctx.cwdRootArtifacts.length === 0,
    detail: `root=${ctx.cwdRootArtifacts.length} reports/=${ctx.defaultDirArtifacts.length}`,
  })],
  [/^the source tree is canonically formatted$/, () => {
    const r = spawnSync('moon fmt --check', { cwd: root, encoding: 'utf8', shell: true, timeout: 300000 });
    return { ok: r.status === 0, detail: `exit=${r.status}` };
  }],
  [/^the unit suite passes$/, () => {
    const r = spawnSync('moon test src/app --target native', { cwd: root, encoding: 'utf8', shell: true, timeout: 900000, maxBuffer: 64 * 1024 * 1024 });
    const text = (r.stdout ?? '') + (r.stderr ?? '');
    const m = text.match(/Total tests: (\d+), passed: (\d+), failed: (\d+)/);
    return {
      ok: r.status === 0 && m !== null && m[3] === '0',
      detail: m ? `${m[2]}/${m[1]} passed` : `exit=${r.status}`,
    };
  }],
  [/^the acceptance verifier passes$/, () => {
    const r = spawnSync('node scripts/verify.mjs', { cwd: root, encoding: 'utf8', shell: true, timeout: 300000 });
    const text = (r.stdout ?? '') + (r.stderr ?? '');
    const m = text.match(/RESULT: (\d+)\/(\d+) checks passed/);
    return { ok: r.status === 0 && m !== null, detail: m ? m[0] : `exit=${r.status}` };
  }],
];

// ------------------------------------------------------------------ runner ---
function parseFeature(path) {
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  const scenarios = [];
  let current = null;
  for (const line of lines) {
    const t = line.trim();
    const sc = t.match(/^Scenario:\s*(.+)$/);
    if (sc) {
      current = { name: sc[1], steps: [] };
      scenarios.push(current);
      continue;
    }
    const st = t.match(/^(Given|When|Then|And|But)\s+(.+)$/);
    if (st && current) current.steps.push({ keyword: st[1], text: st[2] });
  }
  return scenarios;
}

mkdirSync(work, { recursive: true });
const files = readdirSync(featuresDir).filter((f) => f.endsWith('.feature')).sort();
let total = 0;
let failures = 0;

for (const file of files) {
  console.log(`\n# ${file}`);
  for (const scenario of parseFeature(join(featuresDir, file))) {
    total += 1;
    const ctx = {};
    const problems = [];
    for (const step of scenario.steps) {
      const hit = steps.find(([re]) => re.test(step.text));
      if (!hit) {
        problems.push(`undefined step: ${step.keyword} ${step.text}`);
        continue;
      }
      const m = step.text.match(hit[0]);
      const res = hit[1](ctx, m) ?? { ok: true };
      if (!res.ok) problems.push(`${step.keyword} ${step.text}${res.detail ? ` — ${res.detail}` : ''}`);
      if (process.env.GHERKIN_VERBOSE) {
        console.log(`    ${res.ok ? 'ok  ' : 'FAIL'} ${step.keyword} ${step.text}${res.detail ? ` — ${res.detail}` : ''}`);
      }
    }
    if (problems.length) {
      failures += 1;
      console.log(`FAIL  ${scenario.name}`);
      for (const p of problems) console.log(`        ${p}`);
    } else {
      console.log(`PASS  ${scenario.name}`);
    }
  }
}

console.log(`\nRESULT: ${total - failures}/${total} scenarios passed, ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
