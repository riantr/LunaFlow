#!/usr/bin/env node
// The IFDS SPIKE harness.
//
// It runs the spike's white-box driver over a module tree, parses what the
// driver measured, and turns it into the four measurements of
// `docs/qa/IFDS_SPIKE.md`:
//
//   M1  NO LOST SINK. Every taint site the L2 found is also a site the
//       spike with the blanket rule found. A site the L2 has and the spike
//       does not is a sink the flow-sensitive fixpoint LOST, and that is
//       the one failure this harness exists to catch.
//
//   M2  THE RULE'S CONTRIBUTION. Every site the plain spike found is also
//       a site the spike with the blanket rule found -- the rule only
//       ADDS taint -- and every site the rule added carries the rule's own
//       source (`rule:loop`), so the difference between the two modes is
//       explained mechanically rather than asserted.
//
//   M3  THE MODEL'S COVERAGE. The statements the parser could not model are
//       counted, and the spike's gap count has to be exactly that count: a
//       spike that gave up on a statement the L2 understands would be
//       comparing two different modules.
//
//   M4  THE SCALE. The time, the facts and the worklist steps of a run
//       over the corpus.
//
// The harness is FALSIFIABLE: `--falsify` breaks each check on purpose and
// asserts that the check then fails. A check that cannot fail is not a
// check.
//
// Usage:
//   node scripts/qa/ifds_spike.mjs [--corpus <dir>] [--label <name>]
//                                [--falsify] [--json <file>]
import { spawnSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = process.cwd();
const argOf = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i === -1 ? fallback : process.argv[i + 1];
};
const corpus = argOf('--corpus', 'fixtures');
const label = argOf('--label', 'fixtures');
const jsonOut = argOf('--json', join('_build', 'qa', 'ifds_spike', `${label}.json`));
const falsify = process.argv.includes('--falsify');

let failures = 0;
const fail = (msg) => { failures++; console.log(`FAIL  ${msg}`); };
const pass = (msg) => console.log(`PASS  ${msg}`);

// --- 1. run the driver -------------------------------------------------------
const env = { ...process.env, LUNAFLOW_IFDS_SPIKE_MODULE: corpus };
const run = spawnSync(
  'moon',
  ['test', 'src/app', '--target', 'native', '-f', 'ifds_spike*'],
  { cwd: root, encoding: 'utf8', env, timeout: 900000, maxBuffer: 64 * 1024 * 1024 },
);
const output = `${run.stdout ?? ''}\n${run.stderr ?? ''}`;

const lines = output.split(/\r?\n/).filter((l) => l.startsWith('IFDS_SPIKE_'));
if (run.status !== 0) {
  fail(`the spike's driver exited with code ${run.status}`);
  for (const l of output.split(/\r?\n/).filter((l) => /failed:|Total tests/.test(l)).slice(0, 8)) {
    console.log(`      ${l.trim()}`);
  }
  console.log(`RESULT: ${failures} failure(s)`);
  process.exit(1);
}

const kv = (line) => {
  const out = {};
  for (const part of line.split(/\s+/).slice(1)) {
    const at = part.indexOf('=');
    if (at === -1) continue;
    out[part.slice(0, at)] = part.slice(at + 1);
  }
  return out;
};

const corpusLine = lines.find((l) => l.startsWith('IFDS_SPIKE_CORPUS'));
const l2Line = lines.find((l) => l.startsWith('IFDS_SPIKE_L2'));
const engineLines = lines.filter((l) => l.startsWith('IFDS_SPIKE_ENGINE'));
const timeLines = lines.filter((l) => l.startsWith('IFDS_SPIKE_TIME'));
const kindLines = lines.filter((l) => l.startsWith('IFDS_SPIKE_KIND'));
const siteLines = lines.filter((l) => l.startsWith('IFDS_SPIKE_SITE'));

