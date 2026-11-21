#!/usr/bin/env node
// THE PUBLISHED INTERFACE, CHECKED AGAINST THE RELEASE NOTES.
//
// A release that changes the published `.mbti` can break a consumer's build,
// and the only place a consumer reads that the build breaks is the release
// notes. This check makes the two agree, and it does it by MEASUREMENT
// rather than by a list somebody remembered:
//
//   * the published surface of a version is the `.mbti` AT THAT VERSION'S
//     TAG -- `git show v0.1.29:src/app/pkg.generated.mbti` -- so the thing
//     compared is what the registry actually served, not what the working
//     tree holds. For the version being PREPARED, which has no tag yet, it
//     is the working tree's `.mbti`, because that is what the release will
//     publish;
//   * the release notes for a version are that version's "### What changed
//     in X.Y.Z" section of the README, which is the section the registry
//     page carries.
//
// WHAT COUNTS AS A BREAK is a question about the CONSUMER, not about the
// diff:
//
//   * a public function LOST a parameter, GAINED a required one, changed a
//     parameter's type, or changed its return type -- a caller has to change;
//   * a public function was REMOVED;
//   * a public type was REMOVED;
//   * a `pub(all)` type's PUBLIC members changed -- a consumer that
//     constructs the value has to change. The visibility is what decides
//     this: in a plain `pub struct` the fields are private to the package,
//     so a member change there is invisible to a consumer.
//
// What is NOT a break: a new public function, and an OPTIONAL parameter
// added to an existing one (`x? : T` has a default, so every existing call
// still compiles).
//
// The comparison is on SHAPES, not on strings: a type is compared by its
// kind, its visibility and the set of members it names, so the notes may
// write the fields inline and the `.mbti` may write them one per line.
//
// WHAT IS ENFORCED, AND WHY ONLY THAT.
//
//   * The version being prepared -- the version in `moon.mod` -- is
//     ENFORCED: every break it introduces must be named in its notes, and
//     every machine-readable declaration in its notes must be TRUE. This is
//     the one that can still be fixed, and the one a gate at release-prep
//     time is for.
//   * Every other version is COMPARED and REPORTED, but not enforced: the
//     registry freezes a published version's README page at publish time,
//     so a note that is missing there cannot be added, and enforcing it
//     would leave the gate permanently red over pages nobody can fix. The
//     report keeps the information instead of throwing it away.
//
// A version whose tag has no `.mbti` at that path is reported as UNKNOWN
// and skipped. It is never a failure: the check cannot tell, so it does not
// guess.
//
// Usage: node scripts/qa/release_interface.mjs [--report]
//
//   --report  print every version pair and what it found. The default does
//             that too; the flag exists so the history can be read without
//             the enforced checks' output in the way.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(process.cwd());
const reportOnly = process.argv.includes('--report');

const MBTI = 'src/app/pkg.generated.mbti';

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};
const note = (text) => console.log(`      ${text}`);

// ---------------------------------------------------------------------------
// git and the manifest
// ---------------------------------------------------------------------------

function git(args) {
  const r = spawnSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return { code: r.status, out: (r.stdout ?? '') + (r.stderr ?? '') };
}

///|
/// The version of a tag, as numbers. "v0.1.30" -> [0, 1, 30].
function versionOf(tag) {
  const m = /^v(\d+)\.(\d+)\.(\d+)$/.exec(tag);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

///|
/// Is a version at least another one? The comparison is by NUMBERS: as
/// strings, "0.1.9" is GREATER than "0.1.30", which is the wrong answer.
function atLeast(a, b) {
  const va = a.split('.').map(Number);
  const vb = b.split('.').map(Number);
  for (let i = 0; i < 3; i += 1) {
    if ((va[i] ?? 0) !== (vb[i] ?? 0)) return (va[i] ?? 0) > (vb[i] ?? 0);
  }
  return true;
}

///|
/// The version the tree is preparing: the one in `moon.mod`.
function manifestVersion() {
  const text = readFileSync(join(root, 'moon.mod'), 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const m = /^\s*version\s*=\s*"([^"]+)"/.exec(line);
    if (m) return m[1];
  }
  return null;
}

