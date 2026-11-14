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
| Toolchain | `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, native backend; the async runtime is the toolchain-bundled `moonbitlang/core/async` |

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
  *_test.mbt                 73 tests in 11 files
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
- interpreted-function cap (`--max-functions`),
- per-function step budget (`2000`),
- expression/statement nesting depth (`256`, `MAX_PARSE_DEPTH`). A deeper
  construct is skipped whole and counted as a parse gap (`unsupported_stmts`),
  never parsed on a deeper native stack: before this guard, 5,000 nested `if`
  statements and 2,000 nested parentheses aborted the process with
  `0xC0000409` (STATUS_STACK_BUFFER_OVERRUN) on an untrusted module.

### 3.4 Syntax evolution and frontend coverage

The frontend is a structural parser for the MoonBit subset needed by the analyses, not a full type-checking frontend. Supported: `fn` (including `Type::method` names), parameters and return annotations, `let`/`let mut`, assignments and compound assignments, `if/else if/else`, `while`, C-style `for` and `for … in` (including the destructuring `for k, v in entries`), `return`, `break`, `continue`, blocks, `try` bodies, array/tuple literals, struct and record literals, qualified paths (`CART::Leaf`, `Rec::{ … }`), named arguments, calls, method calls, field access, indexing, `if` and `match` expressions, function literals, unary/binary operations, multi-line `#|` strings.

The `#|` string is modelled the way the toolchain builds it, and the semantics were measured **by value** rather than by acceptance -- `moon check` accepts every shape of this construct, so acceptance measures nothing here. `#|` opens the literal, the text after the marker is the first chunk, every following line whose first non-blank characters are `#|` is one more chunk, and the value is the chunks joined with `"\n"`. There is no `|#` terminator (a bare `#` is a lexing error in MoonBit), a bare `#|` line is an **empty chunk** rather than the closer, a chunk is not trimmed, and a blank line inside the literal is skipped. The newline that ends the last chunk line is the statement separator before whatever follows, so it is a token of its own; the newlines between chunk lines are string content.

Unsupported constructs are counted, not hidden: `match` arms, `impl` bodies, functional `for`, and `loop` are recorded as `SUnsupported` / `EvUnsupported` and appear in the CFG as `unsupported: …` nodes. A construct the parser has no rule for at all — an operator it does not model — is folded into the statement it belongs to and counted as unsupported, so it cannot shred itself into statements of its own. Report §2 states statements-understood vs unsupported, so the reader can judge confidence per module. Measured frontend coverage:

| Module | Statements understood | Unsupported | Coverage |
| --- | --- | --- | --- |
| doubleML 0.164.64 | 29,853 | 320 | **98.94 %** |
| static_analysis 0.4.46 | 12,970 | 595 | **95.61 %** |

The counts fell because the old ones were wrong: the parser shredded every construct it did not model into one statement per fragment, and a shredded fragment ate the closing brace of its function, so whole function bodies were truncated. The coverage number is *lower* than before because the analyzer now says what it does not understand instead of silently shredding it.

Compatibility strategy: the parser is tolerant (it clamps brace depth and skips unparseable statements) so a new syntax form degrades to an explicit gap instead of aborting the file. When a module's coverage is low, the report says so, and the coverage bridge can still supply compiled-execution evidence.

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

Domain (`AbsVal`): `Int` and `Double` intervals, `Bool` as a pair of possible values, bounded `String` sets, array **length** intervals, tuples, `top`/`bottom`. Taint is a three-valued lattice (`clean`, `maybe`, `tainted`) so a may-analysis can say "possibly tainted".

State: `Map[var -> AbsCell{value, taint}]`. Transfer functions:

- arithmetic via interval arithmetic with conservative division/modulo;
- comparisons return a `Bool` pair (can-be-true, can-be-false);
- `if`: evaluate the condition, refine the state on the true and false edges (`i >= 0`, `i < n`, `i == k`), execute both branches, join the results; a branch that cannot be taken is reported as unreachable **for the abstract input set**;
- `while` / `for`: iterate to a bounded fixpoint (6 rounds), joining states; from round 3 a widening step pushes growing intervals to the default bound; the loop exit state is refined by the negated condition;
- array indexing: tainted index → `TAINT-INDEX` (mode `L2-abstract`, confidence 0.6); interval may exceed `[0, len-1]` → `RANGE-VIOLATION` (0.6 may, 0.95 when the interval proves it); allocation size tainted or possibly negative → `TAINT-ALLOC` / `RANGE-VIOLATION`;
- `assert`/`require`: "may fail" when the condition can be false;
- loop condition taint propagates to numeric variables read by the condition (implicit flow), which is why `while i < len { a[i] }` is flagged even though `i` starts at 0.

Cost: linear in the number of statements × fixpoint rounds; measured 127 findings from 120 doubleML functions in the same run as L1 (6 s total), and 47 findings from 200 static_analysis functions (3 s total).

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