if (!corpusLine || !l2Line || engineLines.length !== 2) {
  fail('the driver did not print the measurement lines');
  console.log(`      saw ${lines.length} IFDS_SPIKE line(s)`);
  console.log(`RESULT: ${failures} failure(s)`);
  process.exit(1);
}
pass(`the driver ran over '${corpus}' and printed its measurement`);

const corpusInfo = kv(corpusLine);
const l2Info = kv(l2Line);
const engines = {};
for (const l of engineLines) {
  const info = kv(l);
  engines[info.mode] = info;
}
const times = {};
for (const l of timeLines) {
  const info = kv(l);
  times[info.engine] = Number(info.ms);
}
const kinds = {};
for (const l of kindLines) {
  const info = kv(l);
  kinds[info.kind] = Number(info.count);
}

// A site is KIND|FILE|LINE. The three engines report the same site with
// different flags, so the site list is the union of all of them.
const sites = new Map();
for (const l of siteLines) {
  const info = kv(l);
  const key = `${info.kind}|${info.file}|${info.line}`;
  sites.set(key, {
    kind: info.kind,
    file: info.file,
    line: Number(info.line),
    l2: info.l2 === '1',
    plain: info.plain === '1',
    withrule: info.withrule === '1',
    container: info.container ?? 'unknown',
    sources: info.sources ? info.sources.split(',').filter(Boolean) : [],
  });
}
const keys = [...sites.keys()];
const l2Sites = keys.filter((k) => sites.get(k).l2);
const plainSites = keys.filter((k) => sites.get(k).plain);
const withRuleSites = keys.filter((k) => sites.get(k).withrule);

// --- the checks, as functions of the data ------------------------------------
// They take the data as arguments so that the falsification can break the
// data and watch them fail.
const checkM1 = (l2, withRule) => {
  const missing = l2.filter((k) => !withRule.includes(k));
  return { ok: missing.length === 0, missing };
};
const checkM2a = (plain, withRule) => {
  const extra = plain.filter((k) => !withRule.includes(k));
  return { ok: extra.length === 0, extra };
};
const checkM2b = (siteMap, plain, withRule) => {
  const unexplained = withRule
    .filter((k) => !plain.includes(k))
    .filter((k) => !siteMap.get(k).sources.includes('rule:loop'));
  return { ok: unexplained.length === 0, unexplained };
};
const checkM3 = (gaps, histogramUnsupported, parserUnsupported) => {
  const consistent = Number(gaps) === Number(histogramUnsupported);
  const notWorse = Number(gaps) <= Number(parserUnsupported);
  return {
    ok: consistent && notWorse,
    consistent,
    notWorse,
    gaps: Number(gaps),
    histogramUnsupported: Number(histogramUnsupported),
    parserUnsupported: Number(parserUnsupported),
  };
};

const m1 = checkM1(l2Sites, withRuleSites);
const m2a = checkM2a(plainSites, withRuleSites);
const m2b = checkM2b(sites, plainSites, withRuleSites);
const m3 = checkM3(
  engines['with-rule'].gaps,
  kinds.unsupported ?? 0,
  corpusInfo.unsupported,
);

