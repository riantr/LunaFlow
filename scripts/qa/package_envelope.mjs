#!/usr/bin/env node
// THE PACKAGE THE REGISTRY CAN READ.
//
// `moon publish` packs the working tree minus the files the ignore rules match,
// and uploads the archive. The registry refuses an archive it cannot read, and
// it says so in a way that names nothing: the 0.1.35 upload came back with
// "400 Bad Request, detail: Invalid ZIP archive" -- the bytes it received were
// not an archive it could parse, and the message does not say whether the
// archive was too big, too odd, or cut in half.
//
// MEASURED, from the registry's own copies and from the archives this tree
// builds:
//
//   | package                    | unpacked bytes | largest entry  | registry |
//   | 0.1.28                     |    43,939,073  |    38,549,443  | accepted |
//   | 0.1.34                     |    46,274,868  |    39,479,846  | accepted |
//   | 0.1.35 (with the traces)  |   162,703,756  |    80,863,997  | REJECTED |
//   | 0.1.35 (without them)     |     5,160,245  |       993,480  | accepted |
//
// So the registry's ceiling lies between the accepted 0.1.34 and the rejected
// 0.1.35, and this check keeps the package inside the range the registry has
// ALREADY accepted -- the ceiling is the largest archive the registry served,
// read from the registry's own copy, and recorded in
// `docs/qa/PUBLISH_ENVELOPE.json`. A package that grows past it fails HERE,
// before a release, instead of at the registry, after one.
//
// The file set is not guessed. `git ls-files --cached --others --exclude-standard`
// is git's own answer to "which files are not ignored", and the packer was
// MEASURED to agree with it: an untracked file that no rule matches was in the
// archive, and a tracked file a rule matches was not. When the archive itself
// is there -- the release builds one before it uploads -- this check reads it
// and compares the two, so the model cannot drift away from the packer
// unnoticed.
//
// It also checks the OTHER half of the rule, the half that is easy to break by
// accident: the artefacts a reader uses (the report, the sidecar, the summary)
// are packed, and the raw traces -- which stay in the repository -- are not.
//
// And when a raw trace is NOT in the repository, the check says WHY and WHAT TO
// RUN.  The rule that keeps the traces out of the package is the very rule that
// makes a plain `git add` refuse them, so a failure that says only "not
// tracked" is a dead end: the reader is left with the fact and no command.  The
// rule is MEASURED (`git check-ignore`), not assumed, and the falsifier proves
// both branches of the advice -- `git add -f` for a path a rule matches, and
// `git add` for one that no rule matches.
//
// Usage:
//   node scripts/qa/package_envelope.mjs [--packed <json>] [--archive <zip>]
//
//   --packed <json>  check a MODEL instead of the tree: the file is the JSON
//                    this check builds for itself. The falsifier uses it to
//                    feed the check a package that is wrong.
//   --archive <zip>  compare the model against this archive.
//
// Exit codes: 0 pass, 1 fail, 2 could not decide.
//
// Dependency-free, like the rest of the harness.

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const ENVELOPE_FILE = join(ROOT, 'docs', 'qa', 'PUBLISH_ENVELOPE.json');

let checks = 0;
let failures = 0;
const check = (name, ok, detail = '') => {
  checks += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
};
const note = (text) => console.log(`NOTE  ${text}`);
// The way out, when there is one.  A check that says what is wrong and stops
// there leaves the reader to work out the command; this prints it.
const fix = (text) => console.log(`FIX  ${text}`);

const argValue = (flag) => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const PACKED = argValue('--packed');
const ARCHIVE = argValue('--archive');
const DUMP = argValue('--dump-model');

// --------------------------------------------------------------- the envelope

function readEnvelope() {
  if (!existsSync(ENVELOPE_FILE)) return null;
  try {
    return JSON.parse(readFileSync(ENVELOPE_FILE, 'utf8'));
  } catch {
    return null;
  }
}

// ------------------------------------------------------------- the file set

/// git's own answer to "which files are not ignored".
function gitPaths(args) {
  const r = spawnSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) return null;
  return r.stdout.split('\0').filter((s) => s !== '');
}