Budgets: 2000 steps per trial, 64 iterations per loop, 6 frames of call depth, 120 interpreted functions by default. A budget hit is reported with `BUDGET-EXCEEDED`, not as a proof of non-termination.

**Implicit flows.** When a loop condition is tainted, numeric variables read by that condition are marked tainted (control dependence). This is what lets `while i < len { buffer[i] }` report a tainted index even though `i` is initialized to `0`. It is deliberately conservative; see §5.5 for the precision cost.

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
5. implicit control dependence: tainted loop condition taints numeric loop variables (see §5.3);
6. string operations are coarse: `to_string` propagates taint; char-level operations are unknown.

Sinks:

| Sink | Rule | Finding |
| --- | --- | --- |
| array/buffer index | index expression whose value is tainted | `TAINT-INDEX`, error, 0.8 |
| allocation size | `Array::make` / `FixedArray::make` size tainted | `TAINT-ALLOC`, error, 0.8 |
| abort/panic | tainted argument reaches `abort`/`panic` | recorded as `abort` event |
| out-of-range observed index | concrete index outside array bounds | `RANGE-VIOLATION`, warning, 1.0 |

MoonBit has no raw pointer arithmetic; "pointer" sinks in the TrustInSoft sense are represented by array indexing and `Ref` values. `Ref` reads/writes currently degrade to unknown (documented limitation).