// --- why the spike has sites the L2 does not ---------------------------------
// Every site the spike has and the L2 does not is attributed to a cause,
// so that the difference is COUNTED rather than waved at.
//
//   alloc   -- the site is an allocation size. The L2's allocation rule
//              matches a name the parser never produces, so the L2's
//              allocation family cannot fire at all.
//   dedupe  -- another site of the same kind on the same LINE is one the
//              L2 has. The L2's `add_finding` keys a finding on
//              (kind, line, message) and NOT on the file, so the second
//              file's finding on a line is silently dropped.
//   made    -- the container is the result of an allocation. The L2 does
//              not see such a container as an array, for the same reason
//              as `alloc`.
//   unknown -- the container's type is not known, so the L2's sink filter
//              stops the site.
//   array   -- the container IS an array by type, so the L2 agrees about
//              the container: whatever stopped it is its taint or its
//              length bound.
const causes = new Map();
const l2IndexLines = new Set(
  [...sites.values()]
    .filter((s) => s.l2 && s.kind === 'TAINT-INDEX')
    .map((s) => s.line),
);
for (const key of withRuleSites) {
  if (l2Sites.includes(key)) continue;
  const s = sites.get(key);
  let cause;
  if (s.kind === 'TAINT-ALLOC') cause = 'alloc';
  else if (l2IndexLines.has(s.line)) cause = 'dedupe';
  else if (s.container === 'made') cause = 'made';
  else if (s.container === 'unknown') cause = 'unknown';
  else cause = 'array';
  causes.set(cause, (causes.get(cause) ?? 0) + 1);
}
const causeOf = (k) => causes.get(k) ?? 0;

if (m1.ok) {
  pass(`M1: no lost sink -- all ${l2Sites.length} L2 taint site(s) are also spike sites`);
} else {
  fail(`M1: ${m1.missing.length} L2 taint site(s) the spike did NOT find -- a lost sink:`);
  for (const k of m1.missing) console.log(`      ${k}`);
}
if (m2a.ok) {
  pass(`M2: the plain spike's ${plainSites.length} site(s) are all sites of the spike with the rule`);
} else {
  fail(`M2: ${m2a.extra.length} site(s) the plain spike has and the spike with the rule does not -- the rule only adds taint, so this cannot happen:`);
  for (const k of m2a.extra) console.log(`      ${k}`);
}
if (m2b.ok) {
  const added = withRuleSites.filter((k) => !plainSites.includes(k));
  pass(`M2: all ${added.length} site(s) the blanket rule added carry the rule's own source (rule:loop)`);
} else {
  fail(`M2: ${m2b.unexplained.length} site(s) the blanket rule added are NOT explained by it:`);
  for (const k of m2b.unexplained) console.log(`      ${k}  sources=${sites.get(k).sources.join(',')}`);
}
if (m3.ok) {
  pass(`M3: the spike's ${m3.gaps} gap(s) are the ${m3.histogramUnsupported} unmodelled statement(s) it walked, and no more than the ${m3.parserUnsupported} the parser could not model`);
} else {
  fail(`M3: the spike's gap accounting does not hold -- gaps=${m3.gaps}, histogram=${m3.histogramUnsupported}, parser=${m3.parserUnsupported}`);
}

// --- 2. the falsification ----------------------------------------------------
// Each check is broken on purpose and has to fail. A check that cannot fail
// is not a check, and this harness asserts that these ones can.
if (falsify) {
  // M1 asks "is every L2 site also a spike site?". Taking a site AWAY from
  // the spike's set is what breaks it: the L2 site is then a lost sink.
  const victim = l2Sites.find((k) => withRuleSites.includes(k));
  const brokenWithRule = withRuleSites.filter((k) => k !== victim);
  const b1 = checkM1(l2Sites, brokenWithRule);
  if (!b1.ok && b1.missing.includes(victim)) {
    pass('falsification: M1 fails when a site is taken away from the spike');
  } else {
    fail('falsification: M1 did NOT fail when one of its sites was removed -- the check is vacuous');
  }

  const b2a = checkM2a(plainSites, plainSites.filter((k) => k !== plainSites[0]));
  if (!b2a.ok) {
    pass('falsification: M2a fails when a plain site is removed from the rule set');
  } else {
    fail('falsification: M2a did NOT fail when a site was removed -- the check is vacuous');
  }

  const brokenSources = new Map(sites);
  const ruleSite = withRuleSites.find((k) => !plainSites.includes(k));
  if (ruleSite) {
    brokenSources.set(ruleSite, { ...sites.get(ruleSite), sources: ['param:x'] });
    const b2b = checkM2b(brokenSources, plainSites, withRuleSites);
    if (!b2b.ok && b2b.unexplained.includes(ruleSite)) {
      pass('falsification: M2b fails when a rule site loses the rule source');
    } else {
      fail('falsification: M2b did NOT fail when the rule source was taken away -- the check is vacuous');
    }
  } else {
    pass('falsification: M2b -- no rule site to break, nothing to falsify');
  }

  const b3 = checkM3(999, kinds.unsupported ?? 0, corpusInfo.unsupported);
  if (!b3.ok) {
    pass('falsification: M3 fails when the gap count is wrong');
  } else {
    fail('falsification: M3 did NOT fail when the gap count was wrong -- the check is vacuous');
  }
}

