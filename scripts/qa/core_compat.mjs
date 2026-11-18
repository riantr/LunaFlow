// The CORE COMPATIBILITY gate.
//
// The async runtime comes from the toolchain, so the version of
// `moonbitlang/core` this module builds against is decided by the USER'S
// toolchain, not by a pin here. That is the point of the swap -- and it is
// also a hazard: the core's API is allowed to change shape between the
// toolchains the users have, and this module has to build against all of
// them.
//
// MEASURED, and the reason this gate exists: the CI runner installed
// moon 0.1.20261104, which bundles core 0.10.20, while this machine had core
// 0.10.19. Between them,
//
//   read_from_process()  -> &ProcessOutput
//                        -> (ReadFromProcess, SharedProcessOutput) raise
//   run's stdout~        : &ProcessOutput = @stdio.stdout
//                        : ProcessOutput = Inherit
//
// so a call that captured the child's output compiled against ONE core
// version and not the other, and the release failed on the runner with
//
//   Expr Type Mismatch
//     has type : (ReadFromProcess, SharedProcessOutput)
//     wanted   : ProcessOutput
//
// A diff of the two cores' APIs would have shown it before the release. So
// this gate does that diff, for the APIs THIS MODULE ACTUALLY USES: it
// fetches the registry's newest `moonbitlang/core`, finds every core this
// machine has, and compares the declarations.
//
// WHAT IS COMPARED. The whole declaration is not the requirement; the
// requirement is that the CALLS COMPILE. A declaration may differ in a
// parameter this module does not pass -- `run`'s `stdout~` differs, and this
// module does not pass it -- and that is not a break. So each core is
// compared on the parameters the call sites actually use, plus the RETURN
// TYPE, which is what the release failure turned out to be.
//
// AND THE LABELS. A parameter this module passes BY LABEL is not just a
// type: the LABEL is part of the call, and a core that renames it breaks the
// call site even when the type is unchanged. A label the module passes that a
// core does not declare is therefore a break, and it is reported as one.
//
// Usage: node scripts/qa/core_compat.mjs

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = resolve(new URL("../../", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const SCRATCH = join(ROOT, "_build", "qa", "core_compat");

// The core packages this module imports, and the alias each is used under.
//
// `testOnly` marks a package that is imported FOR TESTS ONLY. Such a package
// is not a dependency of the PUBLISHED library: the library still builds
// against a core that does not declare it, and only this module's own test
// build needs it. So a core that does not declare it is reported as a
// NOTE, not as a break -- and a core that declares it with a DIFFERENT
// signature is still a break, because the tests would not compile against
// it.
//
// The `moonbitlang/core/quickcheck` package is the first one: it is the
// property-test driver, and it is imported as
//
//   import { "moonbitlang/core/quickcheck" @coreqc } for "test"
//
// so `moon.mod` keeps its empty import block and the published artifact is
// byte-identical with and without the tests. MEASURED (2026-11-18): every
// core in the compatibility contract declares it, with the SAME `check`
// signature -- including the `count` LABEL the tests pass, which is why the
// label rule below applies to it as well.
const PACKAGES = {
  async: { pkg: "async" },
  fs: { pkg: "async/fs" },
  process: { pkg: "async/process" },
  env: { pkg: "env" },
  io: { pkg: "async/io" },
  stdio: { pkg: "async/stdio" },
  coreqc: { pkg: "quickcheck", testOnly: true },
};

// --------------------------------------------------------------- the cores

///| Every core this machine has.
///
/// There is more than one, and that is the point: a user may be on any
/// toolchain, and the module has to build against all of them. The core
/// under `~/.moon/lib/core` is whatever toolchain is installed there, and the
/// core NEXT TO the `moon` on PATH is the one that binary actually uses.
function findLocalCores() {
  const found = [];
  const home = process.env.HOME || process.env.USERPROFILE;
  if (home) {
    const p = join(hhome(home), ".moon", "lib", "core");
    if (existsSync(p)) found.push(p);
  }
  try {
    const which = spawnSync(process.platform === "win32" ? "where" : "which", ["moon"], {
      encoding: "utf8",
    });
    const bin = (which.stdout || "")
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean)[0];
    if (bin) {
      const p = resolve(bin, "..", "..", "lib", "core");
      if (existsSync(p) && !found.includes(p)) found.push(p);
    }
  } catch {
    // No `moon` on PATH.
  }
  if (process.env.LUNAFLOW_CORE_DIR) {
    const p = process.env.LUNAFLOW_CORE_DIR;
    if (!found.includes(p)) found.unshift(p);
  }
  return found;
}

function hhome(home) {
  return home;
}

///| The version a core tree declares, for the report.
function coreVersion(dir) {
  try {
    const text = readFileSync(join(dir, "moon.mod"), "utf8");
    return text.match(/^version\s*=\s*"([^"]+)"/m)?.[1] ?? "unknown";
  } catch {
    return "unknown";
  }
}