///|
/// Every tag, in RELEASE ORDER -- ascending by version, which is not the
/// order `git tag` prints.
function taggedVersions() {
  const r = git(['tag', '--list']);
  if (r.code !== 0) {
    console.error('cannot list the tags:');
    console.error(r.out);
    process.exit(2);
  }
  const tags = [];
  for (const line of r.out.split('\n')) {
    const tag = line.trim();
    const v = versionOf(tag);
    if (v) tags.push({ tag, v, version: tag.replace(/^v/, '') });
  }
  tags.sort((a, b) => a.v[0] - b.v[0] || a.v[1] - b.v[1] || a.v[2] - b.v[2]);
  return tags;
}

///|
/// The `.mbti` at a tag, or null when that tag has none at this path.
function mbtiAt(tag) {
  const r = git(['show', `${tag}:${MBTI}`]);
  return r.code === 0 ? r.out : null;
}

///|
/// The `.mbti` of the working tree -- what the release being prepared will
/// publish.
function workingMbti() {
  const path = join(root, MBTI);
  return existsSync(path) ? readFileSync(path, 'utf8') : null;
}

// ---------------------------------------------------------------------------
// the surface of a `.mbti`
// ---------------------------------------------------------------------------

///|
/// One member of a type: a field or an enum variant. The text is normalised
/// so that "x : Int32" and "x:Int32" are the same member.
///
/// The trim comes FIRST: the notes write the members inline, so the piece
/// that reaches here usually begins with a space, and an ellipsis marker
/// ("… the rest is unchanged") sits in front of the first one.
function member(text) {
  return text
    .trim()
    .replace(/^[.…]{1,3}\s*/, '')
    .replace(/\s*:\s*/g, ' : ')
    .replace(/,$/, '')
    .trim();
}

///|
/// The published surface of a `.mbti`.
///
/// FUNCTIONS are keyed by their symbol ("version_parts", "AbsCell::new") and
/// carry the whole declaration.
///
/// TYPES carry their kind, their VISIBILITY and their members. The visibility
/// is the difference that decides whether a member change is a break: in a
/// `pub struct` the fields are private to the package, so a consumer cannot
/// see them and cannot construct the type with them; in a `pub(all) struct`
/// they are public, so adding a field breaks every consumer that constructs
/// the value.
function parseSurface(text) {
  const fns = new Map();
  const types = new Map();
  let cur = null;

  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('//')) continue;

    if (cur) {
      if (line === '}') {
        cur = null;
        continue;
      }
      cur.members.add(member(line));
      continue;
    }

    let m = /^pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)\s*\(.*/.exec(line);
    if (m) {
      fns.set(m[1], line.replace(/\s+/g, ' '));
      continue;
    }

    m = /^pub(\(all\))?\s+(struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{$/.exec(line);
    if (m) {
      cur = {
        kind: m[2],
        vis: m[1] ? 'all' : 'plain',
        name: m[3],
        members: new Set(),
      };
      types.set(m[3], cur);
      continue;
    }
  }
  return { fns, types };
}

// ---------------------------------------------------------------------------
// what a consumer can observe
// ---------------------------------------------------------------------------

///|
/// Split a parameter list on the commas that are not inside brackets.
function splitTop(text) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of text) {
    if (ch === '[' || ch === '(' || ch === '{' || ch === '<') depth += 1;
    else if (ch === ']' || ch === ')' || ch === '}' || ch === '>') depth -= 1;
    if (ch === ',' && depth === 0) {
      out.push(cur);
      cur = '';
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out.map((s) => s.trim()).filter((s) => s.length > 0);
}

///|
/// One parameter of a function: its name (when the `.mbti` gives one), whether
/// it is OPTIONAL, and its type.
///
/// A parameter can be NAMELESS: the `.mbti` writes `pub fn AbsCell::new(AbsVal,
/// Array[String])` where the source says `new(v : AbsVal, srcs : Array[String])`
/// -- the names are dropped for a function whose parameters are not part of its
/// contract. Such a parameter is identified by its TYPE.
function parseParam(text) {
  const t = text.trim();
  const m = /^([A-Za-z_][A-Za-z0-9_]*)(\?)?\s*:\s*(.+)$/.exec(t);
  if (m) return { name: m[1], optional: Boolean(m[2]), type: m[3].replace(/\s+/g, ' ').trim() };
  return {
    name: null,
    optional: /\?$/.test(t),
    type: t.replace(/\?$/, '').replace(/\s+/g, ' ').trim(),
  };
}

///|
/// A function's declaration, read into its parts.
function parseFn(decl) {
  const m = /^pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)\s*\((.*)\)\s*(?:->\s*(.+))?$/.exec(
    decl,
  );
  if (!m) return null;
  return {
    name: m[1],
    params: splitTop(m[2]).map(parseParam).filter((p) => p !== null),
    ret: (m[3] ?? '').replace(/\s+/g, ' ').trim(),
  };
}

