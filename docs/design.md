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
| Toolchain | `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, native backend — and the release is verified against the NEWEST toolchain as well (`moon 0.1.20261119`, `moonc v0.10.22+124d61d05`), because the CI runner installs that one; the async runtime is the toolchain-bundled `moonbitlang/core/async` |

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
- the L1 dynamic layer's **step budget** (`--max-total-steps`, default
  `100000`) — the module-wide bound on the interpreter's WORK. The default scan
  enters **every** function of the module and stops when the budget is spent;
  the report's **Entry selection** row says which bound stopped it,
- an explicit **count** cap (`--max-functions`, default `0` = no cap) — this
  caps the **L1 dynamic layer's entry points**, and therefore the trace. It does
  **not** cap the abstract layer: the L2 analyses the whole module and is
  bounded by its own step budget instead,
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
| doubleML 0.164.66 | 30,003 | 281 | **99.07 %** |
| static_analysis 0.4.50 | 15,854 | 738 | **95.55 %** |
| quickcheck 0.15.1 | 1,549 | 355 | **81.3 %** |

The counts fell because the old ones were wrong: the parser shredded every construct it did not model into one statement per fragment, and a shredded fragment ate the closing brace of its function, so whole function bodies were truncated. The coverage number is *lower* than before because the analyzer now says what it does not understand instead of silently shredding it.

The quickcheck row is the one this paragraph measures: against the published 0.1.24 artifact the same tree read **370** functions, **1,519** statements understood, **358** unsupported, **80.9 %** coverage and **5 parse issues**. With `guard` modelled and the parameterised `test` blocks parsed, it reads **375** functions, **1,549** understood, **355** unsupported, **81.3 %** and **0 parse issues** — five more functions, thirty more statements understood, three fewer gaps.

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
- array indexing: tainted index → `TAINT-INDEX` (mode `L2-abstract`, confidence 0.6), and the finding **names the source** — "tainted value from parameter `len` may reach an array index"; interval may exceed `[0, len-1]` → `RANGE-VIOLATION` (0.6 may, 0.95 when the interval proves it); allocation size tainted or possibly negative → `TAINT-ALLOC` / `RANGE-VIOLATION` — except when the size's own interval proves it **constant**, because no tainted value can control a size that is provably 1;
- `assert`/`require`: "may fail" when the condition can be false;
- the taint is **kill-exact**: `let` and `=` kill the variable's taint and re-bind it with the right-hand side's sources, so a tainted value that is overwritten leaves nothing behind.

**There is no implicit flow in this layer.** The L2 used to taint every number a tainted loop condition read, so that `while i < len { a[i] }` was flagged although `i` starts at 0. That was a false claim — the tainted value is the *bound*, and the counter does not carry the bound's taint — and it was **removed** in IFDS Phase 1. What survives it is the honest claim, in the value domain: the counter's value is bounded by the bound, so the index may be out of bounds. The measurement and the falsification are in `docs/qa/IFDS_PHASE1.md`.

**The one exception was known and recorded, and it is now closed.** The length of a container used to inherit the container's **content** taint, and the content's taint says nothing about the count — the same shape as the blanket rule above. The layer did not make a claim its own value domain could refute (a size that is provably constant is not reported), but at the three sites where the size is `top` the claim was a *may*-claim the layer could not prove. The repair separates the taint that reaches a container's **size** from the taint that reaches its **contents**: `AbsVal`'s array value carries the **size's** taint, and the size's taint is computed where the size is produced — a literal's count is fixed by the code, `Array::make(n, x)`'s count is `n`, a caller's array's count is the caller's choice, a `push` carries the old count's taint, and a join unions the two. That is a change to the value domain with a published-interface cost (`AbsVal::AArr` grew a third component), and it was **made** in IFDS Phase 2, declared in the release notes and enforced by `scripts/qa/release_interface.mjs`. `docs/qa/IFDS_PHASE2.md` has the plan, the measurement and the adjudication; `docs/qa/IFDS_PHASE2_ACCEPTANCE.md` has the acceptance record.

Cost: linear in the number of statements × fixpoint rounds; measured 3,316 findings from the 1411 doubleML functions in the same run as L1 (9.6 s total), and 188 findings from the 1422 static_analysis functions (1.7 s total). The step count is the deterministic measure: **272,316** steps on doubleML, against 167,211 before the value domain was repaired — the repair analyses the loop bodies the defective boolean literal used to prune — and 185,766 before the size/contents separation. The wall clock is the machine's: the same tree read 10.1 s and 16.0 s in one session, and the step count did not move.

**The universe excludes the `test` BLOCKS, and nothing else.** The module as scanned holds every `.mbt` file the scanner found — test files included; the scanner excludes build and vendored trees, not `_test.mbt` — and `ModuleAst::all_funcs()` filters on the **function** (`fn.is_test`), not on the file. So an ordinary helper that lives in a `_test.mbt` file is analysed, and a `test "..." { }` block is not. For a module whose test files are most of its code that is worth stating: **129 of doubleML's 220 `.mbt` files are test files**. What says how much of the output is about test code is the finding split, not the scope line: measured on the committed doubleML artefact, **486 of the 2,511 findings shown in §5.2 (19.4 %) are in test files**, and every one of them is in a helper (`v120_check_enet`, `count_eq`, `expand_v091_iivm_data`, …), not in a test block.

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

Budgets: 2000 steps per trial, 64 iterations per loop, 6 frames of call depth, and a budget of 100,000 interpreted steps **per package** by default (`DEFAULT_MAX_TOTAL_STEPS`) — the module's own budget under `--module-wide`. The `--max-functions` count cap is **0** by default, which is no cap at all: a count of functions is not a bound on work. A budget hit is reported with `BUDGET-EXCEEDED`, not as a proof of non-termination.

**THE BUDGET IS SPENT PER PACKAGE, AND THAT IS NOW THE DEFAULT.** A MoonBit package is the directory that holds its `moon.pkg`, and the work of a module is the work of its packages — so a module-wide budget is spent on the FIRST packages in file order, and the rest of the tree is never interpreted. `--per-package` gives each package its own budget, so a module of N packages has a budget of N times the one; **since 0.1.37 it is what a scan does with no flag at all**, and `--module-wide` asks for the old behaviour by name. The `--max-functions` count cap stays module-wide, because a reader who asked for "150 functions" did not ask for "150 functions per package". The trace is written one file per package, and the report gains a package table that says what each package cost and whether its own budget was reached.

MEASURED on `riantr/moonbit_static_analysis@0.5.4` (17 packages): the module-wide budget enters **711** of 1,437 functions and stops inside `src/flow`, while the per-package mode enters **1,212** and reaches every other package whole. On `riantr/moonbit_doubleML@0.164.66` the mode does **nothing at all** — that module is FLAT, one `moon.pkg` at its root, so all 220 of its files sit in the root package and there is only one package. §7.2 has the sizes.

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

**The `#cfg` findings, and the correction the 2026-11-22 round forced.** The peer
does not model `#cfg`. A module that defines a name twice — once for the
native/wasm backends and once as a stub for the others — has two definitions of
that name, and the peer binds the name to **one** of them. That much is true, and
the first reading of it was:

| what the peer reported | the first reading |
|---|---|
| `ArgTypeMismatch` — "expected 5, got 6" | the native/wasm definition has **6** parameters and the js stub has **5**; the peer bound the name to the stub |
| `UnusedParam` on the stub's parameters | the stub's body is **empty**, and the parameter exists in the *other* definition |

**That reading was wrong, and the QA round of 2026-11-22 proved it by measurement.**
The stub for `walk_dir` took **five** parameters while the live one took **six**,
and the compiler had been reporting the stub as `Unused function 'walk_dir'` on
every backend it was compiled for. A definition that nothing calls, whose signature
disagrees with the definition it stands in for, is **dead code with a wrong shape**
— which is a defect in this module, not a limit of the peer. The peer was right
about the shape and only imprecise about the cause.

The distinction that survives: the peer cannot tell a **dead** definition from a
live one, because it does not evaluate `#cfg`. So an `ArgTypeMismatch` from it is
not automatically a defect — it is a **question about the shape of a name**, and the
answer has to be measured. On this tree the answer was "the two shapes disagree and
one of them is dead", and the fix was to delete the dead one. **MEASURED after the
fix**: the peer reports **0 actionable findings in this project's own source.**

`WalkState`, the walker's state type, went the same way: cfg'd to match the walker
that owns it, because `moon check --target js` reported `Unused type 'WalkState'`
once the walker was confined to the other two targets.

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
reports **20 rows**.

**The cross-check is now a step, not a paragraph.** `scripts/qa/peer_scan.mjs` runs
the peer over this tree and fails when it reports an actionable finding in the
source that ships. The fixture corpus is excluded and the exclusion is **printed**,
because "no actionable finding" has to mean the code that is published. It needs the
registry, so it exits **2** — "could not decide" — when it cannot reach it. A newer
peer that finds something new turns the step red on purpose: that is the event it
exists to surface, and it is how the `walk_dir` stub would have been caught two
releases earlier.

Cost: one peer run per release (now one per gate run), plus a probe file per
disputed claim.

### 5.17 The verdict of a finding: a claim that could not be decided

A finding is a **CLAIM**, and a claim can end in three ways: the analyser
decided it, the analyser decided it is false, or the analyser **could not
decide it at all**. The third state is the one the finding model had no room
for. Without it, a claim the analyser could not decide is simply **absent**,
and an absent claim is indistinguishable from a claim that was decided and
found clean — which is the price Phase 3 paid, where fourteen true claims
vanished and the report could say nothing about why.

The vocabulary already existed elsewhere: the L3 has `VCStatus::VCUnknown`
("insufficient facts for a decision") and the abstract layer has `EUnknown`.
What was missing was the same state **on the finding**, so that the difference
reaches the reader.

| | |
| --- | --- |
| `Finding.verdict` | `VerdictCertain` or `VerdictUnknown`. `Finding::new` makes a decided claim; `Finding::undecided` makes one that could not be decided. |
| the findings table | a **Verdict** column, next to the severity. |
| the `_findings.jsonl` sidecar | a `verdict` key per finding. |
| report §5.10 | **Claims that could not be decided** — the count, and each one with its reason. |

**WHAT AN UNDECIDED CLAIM MEANS IS A POLICY, AND THE POLICY IS FAIL-CLOSED.**
An undecided claim about a **safety** property is an **error**: the module's
safety is then not established, and "we could not decide" is not "it is fine".
An undecided claim about anything else is a **warning** — worth knowing, and
not by itself a safety claim. An undecided claim is never merely
*informational*: `info` is how this project renders the families that never
fire, and a claim that could not be decided is not a claim that never applies.
The policy is one table, `src/app/policy.mbt`, because adding a family should
be a decision somebody has to make.

**THE PRODUCER TODAY IS THE ANALYSER'S OWN BUDGET.** A loop that runs past the
step budget means the rest of that function was never analysed, so nothing
about it was decided — and the report now says so in words instead of implying
it by silence. It is the smallest honest "we could not tell" there is, and it
is reachable from the command line.

**THE CHANGE TO THE PUBLISHED INTERFACE.** `Finding` gains a field, so the
`.mbti` changes: `Finding` carries `verdict : FindingVerdict`, and
`FindingVerdict`, `Finding::undecided`, `Finding::severity`,
`undecided_severity`, `undecided_findings` and `count_undecided` are new
declarations. `Finding::new`'s signature is unchanged, so a consumer that
BUILDS findings is unaffected; a consumer that constructs one by struct
literal is not, and the release that carries this must say so in its notes —
`scripts/qa/release_interface.mjs` enforces exactly that.

Cost: one field on the finding model, one policy table, one report section.

### 5.18 The metamorphic gate: the findings must not depend on the spelling

A check that runs the analyser once measures ONE shape of the input. The
metamorphic relations measure the **analyser**, by running it over the same
program written several ways and comparing the claims:

| relation | the claim |
| --- | --- |
| **RENAME** | the same program with different identifiers makes the same claims. An analyser whose claims depend on the *name* of a local is not analysing the program. |
| **REORDER** | the same program with its functions in another order makes the same claims. A finding that depends on how many functions happen to precede it is a finding about the file order — and the CFG pass takes the FIRST functions in file order. |
| **SWAP** | `a + b` and `b + a` make the same claims. The count of a `+`-built array is the sum of the two counts, and a sum does not remember which side was first. |

