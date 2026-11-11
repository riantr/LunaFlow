// The HOST CONTRACT of the published wasm artifact.
//
// The published wasm is not self-contained: it imports symbols from the
// `moonbitlang/async` HOST ABI -- the file IO, the process calls, the event
// loop -- and the HOST has to provide every one of them when the module is
// instantiated. `moonx` provides them from the async runtime bundled with
// the USER's MoonBit toolchain. So the artifact's host requirements are a
// property of the PUBLISHED BYTES, and nothing in the source tree can see
// them.
//
// THE HOST ABI NAME DID NOT CHANGE, AND THAT IS THE SURPRISING PART. The
// runtime moved from the standalone `moonbitlang/async` MODULE into the
// toolchain-bundled `moonbitlang/core` module, so the package path is now
// `moonbitlang/core/async` and there is no dependency to pin. But a wasm
// import's module name comes from the FFI declaration in the SOURCE, and
// `moonbitlang/core/async` still declares its host externs under the ABI name
// "moonbitlang/async" -- measured in the toolchain's own source, every
// `= "moonbitlang/async" "..."` declaration is still there. So the host
// supplies the same MODULE as before; what changed is the SET of symbols, and
// the set got BIGGER.
//
// WHY IT IS MEASURED HERE. The floor is a property of the TOOLCHAIN, not of
// a pinned dependency, so it has to be re-measured whenever the runtime
// moves. This script reads the artifact's own import section -- the bytes
// that are published -- and compares it against the externs the toolchain's
// bundled core declares. The symbols the bundled core does NOT cover are the
// floor: a host that lacks them fails with "function import requires a
// callable" at instantiation, not at build time.
//
// Usage:
//   node scripts/qa/host_requirements.mjs
//   node scripts/qa/host_requirements.mjs --write <contract-file>
//   node scripts/qa/host_requirements.mjs --wasm <path> --core <dir>

import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

// The WASI modules are served by the HOST RUNTIME, not by the toolchain's
// core: `moonrun` and `moonx` implement WASI preview1 themselves.
const WASI_MODULES = new Set(['wasi_snapshot_preview1', 'wasi_unstable']);

// ---------------------------------------------------------------- arguments

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const wasmPath = arg('--wasm', join(ROOT, '_build', 'wasm', 'debug', 'build', 'LunaFlow.wasm'));
const coreDir = arg('--core', findCoreDir());
const writeTo = arg('--write', '');

///| Locate the toolchain's bundled `moonbitlang/core`.
///
/// The floor is a property of the TOOLCHAIN, so the toolchain's own copy is
/// what has to be measured. It is not always at `$HOME/.moon/lib/core`: a
/// toolchain installed elsewhere keeps its core next to its `moon` binary, so
/// that location is tried too.
function findCoreDir() {
  if (process.env.LUNAFLOW_CORE_DIR) return process.env.LUNAFLOW_CORE_DIR;
  const home = process.env.HOME || process.env.USERPROFILE;
  if (home) {
    const p = join(home, '.moon', 'lib', 'core');
    if (existsSync(p)) return p;
  }
  try {
    const which = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['moon'], {
      encoding: 'utf8',
      shell: true,
    });
    const bin = (which.stdout || '')
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean)[0];
    if (bin) {
      const p = resolve(bin, '..', '..', 'lib', 'core');
      if (existsSync(p)) return p;
    }
  } catch {
    // No `moon` on PATH: the caller gets an empty core dir and the check says
    // so, rather than pretending the floor was verified.
  }
  return '';
}

// ------------------------------------------------------- the wasm reader

