# LunaFlow (module `riantr/LunaFlow`) — design and method

Dynamic-first control-flow, data-flow, taint, value-range and slicing visualization for MoonBit modules published on [mooncakes.io](https://mooncakes.io/).

This document is the design record for the implementation in `src/app` and `src/cli`. All numbers quoted here were measured on the two required modules and are reproducible with the commands in §10.

---

## 1. Scope and constraints

| Constraint | Decision |
| --- | --- |
| Implementation language | MoonBit (module `riantr/LunaFlow`, native target) |
| Analysis subjects | MoonBit modules hosted on mooncakes.io; first-class validation on `riantr/moonbit_doubleML@latest` and `riantr/moonbit_static_analysis@latest` |
| Analysis paradigm | Dynamic-first: concrete execution of parsed function bodies produces the trace that drives CFG coverage, taint, ranges and slicing; static syntax-directed CFG supplements it |
| Visualization carrier | Markdown with embedded Mermaid diagrams only (no server, no HTML, no binary images) |
| Version policy | `@latest` is resolved once by `moon fetch`, the resolved version is recorded in the report and pinned for every later stage |
| Toolchain | `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, native backend — and the release is verified against the NEWEST toolchain as well (`moon 0.1.20261117`, `moonc v0.10.21+06da1ed44`), because the CI runner installs that one; the async runtime is the toolchain-bundled `moonbitlang/core/async` |

The analyzer never mutates the analyzed module. It reads source files, executes a model of them, and writes only under `reports/`.

### 1.1 The backend matrix

The analyzer needs two things the host provides: the **filesystem** (it reads
the sources it analyses) and **process spawning** (it runs `moon fetch`). The
toolchain's async runtime implements both on native and wasm only — on js and
on wasm-gc the `fs` and `process` packages compile to nothing.

The decision is to keep the analyzer **backend-independent** and push the
filesystem dependence to the edges:

| Package | native | wasm | js | wasm-gc |
| --- | --- | --- | --- | --- |
| `src/app` (library) | yes | yes | yes | yes |
| `src/command` (library) | yes | yes | yes | yes |
| `src/cli` and the root package (executables) | yes | yes | yes | no |

Three rules make that work, and each of them is a consequence of a toolchain
behaviour rather than a preference:

- **`#cfg` guards declarations, not statements.** A call site that cannot
  exist on a backend has to live in a declaration of its own, with a stub
  beside it. That is why the `@fs.mkdir` call in the report writer became a
  helper, `ensure_dir`.
- **Mutable state has to be touched on every backend.** `ScanStats`' counters
  were accumulated by the caller; with the scan stubbed out, the `mut` fields
  went untouched on js and the compiler REJECTED the build. They moved into
  `ScanStats::add_file`, which every backend calls.
- **The command line arrives differently on Node.** `env.args()` is
  `process.argv` there, so the node executable AND the script path come first:
  `[node, script.js, "analyze", ...]`, where every other backend gives
  `[exe, "analyze", ...]`. `cli_args` normalises it.

wasm-gc is excluded from the published set for a different reason: the core's
wasm-gc async stub has no `run_async_main`, so `async fn main` — the only way
to reach the async runtime — cannot compile there. A plain `fn main` may not
call an async function on any backend (`Error: [4149]`).

---

## 2. Architecture

```
src/app/                     one library package (avoids cross-package plumbing)
  model.mbt                  AST, CFG, trace, range, finding, taint, slice model
  util.mbt                   spans, escaping, Mermaid sanitizing, formatting
  lexer.mbt   parser.mbt     MoonBit-subset frontend + function extractor
  cfg.mbt                    CFG construction + dead/unreachable/infinite detection
  value.mbt   interp.mbt     concrete-execution trace engine + input synthesis
  analyze.mbt                dependence graph, taint graph, backward/forward slicing
  abs.mbt                    L2 abstract interpreter (interval/value-set/may-taint)
  contract.mbt               L3 contract parsing, WP-style VCs, three-state prover
  funnel.mbt                 L1 -> L2 -> L3 escalation, dedup, specification gaps
  report.mbt                 Markdown + Mermaid rendering and diagram validation
  scan.mbt    coverage.mbt   module acquisition, manifest parsing, Cobertura import
  *_test.mbt                 223 tests in 20 files
src/cli/main.mbt             async CLI entrypoint; thin, over src/command
fixtures/vuln_demo/          intentionally defective MoonBit package for acceptance
scripts/verify.mjs           dependency-free acceptance checker
reports/                     generated Markdown / JSONL / JSON artifacts
```

Pipeline:

```
coordinate ──moon fetch──▶ .repos/author/module/version
                               │
                               ▼
                  lexer → structural parser → functions + statements + spans
                               │
                 ┌─────────────┴─────────────┐
                 ▼                           ▼
          static CFG builder        concrete executor (4 input trials/function)
                 │                           │
                 │                    trace events (JSONL)
                 │                           │
                 ├───── coverage import ─────┤
                 ▼                           ▼
          dead/unreachable/infinite   ranges, taint graph, dependence graph
                 │                           │
                 └─────────────┬─────────────┘
                               ▼
                 Markdown + Mermaid report (+ trace JSONL + summary JSON)
```

### 2.1 Why one library package

MoonBit requires `@alias.symbol` across package boundaries. Keeping the analyzer in one package (`src/app`) keeps the model types, parser and analyses directly visible to each other; only `src/cli` imports it. This is a deliberate trade-off for a single-binary tool, at the cost of a larger package.

---

## 3. Module acquisition, parsing and version compatibility

### 3.1 Acquisition

`LunaFlow analyze <author>/<module>[@<version>|@latest]` runs:

```
moon fetch <author>/<module>[@<version>] --no-update
```

`moon fetch` materializes the module under `.repos/<author>/<module>/<version>/` from the local mooncakes cache (network is used only when the cache misses). The analyzer then walks that directory, skipping `_build`, `.git`, `.repos`, `target` and `node_modules`.

The version directory is the pin. Every reported location is relative to that directory, so a report can be reproduced by fetching the same version.

### 3.2 `@latest` semantics and pinning

- A bare coordinate (no `@version`) asks the registry for the newest **non-yanked** version; `moon fetch` performs that resolution.
- `@latest` is normalized to the bare coordinate because `moon fetch` rejects a literal `latest` in a version field.
- The resolved version is recorded in report §1 and in the file name (`<author>_<module>_<version>.md`).
- If the caller passes an explicit version, no resolution happens; the report says so.
- The local registry index (`~/.moon/registry/index/user/<author>/<module>.index`) is the source of truth for what "latest" means on this machine. It is refreshed by `moon update`; the report never silently re-resolves during a run.
- The analyzer does **not** resolve the module's transitive dependencies, because it does not compile the target. This is why doubleML (which depends on `sqlite3` and `async`) can be analyzed without a native build. The optional coverage bridge (§5.8) is the only path that needs a working target build.

### 3.3 Extension to arbitrary modules

Everything is coordinate-driven; there is no allow-list. `--dir <path>`, and a
target that is a path, analyze a vendored checkout with the same pipeline. The
only hard limits are:

- files walk limit (`2000`, stated in `load_module`),
- interpreted-function cap (`--max-functions`) — this caps the **L1 dynamic
  layer's entry points**, and therefore the trace. It does **not** cap the
  abstract layer: the L2 analyses the whole module and is bounded by its own
  step budget instead,
- per-function step budget (`2000`),
- the abstract layer's total step budget (twenty times its per-function
  budget). The abstract layer's scope is the module, so it needs a bound on
  the TOTAL work and not only on one function's; the report says how far it
  got, so a truncated analysis is visible rather than silent,
- expression/statement nesting depth (`256`, `MAX_PARSE_DEPTH`). A deeper
  construct is skipped whole and counted as a parse gap (`unsupported_stmts`),
  never parsed on a deeper native stack: before this guard, 5,000 nested `if`
  statements and 2,000 nested parentheses aborted the process with
  `0xC0000409` (STATUS_STACK_BUFFER_OVERRUN) on an untrusted module.

### 3.4 Syntax evolution and frontend coverage

The frontend is a structural parser for the MoonBit subset needed by the analyses, not a full type-checking frontend. Supported: `fn` (including `Type::method` names), parameters and return annotations, `let`/`let mut`, assignments and compound assignments, `if/else if/else`, `guard`, `while`, C-style `for` and `for … in` (including the destructuring `for k, v in entries`), `return`, `break`, `continue`, blocks, `try` bodies, array/tuple literals, struct and record literals, qualified paths (`CART::Leaf`, `Rec::{ … }`), named arguments, calls, method calls, field access, indexing, `if` and `match` expressions, function literals, unary/binary operations, multi-line `#|` strings. Parameterised `test` blocks (`test (b : @bench.T) { … }`) are parsed as functions and named after the parameters they bind.

**`guard` is desugared, and the desugaring is sound.** `guard c else { body }` becomes `if c { } else { body' }`, where `body'` ends in a `return` of the block's last expression — which is what the toolchain does, MEASURED: in a function declared `-> String`, `guard total > 0 else { "0%" }` returns **"0%"** when the condition is false, so the `else` block's value **is** the return value and the else path never falls through. The desugaring only works because the join rule is **symmetric**: a branch that **returns** contributes no join, on either side of the `if`. Without that, the state after `if c { } else { return }` would be joined with a branch that left the function, and the refinement the guard was written to give would be thrown away — which is exactly what happened before this release, and it made the analyser report a division by zero on a divisor a `guard` excludes.

The `#|` string is modelled the way the toolchain builds it, and the semantics were measured **by value** rather than by acceptance -- `moon check` accepts every shape of this construct, so acceptance measures nothing here. `#|` opens the literal, the text after the marker is the first chunk, every following line whose first non-blank characters are `#|` is one more chunk, and the value is the chunks joined with `"\n"`. There is no `|#` terminator (a bare `#` is a lexing error in MoonBit), a bare `#|` line is an **empty chunk** rather than the closer, a chunk is not trimmed, and a blank line inside the literal is skipped. The newline that ends the last chunk line is the statement separator before whatever follows, so it is a token of its own; the newlines between chunk lines are string content.

Unsupported constructs are counted, not hidden: `match` arms, `impl` bodies, functional `for`, and `loop` are recorded as `SUnsupported` / `EvUnsupported` and appear in the CFG as `unsupported: …` nodes. A construct the parser has no rule for at all — an operator it does not model — is folded into the statement it belongs to and counted as unsupported, so it cannot shred itself into statements of its own. Report §2 states statements-understood vs unsupported, so the reader can judge confidence per module. Measured frontend coverage:

| Module | Statements understood | Unsupported | Coverage |
| --- | --- | --- | ---: |
| doubleML 0.164.64 | 29,977 | 281 | **99.07 %** |
| static_analysis 0.4.50 | 15,854 | 738 | **95.55 %** |
| quickcheck 0.15.1 | 1,549 | 355 | **81.3 %** |

The counts fell because the old ones were wrong: the parser shredded every construct it did not model into one statement per fragment, and a shredded fragment ate the closing brace of its function, so whole function bodies were truncated. The coverage number is *lower* than before because the analyzer now says what it does not understand instead of silently shredding it.

The quickcheck row is the newest measurement, and it is the one that moved: against the published 0.1.24 artifact the same tree read **370** functions, **1,519** statements understood, **358** unsupported, **80.9 %** coverage and **5 parse issues**. With `guard` modelled and the parameterised `test` blocks parsed, it reads **375** functions, **1,549** understood, **355** unsupported, **81.3 %** and **0 parse issues** — five more functions, thirty more statements understood, three fewer gaps.