The signature of a finding is its rule, severity, verdict, function, method,
message and evidence, with the renamed identifiers folded to one placeholder.
The **line is not in the signature**: the reorder relation legitimately moves a
finding's line, and what has to be invariant is *which* claims the analyser
makes and *what* it says — not where they sit in a file.

Two more relations, because a metamorphic gate that cannot fail is decoration:
the comparison must be able to **tell two programs apart** (a program whose
claims really are different gets a different signature), and the same program
analysed **twice** must give the same findings **in the same order** — a
hash-order artefact would show up there and nowhere else.

Cost: one script, four analyser runs.

### 5.19 A signature must not depend on the target

A `#cfg` guard selects a definition per target, and that is exactly what it is
for. The invariant this section is about is one level down: **within a
compilation unit, every definition of one name must take the same number of
parameters.** When it does not, the target that compiles the smaller shape is
the target whose call sites do not match — and the definition that nothing
calls is dead code carrying a signature nobody can satisfy.

**The measurement that found it.** `src/app/scan.mbt` held two definitions of
`walk_dir`:

```moonbit
#cfg(any(target="native", target="wasm"))
async fn walk_dir(dir, rel, st, limit, depth, excludes) -> Unit   // SIX

#cfg(not(any(target="native", target="wasm")))
async fn walk_dir(dir, rel, st, limit, depth) -> Unit             // FIVE
```

The two guards are mutually exclusive, so no build ever saw both, and
`moon check --target js` reported the five-parameter one as **`Unused function
'walk_dir'`** — the compiler had been saying so on every backend it compiled.
The stub is gone; on a backend with no filesystem, `load_module` returns an
empty module and never walks anything.

**Why a checker is needed when the compiler already says it.** The compiler
reports dead code, and dead code is a *warning* on this project. A dead
definition that is **also** shaped differently is a worse thing: it is a
signature that lies to every reader and to every analyser that does not
evaluate `#cfg`. `scripts/qa/cfg_signatures.mjs` holds the invariant directly —
it reads the source, computes the arity of every definition, groups by
compilation unit, and fails when one name disagrees with itself.

The reader it needs is not the naive one: a `fn` inside a comment, a string or a
**block string** is not a definition, and the test files carry whole MoonBit
modules as `#|` fixtures. MoonBit's block string has **no terminator** — `#|`
opens it, each following line whose first non-blank characters are `#|` is
another chunk, and the first line that is not one ends it. That rule is
implemented here as it is in this module's own lexer (`src/app/lexer.mbt`,
`lex_block_string`), measured by value against the toolchain. A naive reader
reported **six** phantom mismatches on this tree; the correct one reports
**zero**, and the six names it does see defined twice
(`fetch_module`, `load_module`, `write_text`, `read_text`, `cli_args`,
`ensure_dir`) all take the same shape.

`cfg_signatures_falsify.mjs` breaks the invariant **on a copy of the tree**
under `_build/` — the real `src/` is never written — and asserts three things:
the copy is green before the mutation, the mutated copy is red, and the red
report **names the function and shows both shapes**. That last one is the
difference between a detector and a tripwire: a check that goes red for the
wrong reason is not checking the right thing.

Cost: one source scan, no build, no network.

### 5.20 The rule × dimension matrix: who found what

Every other findings table in the report answers **what was found**. §5.11
answers a different question: **who found it**. It crosses the finding families
(the RULES) against the analysis method that produced each finding (the
DIMENSIONS), and gives a count per cell.

**Why it is worth a section.** A claim rests on the evidence of the lens that
made it. A family reported by one lens has one kind of evidence behind it; a
family reported by two lenses has two independent reasons to be believed, and a
reader deciding what to act on should be able to see which is which without
reading the Method column of every row. No per-family count can express that:
`TAINT-INDEX 11` says nothing about whether those eleven came from one lens or
three.

It also makes a COVERAGE fact visible. A lens that reports nothing is a lens
whose evidence did not fire, and that is a different thing from a module with
nothing to say. A matrix with an empty column says so at a glance.

**The shape, and why it is the shape it is.**

| thing | rule |
|---|---|
| rows | the families, sorted by total count then by name |
| columns | the methods (`Finding.mode`), sorted by total count then by name |
| a cell | the number of findings of that family from that method; **`·`** when zero |
| the last column | the family total — the same number `family_count_table` gives |
| the last row | the method totals, with the grand total in the corner |

The totals are the point: the table **checks itself**, and a reader can add a row
up in public. The sort is the one `family_count_table` already uses, so the table
is identical on every run and does not depend on the order the findings arrived
in.

`·` rather than `0` is deliberate. A zero and a dot are the same number and
different facts: the dot says *this lens considered the module and made no such
claim*, which is the useful reading when the column is sparse.

**What it found on this tree.** 30 families over 8 methods; **exactly one**,
`TAINT-INDEX`, is corroborated by two lenses (`dynamic+symbolic` and
`L2-abstract`). The other 29 rest on one kind of evidence. That is a coverage
statement about this module and about the analyser, and it was not visible
anywhere in the report before.

**The matrix creates no finding, and that is measured.** Adding §5.11 to the
renderer leaves the three committed artefacts' **traces and findings sidecars
byte-identical** — `git status` shows only the `.md` and the `_summary.json`
changed, and the `_summary.json` diff is `elapsed_ms` alone. An addition that
produced new CLAIMS would show up in the sidecar; an addition that CROSSES the
claims already there cannot. That is the difference, and the artefact is where
it is checked.

**How it is pinned.** Eight whitebox tests (`src/app/report_wbtest.mbt`, the
prefix `the dimension matrix: `) assert the row/column counts, the dot, the
totals, the corroboration sentence by NAME, the empty-input case, determinism
under reordering, and — the one the section exists for — that the matrix's
counts are the counts of the rows of the findings table rendered from the
**same** findings. They run inside `moon test src/app` on all three targets,
so they are gate steps.