/// Which ignore rule matches each of these paths -- git's own answer, and the
/// answer the packer is built on.
///
/// Two flags are not optional, and both were MEASURED rather than assumed:
///
///   --no-index   without it git does not report a rule for a TRACKED path, and
///                every raw trace here is tracked AND ignored -- so the
///                measurement would come back empty and the check would name
///                the wrong cause.
///   --stdin      `-z` only makes sense with `--stdin`, and with both of them
///                git emits FOUR NUL-separated fields per record -- source,
///                line, pattern, path -- instead of one line per path.
function ignoreRules(paths) {
  const rules = new Map();
  if (paths.length === 0) return rules;
  const r = spawnSync('git', ['check-ignore', '-v', '-z', '--no-index', '--stdin'], {
    cwd: ROOT,
    encoding: 'buffer',
    input: Buffer.from(paths.join('\0') + '\0', 'utf8'),
    maxBuffer: 64 * 1024 * 1024,
  });
  // 0: at least one path is ignored.  1: none of them is.  Both are answers;
  // anything else is not an answer at all, and then no rule is claimed.
  if (r.status !== 0 && r.status !== 1) return rules;
  const fields = (r.stdout ?? Buffer.alloc(0)).toString('utf8').split('\0');
  for (let i = 0; i + 3 < fields.length; i += 4) {
    const [source, line, pattern, path] = fields.slice(i, i + 4);
    rules.set(path, `${source}:${line}:${pattern}`);
  }
  return rules;
}

/// The model: what goes into the archive, what the artefacts are, and what the
/// raw traces are.
///
/// The packer's rule was MEASURED, not assumed:
///
///   * a file no ignore rule matches IS packed, tracked or not -- an untracked
///     file in `reports/` was in the archive;
///   * a file an ignore rule matches is NOT packed, even when it is TRACKED --
///     the raw traces are tracked, and the archive does not carry them;
///   * a path with a dot in any of its parts is NOT packed -- neither
///     `.gitignore` nor `.github/workflows/ci.yml` is in the archive, and
///     neither is in any archive the registry has served (0.1.28: 0 dot
///     entries, 0.1.34: 0 dot entries).
export function measureModel() {
  const trackedPaths = gitPaths(['ls-files', '-z', '--cached']);
  const untrackedPaths = gitPaths(['ls-files', '-z', '--others', '--exclude-standard']);
  const ignoredPaths = gitPaths(['ls-files', '-z', '--cached', '--ignored', '--exclude-standard']);
  if (trackedPaths === null || untrackedPaths === null || ignoredPaths === null) return null;
  const ignored = new Set(ignoredPaths);

  const packed = [];
  let missing = 0;
  const seen = new Set();
  for (const p of [...trackedPaths, ...untrackedPaths]) {
    if (seen.has(p)) continue;
    seen.add(p);
    if (ignored.has(p)) continue;
    if (p.split('/').some((seg) => seg.startsWith('.'))) continue;
    let bytes;
    try {
      bytes = statSync(join(ROOT, p)).size;
    } catch {
      // A tracked file that is not on disk cannot be packed, and its absence
      // is not this check's business -- but it is counted, so the note below
      // can say so instead of quietly measuring a smaller package.
      missing += 1;
      continue;
    }
    packed.push({ path: p, bytes });
  }

  const tracked = new Set(trackedPaths);
  const artefacts = [];
  const traces = [];
  const reportsDir = join(ROOT, 'reports');
  if (existsSync(reportsDir)) {
    const names = readdirSync(reportsDir);
    // Which rule hides each trace is MEASURED, because the remedy depends on
    // it: a path a rule matches cannot be staged with a plain `git add`.
    const rules = ignoreRules(
      names.filter((n) => n.endsWith('_trace.jsonl')).map((n) => `reports/${n}`),
    );
    for (const name of names) {
      const rel = `reports/${name}`;
      if (name.endsWith('_trace.jsonl')) {
        traces.push({
          path: rel,
          tracked: tracked.has(rel),
          ignored: rules.has(rel),
          ignoredBy: rules.get(rel) ?? null,
        });
      } else if (name.endsWith('.md') || name.endsWith('_findings.jsonl') || name.endsWith('_summary.json')) {
        artefacts.push({ path: rel });
      }
    }
  }
  return { packed, artefacts, traces, missing };
}

// ------------------------------------------------------------- the archive