///|
/// Does the change to one function break a CALLER?
///
/// The parameters are compared POSITIONALLY, because the `.mbti` sometimes
/// drops a parameter's name, and because a caller passes arguments by
/// position anyway.
///
///   * a parameter whose TYPE changed breaks every call -- including a
///     NAMELESS one, which is how `AbsCell::new`'s second argument changes
///     from `TaintMode` to `Array[String]`;
///   * a REQUIRED parameter that is new breaks every call;
///   * an OPTIONAL parameter that is new does NOT: it has a default, so the
///     existing calls still compile.
function fnBreak(prevDecl, nextDecl) {
  const a = parseFn(prevDecl);
  const b = parseFn(nextDecl);
  if (!a || !b) return { break: true, why: 'the declaration could not be read' };

  const common = Math.min(a.params.length, b.params.length);
  for (let i = 0; i < common; i += 1) {
    if (a.params[i].type !== b.params[i].type) {
      return {
        break: true,
        why: `parameter ${i + 1} changed from ${a.params[i].type} to ${b.params[i].type}`,
      };
    }
  }
  if (b.params.length > a.params.length) {
    const extra = b.params.slice(a.params.length);
    if (extra.some((p) => !p.optional)) {
      return { break: true, why: `a required parameter was added (${extra.map((p) => p.type).join(', ')})` };
    }
    return { break: false, why: 'an optional parameter was added' };
  }
  if (a.params.length > b.params.length) {
    return { break: true, why: `${a.params.length - b.params.length} parameter(s) were removed` };
  }
  if (a.ret !== b.ret) {
    return { break: true, why: `the return type changed from ${a.ret} to ${b.ret}` };
  }
  return { break: false, why: '' };
}

///|
/// The breaks between two surfaces: the changes a consumer's build can see.
function breaksBetween(prev, next) {
  const out = [];

  for (const [sym, decl] of prev.fns) {
    if (!next.fns.has(sym)) {
      out.push({ symbol: sym, kind: 'a public function was removed', detail: decl });
      continue;
    }
    const changed = fnBreak(decl, next.fns.get(sym));
    if (changed.break) {
      out.push({
        symbol: sym,
        kind: 'a public function changed in a way a caller can see',
        detail: `${changed.why}\n         ${decl}\n      ->  ${next.fns.get(sym)}`,
      });
    }
  }

  for (const [name, t] of prev.types) {
    if (!next.types.has(name)) {
      out.push({ symbol: name, kind: `a public ${t.kind} was removed`, detail: '' });
      continue;
    }
    const nt = next.types.get(name);
    if (t.vis !== 'all' || nt.vis !== 'all') continue; // private members: not visible
    const added = [...nt.members].filter((x) => !t.members.has(x));
    const gone = [...t.members].filter((x) => !nt.members.has(x));
    if (added.length || gone.length) {
      out.push({
        symbol: name,
        kind: `a public ${t.kind}'s public members changed`,
        detail: [...gone.map((x) => `- ${x}`), ...added.map((x) => `+ ${x}`)].join(', '),
      });
    }
  }
  return out;
}