**And the matrix is checked against the REPORT, not only against itself.**
`scripts/qa/dimension_matrix.mjs` is a gate step too, and it is the only check
that can see the **wiring**: the tests call `rule_dimension_matrix` directly,
so a matrix wired to the wrong set of findings still passes every one of them.
The gate step reads the report — the three committed artefacts and a live run —
and checks that every row adds up to its own total, every column to its own,
every CELL is the count of the findings of that family that that method found,
and the grand total is the number of findings the tables were given, including
the rows a truncated table left out (which the report states in the count table
above the truncated one). MEASURED: **56 of 56 checks pass**.

The shape of that check is worth stating, because it is a **row-shape**
argument and not a text search: the findings tables are found by their HEADER,
the family-count table that precedes a truncated table is found by ITS header,
and a matrix cell is found by its position in the row. A checker that counted a
family code in the whole report would count the matrix's own row as well — and
MEASURED, that is exactly what happened: §5.11 made six of `root_package.mjs`'s
family counts read **2** instead of **1**, because those counts were over the
text, and the report grew a table of the same names. They count ROWS now, and
the three "not filed as the classic abstract findings" checks look at the rows
too, because the matrix's own column header carries a method name.

`scripts/qa/matrix_falsify.mjs` is the proof that these checks can fail. It
MUTATES THE SOURCE, so it is a **manual, local tool** and deliberately not a
gate step — the arrangement `plus_size_falsify.mjs` and `size_taint_falsify.mjs`
already use. It breaks the matrix **five** ways (a row loses its total, the dot
becomes `0`, the corroboration list is emptied, the section is wired to
another set of findings, the section is not rendered at all), restores the
source byte for byte between cases, and asserts that the check **about that
defect** is the one that goes red. The last two cases are the ones the unit
tests provably cannot catch, and the falsifier asserts that they leave the unit
tests **green** while the report-level check goes red — the proof that the two
kinds of check are not the same check twice. MEASURED: **13 of 13 checks
pass**.

It earned its keep on the first run. The corroboration test originally asserted
that `TAINT-INDEX` appeared **somewhere** in the output — and it also appears as
a row label, so the test passed with the sentence's list emptied. The falsifier's
F3 case is what found that, and the test now asserts the sentence itself:
`more than one kind of evidence: TAINT-INDEX.`. A test that cannot tell "the
sentence says it" from "the name is on the page" is decoration, and only a
mutation that removes the sentence can show the difference.

Cost: one pass over the findings per cell computation, no new analysis.

### 5.21 The counterexample minimisation: the smallest input that reproduces a finding

Every other findings table in the report answers **what was found**. §5.12
answers a different question: **what makes it happen again**. For each finding
an **execution** produced, it re-runs that finding on its own input and
reports the smallest input that reproduces it.

**The claim, and its boundary.** "Smallest" is a statement about an **order**,
and the order is the analyser's own:

- the candidates of a parameter are the values `value.mbt` synthesizes for
  that parameter's type, in the order that file lists them (`Int`:
  `-1, 0, 1, 2, 5`; `String`: `""`, `"abc"`, `"../../etc/passwd"`, a long
  zero string; `Array[T]`: empty, one element, three, two-reversed);
- the candidates of the parameters form a **product**, and the analyser walks
  that product with the **last parameter varying fastest** (`synthesize`);
- the counterexample is the **first** input in that walk that reproduces the
  finding, so every input before it was tried and did not reproduce it.

That is what the word means here, and the report says so in the same breath:
*the smallest over the analyser's own candidate set*. It is **not** a globally
minimal program, and it is **not** a minimal source — those are different
problems with different answers, and claiming them would be claiming
something this does not do.

**Why the walk is the analyser's own.** The order cannot drift from the order
the analyser itself uses, because it IS that order: the minimisation calls
`synthesize`, the same function the interpreter calls. The walk here is
**longer** than the analyser's — the analyser samples a bounded number of
trials, and a finding raised in a **callee** can need an input past that
bound. Finding it is the part of this that is worth the re-runs.

**Why the reproduction is checked against the SITE.** A finding's identity
across runs is its family, its file, its line and its function — `same_site`,
the same comparison the funnel already uses to decide that two findings are
the same finding. It is **not** the message and **not** the evidence: the
evidence carries the observed value (`values[0] of length 0`), and the
observed value is exactly what the smaller input changes. Matching on the
evidence would mean that no counterexample ever matched the finding it came
from.

**The entry is the finding's own function.** The finding is raised there, so
entering that function with a tainted argument is what raises it again. The
interpreter gains one optional argument for this — `run_function(inputs=…)`
runs ONE input instead of the synthesized trials — and that is the whole
seam. No new analysis engine, no second interpreter.

**What has no counterexample, and why that is stated.** Two classes of
finding have no input to minimise:

- the **L2 families** are may-claims over the whole input set. A may-claim
  says *every* input in the abstraction may do this; there is no single input
  that reproduces it, because the claim is not about a single input.
- the **CFG families** are claims about the program's shape (dead code, an
  unreachable node, a non-terminating loop) — a claim about the program, not
  about an input.

They are **counted apart** in the section, and the count is published: on this
tree, **67** findings were in that class.

The findings an execution produced and that **no** input reproduced are
**listed**, with their message. A count is not a list, and on this tree that
list has exactly one entry — `BUDGET-EXCEEDED` at `src/app/ffi.mbt:391` —
which is the most honest answer the feature can give: the claim is about the
analyser's own **step budget**, and no input reproduces a budget.

**Why it is opt-in.** The minimisation re-runs the analyser, once per input
tried. It is therefore a flag (`--counterexamples`) and not part of the
published artefact recipe, and it is bounded twice: a limit on the findings
covered (`--counterexample-limit`, default 64) and a budget on the inputs
tried. The section states which bound stopped it.

**How the minimality is pinned.** Eight whitebox tests
(`src/app/minimize_wbtest.mbt`) assert the reproduction, the chosen
candidate's index, the rendering, the bounds, and — the one the feature
exists for — that **every input before the counterexample's fails to
reproduce the finding**. The test module **guards** its index, so the first
input of the product does not reach the read and the minimiser has to move
to the second candidate: the refutation is not vacuous, because there is
something to refute.

