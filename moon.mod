// LunaFlow — dynamic-first control/data-flow visualizer for mooncakes.io modules.
//
// The analyzer never compiles the module it analyses: it parses the MoonBit
// source it is pointed at, executes a model of it, and writes a Markdown
// report with embedded Mermaid diagrams.
//
// THE ASYNC RUNTIME COMES FROM THE TOOLCHAIN, AND THERE IS NO DEPENDENCY
// BELOW. The runtime is `moonbitlang/core/async`, part of the
// `moonbitlang/core` module the toolchain already bundles, so there is no pin
// here that could disagree with the toolchain that builds the artifact — and
// that disagreement is exactly what broke releases before, when a pinned
// runtime and the host's own copy were two different versions.
//
// The host ABI MODULE NAME did not change: a wasm import's module name comes
// from the FFI declaration in the source, and `moonbitlang/core/async`
// still declares its host externs under the name "moonbitlang/async". What
// changed is the SET of symbols, and the set got BIGGER. The floor is
// therefore a TOOLCHAIN now, and it is higher than it was: a host that still
// carries the standalone `moonbitlang/async` module cannot instantiate this
// artifact, and the failure is "function import requires a callable" at
// instantiation rather than at build time. See the README for the measured
// contract.
//
// `moonbitlang/core/async` is still marked EXPERIMENTAL by the core team, so
// every package that uses it says so in
// `options("allow-experimental-packages": ...)`. That is the other side of
// the same trade: a package that ships with the toolchain but is not yet
// stable.
//
// NATIVE, WASM AND JS. The analyzer needs the filesystem (it reads the
// sources it analyses) and process spawning (it runs `moon fetch`), and the
// async runtime implements both only on native and wasm: on js the `fs` and
// `process` packages compile to nothing. The call sites therefore sit behind
// `#cfg` guards with stubs for the other backends, which is what makes the
// js build real -- the library is checked and its tests run there, not
// skipped.
//
// wasm-gc is NOT supported, and it is not a choice: the core's wasm-gc async
// stub has no `run_async_main`, so `async fn main` cannot compile there at
// all. Naming the supported set makes check/test SKIP that backend instead
// of failing with a wall of errors.
//
// The module coordinate is `riantr/LunaFlow`: `riantr` is the author and
// `LunaFlow` the module. The library package is `riantr/LunaFlow/src/app`,
// the CLI is `riantr/LunaFlow/src/cli`, and the module's ROOT package is the
// executable `moonx` resolves.

name = "riantr/LunaFlow"

version = "0.1.9"

// The file with the real content. The registry publishes this file as the
// module's documentation page.

readme = "README.md"

// Where the source lives. `moon publish` warns
// "'repository' field is not set or empty in module manifest" without it, and
// the registry entry is the only place a reader can get from the package back
// to the code.

repository = "https://github.com/riantr/LunaFlow"

license = "MIT"

keywords = [
  "static-analysis",
  "dynamic-analysis",
  "taint",
  "program-slicing",
  "control-flow",
  "contracts",
  "mermaid",
  "mooncakes",
]

description = "Trace-driven three-proof-strength control-flow, taint, value-range, slicing and contract analysis for MoonBit modules, as one Markdown report with Mermaid diagrams"

// WASM, not native: the registry publishes ONE artifact per version, and
// `moonx` runs the WASM one — `moonx --target` accepts no other value. A
// module whose preferred target is native publishes a native artifact, and
// `moonx <module>@latest` then fails with "Prebuilt wasm asset does not
// exist". The native build is still supported and still what the local QA
// harness runs; it is just not the artifact the registry serves.

preferred_target = "wasm"

supported_targets = "+native+wasm+js"