///| Read the import section of a wasm module: a flat list of triples.
///
/// The reader lives here because the PUBLISHED bytes have to be read exactly
/// the way the local build is read, and one reader is one answer.
function readWasmImports(path) {
  const buf = readFileSync(path);
  if (buf.length < 8) throw new Error(`not a wasm module: ${path}`);
  if (buf[0] !== 0x00 || buf[1] !== 0x61 || buf[2] !== 0x73 || buf[3] !== 0x6d) {
    throw new Error(`not a wasm module: ${path}`);
  }
  let pos = 8;
  const imports = [];

  function leb() {
    let result = 0;
    let shift = 0;
    let b;
    do {
      b = buf[pos++];
      result += (b & 0x7f) * 2 ** shift;
      shift += 7;
    } while (b & 0x80);
    return result;
  }

  function readName() {
    const len = leb();
    const s = buf.toString('utf8', pos, pos + len);
    pos += len;
    return s;
  }

  function skipLimits() {
    const flags = leb();
    leb();
    if (flags & 0x01) leb();
  }

  while (pos < buf.length) {
    const id = buf[pos++];
    const size = leb();
    const end = pos + size;
    if (id === 2) {
      const count = leb();
      for (let i = 0; i < count; i++) {
        const module = readName();
        const name = readName();
        const kind = buf[pos++];
        if (kind === 0) {
          imports.push({ module, name, kind: 'func' });
          leb();
        } else if (kind === 1) {
          imports.push({ module, name, kind: 'table' });
          pos++;
          skipLimits();
        } else if (kind === 2) {
          imports.push({ module, name, kind: 'memory' });
          skipLimits();
        } else {
          imports.push({ module, name, kind: 'global' });
          pos += 2;
        }
      }
    }
    pos = end;
  }
  return imports;
}

// ------------------------------------------------- the toolchain's externs

///| Every extern the bundled core declares, grouped by ABI module name.
///
/// The declaration form in the core source is the FFI form
/// `fn ... = "<module>" "<symbol>"`, so the symbols are read out of the source
/// rather than guessed. The grouping matters: the artifact imports from more
/// than one module, and the floor is over ALL of them.
function readCoreExterns(dir) {
  const found = new Map();
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    let entries;
    try {
      entries = readdirSync(d);
    } catch {
      continue;
    }
    for (const entry of entries) {
      const p = join(d, entry);
      let st;
      try {
        st = statSync(p);
      } catch {
        continue;
      }
      if (st.isDirectory()) {
        stack.push(p);
        continue;
      }
      if (!entry.endsWith('.mbt') && !entry.endsWith('.mbti')) continue;
      let text;
      try {
        text = readFileSync(p, 'utf8');
      } catch {
        continue;
      }
      const re = /=\s*"([^"]+)"\s*"([^"]+)"/g;
      let m;
      while ((m = re.exec(text)) !== null) {
        if (!found.has(m[1])) found.set(m[1], new Set());
        found.get(m[1]).add(m[2]);
      }
    }
  }
  return found;
}

// ------------------------------------------------------------------- main

const failures = [];

if (!existsSync(wasmPath)) {
  console.error(`missing wasm artifact: ${wasmPath}`);
  console.error('build it first: moon build . --target wasm');
  process.exit(2);
}

const imports = readWasmImports(wasmPath);
const funcs = imports.filter((i) => i.kind === 'func');
const modules = [...new Set(imports.map((i) => i.module))].sort();

console.log(`wasm:      ${wasmPath}`);
console.log(`imports:   ${imports.length} total, ${funcs.length} function imports`);
console.log(`modules:   ${modules.join(', ')}`);

const byModule = new Map();
for (const i of funcs) {
  if (!byModule.has(i.module)) byModule.set(i.module, []);
  byModule.get(i.module).push(i.name);
}
for (const [m, names] of [...byModule].sort()) {
  console.log(`  ${m}: ${names.length} function imports`);
}

// The ABI module name has to stay "moonbitlang/async": the host supplies the
// module under that name, and the package path changed, not the ABI name.
const abi = byModule.get('moonbitlang/async');
if (!abi) {
  failures.push('the artifact imports no "moonbitlang/async" functions at all');
}