**And the division of labour is measured, not assumed.**
`scripts/qa/counterexamples.mjs` is a gate step, and it checks the ARTEFACTS:
the table and the `_counterexamples.jsonl` sidecar agree row by row, every
counterexample names a finding the report **shows**, every argument **is** the
candidate its index points at, and the prose counts are the counts the
sidecars imply. It runs over the fixture **and** over a live self-scan —
the self-scan is there because the fixture has no finding that no input
reproduces, and a check that never sees one is a check that never fires.

Whether there **is** such a finding is a fact about the tree and the
toolchain, not an invariant, so the self-scan's count is **reported** rather
than asserted — and the mechanism is exercised on every tree by the
falsifier's F6 case, which claims a without-count the without-list does not
support and requires the check to go red.

That check **cannot** see the minimality: a non-minimal counterexample
produces artefacts that are internally consistent. `scripts/qa/minimize_falsify.mjs`
is what says so with a measurement — it **mutates the source** (so it is a
manual, local tool and deliberately not a gate step), breaks the minimiser
three ways, and asserts that the unit test about the minimality goes red
**while the report-level check stays green** on the case that is purely about
the order. MEASURED: the F2 case — the walk takes the last reproducing input
instead of the first — leaves the report-level check **green**. The minimality
is pinned by the unit test and by nothing else, and that is now a measured
fact about this harness rather than an assumption about it.

Cost: one re-run of the entry function per input tried. On this tree the
minimisation tried **22** inputs for **9** findings, and the whole self-scan
with `--counterexamples` read **738 ms** against **750 ms** without it — the
same run, the same machine, and the difference is inside the noise.

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
buffer model (5.9) and the classes the C boundary makes real (5.15). The
counterexamples (5.21) and the rule × dimension matrix (5.20) are sections
inside §5, and the matrix is rendered from the same findings the tables
fill.

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
  [--max-total-steps <n>]
  [--level <1|2|3>] [--funnel]
  [--function <fn>] [--slice <crit>] [--forward|--backward]
  [--coverage <cobertura.xml>] [--max-cfg <n>] [--max-taint <n>]
  [--max-slice <n>] [--list-functions] [--quiet]
  [--exclude <name>]... [--families <codes>] [--exclude-families <codes>]
  [--explain <code>] [--explain-all] [--metrics] [--per-function]
  [--per-package|--module-wide]
  [--counterexamples] [--counterexample-limit <n>]
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
| `--per-function` | enter EVERY function as an entry point, with the step budget and the `--max-functions` cap lifted |
| `--per-package` | scan PACKAGE BY PACKAGE, each package with its own step budget, and write one trace per package. **This is the default.** |
| `--module-wide` | ONE step budget for the whole module, spent on the first packages in file order, and ONE trace file for the module. This is what a scan did by default before 0.1.37. |

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

`--per-package` is the other half of the same rule, and it is a BOUND and not a mode of its own: the module is still scanned as a module, and the only thing that changes is WHICH budget stops it — the package's own instead of the module's. It is the **default** since 0.1.37, and `--module-wide` asks for the module's own by name. §5.3 has the measurement, and the part of it that decides the question is that the mode does nothing at all for a module that has ONE package.

`--per-function` has no module-mode counterpart here: LunaFlow's L1 already
enters functions rather than executing module-level statements, so the
counterpart of the peer's toggle is the bound on the dynamic layer, and the
option lifts it — both the step budget and the `--max-functions` cap. The cost
is real — measured on `riantr/moonbit_doubleML@0.164.64` (2,529 functions),
9.2 s capped against 127.9 s uncapped, 193,906 trace events against 2,069,372 —
so it stays opt-in.

Outputs, all deterministic except `elapsed_ms`:

- `<author>_<module>_<version>.md` — the report;
- `..._trace.jsonl` — one JSON object per event (`k`, `fn`, `file`, `line`, `stmt`, `name`, `value`, `tainted`, `trial`, `detail`);
- `..._summary.json` — machine-readable counts for CI gates;
- `..._findings.jsonl` — one JSON object per finding the report rendered;
- `..._counterexamples.jsonl` — one JSON object per counterexample, written
  **only** when `--counterexamples` is given (§5.21).

`--list-functions` prints `FUNCTION<TAB>FILE<TAB>STATEMENTS` so a slice criterion can be chosen without guessing.

### 7.2 Measured performance (native, Windows 11, warm cache)