// --- 3. the report -----------------------------------------------------------
const summary = {
  label,
  corpus,
  corpusInfo,
  l2: l2Info,
  engines,
  times,
  kinds,
  totals: {
    sites: sites.size,
    l2: l2Sites.length,
    plain: plainSites.length,
    withRule: withRuleSites.length,
    ruleAdded: withRuleSites.filter((k) => !plainSites.includes(k)).length,
    spikeOnly: withRuleSites.filter((k) => !l2Sites.includes(k)).length,
    l2Only: l2Sites.filter((k) => !withRuleSites.includes(k)).length,
  },
  checks: {
    m1: m1.ok,
    m2a: m2a.ok,
    m2b: m2b.ok,
    m3: m3.ok,
  },
  sites: [...sites.values()].map((s) => ({
    kind: s.kind,
    file: s.file,
    line: s.line,
    l2: s.l2,
    plain: s.plain,
    withrule: s.withrule,
    container: s.container,
    sources: s.sources,
  })),
  causes: Object.fromEntries(causes),
};
try {
  mkdirSync(resolve(jsonOut, '..'), { recursive: true });
  writeFileSync(jsonOut, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
  console.log(`\nDATA  ${jsonOut}`);
} catch (e) {
  console.log(`\nDATA  not written: ${e.message}`);
}

console.log('\n| measurement | value |');
console.log('| --- | ---: |');
console.log(`| corpus | ${corpus} |`);
console.log(`| files / functions / statements | ${corpusInfo.files} / ${corpusInfo.funcs} / ${corpusInfo.stmts} |`);
console.log(`| L2 taint sites | ${l2Sites.length} |`);
console.log(`| spike (plain) taint sites | ${plainSites.length} |`);
console.log(`| spike (with rule) taint sites | ${withRuleSites.length} |`);
console.log(`| sites the rule added | ${summary.totals.ruleAdded} |`);
console.log(`| sites the spike has and the L2 does not | ${summary.totals.spikeOnly} |`);
console.log(`| ... of which the L2's dead allocation rule | ${causeOf('alloc')} |`);
console.log(`| ... of which the L2's file-less dedupe dropped it | ${causeOf('dedupe')} |`);
console.log(`| ... of which the container is an allocation | ${causeOf('made')} |`);
console.log(`| ... of which the container's type is unknown | ${causeOf('unknown')} |`);
console.log(`| ... of which the container is an array by type | ${causeOf('array')} |`);
console.log(`| sites the L2 has and the spike does not | ${summary.totals.l2Only} |`);
console.log(`| L2 time / spike time (ms) | ${times['l2'] ?? '-'} / ${times['spike-with-rule'] ?? '-'} |`);
console.log(`| spike facts / worklist steps | ${engines['with-rule'].facts} / ${engines['with-rule'].steps} |`);
console.log(`| spike gaps / walked unmodelled / parser unmodelled | ${engines['with-rule'].gaps} / ${kinds.unsupported ?? 0} / ${corpusInfo.unsupported} |`);

console.log(`\n${failures === 0 ? 'RESULT: ifds spike OK' : `RESULT: ${failures} failure(s)`}`);
process.exit(failures === 0 ? 0 : 1);