///| Is a fetched core tree actually USABLE?
///
/// MEASURED BUG (2026-11-17): `moon fetch` creates the destination directory
/// BEFORE it unpacks the package, so an interrupted fetch leaves an EMPTY
/// directory behind. The next fetch then says "already exists" and does
/// nothing, and the gate compares the module's declarations against an EMPTY
/// tree -- which reads as "the newest core does not declare any of them", a
/// compatibility break that does not exist. The core was fine; the extraction
/// was not.
///
/// So the tree is checked for CONTENT, not for existence: it has to carry the
/// packages the comparison reads. An empty or package-less tree is cleared and
/// fetched again once; if it is still unusable, that is reported as a FETCH
/// failure and never as an incompatible declaration.
function coreIsUsable(dir) {
  const expected = ["async", "env"];
  return (
    existsSync(dir) &&
    expected.every((pkg) => existsSync(join(dir, pkg)) && readdirSync(join(dir, pkg)).length > 0)
  );
}

///| The registry's newest `moonbitlang/core`, fetched and extracted.
async function fetchNewestCore() {
  const res = await fetch("https://mooncakes.io/api/v0/modules/moonbitlang/core");
  if (!res.ok) throw new Error(`registry query failed: HTTP ${res.status}`);
  const body = await res.json();
  const version = body.latest_version;
  if (!version) throw new Error("the registry named no latest_version for moonbitlang/core");

  const probe = join(SCRATCH, "probe");
  mkdirSync(probe, { recursive: true });
  // A bare manifest: the probe must NOT import `moonbitlang/core`, or the
  // toolchain sees two versions of the stdlib core and refuses.
  writeFileSync(
    join(probe, "moon.mod"),
    'name = "probe/core_compat"\n\nversion = "0.1.0"\n',
    "utf8",
  );
  const extracted = join(probe, ".repos", "moonbitlang", "core", version);

  // An empty tree from an interrupted fetch is cleared first: `moon fetch`
  // would otherwise say "already exists" and unpack nothing.
  if (existsSync(extracted) && !coreIsUsable(extracted)) {
    rmSync(extracted, { recursive: true, force: true });
  }

  for (let attempt = 1; attempt <= 2; attempt++) {
    const run = spawnSync("moon", ["-C", probe, "fetch", `moonbitlang/core@${version}`], {
      cwd: ROOT,
      encoding: "utf8",
      timeout: 900000,
    });
    if (run.status !== 0) {
      throw new Error(
        `moon fetch moonbitlang/core@${version} failed:\n${run.stdout}\n${run.stderr}`,
      );
    }
    if (coreIsUsable(extracted)) return { version, dir: extracted };
    // A fetch that "succeeded" but unpacked nothing: clear it and try once
    // more, because the second attempt is the one that actually downloads.
    if (existsSync(extracted)) rmSync(extracted, { recursive: true, force: true });
    if (attempt === 2) {
      throw new Error(
        `moon fetch moonbitlang/core@${version} reported success but unpacked no packages ` +
          `at ${extracted}; the registry's newest core could not be obtained, so its ` +
          `compatibility is UNKNOWN rather than broken`,
      );
    }
  }
  throw new Error(`could not obtain moonbitlang/core@${version}`);
}