Compatibility strategy: the parser is tolerant (it clamps brace depth and skips unparseable statements) so a new syntax form degrades to an explicit gap instead of aborting the file. When a module's coverage is low, the report says so, and the coverage bridge can still supply compiled-execution evidence.

### 3.5 Property-based tests over the analyzer

A hand-written test states **one case**; a property states the **invariant** once and checks it over generated inputs. The analyzer is the thing most worth testing that way, because its failure mode is a class of defect rather than a single bug: a construct the parser does not model loses its refinement, and the analyzer then reports something the runtime would never do.

Three properties run on every target, driven by the toolchain's own `moonbitlang/core/quickcheck` — the package inside the bundled `moonbitlang/core`, imported **for tests only**, so `moon.mod` keeps its empty import block and the published artifact is byte-identical with and without them:

| Property | Invariant |
|---|---|
| a literal divisor is a division by zero **exactly when the literal is zero** | the generated value decides the expected verdict |
| a guarded divisor is **never** a division by zero, whatever the shape | paired with the unguarded twin, which always is one |
| the analyzer produces a verdict for **every generated shape** | no parse issue, no missing function, no crash |

**MEASURED, and this is why they exist.** Against the **pre-fix** parser (the tree at v0.1.24, before `guard` was modelled) the guarded property **fails**, with a shrunk counterexample `(0, 0)`; against the fixed parser it passes. The hand-written test caught that defect too — what the property adds is coverage of the whole shape space, and a **shrunk** counterexample rather than a written-down one.

Two rules follow from the measurement, and both are enforced by the properties themselves:

- **The generated input must be bounded.** `Arbitrary for Int32` draws from the whole 32-bit range, so a property that sized work from a generated count built a program with billions of statements and **never finished**. Counts are clamped; values are not, because the analyzer reads a literal's value and the whole range is meaningful.
- **The assertion must be paired.** A property that checked only the "must not be reported" half would also pass if the analyzer stopped reporting every division by zero. Each property states both directions.

**Apply when** → Any change to the parser, the abstract layer or the value analysis: the property that covers the changed family is the regression test, and the hand-written case is the minimal reproduction beside it.

---

## 4. Proof-strength levels and funnel

The analyzer exposes three proof strengths over the same parsed program. They are **cumulative**: `--level N` runs levels 1..N, and `--funnel` runs all three and reports what each stage adds.

| Level | Name | Engine | Input model | Result strength | Failure mode |
| --- | --- | --- | --- | --- | --- |
| L1 | Interpreter | concrete execution on the formal interpreter | concrete boundary values, `--trials` trials | observed facts about executed paths | misses unexecuted inputs and paths |
| L2 | Value | abstract interpretation over a value-set / interval domain | whole input sets: `Int` intervals, `Bool`/`String` sets, array-length intervals | exhaustive over the abstract state; may-taint / may-range alarms | false positives from joins, widening and implicit flows |
| L3 | Proof-by-contract | WP-style weakest-precondition VC generation + interval decision | ACSL-style `//@ requires` / `//@ ensures` annotations | `proved` / `failed` / `unknown` per verification condition | needs specifications; interval prover is not an SMT solver |

### 4.1 Level 1 — Interpreter Mode

This is the dynamic-first engine described in §5.3: parse the function, synthesize boundary inputs by annotated type, execute, and record every `def`/`cond`/`index`/`alloc`/`call` event. It clears obvious issues fastest and produces the trace that drives CFG path coverage, dynamic taint, observed ranges and slicing. Its claims are always "observed on these inputs", never "true for all inputs".

### 4.2 Level 2 — Value Mode (abstract interpretation)

Domain (`AbsVal`): `Int` and `Double` intervals, `Bool` as a pair of possible values, bounded `String` sets, array **length** intervals, tuples, `top`/`bottom`. Taint is a **set of sources** — the labels of the parameters whose values may have reached the value (`param:<name>`) — so a may-analysis can say "possibly tainted" *and* say which input was untrusted. The set is finite: it is a subset of the function's parameters, so the join grows to at most one entry per parameter and the widening cannot run away.

State: `Map[var -> AbsCell{value, sources}]`. Transfer functions:

- arithmetic via interval arithmetic with conservative division/modulo;
- comparisons return a `Bool` pair (can-be-true, can-be-false);
- `if`: evaluate the condition, refine the state on the true and false edges (`i >= 0`, `i < n`, `i == k`), execute both branches, join the results; a branch that cannot be taken is reported as unreachable **for the abstract input set**;
- `while` / `for`: iterate to a bounded fixpoint (6 rounds), joining states; from round 3 a widening step pushes growing intervals to the default bound; the loop exit state is refined by the negated condition;
- a comparison against another **variable** narrows the left-hand side by the right-hand side's interval (`i < len` gives `i ≤ len.hi − 1`), so a loop counter is bounded by the bound it is compared against;
- array indexing: tainted index → `TAINT-INDEX` (mode `L2-abstract`, confidence 0.6), and the finding **names the source** — "tainted value from parameter `len` may reach an array index"; interval may exceed `[0, len-1]` → `RANGE-VIOLATION` (0.6 may, 0.95 when the interval proves it); allocation size tainted or possibly negative → `TAINT-ALLOC` / `RANGE-VIOLATION`;
- `assert`/`require`: "may fail" when the condition can be false;
- the taint is **kill-exact**: `let` and `=` kill the variable's taint and re-bind it with the right-hand side's sources, so a tainted value that is overwritten leaves nothing behind.

**There is no implicit flow in this layer.** The L2 used to taint every number a tainted loop condition read, so that `while i < len { a[i] }` was flagged although `i` starts at 0. That was a false claim — the tainted value is the *bound*, and the counter does not carry the bound's taint — and it was **removed** in IFDS Phase 1. What survives it is the honest claim, in the value domain: the counter's value is bounded by the bound, so the index may be out of bounds. The measurement and the falsification are in `docs/qa/IFDS_PHASE1.md`.

Cost: linear in the number of statements × fixpoint rounds; measured 3,321 findings from the 1411 doubleML functions in the same run as L1 (10.1 s total), and 188 findings from the 1422 static_analysis functions (1.6 s total). The step count is the deterministic measure: **185,766** steps on doubleML, against 167,211 before the value domain was repaired — the repair analyses the loop bodies the defective boolean literal used to prune.

**The universe excludes the `test` BLOCKS, and nothing else.** The module as scanned holds every `.mbt` file the scanner found — test files included; the scanner excludes build and vendored trees, not `_test.mbt` — and `ModuleAst::all_funcs()` filters on the **function** (`fn.is_test`), not on the file. So an ordinary helper that lives in a `_test.mbt` file is analysed, and a `test "..." { }` block is not. For a module whose test files are most of its code that is worth stating: **129 of doubleML's 220 `.mbt` files are test files**. What says how much of the output is about test code is the finding split, not the scope line: measured on the committed doubleML artefact, **24 of the 926 findings shown in §5.2 (2.6 %) are in test files**, and every one of them is in a helper (`v120_check_enet`, `count_eq`, `expand_v091_iivm_data`, …), not in a test block.

Precision: sound relative to the abstract semantics, but joins and widening lose path and value precision; the default interval bound (`±1,000,000`) is a practical closure, not the mathematical top. Every L2 finding carries `mode = L2-abstract` so it is never confused with an observed L1 fact.

### 4.3 Level 3 — Proof-by-Contract (WP-style)

Specifications are written as MoonBit comments (ACSL-inspired, adapted because ACSL itself targets C):

```moonbit
//@ requires n >= 0;
//@ requires n < values.length();
//@ ensures 
esult >= 0;
pub fn get_checked(values : Array[Int], n : Int) -> Int {
  values[n]
}
```

Supported clauses: `requires`, `ensures`, `invariant` (treated as an assumption for the function), `assigns` (parsed and recorded). `
esult` is rewritten to an internal `__result` symbol before expression parsing; `
othing` is accepted for `assigns`.

VC generation is a forward symbolic execution with substitution:

- safety VCs: every `a[i]` → `0 <= i && i < a.length()`; every `Array::make(n, _)` → `n >= 0`; every `/` or `%` → divisor `!= 0`; `assert`/`require` → the argument;
- postcondition VCs: at every `return`, and at the tail expression of the function, each `ensures` is substituted with the symbolic result and checked;
- loops and branches: both branches are checked; after a merge or loop, assigned variables are havoced, so any goal depending on them becomes `unknown` unless an invariant supplies the fact.

Decision procedure: conjunctive facts from `requires`/`invariants` are converted into per-name intervals (`x >= c`, `x < c`, `x == c`, and `x < a.length()` as a symbolic key), then each goal conjunct is discharged by (a) syntactic match against a fact or (b) interval arithmetic. Three outcomes are reported honestly: `proved`, `failed`, `unknown`. This is not an SMT-backed WP: `unknown` means "the prover could not decide", not "the program is wrong".