///|
/// Is the break NAMED in the release notes?
///
/// A method may be named by its own path ("AbsCell::new") or by the grouped
/// form the `.mbti` itself uses ("TaintMode::{code, equal, join, not_equal}"),
/// so both count. A type is named by its own name.
function namesBreak(section, brk) {
  const sym = brk.symbol;
  if (section.includes(sym)) return true;
  if (sym.includes('::')) {
    const type = sym.split('::')[0];
    return section.includes(type + '::{') || section.includes(type + '::');
  }
  return false;
}

// ---------------------------------------------------------------------------
// the release notes
// ---------------------------------------------------------------------------

///|
/// The README's "### What changed in X.Y.Z" sections, keyed by version.
function readSections() {
  const md = readFileSync(join(root, 'README.md'), 'utf8');
  const lines = md.split(/\r?\n/);
  const sections = new Map();
  let current = null;
  let level = 0;

  for (const line of lines) {
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      const thisLevel = h[1].length;
      const title = h[2].trim();
      const m = /^What changed in (\d+\.\d+\.\d+)$/.exec(title);
      if (m) {
        current = m[1];
        level = thisLevel;
        sections.set(current, []);
        continue;
      }
      if (current && thisLevel <= level) {
        current = null;
        continue;
      }
    }
    if (current) sections.get(current).push(line);
  }

  const out = new Map();
  for (const [version, body] of sections) out.set(version, body.join('\n'));
  return out;
}

///|
/// The machine-readable declarations of a section: the rows of a
/// `| before | after |` table.
function declaredRows(section) {
  const rows = [];
  let header = false;
  for (const line of section.split(/\r?\n/)) {
    if (!line.trim().startsWith('|')) {
      header = false;
      continue;
    }
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((s) => s.trim());
    if (!header) {
      if (cells.length === 2 && /before/i.test(cells[0]) && /after/i.test(cells[1])) header = true;
      continue;
    }
    if (cells.length === 2 && !cells.every((c) => /^-{2,}$/.test(c))) {
      rows.push({ before: cells[0], after: cells[1] });
    }
  }
  return rows;
}