The **committed artefacts**, regenerated with the release recipe in §7.2 of the
README — `--funnel --trials 4` and one slice each, with **no** `--max-functions`
cap (the default scan's bound is the **step budget**, not a count):

| Module | Files | Statements | L1 events | L2 findings | L3 proved/failed/unknown | Dead | Taint sinks | Wall time | Report | Trace |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| doubleML 0.164.66 | 220 | 30,284 | 508,422 | **3,326** | 0 / 0 / 0 (no specs) | 0 | 265 | **16.0 s** | **416 KB** | 76.3 MB |
| static_analysis 0.5.4 | 263 | 17,843 | 673,492 | **188** | 0 / 0 / 0 (no specs) | 0 | 291 | **14.2 s** | **279 KB** | **106.2 MB** in 17 (largest 75.3 MB) |
| fixtures/vuln_demo | 1 | 32 | 604 | 15 | 2 / 1 / 3 | 3 | 8 | 4 ms | 37 KB | 79 KB |

Sizes are in **KB = 1024 bytes**, against a 512 KB limit, so the doubleML report
(425,947 B) sits at **81 %** of A12. The L2 column moved from 187 / 8 to 1,282 / 184
because the abstract layer's scope stopped being the interpreter's entry-point cap
and became the whole module, then to **3,305 / 190** because the five dead
`::`-spelled rules were repaired (the allocation family could not fire at all)
and the de-duplication key was given the file it had been omitting, and then to
**3,321 / 188** because the value domain was repaired: a boolean **literal** was
modelled as a value that can be neither true nor false, and the contradiction
pruned the branches it guarded. The repair brought the findings the pruned
branches hid back and took the false positives the same defect produced away.
And it moved once more, **3,321 → 3,301 / 195**, because the value domain let a
container's **size** inherit its **contents'** taint: the size's taint is now
computed where the size is read, and the twenty `TAINT-INDEX` claims that
inheritance carried are gone. Each of the twenty was adjudicated against the
source — two were self-refuting, eighteen were a registered coverage cost —
and `docs/qa/IFDS_PHASE2.md` §9 is the adjudication.

**The L1 event and trace columns moved too, and the reason is the repair, not
the taint.** The allocation rule records an `EvAlloc` event for every
allocation it sees, and the rule was dead before — so repairing it added
**5,624** trace events on doubleML (237,904 → 243,528) and the trace grew
from 36.8 MB to 37.6 MB, still inside the 64 MB cap. The **other two artefacts'
event counts did not move at all**: the static-analysis module is still 17,029
and the fixture still 604.

**The count cap is not part of the recipe, and adding it moves the dynamic layer's
numbers.** With `--max-functions 120` the doubleML run produces **198,694** trace
events; without it, **508,422**. The cap binds the **dynamic** layer's entry
points, and with them the trace.

**What bounds the recipe now is the STEP BUDGET, not a count of functions.** The
default scan enters **every** function of the module and stops when the
**100,000**-step budget is spent — **per package**, because that is the default
since 0.1.37. Measured on the committed artefacts: the doubleML run is **one**
package, so its budget is the module's, and it stops after **100,020** steps and
**508,422** trace events; the static-analysis one has **17** packages, and it
spends **136,821** steps across them for **673,492** events — **sixteen of the
seventeen packages whole**, and only `src/flow` spending its own budget; and the
fixture's budget is never reached, so **every one of its 12** functions is
entered. `--max-total-steps <n>` raises the budget; `--per-function` lifts it, and `--module-wide` spends it once for the whole module.

**THE PER-PACKAGE MODE's SIZES, because the PUBLISH envelope is where its cost shows.** The envelope is the one the registry has already accepted (`docs/qa/PUBLISH_ENVELOPE.json`): **46,274,868** bytes unpacked and a **39,479,846**-byte largest entry. Measured with `--trials 4`: on this tree the split takes the trace from **22,691,389** bytes in one file to the same **22,691,389** bytes in ten, with the largest entry down to **21,923,396**; on the static-analysis module it GROWS, from **76,591,727** bytes in one file to **111,328,416** in seventeen, the largest entry up to **78,902,704**, because the mode interprets more and the evidence is more; on doubleML it does not change a byte, because there is one package — one file, **80,035,384** bytes. The ceiling is a limit on the TOTAL, and a split does not touch the total.

The statement counts fell and the dead-code column emptied because the old
numbers were wrong: the parser shredded every construct it did not model into
one statement per fragment, and a shredded fragment ate the closing brace of
its function, so whole function bodies were truncated. Neither module has an
unreachable statement, and the analyzer now says so. The event count rose
because the analyzer understands more of the module and explores more paths.

**THE PACKAGE IS NOT THE ARTEFACTS.** The recipe above commits the artefacts, and the
published package is a different thing: `moon publish` packs the working tree minus
the files the ignore rules match, so the raw traces — the largest files in the
repository — are **not** in the archive. That is not a preference: the registry
**refused** the 0.1.35 upload with `400 Bad Request, detail: Invalid ZIP archive`
when the package carried **162,703,756** bytes unpacked and an **80,863,997**-byte
entry, where the largest archive it had served (**0.1.34**) carried **46,274,868**
bytes and a **39,479,846**-byte entry. The limit is a check now:
`scripts/qa/package_envelope.mjs` measures the package the tree would publish and
keeps it inside the envelope the registry has already accepted, and
`docs/qa/PUBLISH_ENVELOPE.json` records where the measurement put the boundary.

Memory is dominated by the trace array (one record per event, ~150–250 bytes) and the parsed AST; both are linear in the caps. The **76.3 MB** JSONL for doubleML is deliberate: it is the audit evidence. A production deployment should cap `--trials`/`--max-total-steps` or stream events to disk.

Deep-QA measurements (2026-11-11, `scripts/qa/load.mjs`, `scripts/qa/e2e.mjs`, `scripts/qa/metrics.mjs`):

| Measurement | Value |
| --- | --- |
| doubleML full run (`@latest` → 0.164.64), wall time | 8.5–9 s |
| doubleML full run, peak working set (sampled) | 295.9 MB |
| doubleML full run, trace size / events | 69.6 MB / 448,001 (default `--trials 8`) |
| doubleML with a `--max-functions 120` cap (`--trials 4`, no slice) | 193,906 events, 85 sinks, 0 dead, 9.2 s — re-measured on 2026-11-24 on 0.164.66 with the slice: **198,694** events, 155 sinks, 0 dead, 7.2 s |
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
and not a decoration.

**THE FALSIFICATION ARRIVED LATE, AND THE CHECK WAS BLIND UNTIL IT DID.** The 0.1.27
release notes published that this check "is falsified against both failure modes:
it is proved to fail, not assumed to" — and no falsifier for it existed in the
repository. The check's own string-stripper treated a `#|` as the start of a
block string closed by `|#`, but MoonBit's multi-line string has **no
terminator**: the literal opens with `#|`, every content line carries the
prefix, and it ends at the first line that does not. The closer was therefore
never found, and the stripper blanked **the rest of the file** — MEASURED by
evaluating the stripper out of the tracked source, the check read **20,964** of
the tree's code lines where it reads **24,321** now, **3,357 more, 16.0 % more**,
and `src/command/command.mbt` alone lost **1,158** of its **1,260** to its own
65-line usage literal. A reserved identifier planted after that literal left
the check **green**: it measured nothing about the code after the literal and
said OK. The stripper is repaired, and `scripts/qa/coverage_route_falsify.mjs`
now plants a reserved identifier in three places and asserts the check goes red
and names the file — on **copies**, so no tracked source is ever written. The other **8 of the 9** formats read the same data
without parsing the source — `bisect`, `caret`, `summary`, `full_summary`,
`sorted_summary`, `cobertura`, `html`, `coveralls` — so a module that *does* use
a reserved word still has a route: *"use -f caret to report coverage without
parsing"*.

**THE RECURSION FIX COSTS ONE CLAIM AND ONE EVENT, AND THE WALL CLOCK DOES NOT SEE
THEM.** The L1's depth guard used to return `VUnknown` when the recursion budget
was spent — no claim, no event, no trace — so a truncated analysis looked like a
clean one. It now reports an **undecided** `BUDGET-EXCEEDED` claim and an
`EvBudget` event, the way the step budget already reports itself, and the limit
itself is unchanged (**6**, at `src/command/command.mbt:1044`): the fix changes the
**report**, not the budget. MEASURED, paired on this machine: the tree **without**
the fix read **2,036 ms** to **2,343 ms** over five self-scans, the tree **with** it
read **2,092 ms** to **2,168 ms** minutes later, and the medians — **2,100 ms** and
**2,142 ms** — differ by **42 ms**, which is smaller than the **307 ms** spread the
same binary showed over its own five runs. The self-scan's counts did move, and by
exactly what the fix adds: **68** files, **7,846** statements and **230,667** events
where the row read **66**, **7,746** and **230,577**. The committed artefacts did
not move at all — **0** depth-budget findings in each of `doubleML` and
`static_analysis` — so `reports/` was not regenerated.

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

### 8.1 A borrowing examined and not adopted: the gate policy file

The `Veriflow` verification project (`NineSense9/Veriflow`) runs its gate with a **policy file** whose thresholds live in one machine-readable place. The six keys, from its `packages/verify/veriflow_verify/gate.py`:

```python
DEFAULT_POLICY = {
    "fail_on": {"severity": ["CRITICAL", "HIGH"]},
    "unknown_policy": {"runtime": "warning", "safety": "fail"},
    "requirements": {"minimum_coverage": 0.9},
    "repair": {"allow_auto_repair": False},
    "regression": {"allow_new_high_severity": False},
    "benchmark": {"minimum_detection_f1": None},
}
```

The proposal was to give this project's gate the same shape: one file of thresholds, read by the checks, instead of the thresholds living inside the harnesses.

**Not adopted — and the reason is the shape of a threshold, not the inconvenience of a file.** Every comparison this project makes between a published number and a measured number is an **exact equality**: `scripts/qa/readme_table.mjs` writes `cell !== s[f]` for a difference and `want.every((w, i) => w === got[i])` for a match, and it contains **no ordering comparison between two values at all** — no `<`, no `<=`, no `>`, no `>=`. The only way such a check passes is for the number to *be* the number, and that is what makes a published number falsifiable.

**And that is now ENFORCED, not just observed.** `scripts/qa/exact_counts.mjs` is a gate step: it reads the drift detector's source with its comments and string literals stripped — so a comparison that is only *mentioned* in prose is not a comparison, and the `>` of an arrow function is not a comparison — and fails when it finds an ordering comparison between two values. The one ordering comparison the detector legitimately has is the sentinel "was the index found?" (`start < 0`, `i < 0`), and it is exempt because one side is a literal: no published count is compared with a measured count through it. The check also asserts the opposite — that the detector does compare counts, by exact equality — so a detector that compares nothing cannot satisfy the rule by having nothing to weaken. `scripts/qa/exact_counts_falsify.mjs` proves both halves: it weakens a count comparison to an ordering one on a **copy** and requires the check to go red and to name the line, and it puts an ordering comparison in a comment and in a message and requires the check to stay green.

A threshold is the one shape that can pass **vacuously**. "The tree's L2 findings must be at most 300" is satisfied by a tree with three million findings: the check goes green while the tree gets worse, and nothing in the run says so. Veriflow shows that shape's edge in its own code — its coverage criterion reads `if coverage is not None and coverage < minimum`, so a coverage that was **never measured** passes the floor, and an unmeasured value is not a good value (that is the whole subject of §5.17). Moving this project's thresholds into a policy file would make the vacuous shape the default, and would trade away the discipline the whole harness rests on.

The second reason is that **there is nothing to put in the file yet**. This project's thresholds are not values; they are the checks themselves, and each check is a program that measures something and compares it. `scripts/qa/gate.ps1` writes one line per step (`ok`, `FAIL(n)`, `UNKNOWN(2)`), and `scripts/qa/gate-steps.json` holds the step list in the repository, so the gate's decisions are already auditable in place and reviewable in a diff.

**What would reverse this decision.** A policy file becomes **mandatory** the moment a threshold is introduced — the first check whose verdict is "the tree is good enough" rather than "the tree is exactly what it claims". Concretely: a `fail_on: severity` rule over the findings sidecar, a `minimum_coverage` floor, or a per-family `unknown_policy`. Then three things have to hold, or the file is only a place to hide a criterion that can pass vacuously:

1. the thresholds live in **one** place and are **read** by the checks, never duplicated in a script;
2. every threshold is a falsifier's subject — the check has to be shown to go red when the threshold is crossed, the way `readme_table.mjs --falsify` inverts its own expectations today;
3. a threshold that is satisfied by a **worse** tree is rejected at the design stage: "at most N" is admissible only where a larger N is not a regression.

**And this closes a record gap.** The comparison with that project produced several borrowings that were examined and not adopted — the guarded self-repair loop, the web UI, the natural-language→IR pipeline, and this policy file — and until now **none of them was written down**: §5.16–§5.19 describe what the analyser does, not what this project declined to borrow. The other three are recorded in §8.2; this one is recorded because its reason is a property of the harness that a later change could quietly undo.

### 8.2 The other three borrowings examined and not adopted

Three more ideas from the same comparison were examined and not adopted. Each was examined against a **stated** property of this project, not against a preference — and each is recorded here because a rejection that is not written down is not a decision, it is a memory.

**The guarded self-repair loop.** Veriflow's `repair/{patch,guard,planner,select,loop,diff}.py` proposes a patch, screens it incrementally, re-verifies it fully, and accepts it only on improvement, with the rejection codes `REPAIR_REJECTED_REGRESSION`, `INVALID_PATCH` and `NO_IMPROVEMENT` (`docs/INNOVATION.md` §4). It is a good design and it is **not borrowable here**: §1 of this document says *"The analyzer never mutates the analyzed module. It reads source files, executes a model of them, and writes only under `reports/`."* A repair loop is a different product — a fixer — and putting one in this module would break that property at the root rather than extend it. What **is** borrowable is the shape of the decision: the loop is a JUDGE that decides and a PROPOSER that proposes, with acceptance settled by measurement. This analyser is the judge and proposes nothing, which is the same separation with the proposer left empty. What would reverse this: a **separate** tool that consumes LunaFlow's findings and proposes patches — a different repository, not this one.

**The web UI ("Verification Studio").** Veriflow's Studio highlights the path of a constraint in the browser (`docs/INNOVATION.md` §3: "Studio 点击 constraint 高亮 path"). It is not borrowable here because it contradicts a **stated** design decision rather than a taste: §1 of this document fixes the visualization carrier as *"Markdown with embedded Mermaid diagrams only (no server, no HTML, no binary images)"*. A UI would not make this tool better at what it is — it would change what it is, and the deliverable is a Markdown report that a registry user reads without installing anything. What would reverse this: a decision to change the carrier, which is a design change with its own costs, not a borrowing.

**The natural-language → IR pipeline.** Veriflow compiles a specification into a canonical IR (`packages/ir/veriflow_ir/graph.py`) and verifies the IR. It is not borrowable here because this project starts at MoonBit source and **parses** it: the CFG, the value domain and the abstract fixpoint are already the intermediate forms the analyses own. An IR layer would sit between the parser and every claim, and would put a second, unaudited representation between the source and each finding — so every claim would need a new argument that the IR agrees with the source. That is a rewrite of the front half of the pipeline, not an addition to it.

These are verdicts on what fits **here**, not on the peer: the repair loop, the Studio and the IR pipeline are each a coherent answer to a different question, and a project that asked those questions would be right to take them.

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
| D8 | 352 unit/integration tests | `src/app/*_test.mbt` |

The raw traces of D5 are committed to the repository and are **not** part of the
published package (§7.2): the registry refuses an archive it cannot read, and they
are what made it unreadable.

### 10.2 Acceptance criteria (quantified, reproducible)

| ID | Criterion | Threshold | Measured |
| --- | --- | --- | --- |
| A1 | Build | `moon build src/cli --target native` exits 0 | 0 |
| A2 | Tests | `moon test src/app --target native` ≥ 352 passed, 0 failed | 352/352 |
| A3 | Acquisition | both coordinates resolve; resolved version recorded in §1 | 0.164.66, 0.5.4 |
| A4 | Frontend coverage | ≥ 95 % statements understood on both modules | 99.08 %, 95.88 % |
| A5 | CFG | ≥ 1 diagram per module; every diagram ≤ 90 nodes; Mermaid validator reports 0 issues | 8 diagrams each; validator clean |
| A6 | Dead code | fixture reports exactly 3 `DEAD-CODE` + 1 `UNREACHABLE` | 3 / 1 |
| A7 | Infinite loop | fixture `spin` yields ≥ 1 `INFINITE-LOOP`; unit test pins it | 1 |
| A8 | Taint | fixture yields ≥ 1 `TAINT-INDEX`; each target yields ≥ 1 sink | fixture 8; doubleML 265; static 291 |
| A9 | Ranges | per-point table non-empty; ≥ 1 numeric variable per module | non-empty on all reports |
| A10 | Slicing | doubleML `theta_hat@aggregate_coef_se` ≥ 4 nodes; static `buf@render_reports` ≥ 1 node | 4, 1 |
| A11 | Runtime | ≤ 60 s per module on a warm cache | 16.0 s, 14.2 s |
| A12 | Artifact size | report ≤ 512 KB; trace ≤ 128 MB | 416 KB / 76.3 MB; 279 KB / 106.2 MB |
| A13 | Determinism | two runs produce identical `summary.json` except `elapsed_ms` | verified |
| A14 | Verifier | `node scripts/verify.mjs` exits 0 | 87/87 checks pass |
| A15 | L2 runs | `abstract_findings ≥ 1` on both targets and the fixture | 3326 / 188 / 15 |
| A16 | L3 on fixture | ≥ 1 `proved` and ≥ 1 `failed` VC | 2 proved, 1 failed, 3 unknown |
| A17 | Funnel report | every report contains the funnel Mermaid diagram and L1/L2/L3 rows | present in all three |
| A18 | Cumulative levels | `--level N` runs levels 1..N; `--funnel` runs all three | covered by unit + E2E runs |

A6/A7 are pinned by unit tests rather than by the report, so they remain valid even if the fixture changes; A8–A10 and A15–A17 are checked from the generated reports by `scripts/verify.mjs`.

**Where the "Measured" column comes from.** It records the **committed artefacts** in
`reports/`, regenerated with the release recipe — `--funnel --trials 4` and
one slice each, with **no** `--max-functions` cap — when `@latest` resolved to
**0.164.66** and **0.5.4**. Every cell is that artefact's own counter, so it is
traceable to a file: A4 is `(statements − unsupported) / statements`, A11 is the
artefact's `elapsed_ms`, A12 is the artefact's size on disk, and A10 is the node
count of the slice section. `scripts/qa/e2e.mjs` re-measures the same thresholds
against **fresh** runs.

A12's trace ceiling is the tightest margin, and it moves with the coverage: it
was 64 MB, and the default scan's step budget took the doubleML trace from
**37.6 MB** to **76.3 MB** — the scan now enters every function the budget
covers instead of the first 150 in file order. The ceiling moves to **128 MB**
with it, and the E2E's own doubleML-full run carries its own, looser ceiling
(**192 MB**) for the same reason.

---

## 11. Known gaps and next iterations

1. Parse `match`, closures and `impl` bodies; model ADT payloads instead of treating them as unknown.
2. Field- and index-sensitive taint (per-element labels) and a small alias set for `Ref`.
3. Optional native probe instrumentation (source rewriting + a probe library) so compiled execution, not only the interpreter, emits the trace.
4. Stream trace events to disk with a bounded buffer to remove the 27 MB JSONL spike.
5. Path enumeration from the CFG with feasibility pruning, to report *unexecuted* paths rather than only observed ones.
6. Package-qualified slice criteria (`<pkg>::<fn>`), now that the trace has file paths.
7. Diff mode: compare two versions' findings and coverage.