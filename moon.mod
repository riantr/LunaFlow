// LunaFlow — dynamic-first control/data-flow visualizer for mooncakes.io modules.
//
// The analyzer never compiles the module it analyses: it parses the MoonBit
// source it is pointed at, executes a model of it, and writes a Markdown
// report with embedded Mermaid diagrams. That is why the only dependency is
// `moonbitlang/async`, and why the module is native-only — the async IO,
// process and filesystem packages it needs do not exist on the other backends.
//
// The module coordinate is `riantr/LunaFlow`: `riantr` is the author and
// `LunaFlow` the module. The library package is `riantr/LunaFlow/src/app` and
// the executable is `riantr/LunaFlow/src/cli`; the two differ because a
// `moon.pkg` import carries no version and a `moon.mod` import does.

name = "riantr/LunaFlow"

version = "0.1.0"

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

preferred_target = "native"

supported_targets = "+native"

import {
  "moonbitlang/async@0.22.9",
}