// ------------------------------------------------------- the declarations

function pkgFiles(coreDir, pkg) {
  const dir = join(coreDir, pkg);
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const e of entries) {
    if (!e.endsWith(".mbt")) continue;
    const p = join(dir, e);
    if (statSync(p).isFile()) out.push(p);
  }
  return out;
}

///| The import aliases a package declares, mapped to their core paths.
///
/// A re-export (`pub using @event_loop {now}`) names the source package by
/// ALIAS, and the alias is the last segment of the imported path, so the
/// package's own `moon.pkg` is where the path is recovered from.
function pkgAliases(coreDir, pkg) {
  const map = new Map();
  const manifest = join(coreDir, pkg, "moon.pkg");
  let text;
  try {
    text = readFileSync(manifest, "utf8");
  } catch {
    return map;
  }
  const re = /"moonbitlang\/core\/([^"]+)"/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const alias = m[1].split("/").pop();
    map.set(alias, m[1]);
  }
  return map;
}

///| Split a parameter list into `{ name, text }` entries.
///
/// The NAME is what a call site passes by label, so it has to be the name and
/// not the whole head. MEASURED BUG (2026-11-17): the head used to be taken
/// as the name, and a head is `"recursive~ : Bool"`, so the name read as
/// `"recursive~ : Bool"` and never matched the label a call site passes
/// (`recursive`). The gate therefore compared no label at all.
///
/// `~` marks an optional parameter and `?` marks one without a default; a
/// label is spelled without either, so both are stripped.
function splitParams(text) {
  const out = [];
  let depth = 0;
  let cur = "";
  for (const ch of text) {
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") depth--;
    if (ch === "," && depth === 0) {
      out.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  if (cur.trim() !== "") out.push(cur);
  return out
    .map((p) => p.trim())
    .filter((p) => p !== "")
    .map((p) => {
      const eq = p.indexOf("=");
      const head = (eq >= 0 ? p.slice(0, eq) : p).trim();
      const name = head.split(":")[0].trim().replace(/[~?]$/, "").trim();
      return { name, text: p.replace(/\s+/g, " ") };
    });
}

///| The parameter list of a function declaration, scanned with BALANCED
/// parentheses.
///
/// MEASURED (2026-11-18): the parameter list used to be taken with a
/// non-greedy scan up to the FIRST `)`, so a parameter whose TYPE contains
/// parentheses ended the scan early. The core's `quickcheck.check` takes
///
///   property : (A) -> Bool raise?
///
/// so the whole signature read as ONE parameter named "property : (A", and
/// the `count` label the tests pass was reported as a label no core
/// declares -- a break that did not exist.
function scanParams(text, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < text.length; i++) {
    const ch = text[i];
    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0) {
        return { params: text.slice(openIdx + 1, i), end: i };
      }
    }
  }
  return null;
}