Imprecision: field-insensitive, container-index-insensitive, no alias analysis, depth-6 call cutoff, unsupported `match` arms break propagation, and the conservative loop-counter rule can produce false positives. On the validation modules this yields 73 sinks (doubleML) and 6 (static_analysis) — the count is the number of distinct sites, since one site observed in many trials is one sink — high by design because every parameter is treated as hostile input; the report exposes the rule and the observed value for triage.

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
moon coverage analyze
moon coverage report -f cobertura -o cov.xml
LunaFlow analyze <coord> --coverage cov.xml
```

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
| Files walked | 2,000 | stated in the report if the cap is hit |
| Syntactic nesting depth | 256 | beyond this the construct is a recorded parse gap; protects the native stack on hostile input |

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
(2,520 functions), 4.1 s capped against 65 s uncapped, 218,391 trace events
against 2,150,934 — so it stays opt-in.

Outputs, all deterministic except `elapsed_ms`:

- `<author>_<module>_<version>.md` — the report;
- `..._trace.jsonl` — one JSON object per event (`k`, `fn`, `file`, `line`, `stmt`, `name`, `value`, `tainted`, `trial`, `detail`);
- `..._summary.json` — machine-readable counts for CI gates.

`--list-functions` prints `FUNCTION<TAB>FILE<TAB>STATEMENTS` so a slice criterion can be chosen without guessing.

### 7.2 Measured performance (native, Windows 11, warm cache)

| Module | Files | Statements | L1 events | L2 findings | L3 proved/failed/unknown | Dead | Taint sinks | Wall time | Report | Trace |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| doubleML 0.164.64 (120 fn) | 220 | 29,853 | 218,391 | 166 | 0 / 0 / 0 (no specs) | 0 | 73 | 4.5 s | 94 KB | 33.8 MB |
| static_analysis 0.4.46 (200 fn) | 199 | 12,970 | 14,296 | 43 | 0 / 0 / 0 (no specs) | 0 | 6 | 1.0 s | 62 KB | 4.5 MB |
| fixtures/vuln_demo | 1 | 32 | 604 | 11 | 2 / 1 / 3 | 3 | 6 | 4 ms | 21 KB | 79 KB |

The statement counts fell and the dead-code column emptied because the old
numbers were wrong: the parser shredded every construct it did not model into
one statement per fragment, and a shredded fragment ate the closing brace of
its function, so whole function bodies were truncated. Neither module has an
unreachable statement, and the analyzer now says so. The event count rose
because the analyzer understands more of the module and explores more paths.

Memory is dominated by the trace array (one record per event, ~150–250 bytes) and the parsed AST; both are linear in the caps. The 34 MB JSONL for doubleML is deliberate: it is the audit evidence. A production deployment should cap `--trials`/`--max-functions` or stream events to disk.

Deep-QA measurements (2026-11-11, `scripts/qa/load.mjs`, `scripts/qa/e2e.mjs`, `scripts/qa/metrics.mjs`):

| Measurement | Value |
| --- | --- |
| doubleML full run (`@latest` → 0.164.64), wall time | 8.5–9 s |
| doubleML full run, peak working set (sampled) | 295.9 MB |
| doubleML full run, trace size / events | 70.3 MB / 387,638 (default `--trials 8`) |
| doubleML documented parameters (`--trials 4 --max-functions 120`) | 218,391 events, 73 sinks, 0 dead, 3.9 s |
| fixture run, peak working set | 7.5 MB |
| 4 concurrent doubleML runs vs sequential | 1,392 ms vs 5,145 ms (**3.70×**, no failures) |
| LunaFlow's own line coverage (`moon coverage`) | **44.18 %** (1,855 / 4,199 coverable lines of `src/app`) |

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
| D2 | MoonBit implementation (14 library files + 4 test files) | `src/app`, `src/cli` |
| D3 | Validation fixture with taint/dead-code/infinite-loop defects | `fixtures/vuln_demo` |
| D4 | Generated reports for the two required modules | `reports/riantr_*.md` |
| D5 | Machine-readable summaries and full traces | `reports/*_summary.json`, `reports/*_trace.jsonl` |
| D6 | Acceptance checker | `scripts/verify.mjs` |
| D7 | Usage documentation | `README.md` |
| D8 | 24 unit/integration tests | `src/app/*_test.mbt` |

### 10.2 Acceptance criteria (quantified, reproducible)

| ID | Criterion | Threshold | Measured |
| --- | --- | --- | --- |
| A1 | Build | `moon build src/cli --target native` exits 0 | 0 |
| A2 | Tests | `moon test src/app --target native` ≥ 24 passed, 0 failed | 24/24 |
| A3 | Acquisition | both coordinates resolve; resolved version recorded in §1 | 0.164.62, 0.4.43 |
| A4 | Frontend coverage | ≥ 95 % statements understood on both modules | 99.87 %, 97.32 % |
| A5 | CFG | ≥ 1 diagram per module; every diagram ≤ 90 nodes; Mermaid validator reports 0 issues | 8 diagrams each; validator clean |
| A6 | Dead code | fixture reports exactly 3 `DEAD-CODE` + 1 `UNREACHABLE` | 3 / 1 |
| A7 | Infinite loop | fixture `spin` yields ≥ 1 `INFINITE-LOOP`; unit test pins it | 1 |
| A8 | Taint | fixture yields ≥ 1 `TAINT-INDEX`; each target yields ≥ 1 sink | fixture 28; doubleML 102; static 103 |
| A9 | Ranges | per-point table non-empty; ≥ 1 numeric variable per module | non-empty on all reports |
| A10 | Slicing | doubleML `theta_hat@aggregate_coef_se` ≥ 4 nodes; static `buf@render_reports` ≥ 1 node | 4, 1 |
| A11 | Runtime | ≤ 60 s per module on a warm cache | 6.0 s, 3.0 s |
| A12 | Artifact size | report ≤ 512 KB; trace ≤ 64 MB | 124 KB / 27.4 MB; 78 KB / 4.2 MB |
| A13 | Determinism | two runs produce identical `summary.json` except `elapsed_ms` | verified |
| A14 | Verifier | `node scripts/verify.mjs` exits 0 | 87/87 checks pass |
| A15 | L2 runs | `abstract_findings ≥ 1` on both targets and the fixture | 127 / 47 / 11 |
| A16 | L3 on fixture | ≥ 1 `proved` and ≥ 1 `failed` VC | 2 proved, 1 failed, 3 unknown |
| A17 | Funnel report | every report contains the funnel Mermaid diagram and L1/L2/L3 rows | present in all three |
| A18 | Cumulative levels | `--level N` runs levels 1..N; `--funnel` runs all three | covered by unit + E2E runs |

A6/A7 are pinned by unit tests rather than by the report, so they remain valid even if the fixture changes; A8–A10 and A15–A17 are checked from the generated reports by `scripts/verify.mjs`.

**Re-measurement note (2026-11-10 deep QA).** The "Measured" column records the
committed artefacts, generated when `@latest` resolved to 0.164.62 / 0.4.43.
Today it resolves to 0.164.64 / 0.4.46, so A3/A4/A11/A12 are re-measured
separately by `scripts/qa/e2e.mjs` (fresh runs) and `scripts/verify.mjs` (committed
artefacts, pinned by file name). Current fresh-run values: A2 = 33/33, A4 =
99.87 % / 97.28 %, A10 = 4 / 3 nodes, A11 = 5.7 s / 1.0 s, A12 = 141.7 KB + 56.5
MB trace / 52.7 KB + small trace, A13 = summaries and traces identical across two
runs, A14 = 87/87. A12's trace ceiling (64 MB) is the tightest margin: the
default `--trials 8` on doubleML already produces 56.5 MB, so the documented
`--trials 4` recipe is what keeps it inside the threshold.

---

## 11. Known gaps and next iterations

1. Parse `match`, closures and `impl` bodies; model ADT payloads instead of treating them as unknown.
2. Field- and index-sensitive taint (per-element labels) and a small alias set for `Ref`.
3. Optional native probe instrumentation (source rewriting + a probe library) so compiled execution, not only the interpreter, emits the trace.
4. Stream trace events to disk with a bounded buffer to remove the 27 MB JSONL spike.
5. Path enumeration from the CFG with feasibility pruning, to report *unexecuted* paths rather than only observed ones.
6. Package-qualified slice criteria (`<pkg>::<fn>`), now that the trace has file paths.
7. Diff mode: compare two versions' findings and coverage.