let uncovered = [];
let wasiImports = [];
let totalCovered = 0;
let totalImports = 0;
if (coreDir) {
  const externs = readCoreExterns(coreDir);
  console.log(`core:      ${coreDir}`);
  const totalExterns = [...externs.values()].reduce((n, s) => n + s.size, 0);
  console.log(`externs:   ${totalExterns} host symbols declared by the bundled core, in ${externs.size} module(s)`);
  uncovered = [];
  for (const [m, names] of [...byModule].sort()) {
    // The WASI imports are the HOST RUNTIME's job, not the core's: `moonrun`
    // and `moonx` implement WASI preview1 themselves, and the core source
    // says nothing about them. Only the core's own extern modules have to be
    // checked against the bundled core.
    if (WASI_MODULES.has(m)) {
      wasiImports.push(...names);
      console.log(`  ${m}: ${names.length} host (WASI, provided by the runtime)`);
      continue;
    }
    const declared = externs.get(m) || new Set();
    const missing = names.filter((n) => !declared.has(n)).sort();
    totalImports += names.length;
    totalCovered += names.length - missing.length;
    const mark = missing.length ? 'UNCOVERED' : 'covered';
    console.log(`  ${m}: ${names.length - missing.length}/${names.length} ${mark}`);
    for (const n of missing) uncovered.push(`${m} ${n}`);
  }
  console.log(`covered:   ${totalCovered}/${totalImports} of the core-extern function imports`);
  if (wasiImports.length) {
    console.log(`wasi:      ${wasiImports.length} import(s) served by the host runtime`);
  }
  if (uncovered.length) {
    console.log(`UNCOVERED (${uncovered.length}) — a host without these fails at instantiation:`);
    for (const n of uncovered) console.log(`  ${n}`);
  }
} else {
  console.log('core:      (not located — pass --core <dir> or set LUNAFLOW_CORE_DIR)');
}

if (writeTo) {
  const lines = [];
  lines.push('# THE HOST CONTRACT OF THE SHIPPED ARTIFACT.');
  lines.push('#');
  lines.push('# Generated by scripts/qa/host_requirements.mjs from the artifact\'s own import');
  lines.push('# section. The published wasm is not self-contained: it imports these symbols');
  lines.push('# from the host ABI, and the HOST has to provide every one of them when the');
  lines.push('# module is instantiated. `moonx` provides them from the async runtime bundled');
  lines.push('# with the USER\'s MoonBit toolchain.');
  lines.push('#');
  lines.push('# The ABI module name is "moonbitlang/async" even though the package path is');
  lines.push('# now "moonbitlang/core/async": the module name comes from the FFI');
  lines.push('# declaration in the source, and the source still declares it that way.');
  lines.push('#');
  // The path is written RELATIVE to the repository root: an absolute path
  // would make the contract different on every machine, and a contract that
  // changes when nothing changed is one nobody reads.
  const relWasm = wasmPath.startsWith(ROOT)
    ? wasmPath.slice(ROOT.length).replace(/\\/g, '/')
    : wasmPath.replace(/\\/g, '/');
  lines.push(`# artifact: ${relWasm}`);
  lines.push(`# function imports: ${funcs.length}`);
  for (const [m, names] of [...byModule].sort()) {
    lines.push(`#   ${m}: ${names.length}`);
  }
  lines.push('');
  for (const [m, names] of [...byModule].sort()) {
    lines.push(`[${m}]`);
    for (const n of names.slice().sort()) lines.push(n);
    lines.push('');
  }
  if (uncovered.length) {
    lines.push('# NOT declared by the toolchain\'s bundled core — the host floor.');
    lines.push('[uncovered]');
    for (const n of uncovered) lines.push(n);
    lines.push('');
  }
  writeFileSync(writeTo, lines.join('\n'), 'utf8');
  console.log(`wrote      ${writeTo}`);
}

if (failures.length || uncovered.length) {
  for (const f of failures) console.error(`FAIL  ${f}`);
  for (const u of uncovered) console.error(`FAIL  not declared by the bundled core: ${u}`);
  console.error(`\nRESULT: FAIL (${failures.length + uncovered.length} failure(s))`);
  process.exit(1);
}

console.log(`\nRESULT: PASS (${funcs.length} function imports, ABI module "moonbitlang/async")`);