/// The archive's own central directory, read without a dependency: the entries
/// and their unpacked sizes, exactly as the registry will see them.
export function readArchive(path) {
  let buf;
  try {
    buf = readFileSync(path);
  } catch {
    return null;
  }
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0 && i >= buf.length - 22 - 65536; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return null;

  let count = buf.readUInt16LE(eocd + 10);
  let cdOffset = buf.readUInt32LE(eocd + 16);
  // ZIP64: the 32-bit fields are placeholders and the real ones live in the
  // ZIP64 end-of-central-directory record, which the locator points at.
  if (count === 0xffff || cdOffset === 0xffffffff) {
    const locator = eocd - 20;
    if (locator < 0 || buf.readUInt32LE(locator) !== 0x07064b50) return null;
    const z64 = Number(buf.readBigUInt64LE(locator + 8));
    if (buf.readUInt32LE(z64) !== 0x06064b50) return null;
    count = Number(buf.readBigUInt64LE(z64 + 32));
    cdOffset = Number(buf.readBigUInt64LE(z64 + 48));
  }

  const entries = [];
  let p = cdOffset;
  for (let i = 0; i < count; i++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) return null;
    let uncompressed = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    if (uncompressed === 0xffffffff) {
      // The real size is in the ZIP64 extra field, in order, for the fields
      // that were placeholders.
      let e = p + 46 + nameLen;
      const end = e + extraLen;
      while (e + 4 <= end) {
        const id = buf.readUInt16LE(e);
        const size = buf.readUInt16LE(e + 2);
        if (id === 0x0001) {
          let q = e + 4;
          uncompressed = Number(buf.readBigUInt64LE(q));
          q += 8;
          break;
        }
        e += 4 + size;
      }
    }
    entries.push({ path: name, bytes: uncompressed });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

// --------------------------------------------------------------- the checks

export function envelopeChecks(model, envelope) {
  const packedSet = new Set(model.packed.map((f) => f.path));
  const total = model.packed.reduce((a, f) => a + f.bytes, 0);
  const largest = model.packed.reduce((a, f) => (f.bytes > a.bytes ? f : a), { path: '-', bytes: 0 });

  const results = [];
  // `remedy` is what to RUN when the check fails: a check that says what is
  // wrong and stops there leaves the reader to work out the command.
  const add = (name, ok, detail, remedy = []) => results.push({ name, ok, detail, remedy });

  add(
    'the package fits the envelope the registry has accepted (unpacked bytes)',
    total <= envelope.reference_unpacked_bytes,
    `${total} bytes, ceiling ${envelope.reference_unpacked_bytes}`,
  );
  add(
    'the package fits the envelope the registry has accepted (largest entry)',
    largest.bytes <= envelope.reference_largest_entry_bytes,
    `${largest.path} at ${largest.bytes} bytes, ceiling ${envelope.reference_largest_entry_bytes}`,
  );

  const unpackedArtefacts = model.artefacts.filter((a) => !packedSet.has(a.path));
  add(
    'every report, sidecar and summary is packed',
    unpackedArtefacts.length === 0,
    unpackedArtefacts.length === 0
      ? `${model.artefacts.length} artefact(s)`
      : `not packed: ${unpackedArtefacts.map((a) => a.path).join(', ')}`,
  );

  const packedTraces = model.traces.filter((t) => packedSet.has(t.path));
  add(
    'no raw trace is packed',
    packedTraces.length === 0,
    packedTraces.length === 0
      ? `${model.traces.length} trace(s), none of them packed`
      : `packed: ${packedTraces.map((t) => t.path).join(', ')}`,
  );

  // The traces stay in the repository, and there is at least one of them: a
  // model with NO trace must not pass this check vacuously.
  const untracked = model.traces.filter((t) => !t.tracked);
  // WHY a trace is untracked decides WHAT to run.  A path an ignore rule
  // matches cannot be staged with a plain `git add` -- git refuses it -- and
  // that rule is the very one that keeps the trace out of the package.  So the
  // check names the rule and prints the command that stages it.
  const remedy = [];
  if (untracked.length > 0) {
    const forced = untracked.filter((t) => t.ignored);
    const plain = untracked.filter((t) => !t.ignored);
    if (forced.length > 0) {
      const rules = [...new Set(forced.map((t) => t.ignoredBy).filter(Boolean))];
      remedy.push(
        `${forced.length} of them are matched by the ignore rule ${rules.join(', ')}, so \`git add\` alone refuses them:`,
      );
      remedy.push(`git add -f -- ${forced.map((t) => t.path).join(' ')}`);
    }
    if (plain.length > 0) {
      remedy.push(`${plain.length} of them are matched by no ignore rule, so \`git add\` takes them:`);
      remedy.push(`git add -- ${plain.map((t) => t.path).join(' ')}`);
    }
  }
  add(
    'every raw trace is still tracked by git',
    model.traces.length > 0 && untracked.length === 0,
    model.traces.length === 0
      ? 'there is no raw trace at all, so this check has nothing to compare'
      : untracked.length === 0
        ? `${model.traces.length} trace(s), all tracked`
        : `${untracked.length} of ${model.traces.length} trace(s) are on disk but not in the git index`,
    remedy,
  );

  return { results, total, largest };
}

// ------------------------------------------------------------------- the run

const envelope = readEnvelope();
if (!envelope) {
  console.error(`the envelope record is missing or unreadable: ${ENVELOPE_FILE}`);
  process.exit(2);
}

let model;
if (PACKED) {
  try {
    model = JSON.parse(readFileSync(resolve(PACKED), 'utf8'));
  } catch (e) {
    console.error(`the model could not be read: ${e.message}`);
    process.exit(2);
  }
} else {
  model = measureModel();
  if (!model) {
    console.error('git could not list the files, so the package cannot be measured');
    process.exit(2);
  }
}

// The model, written out. The falsifier starts from THIS -- the check's own
// measurement -- so there is one source of truth for what the package holds.
if (DUMP) {
  writeFileSync(resolve(DUMP), JSON.stringify(model, null, 2), 'utf8');
  console.log(`the model was written to ${DUMP}`);
  process.exit(0);
}

const { results, total, largest } = envelopeChecks(model, envelope);
for (const r of results) {
  check(r.name, r.ok, r.detail);
  for (const line of r.remedy ?? []) fix(line);
}

console.log(
  `      package: ${model.packed.length} file(s), ${total} bytes unpacked, largest ${largest.path} at ${largest.bytes} bytes`,
);
if (model.missing > 0) {
  note(`${model.missing} tracked file(s) are not on disk, so they are not in the measurement`);
}

// The archive, when it is there: the model has to agree with what the packer
// actually produced, or the model is not the packer's rule.
function moduleVersion() {
  const m = /version\s*=\s*"([^"]+)"/.exec(readFileSync(join(ROOT, 'moon.mod'), 'utf8'));
  return m ? m[1] : null;
}
const archivePath = ARCHIVE
  ? resolve(ARCHIVE)
  : (() => {
      const v = moduleVersion();
      return v ? join(ROOT, '_build', 'publish', `riantr-LunaFlow-${v}.zip`) : null;
    })();
