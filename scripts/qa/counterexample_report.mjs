// THE COUNTEREXAMPLES, PARSED.
//
// §5.12 of a report is a table of counterexamples, and the report's
// `_counterexamples.jsonl` sidecar is the same table in machine form.  Two
// renderings of one computation, and this module is what lets a checker
// compare them -- and what lets a FALSIFIER break one of them on a copy and
// watch the comparison notice.
//
// The section is located by its own heading and bounded by the next one, so
// a table elsewhere in the report cannot be mistaken for it.
//
// Dependency-free, like the rest of the harness.

const SECTION_HEADING = '### 5.12 Counterexamples';

/// The §5.12 section: its text and its table rows.
export function parseCounterexampleSection(md) {
  const start = md.indexOf(SECTION_HEADING);
  if (start < 0) return null;
  const rest = md.slice(start);
  const next = rest.indexOf('\n### ', SECTION_HEADING.length);
  const section = next < 0 ? rest : rest.slice(0, next);
  const rows = [];
  for (const line of section.split(/\r?\n/)) {
    if (!line.startsWith('|')) continue;
    const cells = line.split('|').slice(1, -1).map((s) => s.trim());
    if (cells.length !== 5) continue;
    if (cells[0] === 'Finding') continue;
    if (cells[0].startsWith('---')) continue;
    rows.push({
      rule: unquote(cells[0]),
      location: cells[1],
      entry: unquote(cells[2]),
      input: cells[3],
      runs: cells[4],
    });
  }
  return { section, rows };
}

/// The input a counterexample stands for, rendered the way the report
/// renders it: one `name = value` per parameter, in order.  A function with
/// no parameters has no arguments to render, and the report says so.
export function renderInput(params, args) {
  if (!params || params.length === 0) return '_no arguments_';
  return params
    .map((p, i) => '`' + p + ' = ' + args[i] + '`')
    .join(', ');
}

/// The `_counterexamples.jsonl` sidecar: one object per line.
export function parseCounterexampleSidecar(text) {
  return text
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '')
    .map((l) => JSON.parse(l));
}

/// The `_findings.jsonl` sidecar: one object per line.
export function parseFindingsSidecar(text) {
  return text
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '')
    .map((l) => JSON.parse(l));
}

/// A finding's SITE: its family, its place and its function.  This is the
/// identity the counterexample is matched on, and it is the identity the
/// analyser uses: not the message, and not the evidence.
export function siteKey(f) {
  return [f.rule, f.file, f.line, f.fn].join('|');
}

/// The distinct sites of the findings whose METHOD says an execution
/// produced them.
export function dynamicSites(findings) {
  const out = new Set();
  for (const f of findings) {
    if (String(f.method ?? '').startsWith('dynamic')) out.add(siteKey(f));
  }
  return out;
}

/// The distinct sites of the findings whose method says an execution did NOT
/// produce them -- the CFG families (a claim about the program's shape) and
/// the L2 families (a may-claim over the whole input set).
export function nonInputSites(findings) {
  const out = new Set();
  for (const f of findings) {
    if (!String(f.method ?? '').startsWith('dynamic')) out.add(siteKey(f));
  }
  return out;
}

/// The counts the section states in prose.  They are claims about the
/// minimisation, and they have to be measurable.
export function parseProseCounts(section) {
  const covered = section.match(
    /The minimisation covered \*\*(\d+)\*\* of the \*\*(\d+)\*\* findings an execution produced\./,
  );
  const without = section.match(
    /\*\*(\d+)\*\* had no single input in the analyser's candidate set that reproduced them\./,
  );
  const notInput = section.match(
    /\*\*(\d+)\*\* findings in this report are not claims about an input/,
  );
  const skipped = section.match(/\*\*(\d+)\*\* findings were left out by the limit\./);
  const runs = section.match(/The minimisation tried \*\*(\d+)\*\* inputs in total\./);
  if (!covered || !without || !notInput || !skipped || !runs) return null;
  return {
    minimised: Number(covered[1]),
    requested: Number(covered[2]),
    without: Number(without[1]),
    notInput: Number(notInput[1]),
    skipped: Number(skipped[1]),
    tried: Number(runs[1]),
  };
}

/// The findings that no input reproduced, as the section lists them.  The
/// section has no such table when there are none, and an absent table means
/// an empty list -- not a missing check.
export function parseWithoutRows(section) {
  const at = section.indexOf('| Finding | Location | Function | Message |');
  if (at < 0) return [];
  const rest = section.slice(at);
  const rows = [];
  for (const line of rest.split(/\r?\n/)) {
    if (!line.startsWith('|')) {
      if (rows.length > 0) break;
      continue;
    }
    const cells = line.split('|').slice(1, -1).map((s) => s.trim());
    if (cells.length !== 4) continue;
    if (cells[0] === 'Finding') continue;
    if (cells[0].startsWith('---')) continue;
    rows.push({
      rule: unquote(cells[0]),
      location: cells[1],
      fn: unquote(cells[2]),
      message: cells[3],
    });
  }
  return rows;
}

function unquote(s) {
  const t = s.trim();
  if (t.startsWith('`') && t.endsWith('`') && t.length >= 2) {
    return t.slice(1, -1);
  }
  return t;
}