///|
///|
/// A type cell's members, split on the commas that are not inside brackets.
///
/// The members of a published type can carry commas OF THEIR OWN: the enum
/// variant `AArr(Int32, Int32, Array[String])` is ONE member, and a split on
/// every comma would break it into three -- which is how the declaration of
/// the 0.1.31 array case could not be written at all.
function splitMembers(text) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of text) {
    if (ch === '[' || ch === '(' || ch === '{') depth += 1;
    else if (ch === ']' || ch === ')' || ch === '}') depth -= 1;
    if (ch === ',' && depth === 0) {
      out.push(cur);
      cur = '';
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out.map((s) => s.trim()).filter((s) => s.length > 0);
}

///|
/// A declaration cell, read as a shape:
///
///   fn      a full function declaration
///   fngroup the grouped form: "pub fn TaintMode::{code, equal}"
///   type    a full type declaration
///   fragment a list of members with no type name -- "… abs_universe : Int32"
///   removed the word "removed"
///   unknown anything else
function parseCell(cell) {
  const text = cell.replace(/`/g, '').replace(/\*\*/g, '').trim();

  if (/^removed$/i.test(text)) return { kind: 'removed', name: text };

  const g = /^pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)::\{([^}]*)\}$/.exec(text);
  if (g) {
    return {
      kind: 'fngroup',
      type: g[1],
      names: g[2]
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
    };
  }

  const t = /^pub(\(all\))?\s+(struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{(.*)\}$/.exec(text);
  if (t) {
    const members = [];
    for (const part of splitMembers(t[4])) {
      const piece = member(part);
      if (!piece) continue;
      members.push(piece);
    }
    return { kind: 'type', typeKind: t[2], vis: t[1] ? 'all' : 'plain', name: t[3], members };
  }

  const f = /^pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)\s*\(.*/.exec(text);
  if (f) {
    return { kind: 'fn', name: f[1], decl: text.replace(/\s+/g, ' ') };
  }

  if (/^[.…]/.test(text)) {
    const members = [];
    for (const part of text.replace(/^[.…]{1,3}\s*/, '').split(',')) {
      const piece = member(part);
      if (piece) members.push(piece);
    }
    return { kind: 'fragment', members };
  }

  return { kind: 'unknown', name: text };
}

///|
/// Does a declaration cell describe a shape that is really published?
///
/// The members are compared by CONTAINMENT, not by equality: the notes may
/// write "… abs_universe : Int32" and leave the rest of the struct out, and
/// that is a true description of the type as long as every member it names
/// is really there.
function cellMatches(cell, surface) {
  const c = parseCell(cell);
  if (c.kind === 'fn') {
    const decl = surface.fns.get(c.name);
    if (!decl) return { ok: false, why: `${c.name} is not published` };
    if (decl !== c.decl) return { ok: false, why: `${c.name} is published as ${decl}` };
    return { ok: true };
  }
  if (c.kind === 'type') {
    const t = surface.types.get(c.name);
    if (!t) return { ok: false, why: `${c.name} is not published` };
    if (t.kind !== c.typeKind) {
      return { ok: false, why: `${c.name} is a ${t.kind}, not a ${c.typeKind}` };
    }
    if (t.vis !== c.vis) {
      return {
        ok: false,
        why: `${c.name} is published as ${t.vis === 'all' ? 'pub(all)' : 'pub'}, not ${c.vis === 'all' ? 'pub(all)' : 'pub'}`,
      };
    }
    for (const m of c.members) {
      if (!t.members.has(m)) return { ok: false, why: `${c.name} has no member ${m}` };
    }
    return { ok: true };
  }
  return { ok: false, why: `the cell ${cell} is not a declaration` };
}

///|
/// Is a subject ABSENT from a surface? Used by the rows that say a symbol
/// was removed.
function absentFrom(cell, surface) {
  const c = parseCell(cell);
  if (c.kind === 'fn') return !surface.fns.has(c.name);
  if (c.kind === 'fngroup') {
    return c.names.every((n) => !surface.fns.has(`${c.type}::${n}`));
  }
  if (c.kind === 'type') return !surface.types.has(c.name);
  return false;
}

// ---------------------------------------------------------------------------
// the run
// ---------------------------------------------------------------------------

const sections = readSections();
const tags = taggedVersions();
const preparing = manifestVersion();

console.log('The published interface, checked against the release notes.');
console.log(`  ${tags.length} tagged version(s), ${sections.size} release-note section(s).`);
console.log(`  the tree is preparing ${preparing}.\n`);

// --- the version being prepared --------------------------------------------
// Its published surface is the tag's `.mbti` when the tag exists (the
// release is out), and the working tree's when it does not (the release is
// being prepared). The previous version is the newest tag below it.
const preparingTag = tags.find((t) => t.version === preparing);
let prevTag = null;
for (const t of tags) {
  if (t.version === preparing) break;
  prevTag = t;
}
if (!prevTag) {
  console.error(`no tag below ${preparing}: there is nothing to compare it with.`);
  process.exit(2);
}
const preparingText = preparingTag ? mbtiAt(preparingTag.tag) : workingMbti();
const prevText = mbtiAt(prevTag.tag);
if (preparingText === null || prevText === null) {
  console.error(`no ${MBTI} for ${preparing} or ${prevTag.tag}: there is nothing to compare.`);
  process.exit(2);
}
const preparingSurface = parseSurface(preparingText);
const prevSurface = parseSurface(prevText);
const brks = breaksBetween(prevSurface, preparingSurface);

console.log(
  `== ${preparing} against ${prevTag.tag} ==\n` +
    `  ${brks.length} break(s) a consumer can see.`,
);

// --- 1. every break is NAMED ------------------------------------------------
const section = sections.get(preparing);
if (section === undefined) {
  check(
    `${preparing}: the README has a release-note section for it`,
    false,
    'the section is what the registry page carries, and it is not there',
  );
} else {
  const missing = brks.filter((b) => !namesBreak(section, b));
  check(
    `${preparing}: the release notes name every break in the published interface`,
    missing.length === 0,
    missing.length === 0
      ? brks.map((b) => b.symbol).join(', ')
      : `${missing.length} undeclared: ${missing.map((b) => `${b.symbol} (${b.kind})`).join('; ')}`,
  );
  for (const b of missing) note(`${b.symbol}: ${b.kind} — ${b.detail}`);
}

// --- 2. every declaration is TRUE -------------------------------------------
for (const d of declaredRows(section ?? '')) {
  const after = parseCell(d.after);
  const before = parseCell(d.before);

  if (after.kind === 'removed') {
    const subject = ['fn', 'fngroup', 'type'].includes(before.kind) ? before : after;
    const label = subject.type ?? subject.name ?? 'the symbol';
    const gone = absentFrom(d.before, preparingSurface);
    check(
      `${preparing}: the notes say ${label} was removed, and it is`,
      gone,
      gone ? '' : `${label} is still published`,
    );
    continue;
  }

  const subject = ['fn', 'fngroup', 'type'].includes(before.kind) ? before : after;
  if (subject.kind === 'fragment' || subject.kind === 'unknown') {
    check(
      `${preparing}: every declared row names a type or a function`,
      false,
      `the row "${d.before}" -> "${d.after}" names neither`,
    );
    continue;
  }

  const m = cellMatches(d.after, preparingSurface);
  check(`${preparing}: the notes' "after" is what ${preparing} publishes`, m.ok, m.why ?? '');
  if (m.ok) {
    const b = cellMatches(d.before, prevSurface);
    check(
      `${preparing}: the notes' "before" is what ${prevTag.tag} published`,
      b.ok,
      b.why ?? '',
    );
  }
}

// --- 3. the history, compared and reported ----------------------------------
console.log('\n== every released version, compared ==');
const history = [];
for (let i = 1; i < tags.length; i += 1) {
  const a = tags[i - 1];
  const b = tags[i];
  const ta = mbtiAt(a.tag);
  const tb = mbtiAt(b.tag);
  if (ta === null || tb === null) {
    history.push({ version: b.version, state: 'UNKNOWN', why: `${a.tag} or ${b.tag} has no ${MBTI}` });
    continue;
  }
  const sa = parseSurface(ta);
  const sb = parseSurface(tb);
  const hb = breaksBetween(sa, sb);
  const hs = sections.get(b.version) ?? '';
  history.push({
    version: b.version,
    state: 'OK',
    brks: hb,
    undeclared: hb.filter((x) => !namesBreak(hs, x)),
  });
}

for (const h of history) {
  if (h.state === 'UNKNOWN') {
    note(`${h.version}: UNKNOWN — ${h.why}`);
    continue;
  }
  if (h.brks.length === 0) continue;
  const mark = h.undeclared.length === 0 ? 'declared  ' : 'UNDECLARED';
  note(
    `${h.version}: ${h.brks.length} break(s), ${h.undeclared.length} undeclared — ${h.brks
      .map((b) => b.symbol)
      .join(', ')} [${mark}]`,
  );
}

const undeclaredHistory = history.filter(
  (h) => h.state === 'OK' && h.undeclared.length > 0 && h.version !== preparing,
);
console.log('');
if (undeclaredHistory.length > 0) {
  note(
    `${undeclaredHistory.length} earlier release(s) broke the published interface without saying so ` +
      `(${undeclaredHistory.map((h) => h.version).join(', ')}). Their pages were frozen by the registry, ` +
      `so this reports them rather than failing on them.`,
  );
}

console.log('');
if (reportOnly) {
  for (const h of history) {
    if (h.state !== 'OK') continue;
    for (const b of h.brks) {
      console.log(
        `  ${h.version}  ${namesBreak(sections.get(h.version) ?? '', b) ? 'declared  ' : 'UNDECLARED'} ${b.symbol} — ${b.kind}`,
      );
    }
  }
  console.log('');
}

console.log(
  failures === 0
    ? `Release notes and published interface: all ${checks} checks agree.`
    : `Release notes and published interface: ${failures} of ${checks} checks FAILED.`,
);
process.exit(failures === 0 ? 0 : 1);