if (PACKED) {
  note('the model was supplied, so there is no archive to compare it with');
} else if (!archivePath) {
  note('the module version could not be read, so no archive could be looked for');
} else if (existsSync(archivePath)) {
  // A STALE archive is not evidence: the archive in `_build/` is from an
  // earlier build, and comparing it with a tree that has moved since would
  // fail for a reason that says nothing about the package. So it is compared
  // only when it is NEWER than every file it would carry.
  let newest = 0;
  for (const f of model.packed) {
    try {
      const m = statSync(join(ROOT, f.path)).mtimeMs;
      if (m > newest) newest = m;
    } catch {
      /* a file that is not on disk cannot date the archive */
    }
  }
  const archiveMtime = statSync(archivePath).mtimeMs;
  if (archiveMtime < newest) {
    note(`the archive is older than the tree (${archivePath}); it is not compared`);
  } else {
  const entries = readArchive(archivePath);
  if (!entries) {
    check('the archive could be read', false, archivePath);
  } else {
    const archiveTotal = entries.reduce((a, e) => a + e.bytes, 0);
    const archiveLargest = entries.reduce((a, e) => (e.bytes > a.bytes ? e : a), { path: '-', bytes: 0 });
    const modelPaths = new Set(model.packed.map((f) => f.path));
    const archivePaths = new Set(entries.map((e) => e.path));
    const onlyModel = [...modelPaths].filter((p) => !archivePaths.has(p));
    const onlyArchive = [...archivePaths].filter((p) => !modelPaths.has(p));
    check(
      'the model and the archive hold the same files',
      onlyModel.length === 0 && onlyArchive.length === 0,
      onlyModel.length === 0 && onlyArchive.length === 0
        ? `${entries.length} entries`
        : `only in the model: ${onlyModel.slice(0, 3).join(', ')}; only in the archive: ${onlyArchive.slice(0, 3).join(', ')}`,
    );
    check(
      'the model and the archive agree about the unpacked size',
      archiveTotal === total,
      `archive ${archiveTotal}, model ${total}`,
    );
    check(
      'the model and the archive agree about the largest entry',
      archiveLargest.path === largest.path && archiveLargest.bytes === largest.bytes,
      `archive ${archiveLargest.path} at ${archiveLargest.bytes}, model ${largest.path} at ${largest.bytes}`,
    );
  }
  }
} else {
  note(`no archive to compare with (${archivePath}); the model stands alone`);
}
console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${checks} passed, ${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
