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
// Usage: node scripts/qa/core_compat.mjs

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = resolve(new URL("../../", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const SCRATCH = join(ROOT, "_build", "qa", "core_compat");

// The core packages this module imports, and the alias each is used under.
const PACKAGES = {
  async: "async",
  fs: "async/fs",
  process: "async/process",
  env: "env",
  io: "async/io",
  stdio: "async/stdio",
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
  const extracted = join(probe, ".repos", "moonbitlang", "core", version);
  if (!existsSync(extracted)) throw new Error(`moon fetch did not extract ${extracted}`);
  return { version, dir: extracted };
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
      const name = head.replace(/~$/, "").trim();
      return { name, text: p.replace(/\s+/g, " ") };
    });
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

    const fnRe = new RegExp(
      `^pub (?:async )?fn ${esc}\\s*\\(([\\s\\S]*?)\\)\\s*(->[^\\n{]*)?\\{`,
      "m",
    );
    const fn = text.match(fnRe);
    if (fn) {
      return {
        kind: "fn",
        params: splitParams(fn[1] || ""),
        ret: (fn[2] || "").replace(/\s+/g, " ").trim(),
      };
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
    // Comments are stripped first: a package mentioned in prose is not a call.
    const text = raw.replace(/\/\/[^\n]*/g, "");
    for (const m of text.matchAll(/@([a-z_][a-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
      const alias = m[1];
      if (!PACKAGES[alias]) continue;
      const name = m[2];
      // The argument list: scan to the matching close paren.
      let depth = 0;
      let i = m.index + m[0].length - 1;
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
        calls.set(key, { pkg: PACKAGES[alias], name, positional: 0, labels: new Set(), variant: true });
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
        calls.set(key, { pkg: PACKAGES[alias], name: m[2], positional: 0, labels: new Set(), variant: true });
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

for (const [key, rec] of [...calls].sort()) {
  const decls = cores.map((core) => ({ label: core.label, decl: findDecl(core.dir, rec.pkg, rec.name) }));

  const absent = decls.filter((d) => !d.decl);
  if (absent.length) {
    failures.push(`${key}: not declared in ${absent.map((d) => d.label).join(", ")}`);
    console.log(`  FAIL ${key} — absent in ${absent.map((d) => d.label).join(", ")}`);
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
  console.log(`  ok   ${key}  ${parts[0].sig}`);
}

if (failures.length) {
  console.error(`\nRESULT: FAIL (${failures.length} incompatible declaration(s))`);
  for (const f of failures) console.error(`  ${f}`);
  console.error("\nThe module has to build against every core version a user may have.");
  process.exit(1);
}

console.log(`\nRESULT: PASS (${calls.size} declaration(s) identical in every core)`);