///| The declaration of `name` in a core package.
///
/// Returns `{ kind, params, ret, text }` for a function, `{ kind: "enum",
/// enum, variant }` for an enum case, and `{ kind: "using", from }` for a
/// re-export. The RETURN TYPE is part of a function's declaration: the
/// change that broke the release was a return type, and a comparison that
/// ignored it would have reported the two cores as identical.
function findDecl(coreDir, pkg, name) {
  const aliases = pkgAliases(coreDir, pkg);
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  for (const file of pkgFiles(coreDir, pkg)) {
    const text = readFileSync(file, "utf8");

    // A function declaration, WITH OR WITHOUT TYPE PARAMETERS:
    //
    //   pub fn check(property : (A) -> Bool raise?, ...) -> Unit raise
    //   pub fn[A : Arbitrary + @shrink.Shrink] check(...) -> Unit raise
    //
    // MEASURED (2026-11-18): the pattern required the name to follow `fn`
    // directly, so a declaration with type parameters was not found at all
    // -- and the core's `quickcheck.check` has them. The core also spells
    // the return type `-> Unit raise`, which the pattern reads as the
    // return type.
    const fnRe = new RegExp(
      `^pub (?:async )?fn\\s*(?:\\[[^\\]]*\\])?\\s*${esc}\\s*\\(`,
      "m",
    );
    const fn = text.match(fnRe);
    if (fn) {
      const openIdx = fn.index + fn[0].length - 1;
      const scanned = scanParams(text, openIdx);
      if (scanned) {
        // The return type: what is between the closing parenthesis and the
        // body.
        const after = text.slice(scanned.end + 1);
        const ret = after.match(/^\s*(->[^\n{]*)?\{/)?.[1] ?? "";
        return {
          kind: "fn",
          params: splitParams(scanned.params),
          ret: ret.replace(/\s+/g, " ").trim(),
        };
      }
    }

    // A re-export: `pub using @event_loop {now}`.
    const usingRe = new RegExp(`^pub using @([A-Za-z_][A-Za-z0-9_]*)\\s*\\{[^}]*\\b${esc}\\b`, "m");
    const using = text.match(usingRe);
    if (using) {
      const path = aliases.get(using[1]);
      if (path) {
        const inner = findDecl(coreDir, path, name);
        if (inner) return { ...inner, via: path };
      }
      return { kind: "using", from: using[1] };
    }

    // An enum VARIANT: `fs.Directory` is a case of `FileKind`.
    const enumRe = /pub(?:\(all\))? enum ([A-Za-z_][A-Za-z0-9_]*)\s*\{([\s\S]*?)\n\}/g;
    let em;
    while ((em = enumRe.exec(text)) !== null) {
      const variantRe = new RegExp(`^\\s*${esc}\\s*(=|,|$)`, "m");
      if (variantRe.test(em[2])) {
        return { kind: "enum", enum: em[1], variant: name };
      }
    }
  }
  return null;
}

// -------------------------------------------------------- our call sites

///| The source with the COMMENTS and the STRING LITERALS removed.
///
/// A package named inside a string literal is sample code, not a call of
/// this module: the test fixtures embed MoonBit source in block strings,
/// so `@async.all(tasks)` in one of those is NOT a call of this module.
/// A real call cannot be inside a string literal, so removing them cannot
/// hide one.
///
/// The block string is MEASURED, not assumed. It opens with `#|`, EVERY
/// line carries the `#|` prefix -- a line whose content after the prefix
/// is empty is an EMPTY LINE of the string, not the end of it -- and the
/// block ends at the first line that does not carry the prefix. So the
/// block is stripped line by line.
function stripLiterals(raw) {
  const out = [];
  let inBlock = false;
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (inBlock && !t.startsWith("#|")) {
      inBlock = false;
    }
    if (inBlock) {
      // The content of the block is SAMPLE CODE: it is dropped, and the
      // line is kept empty so the line numbers stay right.
      out.push("");
      continue;
    }
    if (t.includes("#|")) {
      inBlock = true;
      out.push("");
      continue;
    }
    out.push(line.replace(/\/\/[^\n]*/g, ""));
  }
  // A normal string literal: a package named in one is prose too.
  return out.join("\n").replace(/"(?:[^"\\\n]|\\.)*"/g, '""');
}