Measured on the fixture: 6 VCs → 2 proved (`get_checked` index bounds, `double` postcondition), 1 failed (`get_negative`, whose precondition `n < 0` contradicts `0 <= n`), 3 unknown (postconditions over array element values, and `get_unsafe`'s missing upper bound). The two target modules contain no `//@` annotations, so L3 reports 0 VCs and lists every escalated function as a specification gap — the honest result for contract-based verification without contracts.

Specified-but-partially-annotated functions are handled per clause: a function
whose only annotations are `//@ invariant` lines also gets VCs (the invariants
enter the fact set as assumptions). Before 2026-11-10 such functions were
skipped entirely, contradicting this section; `Contract::has_spec` now counts
invariants, and the behaviour is pinned by `contract_edges_test.mbt`.

### 4.4 Funnel workflow

```
L1 concrete ── findings ──▶ dedup by (kind, file, line, function) ──▶ L2 abstract
                                                                        │
                              critical functions (any L1/L2 finding) ───┤
                                                                        ▼
                                              L3 contracts on those + all spec-bearing functions
```

Rules:

1. Run L1 first; its findings and trace seed the report.
2. Run L2 next; findings whose `(kind, file, line, function)` already appear in L1 are marked *confirmed*, the rest are *new*. L2 is the exhaustive sweep: it reasons over the whole input abstraction, so it catches branches L1 never executed.
3. Escalate to L3 only the functions with at least one L1/L2 finding, plus every function that already carries a contract. Functions escalated without a contract are reported as **specification gaps** — the funnel's explicit to-do list. In a module with no annotations (both validation targets), L3 correctly produces zero VCs and lists the gaps rather than pretending to prove anything.
4. The funnel diagram and table are always rendered in report §3; the numbers are computed, not narrated.

### 4.5 Soundness and cost ladder

| Level | Claim | False positives | False negatives | Cost |
| --- | --- | --- | --- | --- |
| L1 | "observed on these inputs" | none for observed values (it happened) | unexecuted inputs/paths | trials × steps |
| L2 | "the abstract state cannot exclude it" | joins, widening, implicit loop taint | abstraction gaps (e.g. `match`) | statements × fixpoint rounds |
| L3 | "preconditions entail the VC" | only if specs are wrong | `unknown` results are not proofs | VCs × prover steps |

## 5. Analysis engines

### 5.1 Control-flow graph

`build_cfg(func)` emits nodes for entry/exit, statements, branch heads, loop heads, merge points and dead statements. Edges are `seq`, `true`, `false`, `back`.

- `if`: branch node with `true`/`false` edges to the first node of each arm; both arms converging produce a merge node; a `return` in both arms terminates the block and marks following statements dead.
- `while`: loop head with `true` back into the body, body end `back` to the head, `false` to an after-loop merge. A constant-`true` condition without `break`/`return` produces **no exit edge** — unless the body holds a construct the parser does not model, in which case a `break` may be hidden inside it and the loop is **not** proven infinite.
- `for`: init → head → body → back to head; `for … in` is modelled as a head with a body.
- `return`/`break`/`continue`: jump nodes; the block is terminated; subsequent statements are emitted as `dead` nodes.

Mermaid rendering uses `flowchart TD`, a distinct shape per node kind and `classDef` colours (entry green, exit red, branch yellow, loop purple, merge grey, dead grey, statement blue). Every node label carries the statement text; every table entry carries `file:line`.

### 5.2 Mapping execution traces to the CFG; path coverage

Each trace event carries `(function, file, line, statement-id)`. Mapping is by `(function, line)` onto CFG nodes:

- a statement event marks its node executed;
- a condition event marks the branch and the taken edge;
- a loop event marks the back edge.

A report shows the observed path for the top-complexity function as the ordered sequence of `kind@line` events from trial 0. Coverage is **exact for the executed trials and silent for everything else** — absence of a hit is never reported as dead code unless it is also statically unreachable.

### 5.3 Concrete execution ("dynamic" engine)

The interpreter evaluates parsed statements with a small value domain (`Int`, `Double`, `Bool`, `String`, `Char`, `Array`, tuple, unknown). Unknown calls yield `unknown` and taint the result if any argument is tainted.

Input synthesis: for each entry function, parameters get boundary values by annotated type (`Int` → −1, 0, 1, 2, 5; `String` → empty, ASCII, path-traversal-like, 64-byte; arrays → empty/one/three/two-element variants; `Bool` → false/true; unknown → unknown). The cartesian product is capped by `--trials` (default 8; validation runs use 4).

Every parameter is a **taint source** at entry (`EvSource`). Each executed statement emits events:

| Event | Meaning |
| --- | --- |
| `enter` | function entered (trial) |
| `source` | parameter value enters the function |
| `def` | variable/return value defined (value, taint, read set) |
| `cond` | branch/loop condition evaluated (value, taint) |
| `index` | array index expression evaluated (index value, taint) |
| `alloc` | `Array::make` size evaluated |
| `loop` | loop iteration completed |
| `call` | call site (callee, argument count, taint) |
| `abort`, `budget`, `unsupported` | abort path, step budget, parser gap |

Budgets: 2000 steps per trial, 64 iterations per loop, 6 frames of call depth, 150 interpreted functions by default. A budget hit is reported with `BUDGET-EXCEEDED`, not as a proof of non-termination.

**Implicit flows.** When a loop condition is tainted, numeric variables read by that condition are marked tainted (control dependence). This is what lets `while i < len { buffer[i] }` report a tainted index even though `i` is initialized to `0`. It is deliberately conservative; see §5.5 for the precision cost.

**This is the DYNAMIC layer's rule, and the abstract layer does not have it.** The L2 used to carry the same rule — it was called the *blanket loop rule* — and IFDS Phase 1 removed it, because the claim it makes is false: the tainted value is the loop's *bound*, and the counter does not carry the bound's taint. The dynamic layer keeps its rule because it reports what it *observed* on a concrete path, where a tainted condition really did control the loop. `docs/qa/IFDS_PHASE1.md` has the measurement.

### 5.4 Dead code, unreachable code and infinite loops

| Signal | Method | Rule | Confidence | Known limitation |
| --- | --- | --- | --- | --- |
| Dead code | static | statements after an unconditional `return`/`break`/`continue` in the same block | 0.95 | a parser gap can end a block early |
| Unreachable | static | CFG node with no incoming edge (excluding entry/exit) | 0.90 | merges created for constant-false conditions |
| Infinite loop | static | loop head has a `back` edge and no `false` exit edge | 0.75 | a loop whose exit depends on an unmodelled call will be mislabelled — so a body with an unmodelled construct is **not** called infinite at all |
| Non-termination | dynamic | iteration cap reached on a constant-true loop | 0.70 | bounded budgets cannot prove divergence; a body with an unmodelled construct is not reported |
| Uncovered code | dynamic/coverage | line with zero hits in the imported suite | n/a (evidence) | not executing code is not proof it is dead |

False positives/negatives are stated per rule rather than claimed away. The validation fixture pins the static rules: `unreachable_demo` yields exactly two dead statements and `spin` yields one infinite-loop finding (`src/app/cfg_test.mbt`).

### 5.5 Data flow and taint

Sources (default): every parameter of an entry function; additionally `@env.args(...)` when it appears in the parsed body (`EvSource` with `argv`).

Propagation rules:

1. assignment / `let`: the defined value inherits the taint of every variable read by the right-hand side (`def` events record the read set);
2. call: arguments are evaluated; if the callee is a parsed function it is interpreted, so parameter taint flows into the callee and the return value carries the callee's result taint; if unknown, the result is tainted iff any argument is;
3. containers: reading `a[i]` inherits the array's taint; writing `a[i] = v` makes `a` tainted if `v` is; element-level identity is *not* tracked (index-insensitive);
4. `length()` inherits receiver taint;
5. implicit control dependence: tainted loop condition taints numeric loop variables (see §5.3). This rule is the **dynamic** layer's; the abstract layer does not have it — see §4.2;
6. string operations are coarse: `to_string` propagates taint; char-level operations are unknown.

Sinks:

| Sink | Rule | Finding |
| --- | --- | --- |
| array/buffer index | index expression whose value is tainted | `TAINT-INDEX`, error, 0.8 |
| allocation size | `Array::make` / `FixedArray::make` size tainted | `TAINT-ALLOC`, error, 0.8 |
| abort/panic | tainted argument reaches `abort`/`panic` | recorded as `abort` event |
| out-of-range observed index | concrete index outside array bounds | `RANGE-VIOLATION`, warning, 1.0 |

MoonBit has no raw pointer arithmetic; "pointer" sinks in the TrustInSoft sense are represented by array indexing and `Ref` values. `Ref` reads/writes currently degrade to unknown (documented limitation).

Imprecision: field-insensitive, container-index-insensitive, no alias analysis, depth-6 call cutoff, unsupported `match` arms break propagation, and the conservative loop-counter rule can produce false positives. On the validation modules this yields 118 sinks (doubleML) and 9 (static_analysis) — the count is the number of distinct sites, since one site observed in many trials is one sink — high by design because every parameter is treated as hostile input; the report exposes the rule and the observed value for triage.

### 5.6 Value ranges

Representation:

- per variable per function: `RangeStat { min, max, count, values[] }`, the union over all trials (explicit merge in `Ranges::merge_from`);
- per program point: every `def` event is keyed `(function, line, variable)`, so report §6.1 lists observed values at the exact defining line;
- the raw stream is the JSONL trace, which carries every `(line, stmt, name, value, trial)`.

Theory: this is **runtime sampling**, not abstract interpretation. An interval-domain abstract interpretation (Frama-C value analysis, TrustInSoft) computes a fixpoint that covers *all* inputs and is sound; runtime sampling yields a finite union of observed values and is unsound but cheap and precise on what it sees. The report states this explicitly. Numeric ranges are stored as `Double`, with the original textual samples retained; the interval is the min/max of samples, and `samples` is the observation count.

Cost: linear in events; negligible compared to execution (see §8).

### 5.7 The evolved value analysis (EVA)

The value analysis above asks ONE question about a value: *what is its range?*
The **evolved value analysis** asks the second question, and it is the one a
defect actually turns on: **what happens when this value is USED?**

It is not a separate engine. EVA rides on the L2 fixpoint and asks the extra
questions in the same places the values are computed, so it costs one pass,
not two. The facts it keeps are per-name and flow-sensitive:

| Fact | What it is | Why it is needed |
|---|---|---|
| `none` | the name's value may be `None` | `None.unwrap()` is MoonBit's null dereference |
| `width` | the name's integer type: the bit count, negative for unsigned | MoonBit's `Int` is **32-bit** and `Int64` is 64-bit, so the overflow bound is the TYPE's bound |
| `uninit_len` / `uninit_set` | an `UninitializedArray`'s slot count and the indices written into it | a read before the write is an indeterminate value |
| `loop_depth` | how deep the analysis is inside a loop | a write inside a loop makes the written set unbounded, so a later read cannot be called uninitialized |

The facts are JOINED with the abstract state, branch by branch. That is not a
detail: the idiomatic mutable Option is

```moonbit
let mut x : Int32? = None
if flag { x = Some(1) } else { x = Some(2) }
x.unwrap()
```

and a monotone accumulation reports it as a None dereference, because `None`
went in. It is not one: `x` is `Some` on both paths out. The join is of the
two BRANCHES and not of the branches and the state before them, so a fact that
was true before the `if` and false on both branches is false after it.

**The classes, and what MoonBit actually does.** The request that motivated
this was the classic C memory-safety taxonomy, and MoonBit is not a C-like
language, so every class had to be mapped against the real toolchain rather
than assumed. Every row below was settled by RUNNING it:

| The class | What MoonBit does | The family | Engine |
|---|---|---|---|
| buffer overflow | `Buffer` grows, so there is no fixed capacity to overflow | `INDEX-OOB` | EVA |
| out-of-bounds read/write | `a[5]` on three elements is `RuntimeError: unreachable` at `Array::at`; so is `a[-1]` | `INDEX-OOB` | EVA |
| integer overflow | arithmetic **WRAPS silently**: `Int::MAX_VALUE + 1` is `Int::MIN_VALUE` | `INTEGER-OVERFLOW` | EVA |
| division by zero | `100 / 0` is `RuntimeError: divide by zero`; `100 % 0` is `remainder by zero` | `DIVISION-BY-ZERO` | EVA |
| null pointer dereference | no null pointers; `None.unwrap()` is `RuntimeError: unreachable` | `NONE-DEREF` | EVA |
| uninitialized memory read | an `UninitializedArray` element read before `set` is indeterminate, and does NOT panic | `UNINITIALIZED-READ` | EVA |
| use-after-free | no raw pointers; the collector owns the storage; values are immutable | RESERVED | — |
| illegal pointer arithmetic | no pointer type in safe MoonBit | RESERVED | — |
| memory leak | the collector reclaims unreachable storage; there is no manual free | RESERVED | — |
| format string | no format strings exist; the language interpolates with a typed syntax and the core has no printf | RESERVED | — |
| invalid type cast | `as` is a trait-object downcast only; `Double::to_int` **saturates** silently | `INVALID-CAST` | EVA |

The RESERVED families are in the roster so that `--explain` can answer for
them, and their contracts say why they never fire. Omitting them would read
as "this tool does not look for that", which is a different claim from "that
cannot happen here".

**The domain's interval arithmetic had to change to make the overflow check
sound.** The abstract domain's integer interval is 32 bits wide, and MoonBit's
own arithmetic wraps — so an interval computed in the domain wrapped to a
WRONG bound, and a wrong bound downstream is a false finding somewhere else.
The domain now computes in 64 bits and CLAMPS to the type's range, and the
overflow check reports the overflow that caused it.

**The index class is proved by an interval and FILED as an evolved finding.**
The out-of-bounds check is the interval comparison the abstract domain already
computes — the array's length and the index's range are both known, so the
comparison covers the whole input abstraction rather than one observed
execution. What is new is where the finding is filed: it carries the mode
`L2-EVA` and the report lists it in §5.3 with the other evolved value
findings, because an index is a value USED to address storage. A self-check
with the published 0.1.10 over LunaFlow's own source found the opposite: the
class was in the roster as an evolved family, but the finding was filed with
the mode `L2-abstract` and landed in §5.2, so the section that documents what
the EVA covers listed five of its six classes.

**What it costs.** One pass, no new engine: the EVA checks are six
expressions in the existing evaluation. The measured cost on LunaFlow's own
source is inside the noise of the run.

### 5.8 Optional compiled-coverage bridge

Mermaid does not need a compiler, but real compiled evidence strengthens the dynamic story. `parse_cobertura` reads a Cobertura XML produced by:

```
moon coverage analyze -- -f summary
moon coverage report -f cobertura -o cov.xml
LunaFlow analyze <coord> --coverage cov.xml
```

The `-- -f summary` is not decoration for a module that uses a **reserved word**:
the default report format (`simp_caret`) is the only one that **parses** the
covered sources, and the reporter's own lexer reserves a few identifiers the
MoonBit compiler accepts (`method`, `abstract`). A module that uses one of them
makes the default format fail with *"cannot parse source file '…': N lexical
error(s)"*, and then no coverage data is produced at all. This module's own tree
avoids them (§7.2), so the bare `moon coverage analyze` works here; the other
**8 of the 9** formats read the same data without parsing the source, so the
bridge above works for every module.

Hit counts are mapped onto CFG nodes by `(file, line)`; report §3.4 shows per-function node coverage and every zero-hit line is labelled *uncovered by the observed suite*, never *dead*. A Cobertura fixture is unit-tested (`pipeline_test.mbt`). This bridge requires the target to build; it is optional so heavy modules remain analyzable.

### 5.9 Program slicing

The dynamic dependence graph is built from trace events:

- a node per `(function, event-kind, statement, line)` (the kind is part of the key so a parameter source and a statement on the same line do not collide);
- an edge `previous def of v → current event` for every variable in the event's read set;
- edge labels: `data` for definitions, `use` for conditions/index/call/return.

`slice_graph(graph, ast, criterion, direction, cap)` supports:

| Criterion | Meaning |
| --- | --- |
| `<var>@<function>` | slice on variable `var` inside `function` |
| `<function>:<line>` | slice on the event at that line |
| `<var>` | every occurrence of the name (may span several functions) |

Backward slicing walks incoming edges to sources; forward slicing walks outgoing edges to sinks/returns. The seed is the matching definition/index/condition node. To make the demonstration robust against `--max-functions` caps, the CLI detects `@<function>` and additionally interprets that function before slicing.

Precision: exact for the recorded execution, including values and the concrete path; it is *not* a static closure, so an unexecuted branch contributes nothing. Cost: graph construction is O(events), traversal O(V+E) capped at `--max-slice`.

Ambiguity: MoonBit function names are not package-qualified in the trace. `render_reports` exists in three packages of `moonbit_static_analysis`; a name-only criterion intentionally matches all three. Use `--function` to disambiguate.

### 5.10 The memory layout model

The request behind this section was a hardware memory model: stack, heap, global
region and physical addresses; per-architecture word size, alignment, endianness
and memory maps; MMIO registers and address spaces; and a guarantee that no
conclusion depends on the layout of one lucky run. **MoonBit has none of the
hardware**, and that was measured against the toolchain rather than assumed:

| The question | What the toolchain says |
|---|---|
| A pointer type? | No — no `unsafe_ptr`, no `Pointer`, no address arithmetic in the core. |
| An address space? | No — no MMIO, no physical address, no `mmap`. |
| The target's word size? | No — `Int` is 32 bits on native *and* on wasm (it wraps after 2^30 on both); the toolchain's Why3 prelude pins the same range. |
| The machine's byte order? | No — only `_be` and `_le` variants exist, so the program chooses the order. |
| Layout introspection? | No — no `size_of`, no `align_of`, no reflection. |
| An ARM or RISC-V target? | No — the targets are `wasm`, `wasm-gc`, `js`, `native`, `llvm`. |

What is left is the **placement** question, and it has a real answer:

- **The global region.** Top-level `let` and `const` bindings are parsed and the
  region is evaluated ONCE, in **dependency** order, because MoonBit resolves
  top-level bindings by dependency and not by file order. A top-level binding is
  **immutable** — `let mut` at the top level is a parse error (E3002) — so a
  global is a constant of the module. The values are computed outside the
  trials, so a global's value does not depend on the sampled input.
- **The allocation classes.** Every allocation site is classified by a static
  escape analysis: **global** (bound to a top-level name), **frame** (created in
  a function and never leaves it), **heap** (returned, stored into another
  object, or handed to a call the analyzer cannot see into) and **foreign** (from
  outside the analysed module). Two escape rules are easy to get wrong and are
  pinned by the fixture: a method call's **receiver** is not an escape
  (`a.set(0, 7)` mutates in place), while a call **nested inside** a larger
  expression hands its arguments over (`consume(b) + x`).
- **The tail value.** A MoonBit function body's value is its last
  **expression**. The analyzer returned Unit for every such function, which hid
  the globals behind them; the tail value is now the function's value, looked up
  by the statement's id so the expression is not evaluated twice.
- **The layout-stability self-check.** `--stability` re-runs the analysis at
  several sample sizes and compares the findings row by row. The abstract
  layer's findings do not depend on the sample — they are a may-analysis over
  the whole input abstraction, not a sample of it — and the observed layer's
  do. Measured on this module's own source: the `TAINT-INDEX-RANGE` class
  appears in **0 of 4** re-sampled runs and only in the main one, so it is a
  property of the sample and the report says so.

Cost: the global region is one pass over the globals, the allocation classes
are a static pass over the AST, and the stability check costs one extra
interpreter run per sample size — which is why it is opt-in.

### 5.11 The foreign address space

§5.10 modelled the MoonBit side of the memory story. This section models the
**other** side: the address space the C code lives in, and the isolation
between it and the MoonBit value space.

MoonBit has **no addresses at all** — no pointer type, no address arithmetic,
no address space. So the foreign address space is not something the language
has; it is something that exists on the other side of the C boundary. Every
property of it was MEASURED against the toolchain:

| The question | What the toolchain says |
|---|---|
| The C form? | `extern "C" fn name(args) -> Ret = "c_symbol"`, and the `= "c_symbol"` part is **required** (E4140/E3002 without it). |
| Which targets take it? | **native only**: the wasm backend rejects `extern "C"` (E4156), and native rejects a *module import* (`fn f() = "pkg" "path"`) with the same code. |
| `#external type T`? | An **opaque** type; natively a GC-managed external object (`moonbit_make_external_object(finalize, payload_size)` in the toolchain's `moonbit.h`), so the **payload belongs to the C side**. |
| How a `String` crosses? | As `uint16_t *` (`moonbit_string_t`) — the C side receives the **address** of a MoonBit heap object. A `Bytes` crosses as `uint8_t *`. |
| How the scalars cross? | By value: `Int` as a 32-bit signed integer, `Int64` as 64 bits, `Double` as a C `double` in a **floating-point register**. |
| An 8-bit integer? | **No.** `Int8`/`UInt8` do not exist; `Int16`/`UInt16` do. |
| Who owns a pointer parameter? | The toolchain **refuses** one without `#borrow(x)`/`#owned(x)` (E0055) and says the current default — `#owned` — "will be changed in the future". |
| Is the annotation enforced? | **No.** Using an `#owned` argument after the call compiles clean. |
| Are two claims about one C symbol caught? | **No.** The C function has ONE prototype, and two declarations of the same symbol with different signatures compile clean. |

**The model.** Two spaces: the **MoonBit** one (the reference-counted heap,
the global region, the frame) and the **foreign** one (what the C code owns,
plus the payload of an external object). The **declared type** decides which
side a value lands on:

| Declared type | Space |
|---|---|
| `Int`, `Int32`, `Int64`, `UInt`, `UInt16`, `UInt32`, `UInt64`, `Double`, `Float`, `Bool`, `Char` | **value** — copied by value |
| `String`, `StringView`, `Bytes`, `Array`, `FixedArray`, `Option`, `Result`, `Map`, a user's `struct`, an `enum` that carries a field, a plain opaque `type` | **heap pointer** — the address of a MoonBit object |
| `#external type T` | **foreign address** — the payload belongs to the C side |
| a fieldless `enum`, a tuple | **value** |

The pointer set is not guessed: it is exactly the set the toolchain's own
E0055 fires for, measured one type at a time.

**The findings** are filed under their own method, `L2-FFI`, in report §5.7,
and each family states its own limits:

| Code | What it asserts | What the toolchain does |
|---|---|---|
| `FFI-SIGNATURE-CONFLICT` | one C symbol, two MoonBit signatures | **does not notice** |
| `FFI-USE-AFTER-MOVE` | an `#owned` argument used after the call | **does not enforce** |
| `FFI-UNANNOTATED-OWNERSHIP` | a pointer parameter relies on the current default | errors (E0055) |
| `FFI-TARGET-MISMATCH` | the published target cannot build the declaration | errors (E4156) |
| `FFI-ADDRESS-UNKNOWN` | a slot the module pins at one site and computes at another | — |
| `FFI-ADDRESS-CONFLICT` | one constant reaches two C symbols | — |

A `#cfg(target = "native")` guard is respected, so a module that declares a C
extern behind one and publishes for wasm is **not** reported: the declaration
is not part of that build.

**What the model does not claim.** The analyzer does not claim that an integer
argument to a C function is an address — it may be an address, a length or a
plain value, and nothing in the MoonBit source says which. The named-address
table therefore reports the *constants* that cross the boundary, with the
symbols they reach and the other constants they travel with, and the two
address families state their assumption in the finding text. A `#borrow`
cannot be checked at all: the C side is invisible to the analyzer, and the
compiler does not enforce it either.

Cost: one static pass over the AST, plus one classification pass over the
declarations.

### 5.12 The concurrency model

§5.10 modelled where a value lives and §5.11 the address space on the other
side of the C boundary. This section models the **third** thing: what happens
when more than one **task** runs.

Every property of MoonBit's concurrency was MEASURED against the toolchain,
not read off a document. The measurements are what the model is built on:

| The question | What the toolchain says |
|---|---|
| Do tasks run MoonBit code on several OS threads? | **No.** A spin-lock whose spin loop contains no `await` **HANGS**: the spinner printed its marker and the second task never printed at all, because it never got to run. |
| Then what does the thread pool do? | The pool (`with_event_loop(..., max_worker_count = 1024)`) executes the **blocking I/O**; the coroutine waits on the event-loop thread. |
| Where does a task yield? | **Only at an await point.** The await points are the core's async API (`sleep`, `all`, `any`, `acquire`, `wait`, `with_timeout`, …), a call to the module's own `async fn`, and a package-qualified read or write. |
| Does a read-modify-write lose an update? | **Only when an await point is inside it.** Measured: 8 tasks × 200 000 increments with no await = exactly 1 600 000 counted; a read-**await**-write over a shared `Ref[Int]` lost **21 000 of 24 000** updates — and the same interleaving every run. |
| Does the runtime detect a deadlock? | `set_deadlock_handler` fires when there is no pending event and **every** task is blocked. It caught the ABBA case. It does **not** fire for a busy-wait: one task spinning while another is blocked hangs **silently**. |
| What does `Ref::update` do? | `self.val = f(self.val)` — a **non-atomic** read-modify-write. |

**The defect class is therefore interleaving sensitivity, not a thread-level
data race.** MoonBit has no thread-level data race between two tasks, because
there is no second thread running MoonBit code. Saying otherwise would be a
claim the toolchain does not support; the report says *interleaving
sensitivity* instead.

That is also why the model is a **state-space** model and not a sampling one:
the interleaving space is finite and reproducible, so a conflict can be
*found* rather than waited for.

**The model.**

| Piece | What it is |
|---|---|
| **Task** | a closure handed to a spawn API (`spawn`, `spawn_bg`, `spawn_loop`, `with_task_group`, `all`, `any`). The closure literal is parsed into a **function of its own**, so the body is available to walk. |
| **Instance** | a closure written **inside a loop** is created once per iteration, so its body may be running more than once at the same time. Two instances of the same body conflict exactly as two different tasks would. |
| **Shared cell** | a `Ref` a task **captures** from the function that spawned it, or is handed as a `Ref` parameter. The cell is keyed by the function that binds it, so two functions that each bind `counter` are two cells. A `Ref` the task creates for itself is **private** to that task. |
| **Await point** | a call that may suspend. The yield count along a path is what separates a read from the write that follows it. |
| **Lock** | a `Mutex`. An acquire adds a *waits for* edge; the locks held before it add the *holds while wanting* edge that is the resource-ordering graph. |
| **Overlap** | two tasks may interleave only if their owners are the same function or one calls the other. Two functions that never call each other cannot interleave, so a conflict between them is not a conflict. |

**The findings** are filed under their own method, `L2-CONC`, in report §5.8:

| Code | What it asserts |
|---|---|
| `CONC-RACE-LOST-UPDATE` | a task reads a shared cell and writes it back after an await point, and another writer of that cell can run at the same time — so the write is not atomic with its read and the update can be lost |
| `CONC-RACE-STALE-READ` | a task reads a shared cell, the value is used after an await point, and another task writes that cell without a common lock |
| `CONC-DEADLOCK-CYCLE` | the tasks take the locks in a circular order — each holds a lock the next one wants — so none of them can proceed |
| `CONC-RESOURCE-UNRELEASED` | a lock is acquired and not released on that path, so every later acquire of it waits forever |

**What the model does not claim.** It does not claim a thread-level data race.
It does not model a release on another path, a resource that is not a lock (a
semaphore's permits are counted, not waited on), a closure handed to anything
other than a spawn API, a `Ref` reached through a field or a container, or
anything on the C side of a boundary. Report §5.8.5 lists all of it.

Cost: one static pass over the AST for the tasks, one over each task body for
the accesses, and one over the edges for the cycles.

### 5.13 The IPC and buffer model

§5.11 modelled the address space on the other side of the **C** boundary. This
section models the boundary MoonBit has with **itself**: the IPC that goes
through the core's `BinaryReader` and `BinaryWriter` traits — sockets, pipes
and process stdio.

The contract of those traits is not something the language enforces, so it has
to be measured before it can be checked. Every row below was produced by
running the core:

| The question | What the core says |
|---|---|
| Can a read fill the whole buffer? | **No.** `read_into(dst)` returns the number of bytes it read, and that number can be smaller than the buffer. Measured: a 16-byte buffer pre-filled with `0xFF`, a pipe with 3 bytes in it, one `read_into` → returned **3**, and the buffer afterwards was `61 62 63 FF FF FF … FF`. The bytes past the count were **never written**. |
| Who advances the offset? | The caller. Measured: `read_into(buf, offset=8)` returned 3 and wrote at `buf[8..11]`; `buf[0..8)` was untouched. |
| What does the end of the stream look like? | `read_into` returns **0** and `read()` returns **None**. So `0` is both "no progress" and "the stream ended". |
| How long is a peeked view good for? | Until the next operation on the same reader. The core says so — "the caller of `peek` MUST NOT use the returned slice after any other `BinaryReader` operation" — because the reader keeps **one** buffer and reuses it. Measured: peeked `61 62 63`; after two `read()` calls the **same view** read `78 79 7A`. |
| Can a write come back short? | **No.** `write` is **exhaustive**: it loops until every byte has been handed over. Measured: 5 bytes written and read 2 at a time → 5 bytes in 3 reads. So there is **no partial-write defect** at the `write` level, and this model does not claim one. |
| Is a pending write a snapshot of the buffer? | **No.** Measured: a 4-byte buffer of 'A' handed to `write`, then overwritten with 'B' while the write was still pending → the reader received `42 42 42 42`, the 'B's, not the 'A's that were in the buffer when the write was issued. |

**The model.**

| Piece | What it is |
|---|---|
| **Reader / writer** | a value the module reads from or writes to. The analyzer matches the **method name** — it does not infer types — so the core's API names (`read_into`, `read`, `read_exactly`, `peek`, `write`, …) are what it sees. |
| **Discarded count** | a reader call whose result is thrown away. MoonBit does not let a value be dropped silently, so this is `ignore(reader.read_into(buf))` or `let _ = reader.read_into(buf)`, and both are the same defect. |
| **View** | the result of `peek`, `peek_at_least` or `peek_exactly`: a window into the reader's own buffer, valid only until the next operation on that reader. A `peek` is only a view when the analyzer can SEE the value **used as one** — passed to a `BytesView` parameter, handed to the core's writer, or copied with a method only a view has. |
| **Shared buffer** | a buffer a task body writes and the function that started the task also uses. The buffer is **captured** — the task body uses it and does not bind it. |
| **Base name** | the variable a buffer expression stands for: `buf`, `buf[0]` and `buf.unsafe_reinterpret_as_bytes()` are all the buffer `buf`. |

**Why the view needs EVIDENCE.** `peek` is a common name: a parser has one
and it returns a **token**, not a view. Matching the name alone reported
every one of the analyzer's own `peek` results — **four** distinct views,
**thirteen** findings — on its own source. The evidence rule removes them all
and keeps the real one: the analyzer's own source now reports **zero** IPC
findings, and the fixture reports exactly its four.

**The view is reported ONCE.** A name holds one view: a new binding of it
replaces the old one, and a stale view that is used twice is one finding and
not two.

**The findings** are filed under their own method, `L2-IPC`, in report §5.9:

| Code | What it asserts |
|---|---|
| `IPC-PARTIAL-READ` | a read's count is discarded and the buffer is then used, so the bytes past the count are the bytes that were there before |
| `IPC-READ-EOF` | a loop reads until the stream ends with the count discarded, so the loop cannot see the end |
| `IPC-VIEW-STALE` | a view into a reader's buffer is read after the reader has reused that buffer, so the bytes it shows are not the bytes that were read |
| `IPC-BUFFER-SHARED` | a buffer is written by a task and used by the function that started it, so the two writes can land in the same bytes |

**The C boundary gains three families** in the same release, because the
question was asked about the C side too. The C source is not visible, so a
**release is recognised by the symbol's name** — and the contract says so, so
the limit is stated rather than implied.

| Code | What it asserts |
|---|---|
| `FFI-DOUBLE-FREE` | the same object is handed to a C function that frees it, twice, so the C side frees memory it no longer owns |
| `FFI-USE-AFTER-FREE` | an object the C side has freed is used afterwards, so the use reads memory the allocator may already have handed to someone else |
| `FFI-LENGTH-MISMATCH` | a C call is given an object and a length that is not that object's length, so the C side may read or write outside the object |

The **pointer-type set** was measured one type at a time, and `BytesView` was
added to it after a measurement: an `extern "C" fn takes_view(v : BytesView)`
trips the toolchain's own **E0055** exactly as a `Bytes` parameter does. A
`BytesView` that crosses the boundary is an address, and it needs the same
ownership annotation.

**What the model does not claim.** It does not claim a reader the analyzer
does not recognise by name, a length that comes **from** the stream and sizes
an allocation (the taint families are where a source has to be declared for
that), a buffer reached through a field or a container, a view that was
**copied** (`to_owned()` makes a copy, and a copy is not a view), a count that
is used but an offset that is **not** advanced, or the C side of a socket.
Report §5.9.4 lists all of it.

Cost: one static pass over the AST for the calls, one over each function body
for the discarded counts and the views, and one over the closures for the
shared buffers.

### 5.14 The range loop, the index/length relation, and the abstract layer's precision

§5.6 modelled an integer's range and §4.2 the abstract domain over it. This
section is about the **precision** of that domain, and it starts from a defect the
self-check found on the analyzer's **own source**: **two** out-of-bounds findings,
**both** of them false positives, both of them inside a `for i in 0..<n` loop.

**The root cause was the frontend, not the analysis.** The lexer emitted `..` and
`<` as **two tokens**, so the parser never saw a range. The `for` loop degraded
to an iterator of `0`, the **loop body was left behind**, and its statements
became statements of the enclosing function. The guard that said the index was
inside the array was in that body, so it never reached the abstract state, the
index could not be narrowed, and the index was reported as out of bounds.

The range's semantics are the toolchain's, and they were measured rather than
assumed:

| The question | What the toolchain says |
|---|---|
| What does `0..<3` yield? | 0, 1, 2. MEASURED. |
| What does `0..<=3` yield? | 0, 1, 2, 3. MEASURED. |
| Is the end evaluated once? | Yes. MEASURED: a call in the end position is called **once**, not once per iteration. |
| Where may a range appear? | Only in a `for .. in` loop — error **4137**: *"Range operators are currently only supported in `for .. in` loops."* |

**The model.**

| Piece | What it is |
|---|---|
| **The range** | `ExprKind::ERange(start, end, inclusive)` — a first-class expression, so the exclusive and the inclusive form stay apart. The blast radius was measured: **two** exhaustive `match e.kind` sites, not a hundred. |
| **The lexer** | `..<` and `..<=` are lexed as **one** operator, checked before the two-character table; `..` stays the fallback. |
| **The parser** | the range is read in every `for .. in` form — parenthesised, plain and destructuring — and the body is **kept**. |
| **The interpreter** | the loop runs its **real** trip count, and the bound is evaluated **once**. |
| **The binder** | the range's interval: `[start, end-1]` when the end is exclusive, `[start, end]` when it is inclusive. When the end is **not** a number the analysis could compute, the trip count is not known — but the start is, and the binder keeps it. |
| **The relation** | the index/length relation: "this index is below that array's length". |

**Why the relation is its own fact.** The abstract domain's intervals cannot say
"this index is below that array's length". The two intervals are independent
numbers — the index's upper bound and the length's lower bound — so comparing
them says the index MAY be past the end even when the code says it cannot be.
That is how `for i in 0..<xs.length() { xs[i] }` came to be reported as an
out-of-bounds access when the range's own definition says the index is below the
length. The relation is kept as its own fact, in the state's environment under a
key no source name can have, and it is set in three places that all say the same
thing:

- a comparison that says so — `i < xs.length()`;
- the **false** side of a comparison that says the opposite — `if i >= xs.length()
  { return }` leaves `i < xs.length()` behind;
- a **range** whose end is that length — `for i in 0..<xs.length()`.

It is dropped when the index is bound again (it may be a different number now) or
when the array it names is bound again, it survives a join only when it holds on
**both** sides, and an assignment that only makes the index **smaller**
(`i = i - k`) keeps it.

**Four more defects of the same family**, all found by the same self-check:

| Defect | What it did | The fix |
|---|---|---|
| a comparison of two **overlapping** intervals | `x < 0` with `x` in `[-1000000, 1000000]` read as **impossible**: both branches were "unreachable" and the code after them was analysed as dead | a comparison can hold when the smallest left value is below the largest right one, and can fail when the largest left value reaches the smallest right one |
| the **widening** of a loop variable | a counter that starts at 0 lost its lower bound, so an index that cannot be negative became one that might be | only the bound that **moved** goes to the top; the other one stays where it was |
| the state after a branch that **returns** | the state after `if cond { return }` was a **join** with a branch that left the function, so the narrowing the guard was written to give was thrown away | the state after the `if` is the **false** branch's state |
| the same rule on the **other** side | the state after `if cond { … } else { return }` was joined with the branch that left the function, so a `guard` — which desugars to exactly that shape — lost its refinement | the rule is **symmetric**: a branch that returns contributes no join, so the state after the `if` is the **then** branch's state |
| an index **inside** an array | the index's interval and the array's length interval are independent numbers | the relation above |

**And the loop model itself was wrong in two ways.** The body of a `for .. in`
loop was analysed on the loop's **own** state, so a body that grows an array
(`arr.push(x)`) **erased** the fact that the loop may run **zero** times; and the
body was analysed **once**, so an array the loop grows looked like it had exactly
**one** element — and every refinement of that length was then wrong. Both are
fixed: the body is analysed on a **copy** of the loop's entry state, once **per
iteration**, with the state joined and widened between the iterations, the way a
`while` loop is analysed.

**A tainted index is only claimed when the container is known to be an array.** The
tainted-index rule claims that "a tainted value may reach an array index or a
buffer offset". That claim needs the container to **be** an array: the analyzer
reads a container's type from its **declared** type, and a **field** of a struct
is opaque to it — the frontend does not carry a struct's field types. A container
it cannot see may well be a **Map**, where the index is a **key**: a key cannot
be out of bounds, and it is not an offset that untrusted input chose. The dynamic
layer sees the container's **runtime** type and files the witnessed claim; the
abstract layer files the may-claim only where it can stand behind the words
"array index".

**The proof that nothing else moved.** The **local build** and the **published
0.1.18** were both run over the **same** tree. Every summary number is the same
(45 files, 816 functions, 9 497 events, 2/1/3 VCs, 0 dead, 5 taint sinks) with one
difference in the statements — 5 528 → **5 569** — and it is the point: the new
parser understands **41 more statements** in the old tree, because a range loop's
body is no longer left behind. The findings: **47** rows become **23**, and every
one of the 24 that went away was a false positive — 21 `UNREACHABLE`, 2
`INDEX-OOB` and 1 `TAINT-INDEX` the dynamic layer had already reported at the
same line. **Nothing new appears.**

**What the model does not claim.** It does not claim a range outside a `for ..
in` loop (the toolchain does not allow one), a trip count it cannot compute, an
index that is below the length of an array the analyzer cannot name, or a
tainted index into a container whose type it cannot see.

Cost: one token in the lexer, one expression form in the parser, one interval in
the abstract layer, and one relation in the state's environment.

### 5.15 The classes safe MoonBit cannot express, and the C boundary can

§5.7 modelled the C boundary. §5.15 is about the **four defect classes** the
boundary makes real and the MoonBit side cannot, and about the two **defects**
the self-check found while they were being added.

**The classes.** The evolved value analysis (§5.3) reserves four families:
`USE-AFTER-FREE`, `MEMORY-LEAK`, `POINTER-ARITHMETIC` and `FORMAT-STRING`. The
reservation is not a claim that the classes do not exist — it is a claim that
**safe MoonBit cannot express them**:

| The class | Why safe MoonBit cannot express it |
|---|---|
| `USE-AFTER-FREE` | there is no raw pointer, the collector owns the storage, and values are immutable — there is nothing to free and nothing to dangle |
| `MEMORY-LEAK` | the collector reclaims unreachable storage and there is no manual `free` |
| `POINTER-ARITHMETIC` | there is no pointer type in the core, so there is no pointer arithmetic to be illegal |
| `FORMAT-STRING` | the language interpolates with a typed syntax and the core has no printf-style formatting, so no string is ever *interpreted* as a format |

All four are **real** across a C boundary. A C function allocates, frees,
interprets a format, and takes an address — and the analyzer can see the
**MoonBit** side of every one of those calls. The four new families report them
from there:

| The reserved class | The family at the boundary | What the analyzer can see |
|---|---|---|
| `MEMORY-LEAK` | `FFI-ALLOCATION-NOT-RELEASED` | the module received an allocation and never handed it to anything that frees |
| `FORMAT-STRING` | `FFI-FORMAT-STRING` | the module put a string it did not write out into a slot the C side interprets |
| `POINTER-ARITHMETIC` | `FFI-ADDRESS-OOB` | the module computed an address past the end of a region it carved |
| `USE-AFTER-FREE` | `FFI-DOUBLE-FREE`, `FFI-USE-AFTER-FREE`, `FFI-USE-AFTER-MOVE` | the module gave the same object to a freeing function twice, used one after it was freed, or used one it gave away |

The reserved contracts keep their wording and now **name** the family that
covers their class at the boundary, so `--explain MEMORY-LEAK` answers the
question a reader is actually asking rather than only saying "not applicable".

**The bargain, stated once.** The C source is not visible, so the **name** is
all the analyzer has — the same bargain the release list and the length slot
already make. Each rule is therefore two conditions, not one:

| The thing | The name says | The type says |
|---|---|---|
| an **allocation** | `alloc`, `mmap`, `create`, `reserve`, `open`, `obtain`, `acquire` | it returns an **address**: an `#external` type (one by construction) or an integer (which may be one) |
| a **release** | `free`, `release`, `destroy`, `dispose`, `dealloc`, `finalize`, `close` | the slot is a pointer or the foreign type the allocator returned |
| a **format slot** | `fmt`, `format`, `template`, `spec`, `pattern` | the slot holds a `String` or a `Bytes` |
| a **region** | the size is in the slot named like a length (`len`, `size`, `count`, `n`) | both the base and the size are **constants** |

The type condition is what keeps `map_page` out of the allocator set: it is a
foreign address, but its name is not an allocator's name. The **integer** return
is the weaker case — a function called `created_at` that returns an `Int32` is
not an allocation on the strength of its name alone — so an integer return has
to be one of the allocator names proper.

**The format rule is GCC's.** `-Wformat-security` warns about a format
parameter with **no other argument after it**: a function that takes more
arguments is almost certainly using its format properly, and the analyzer does
not claim it. The value has to come from **outside** the function that makes
the call, which is the analyzer's proxy for "untrusted" — the FFI model is a
static pass over the AST and has no taint of its own, and the contract says so.

**The MoonBit-side answer to `MEMORY-LEAK`** is `UNBOUNDED-GROWTH`. The
collector makes a leak inexpressible, but one shape survives it: a
**module-level collection** (a top-level `let`, which lives for as long as the
module does) that is only ever **added** to, inside a **loop whose trip count
the analyzer cannot bound**. Nothing in the module ever removes an element from
it, and nothing ever replaces it with a fresh one, so it holds every element it
is given. What is **not** claimed: a collection that is trimmed somewhere, a
**local** collection (it dies with the function that made it), and a collection
filled in a loop the analyzer **can** bound.

**Two defects, both found by the analyzer's own source.**

*One defect was reported once per visit.* The FFI walk descends into nested
statements itself, and the collector it used descended as well — so a statement
inside an `if` was visited **twice**, and a double free there was reported
**three** times, at three different lines. The collector is now the one that
does **not** descend, and the descent is the walk's job alone. The probe
`fixtures/ffi_demo`'s flat double free and its nested one now report the same
number of rows.

*The index/length relation could hold only ONE length.* §5.14's relation says
"this index is below that array's length", and it was stored as **one** array
name per index. But an index can be below several lengths at once: `for i in
0..<xs.length()` says the index is below `xs`'s length, and a guard `if i >=
other.length() { continue }` says it is below `other`'s length **too**. The
second guard **overwrote** the first, so an index that was provably inside the
array it indexes was reported as an offset that untrusted input chose. The
relation now holds the whole **set**, and a join keeps the **intersection** of
its two sides — which is the right rule, because a relation that holds on one
side of a branch and not on the other does not hold after it.

**The proof that nothing else moved.** The **local build** and the **published
0.1.19** were run over the **same** trees, and the finding sets were compared
row by row: over **LunaFlow's own tree**, 2 rows go away (the two false
positives above) and 4 appear (one per new family, each on the fixture's defect
half); over `riantr/moonbit_doubleML@0.164.64` (**220 files**, 319 rows) and
`riantr/moonbit_static_analysis@0.4.50` (**239 files**, 20 rows), **not one row
moves**. The new families do not fire on a module with no C boundary and no
unbounded collection, and the relation fix does not change what the analyzer
says about them.

**What the model does not claim.** It does not claim that the C side leaked:
the analyzer cannot see whether the C function freed the allocation by itself,
so `FFI-ALLOCATION-NOT-RELEASED` is a **may**-claim and a warning. It does not
claim a format slot the module filled with its **own** text, or a C function
with another argument after the format. It does not claim an address whose
base or whose offset is **computed** at run time, or a region whose size was
not a constant. It does not claim an allocation the module **hands on** —
returned, or stored into another object — because whoever holds it now owns it.

Cost: four families, two AST walks (both skipped when the module has no C
boundary and no globals), one relation that grew from one array name to a set.

### 5.16 The peer cross-check, and what it does and does not prove

The cross-check is not a formality. `riantr/moonbit_static_analysis` was run over
this module's own source, and the two tools were compared on the same tree. This
section records what that comparison establishes, because a cross-check that is
reported without its error rate is not evidence.

**What the peer found.** 14 actionable findings over 59 files. **One was real**:
`conc_cycles(edges, tasks, reach)` was handed the task list and never read it. The
MoonBit compiler said the same thing independently (`unused_value`), which is the
cross-check that mattered — two independent tools, one conclusion. The parameter and
its argument are gone, and the results are unchanged: the self-scan is 31 rows before
and after, and the three committed artefacts regenerate byte-identically.

**What the peer's other 13 findings were, and why 10 of them are its limit rather
than a defect here.** The peer does not model `#cfg`. A module that defines a name
twice — once for the native/wasm backends and once as a stub for the others — has two
definitions of that name, and the peer binds the name to **one** of them. The
consequences are systematic, and they are not defects in the analysed module:

| what the peer reports | why it is wrong here |
|---|---|
| `ArgTypeMismatch` — "expected 5, got 6" | the native/wasm definition has **6** parameters and the js stub has **5**; the peer bound the name to the stub |
| `UnusedParam` on the stub's parameters | the stub's body is **empty**, and the parameter exists in the *other* definition |

The claim was established by a probe, not by inference: a 25-line file with two `#cfg`
definitions of one name reproduces *"too many arguments to 'gated': expected 1, got 2"*
exactly.

**The other three were the fixtures' own defects.** `fixtures/eva_demo/lib.mbt` holds
deliberate defects — `100 / 0` at line 44 and `a[-1]` at line 65 — and the peer finds
both, at the identical file, line and column LunaFlow reports them at. The peer's
`DeadStore` at line 138 is *literally* true (the initial `None` is overwritten on both
branches before it is read) but is **outside the fixture's stated contract**, which is
about the **unwrap** being safe; LunaFlow correctly reports nothing there. A fixture
that exists to prove a case must not be "fixed" to satisfy a tool.

**What the peer cannot do at all.** It parses **46 of 49** of this module's `.mbt`
files; LunaFlow parses **49 of 49**. Each gap is pinned to a construct and reproduced
by a minimal probe: a block string with bare `#|` continuation lines (`expected ')'`),
a `for` whose pattern is on the next line (``unexpected token `,` ``), and a tuple
pattern in a `for` header (`expected loop variable`).

**The method, stated so it can be repeated.** The peer is run from the **repository
root**, because it resolves `.repos/` relative to the current working directory and
fails with *"cannot locate source for target"* from anywhere else. Its coordinate
target works from the root. Every peer finding was then checked against the source
by reading it, and every claim about the peer's own behaviour was checked by a
**minimal probe** rather than by reasoning about the peer's implementation.

**And the direction that matters is reciprocal.** The peer over its own module
(0.4.50, 257 files) reports **0 actionable** findings; LunaFlow over the same module
reports **20 rows**. Neither tool invents a defect on the other's code.

Cost: one peer run per release, plus a probe file per disputed claim.

---

## 6. Visualization

### 6.1 Report structure

1. Acquisition and version pinning
2. Ingestion statistics (files, functions, statements, unsupported, coverage, parse issues, trace size, wall time)
3. Control-flow analysis — CFG diagrams, observed paths, findings, static-vs-dynamic attribution, optional imported coverage
4. Data flow and taint — taint Mermaid graph, sink table
5. Value ranges — per-program-point observations (5.1), per-function union (5.2)
6. Program slicing — per criterion: Mermaid dependence graph + statement table
7. Method summary
8. Reproduction commands

The report also carries the evolved value analysis (5.3), the global region
(5.4), the allocation classes (5.5), the layout-stability self-check (5.6), the
foreign address space (5.7), the concurrency model (5.8), the IPC and
buffer model (5.9) and the classes the C boundary makes real (5.15).

### 6.2 Mermaid conventions

| Diagram | Type | Node conventions | Edge conventions |
| --- | --- | --- | --- |
| CFG | `flowchart TD` | `n{id}(["entry"])`, `["stmt"]`, `{"if cond"}`, `{{"while cond"}}`, `("merge")`, `[["dead: …"]]`; `classDef` per kind | `-->` sequential, `-->|true|`, `-->|false|`, `-.->|back|` |
| Taint | `flowchart LR` | `t{id}["source: p"]`, `["x = …"]`, `[["index: a[i]"]]` | `-->|propagates|`, `-->|reaches-sink|` |
| Slice | `flowchart TD` | `s{id}["stmt L53: …"]`, `src`/`sink` label prefixes | `-->|data|`, `-->|use|` |

Labels are sanitized: quotes → `#quot;`, angle brackets → `#lt;`/`#gt;`, pipes → `&#124;`, whitespace collapsed, 90-character cap. No raw newline is ever embedded in a diagram. `validate_mermaid` checks the header, quote parity and bracket balance per line; it is unit-tested (`pipeline_test.mbt`).

### 6.3 Granularity and readability limits

| Limit | Default | Rationale |
| --- | --- | --- |
| CFG diagrams | 8 (top cyclomatic complexity) | beyond that, the report becomes a wall of arrows |
| CFG nodes per diagram | 90; larger functions omit the diagram but keep findings | a 100-node Mermaid graph is unreadable in a Markdown viewer |
| Taint nodes | 40 | keeps source→sink chains legible |
| Slice nodes | 40 (render cap), 160 traversal cap | same |
| Observed path events | 24 | shows the shape without the full 1000-event stream |
| Per-point range rows | 300 | bounded table |
| Findings rows | 300 | bounded table; the count table above it states the family mix of the WHOLE set, and the findings the table does not show are in the report's `_findings.jsonl` sidecar, so the bound costs no finding |
| Files walked | 2,000 | stated in the report if the cap is hit |
| Syntactic nesting depth | 256 | beyond this the construct is a recorded parse gap; protects the native stack on hostile input |
| CFG window | 600 functions, in file order | disclosed and configurable (`--max-cfg-functions`); the report states how many functions the flow pass was given and how many it could not reach, and the denominator is the **analysable** universe — the functions that are not test blocks — not the scanner's count, which includes them |

Interaction is intentionally file-based: the CLI produces Markdown that GitHub/GitLab/VS Code render; Mermaid blocks are also extracted by `scripts/verify.mjs`. Source locations are in every label and table row; the JSONL trace allows programmatic drill-down to any event.

---

## 7. Engineering and performance

### 7.1 CLI

```
LunaFlow [analyze] [<target>]
  [--out <dir>] [--trials <n>] [--max-functions <n>]
  [--level <1|2|3>] [--funnel]
  [--function <fn>] [--slice <crit>] [--forward|--backward]
  [--coverage <cobertura.xml>] [--max-cfg <n>] [--max-taint <n>]
  [--max-slice <n>] [--list-functions] [--quiet]
  [--exclude <name>]... [--families <codes>] [--exclude-families <codes>]
  [--explain <code>] [--explain-all] [--metrics] [--per-function]
```

The **target slot** follows the peer analyzer's rule, so the two tools take the
same invocation:

| Target | What it is | What happens |
| --- | --- | --- |
| `author/module[@version]` | a coordinate | fetched through `moon fetch`, then analysed |
| `./path`, `/abs/path`, `C:\path` | a path | analysed where it stands |
| nothing | the default | the current directory is analysed |

`--dir <path>` still names a tree and `analyze` is still accepted as a
subcommand; both are kept because they are in the published documentation and
in every QA harness. A target that LOOKS like a coordinate (`fixtures/x`) is
resolved as one, which is the peer's rule too — a local path needs the `./`.

The **option surface** now matches the peer's as well. The five options below
were added in 0.1.9, and each of them follows the peer's semantics:

| Option | What it does |
| --- | --- |
| `--exclude <name>` | skip a directory NAME while walking; repeatable. The built-in skip list (`_build`, `.git`, `.mooncakes`, `.repos`, `target`, `node_modules`) always applies |
| `--families <codes>` | report ONLY these finding families, by the CODE the report shows (`DEAD-CODE`, `TAINT-INDEX`, …) |
| `--exclude-families <codes>` | report everything EXCEPT these families; same code vocabulary, same rules |
| `--explain <code>` | print one family's contract — property, assumption, exclusions — and STOP |
| `--explain-all` | print the roster of every family and STOP |
| `--metrics` | print the ADEQUACY block: what was read, understood, entered and found, each with its own coverage |
| `--per-function` | enter EVERY function as an entry point, with the `--max-functions` cap lifted |

**A CONTRACT REQUEST IS NOT A SCAN.** `--explain` and `--explain-all` answer
before the profile is validated and before any file is read, so they need no
target and cannot be broken by the tree they are run in.

**Two profile rules, and they are the peer's.** A code the roster does not know
is a WARNING and the scan still runs; a code in both the include and the
exclude set is an ERROR and the scan does not run at all — the two rules
contradict each other, and which one won would otherwise be an accident of the
order of two `if`s.

The families are addressed by the finding's own report code rather than by a
second identifier layer. The peer's ids are `MSA-NNN`; the stability rule is
the same either way — a code is never renamed — but a code the reader already
sees on the finding's row is one less thing to look up.

`--per-function` has no module-mode counterpart here: LunaFlow's L1 already
enters functions rather than executing module-level statements, so the
counterpart of the peer's toggle is the `--max-functions` cap, and the option
lifts it. The cost is real — measured on `riantr/moonbit_doubleML@0.164.64`
(2,529 functions), 9.2 s capped against 127.9 s uncapped, 193,906 trace events
against 2,069,372 — so it stays opt-in.

Outputs, all deterministic except `elapsed_ms`:

- `<author>_<module>_<version>.md` — the report;
- `..._trace.jsonl` — one JSON object per event (`k`, `fn`, `file`, `line`, `stmt`, `name`, `value`, `tainted`, `trial`, `detail`);
- `..._summary.json` — machine-readable counts for CI gates.

`--list-functions` prints `FUNCTION<TAB>FILE<TAB>STATEMENTS` so a slice criterion can be chosen without guessing.

### 7.2 Measured performance (native, Windows 11, warm cache)

The **committed artefacts**, regenerated with the release recipe in §7.2 of the
README — `--funnel --trials 4` and one slice each, with **no** `--max-functions`
cap:

| Module | Files | Statements | L1 events | L2 findings | L3 proved/failed/unknown | Dead | Taint sinks | Wall time | Report | Trace |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| doubleML 0.164.64 | 220 | 30,258 | 243,528 | **3,321** | 0 / 0 / 0 (no specs) | 0 | 195 | **10.1 s** | **384 KB** | 37.6 MB |
| static_analysis 0.5.0 | 254 | 17,450 | 17,029 | **188** | 0 / 0 / 0 (no specs) | 0 | 9 | **1.6 s** | **149 KB** | 2.5 MB |
| fixtures/vuln_demo | 1 | 32 | 604 | 15 | 2 / 1 / 3 | 3 | 8 | 4 ms | 35 KB | 79 KB |

Sizes are in **KB = 1024 bytes**, against a 512 KB limit, so the doubleML report
(392,781 B) sits at **75 %** of A12. The L2 column moved from 187 / 8 to 1,282 / 184
because the abstract layer's scope stopped being the interpreter's entry-point cap
and became the whole module, then to **3,305 / 190** because the five dead
`::`-spelled rules were repaired (the allocation family could not fire at all)
and the de-duplication key was given the file it had been omitting, and then to
**3,321 / 188** because the value domain was repaired: a boolean **literal** was
modelled as a value that can be neither true nor false, and the contradiction
pruned the branches it guarded. The repair brought the findings the pruned
branches hid back and took the false positives the same defect produced away.

**The L1 event and trace columns moved too, and the reason is the repair, not
the taint.** The allocation rule records an `EvAlloc` event for every
allocation it sees, and the rule was dead before — so repairing it added
**5,624** trace events on doubleML (237,904 → 243,528) and the trace grew
from 36.8 MB to 37.6 MB, still inside the 64 MB cap. The **other two artefacts'
event counts did not move at all**: the static-analysis module is still 17,029
and the fixture still 604.

**The cap is not part of the recipe, and adding it moves the dynamic layer's
numbers.** With `--max-functions 120` the doubleML run produces **198,182** trace
events; without it, **243,528**. The committed artefacts are the **no-cap** run, and
re-running the recipe with the current build reproduces all three of them
**byte-identically** — traces included; only the reports' wall time differs.

The statement counts fell and the dead-code column emptied because the old
numbers were wrong: the parser shredded every construct it did not model into
one statement per fragment, and a shredded fragment ate the closing brace of
its function, so whole function bodies were truncated. Neither module has an
unreachable statement, and the analyzer now says so. The event count rose
because the analyzer understands more of the module and explores more paths.

Memory is dominated by the trace array (one record per event, ~150–250 bytes) and the parsed AST; both are linear in the caps. The 37.6 MB JSONL for doubleML is deliberate: it is the audit evidence. A production deployment should cap `--trials`/`--max-functions` or stream events to disk.

Deep-QA measurements (2026-11-11, `scripts/qa/load.mjs`, `scripts/qa/e2e.mjs`, `scripts/qa/metrics.mjs`):

| Measurement | Value |
| --- | --- |
| doubleML full run (`@latest` → 0.164.64), wall time | 8.5–9 s |
| doubleML full run, peak working set (sampled) | 295.9 MB |
| doubleML full run, trace size / events | 69.6 MB / 448,001 (default `--trials 8`) |
| doubleML with a `--max-functions 120` cap (`--trials 4`, no slice) | 193,906 events, 85 sinks, 0 dead, 9.2 s — re-measured on 2026-11-20 with the slice: **198,182** events |
| fixture run, peak working set | 7.5 MB |
| 4 concurrent doubleML runs vs sequential | 1,392 ms vs 5,145 ms (**3.70×**, no failures) |
| LunaFlow's own line coverage (`moon coverage`, `src/app` scope) | **57.35 %** (4,052 / 7,065 coverable lines of `src/app`) |

The coverage row is the **2026-11-18** measurement, re-taken on a CLEAN trace set
with `moon coverage analyze -p src/app -- -f caret` followed by
`moon coverage report -p src/app -f cobertura`; two independent test runs produced
the same **4,052 / 7,065**. The older **44.25 %** row was a defect in the QA ROUTE,
not a property of the tree, and the footnote that excused it was wrong twice.

The first failure — *"invalid source range in 'src/cli/main.mbt'"* — was a **stale
build tree**, not a source defect. `_build/native` still held the `.trace.source`
files of the **2026-11-10** build, written when the module was called
`moonflow/moonflow` and `src/cli/main.mbt` still held the whole CLI: 368 coverage
points, every one of them invalid, the first at line 23 of a file that now has ten
lines. The reporter discovers trace sources **recursively from the current
directory**, so any stale trace under the repository poisons every run, and
`moon coverage clean` does **not** remove them. Moving that tree out of the
repository fixed it and the Cobertura route then worked — so the old claim that
*"the Cobertura route fails"* was false.

The second failure was real, and it was **this tree's**, not the tooling's: the
default report format, `simp_caret`, is the only one that lexes and parses the
source, and the reporter's frontend (`moon_cove@0.3.6`, which pins
`moonbitlang/lexer@0.4.4`) **reserves** identifiers the MoonBit compiler
accepts. `src/app/eva.mbt` (a parameter named `method`) reported **2 lexical
errors**, `src/app/report.mbt` (the `abstract` field of `ReportInput`) **1**, and
`src/command/command.mbt` (the same field in a struct literal) **1**. The three
identifiers are **renamed** — `method` became `conv_method`, and the field became
`abstract_result`, the name the QA report had already asked for — so
`moon coverage analyze` now runs with the **default** format, exit 0, and the
whole tree parses. The compiler had been warning about `abstract` since the QA
pass; the coverage tooling is simply stricter.

`scripts/qa/coverage_route.mjs` keeps it that way, and CI runs it. It fails on a
reserved identifier and on a **stale trace tree** — a `.trace.source` written
before the module was renamed, which makes every report fail with *"invalid
source range"* — and it is falsified against both failure modes, so it is a gate
and not a decoration. The other **8 of the 9** formats read the same data
without parsing the source — `bisect`, `caret`, `summary`, `full_summary`,
`sorted_summary`, `cobertura`, `html`, `coveralls` — so a module that *does* use
a reserved word still has a route: *"use -f caret to report coverage without
parsing"*.

Peak memory is ≈5× the trace size, because the JSONL is materialised as one
String before it is written. That is the same argument as §11 item 4: stream the
trace instead of buffering it.

### 7.3 Scalability

- Parsing and CFG building are linear in tokens/statements; doubleML's 220 files parse and analyze in ~1 s before execution.
- Execution cost is `functions × trials × steps`; the caps make the worst case bounded (120 × 8 × 2000 = 1.92 M steps).
- Mermaid size is bounded by the caps in §6.3; a 10k-function module would still produce a fixed-size report (top 8 CFGs) with counts for the rest.
- The `.repos` cache makes repeat runs offline; module fetching is the only network step.

---

## 8. Comparison with related tools

| Tool / approach | Basis | Precision (FP / FN) | Scalability | Cost | Explainability | Fit for MoonBit |
| --- | --- | --- | --- | --- | --- | --- |
| **TrustInSoft Analyzer / Frama-C** | sound abstract interpretation + SMT, ACSL contracts, C | very low FP on covered properties, but requires contracts; FN from unsupported C and missing specs | medium; whole-program, expensive | high (minutes–hours, memory) | proof obligations, alarms, but steep | none (C only) |
| **Joern** | static code property graph, multi-language, queries (CPGQL) | static may-analysis: FP from aliasing/paths, FN from reflection/dynamic dispatch | high (index once, query fast) | medium index time | graph + query, no runtime values | no MoonBit frontend |
| **CodeQL** | compiled relational database + Datalog queries | high precision on typed languages; FP/FN depend on query; no runtime values | very high for large repos (DB build) | high build cost | excellent query traceability, steep learning curve | no MoonBit extractor |
| **SVF** | pointer analysis on LLVM IR (SVF/Andersen) | precise points-to; FP when unresolved indirect calls | medium; LLVM IR required | medium | pointer graphs, not source-level prose | no MoonBit backend |
| **Soot** | Java bytecode IR (Jimple), static data-flow | good for Java; FP from reflection/native; no runtime | medium | medium | IR-level | no MoonBit |
| **LunaFlow (this work)** | structural frontend + concrete execution + coverage import | *unsound by design*: no FP proof, but observed paths/values are exact; FN for unexecuted code and unsupported `match`/closures; conservative loop-counter taint adds FP | high: no build of target, linear passes, bounded caps | low: seconds, single native binary | high: every claim is tied to a trace event and a `file:line`, rendered as Mermaid | native (parses MoonBit directly) |

Interpretation:

- Against TrustInSoft/Frama-C, the trade is **soundness for reachability**: TIS proves properties over all inputs but needs ACSL specs and a C frontend; LunaFlow shows what actually happened for synthesized inputs, with no annotations, on MoonBit source. TIS is the right tool when a proof is required; LunaFlow is the right tool when a developer needs to see a path, a taint chain and a slice in seconds.
- Against Joern/CodeQL, the trade is **static closure for runtime evidence**: those tools answer "can this happen on any path?" (with aliasing approximations); LunaFlow answers "did this happen on these inputs, and through which values?" and avoids database construction. CodeQL/Joern scale to very large repos better; LunaFlow's caps and single-package design favor modules, which is exactly the mooncakes.io unit.
- Against SVF/Soot, MoonBit has no LLVM/Java IR in this pipeline; the array-index/allocation sink model replaces pointer arithmetic, and the GC removes ownership/alias complexity that those tools must model.

---

## 9. Applicability, strengths, limitations

**Good fits**

- reviewing a mooncakes module before adopting it (taint/index/alloc review without building it);
- explaining a failing test path (observed path + values at each line);
- narrowing a large module to the statements that influence one variable (slice);
- CI gates on counts (`summary.json`), with the caveat that counts are model-based.

**Strengths**

- no target build, no annotations, native MoonBit frontend;
- every finding carries method (static/dynamic), confidence, location and evidence;
- Markdown+Mermaid is diff-friendly and renders on GitHub/GitLab/VS Code;
- deterministic artifacts (except elapsed time) and a machine-readable summary.

**Limitations (explicit)**

- unsound: unexecuted inputs/paths are invisible; absence of a finding is not a proof;
- `match`, closures, `impl` bodies and functional `for` are gaps (1.06 % / 4.39 % of statements in the validation modules);
- taint is field- and index-insensitive, no alias analysis, depth-6 interprocedural cutoff;
- loop-counter implicit taint is conservative and can over-report;
- ranges are sampled unions, not fixpoints;
- slices are trace-exact and name-scoped, not package-scoped;
- the coverage bridge needs a buildable target; the interpreter is a model, not the production binary.

---

## 10. Deliverables and acceptance criteria

### 10.1 Deliverables

| # | Artifact | Location |
| --- | --- | --- |
| D1 | Design document (this file) | `docs/design.md` |
| D2 | MoonBit implementation (21 library files + 19 test files) | `src/app`, `src/cli` |
| D3 | Validation fixture with taint/dead-code/infinite-loop defects | `fixtures/vuln_demo` |
| D4 | Generated reports for the two required modules | `reports/riantr_*.md` |
| D5 | Machine-readable summaries and full traces | `reports/*_summary.json`, `reports/*_trace.jsonl` |
| D6 | Acceptance checker | `scripts/verify.mjs` |
| D7 | Usage documentation | `README.md` |
| D8 | 223 unit/integration tests | `src/app/*_test.mbt` |

### 10.2 Acceptance criteria (quantified, reproducible)

| ID | Criterion | Threshold | Measured |
| --- | --- | --- | --- |
| A1 | Build | `moon build src/cli --target native` exits 0 | 0 |
| A2 | Tests | `moon test src/app --target native` ≥ 262 passed, 0 failed | 262/262 |
| A3 | Acquisition | both coordinates resolve; resolved version recorded in §1 | 0.164.64, 0.5.0 |
| A4 | Frontend coverage | ≥ 95 % statements understood on both modules | 99.08 %, 95.82 % |
| A5 | CFG | ≥ 1 diagram per module; every diagram ≤ 90 nodes; Mermaid validator reports 0 issues | 8 diagrams each; validator clean |
| A6 | Dead code | fixture reports exactly 3 `DEAD-CODE` + 1 `UNREACHABLE` | 3 / 1 |
| A7 | Infinite loop | fixture `spin` yields ≥ 1 `INFINITE-LOOP`; unit test pins it | 1 |
| A8 | Taint | fixture yields ≥ 1 `TAINT-INDEX`; each target yields ≥ 1 sink | fixture 8; doubleML 195; static 9 |
| A9 | Ranges | per-point table non-empty; ≥ 1 numeric variable per module | non-empty on all reports |
| A10 | Slicing | doubleML `theta_hat@aggregate_coef_se` ≥ 4 nodes; static `buf@render_reports` ≥ 1 node | 4, 1 |
| A11 | Runtime | ≤ 60 s per module on a warm cache | 10.1 s, 1.6 s |
| A12 | Artifact size | report ≤ 512 KB; trace ≤ 64 MB | 384 KB / 37.6 MB; 149 KB / 2.5 MB |
| A13 | Determinism | two runs produce identical `summary.json` except `elapsed_ms` | verified |
| A14 | Verifier | `node scripts/verify.mjs` exits 0 | 87/87 checks pass |
| A15 | L2 runs | `abstract_findings ≥ 1` on both targets and the fixture | 3305 / 190 / 14 |
| A16 | L3 on fixture | ≥ 1 `proved` and ≥ 1 `failed` VC | 2 proved, 1 failed, 3 unknown |
| A17 | Funnel report | every report contains the funnel Mermaid diagram and L1/L2/L3 rows | present in all three |
| A18 | Cumulative levels | `--level N` runs levels 1..N; `--funnel` runs all three | covered by unit + E2E runs |

A6/A7 are pinned by unit tests rather than by the report, so they remain valid even if the fixture changes; A8–A10 and A15–A17 are checked from the generated reports by `scripts/verify.mjs`.

**Where the "Measured" column comes from.** It records the **committed artefacts** in
`reports/`, regenerated at 0.1.22 with the release recipe — `--funnel --trials 4` and
one slice each, with **no** `--max-functions` cap — when `@latest` resolved to
**0.164.64** and **0.4.50**. Every cell is that artefact's own counter, so it is
traceable to a file: A4 is `(statements − unsupported) / statements`, A11 is the
artefact's `elapsed_ms`, A12 is the artefact's size on disk, and A10 is the node
count of the slice section. `scripts/qa/e2e.mjs` re-measures the same thresholds
against **fresh** runs.

A12's trace ceiling (64 MB) is the tightest margin: the doubleML trace is **37.6 MB**
at `--trials 4`, and the default `--trials 8` produces a larger one, so the
**documented `--trials 4` recipe** is what keeps it inside the threshold. The
E2E's own runs use the default, and they carry their own, looser ceiling for
exactly that reason.

---

## 11. Known gaps and next iterations

1. Parse `match`, closures and `impl` bodies; model ADT payloads instead of treating them as unknown.
2. Field- and index-sensitive taint (per-element labels) and a small alias set for `Ref`.
3. Optional native probe instrumentation (source rewriting + a probe library) so compiled execution, not only the interpreter, emits the trace.
4. Stream trace events to disk with a bounded buffer to remove the 27 MB JSONL spike.
5. Path enumeration from the CFG with feasibility pruning, to report *unexecuted* paths rather than only observed ones.
6. Package-qualified slice criteria (`<pkg>::<fn>`), now that the trace has file paths.
7. Diff mode: compare two versions' findings and coverage.