///| Every call site in this module that touches a core package.
///
/// The arguments matter as much as the name: a call that passes
/// `inherit_env=` uses that parameter, and a parameter it does not pass may
/// change shape without breaking anything.
function ourCallSites() {
  const files = [];
  const stack = [join(ROOT, "src")];
  if (existsSync(join(ROOT, "main.mbt"))) files.push(join(ROOT, "main.mbt"));
  while (stack.length) {
    const d = stack.pop();
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) stack.push(p);
      else if (e.name.endsWith(".mbt")) files.push(p);
    }
  }

  const calls = new Map();
  for (const f of files) {
    const raw = readFileSync(f, "utf8");
    // Comments and STRING LITERALS are stripped first: a package mentioned
    // in prose is not a call, and neither is a package named inside a
    // string literal.
    //
    // The string literals matter here: the concurrency fixtures embed
    // MoonBit source in `#| ... |#` literals, so `@async.all(tasks)` in
    // those literals is SAMPLE CODE and not a call of this module. The
    // gate's job is the calls THIS module makes -- the ones that have to
    // compile against every core -- and a call inside a string literal
    // cannot break the build of this module.
    const text = stripLiterals(raw);
    for (const m of text.matchAll(/@([a-z_][a-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
      const alias = m[1];
      if (!PACKAGES[alias]) continue;
      const name = m[2];
      // The argument list: scan to the matching close paren.
      //
      // The opening paren is already consumed by the match above, so the
      // collected text is the ARGUMENTS WITHOUT the enclosing parentheses.
      //
      // MEASURED BUG (2026-11-17): the opening paren used to be collected as
      // well, and then the first argument looked like a nested call -- its
      // text carried a "(" -- so NO argument was ever recognised as a LABEL.
      // Every call site therefore looked positional, the gate compared
      // types only, and a core that had RENAMED a label was invisible to it.
      // The proof is in its own output: `fs.mkdir` read as
      // "path : StringView | -> Unit" for a call that passes
      // `recursive=true, allow_exist=true`.
      let depth = 1;
      let i = m.index + m[0].length;
      let args = "";
      for (; i < text.length; i++) {
        const ch = text[i];
        if (ch === "(") depth++;
        else if (ch === ")") {
          depth--;
          if (depth === 0) break;
        }
        args += ch;
      }
      const positional = [];
      const labels = new Set();
      for (const a of splitParams(args)) {
        const eq = a.text.indexOf("=");
        if (eq >= 0 && !a.text.slice(0, eq).includes("(")) {
          labels.add(a.name);
        } else {
          positional.push(a.name);
        }
      }
      const key = `${alias}.${name}`;
      if (!calls.has(key)) {
        calls.set(key, {
          pkg: PACKAGES[alias].pkg,
          testOnly: PACKAGES[alias].testOnly === true,
          name,
          positional: 0,
          labels: new Set(),
          variant: true,
        });
      }
      const rec = calls.get(key);
      rec.positional = Math.max(rec.positional, positional.length);
      for (const l of labels) rec.labels.add(l);
    }

    // An enum CASE is used without an argument list: `@fs.Directory`. It is
    // still a declaration this module depends on, and it can be renamed or
    // removed just as a function can.
    for (const m of text.matchAll(/@([a-z_][a-z0-9_]*)\.([A-Z][A-Za-z0-9_]*)\b(?!\s*\()/g)) {
      const alias = m[1];
      if (!PACKAGES[alias]) continue;
      const key = `${alias}.${m[2]}`;
      if (!calls.has(key)) {
        calls.set(key, {
          pkg: PACKAGES[alias].pkg,
          testOnly: PACKAGES[alias].testOnly === true,
          name: m[2],
          positional: 0,
          labels: new Set(),
          variant: true,
        });
      }
    }
  }
  return calls;
}

// ------------------------------------------------------------------- main

const failures = [];

const localCores = findLocalCores();
if (!localCores.length) {
  console.error("could not locate any moonbitlang/core on this machine");
  console.error("pass --core <dir> or set LUNAFLOW_CORE_DIR");
  process.exit(2);
}
for (const c of localCores) {
  console.log(`local core:    ${c}  (version ${coreVersion(c)})`);
}

let newest;
try {
  newest = await fetchNewestCore();
} catch (e) {
  console.error(`could not fetch the registry's newest core: ${e.message}`);
  process.exit(2);
}
console.log(`registry core: ${newest.version}`);

const cores = [
  { label: `registry ${newest.version}`, dir: newest.dir },
  ...localCores.map((c) => ({ label: `local ${coreVersion(c)}`, dir: c })),
];

const calls = ourCallSites();
console.log(`call sites:    ${calls.size}\n`);

// How many declarations were compared in EVERY core, split by whether they
// are a dependency of the PUBLISHED library or of the TESTS only.
let libraryCompared = 0;
let testOnlyCompared = 0;
const notes = [];

for (const [key, rec] of [...calls].sort()) {
  const decls = cores.map((core) => ({ label: core.label, decl: findDecl(core.dir, rec.pkg, rec.name) }));

  const absent = decls.filter((d) => !d.decl);
  if (absent.length) {
    if (rec.testOnly) {
      // A TEST-ONLY import: the published library declares no dependency on
      // this package, so a core that does not have it still builds the
      // library. It cannot build this module's TESTS, which is information
      // and not a break in the shipped artefact.
      const note =
        `${key}: not declared in ${absent.map((d) => d.label).join(", ")} — a TEST-ONLY import, ` +
        `so the published library still builds against that core, but this module's tests do not`;
      notes.push(note);
      console.log(`  note ${key} — absent in ${absent.map((d) => d.label).join(", ")} (test-only import)`);
      continue;
    }
    failures.push(`${key}: not declared in ${absent.map((d) => d.label).join(", ")}`);
    console.log(`  FAIL ${key} — absent in ${absent.map((d) => d.label).join(", ")}`);
    continue;
  }

  // A LABEL the module passes is part of the call, and a core that does not
  // declare it breaks the call site even when every TYPE still matches.
  //
  // MEASURED BUG (2026-11-17): this gate used to filter each core's
  // parameters down to the labels the module passes, so a core that had
  // RENAMED one produced a SHORTER signature -- which compared equal to the
  // other cores and read as "identical". The registry's newest core renamed
  // `fs.mkdir`'s `allow_exist` to `allow_existing`, and the release failed on
  // the runner with
  //
  //   This function has no parameter with label allow_exist
  //
  // while this gate had reported "12 declaration(s) identical in every core".
  // The rename was invisible here because the label the module passes was
  // dropped from the signature of the core that no longer had it.
  //
  // So a label the core does not declare is reported as a break, naming the
  // label and the parameters the core DOES declare.
  const missing = decls
    .map(({ label, decl }) => {
      const params = decl.params ?? [];
      return {
        label,
        missing: [...rec.labels].filter((l) => !params.some((p) => p.name === l)).sort(),
        declared: params.map((p) => p.name).join(", "),
      };
    })
    .filter((x) => x.missing.length);
  if (missing.length) {
    for (const x of missing) {
      failures.push(
        `${key}: label(s) ${x.missing.join(", ")} not declared in ${x.label} (declared: ${x.declared})`,
      );
    }
    console.log(`  FAIL ${key} — a label it passes is not declared in every core`);
    for (const x of missing) {
      console.log(`         ${x.label}: no parameter with label ${x.missing.join(", ")} (declared: ${x.declared})`);
    }
    continue;
  }

  // The signature that matters: the parameters this module passes, and the
  // return type.
  const parts = decls.map(({ label, decl }) => {
    if (decl.kind === "enum") return { label, sig: `enum ${decl.enum}::${decl.variant}` };
    if (decl.kind === "using") return { label, sig: `using ${decl.from}` };
    const used = decl.params.filter((p) => rec.labels.has(p.name));
    const pos = decl.params.slice(0, rec.positional);
    return {
      label,
      sig: [
        ...pos.map((p) => p.text),
        ...used.map((p) => p.text),
        decl.ret,
      ].join(" | "),
    };
  });

  const distinct = new Set(parts.map((p) => p.sig));
  if (distinct.size > 1) {
    failures.push(`${key}: ${parts.map((p) => `${p.label}="${p.sig}"`).join(" vs ")}`);
    console.log(`  FAIL ${key}`);
    for (const p of parts) console.log(`         ${p.label}: ${p.sig}`);
    continue;
  }
  if (rec.testOnly) testOnlyCompared += 1;
  else libraryCompared += 1;
  console.log(`  ok   ${key}  ${parts[0].sig}`);
}

if (failures.length) {
  console.error(`\nRESULT: FAIL (${failures.length} incompatible declaration(s))`);
  for (const f of failures) console.error(`  ${f}`);
  console.error("\nThe module has to build against every core version a user may have.");
  process.exit(1);
}

for (const n of notes) console.log(`\nNOTE: ${n}`);

console.log(
  `\nRESULT: PASS (${libraryCompared} declaration(s) identical in every core` +
    (testOnlyCompared ? `, ${testOnlyCompared} test-only declaration(s) identical in every core` : "") +
    `)`,
);
