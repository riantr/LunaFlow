# Deep QA report — LunaFlow (`riantr/LunaFlow`) @ 0.1.29

Date: 2026-11-19
Scope: the whole repository in `D:\src\MiniMax\Projects\MoonBit\moonbit_LunaFlow`, **the 0.1.29 release candidate** — the published 0.1.28 plus the Phase-0 IFDS spike, the abstract layer's scope fix (D4) and the deprecation migration (S1)
Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`, native backend, Windows 11 x64
Toolchain (the CI runner's): `moon 0.1.20261117 (eb64713 2026-11-17)`, core `0.10.21+06da1ed44` — **the whole gate re-run against it, side by side, and green**
Node: v24.17.0 (all QA harnesses are dependency-free)

Requested dimensions: SAST / DAST / 依赖 / 单元 / 集成 / API / 契约 / 组件 / Gherkin / E2E /
覆盖率 / Fuzz / 性能 / 负载 / 重复代码 / 指标, plus three this pass adds — the Phase-0
IFDS spike, a **registry self-check** (the published tool analysing the published module)
and a **peer scan** (an independent analyzer on the same tree).

Disposition: **report everything; fix only what is a defect in this module.** The first
pass measured and reported and touched no production file. The second pass fixed the
two findings that were defects here — D4 and S1 — and re-measured everything on the
changed tree, which is where the numbers below come from. Two findings are *not*
defects in this module and are attributed to their owner rather than fixed here; that
is recorded in §2.

The previous pass is `docs/qa/REPORT.md` (0.1.3, dated 2026-11-10). It is kept as that
pass's record; this file is the current one.

---

## 1. Verdict

| Dimension | Result | Evidence |
| --- | --- | --- |
| SAST | ✅ gates green — **0 errors, 80 warnings** (80 native / 80 wasm / 105 js), `moon fmt --check` exit 0, and **0 deprecated** after S1 | `scripts/qa/warn_census.mjs` |
| DAST | ✅ 110/110 fuzz cases, 7/7 output-confined, 0 escapes, 0 crashes, degrade-to-gap holds | `fuzz.mjs`, `path_traversal.mjs`, `vendor_isolation.mjs` |
| 依赖 (dependencies) | ✅ **no pinned dependency at all** — the runtime comes from the toolchain-bundled `moonbitlang/core`; 15 core declarations identical in every core; 108 host imports covered | `core_compat.mjs`, `host_requirements.mjs` |
| 单元 (unit) | ✅ **229/229** on native, wasm **and** js | `moon test src/app --target <t>` |
| 集成 (integration) | ✅ 56/56 E2E, 122/122 root-package checks, the IFDS harness 4/4 | `e2e.mjs`, `root_package.mjs`, `ifds_spike.mjs` |
| API | ⚠️ **293** public declarations (125 top-level fn, 103 methods, 65 structs); the CLI consumes **48** of the 125 | `src/app/pkg.generated.mbti` |
| 契约 (contract / L3) | ✅ 2 proved / 1 failed / 3 unknown, the fixture's three-state semantics intact | self-scan, `contract_edges_test.mbt` |
| 组件 (component) | ✅ per-engine tests for lexer/parser/CFG/interp/abs/contract/funnel/report/scan; 223 tests in the test scope | `src/app/*_test.mbt` |
| Gherkin | ✅ **7/7** scenarios | `scripts/qa/gherkin.mjs` |
| E2E | ✅ **56/56**; doubleML full run 17,510 ms, report 446 KB, trace 67.8 MB, 436,497 events | `scripts/qa/e2e.mjs` |
| 覆盖率 (coverage) | ⚠️ **52.92 %** line coverage (4,036/7,627) — up from 33.14 %; but `src/command/command.mbt` is at **0 %** | `moon coverage analyze/report` |
| Fuzz | ✅ **110/110** in 14.8 s (seed 20261110) | `scripts/qa/fuzz.mjs` |
| 性能 (performance) | ✅ peak working set **451.8 MB** on the heaviest run, 2.5 MB on a fixture run | `scripts/qa/load.mjs` |
| 负载 (load) | ✅ 4 concurrent runs → **3.88×** (7,319 ms → 1,885 ms); 2.86× and 3.71× in two earlier runs of the same harness | `scripts/qa/load.mjs` |
| 重复代码 (duplication) | ⚠️ **10.2 %** (2,306/22,532 code lines), 360 clusters — up from 6.5 % | `scripts/qa/dup.mjs` |
| 指标 (metrics) | ✅ 44 files, 27,798 lines (22,059 code), 649 functions, 3,694 decision points, 17.3 % comments, **0** TODO/FIXME | `scripts/qa/metrics.mjs` |
| Phase-0 IFDS spike | ✅ M1/M2/M3 hold on **three** corpora (fixtures, published LunaFlow, doubleML) with **0 lost sinks**; the measurement found 3 real product defects | `scripts/qa/ifds_spike.mjs`, `docs/qa/IFDS_SPIKE.md` |
| Registry self-check | ✅ the published 0.1.28 runs on itself end to end — exit 0, 94.7 % frontend coverage, 0 parse issues | `moonx riantr/LunaFlow@latest riantr/LunaFlow@latest` |
| Peer scan | ✅ **13 actionable, and none of them is a defect in this module** | `moonx riantr/moonbit_static_analysis@latest …` |

**The 30-step deep-QA driver is green** (`_build/qa/deepqa_driver.mjs`), and the
28-step local gate is green on the same tree.

**This pass ran twice.** The first pass measured and reported; the second pass
fixed the two findings that were defects in this module — **D4** (the abstract
layer's scope) and **S1** (87 deprecated core APIs) — and then re-measured
everything on the changed tree. Every number in §1 and §3 is the **post-fix**
measurement, and the "before" numbers survive in §2's table. Two further
defects surfaced during the re-measurement and are registered as **S12** (the
E2E harness could read a stale artefact) and **S13** (the abstract layer's
universe includes test functions, which the code comment denied).

The register's remaining shape is unchanged: nothing here breaks a gate today,
and nothing here is a defect in this module except the three that are fixed.

---

## 2. Findings

Severity: **High** = wrong output, crash, or security-relevant; **Medium** = a
documented promise the code does not keep, or a gate that silently fails; **Low** =
hygiene.

**D4 and S1 were fixed in the follow-up pass**, after this report's measurement; the
other findings are registered, with the measurement that establishes each one.

### Fixed after the measurement

| # | Sev | Finding | The fix | Evidence |
| --- | --- | --- | --- | --- |
| D4 | Medium | **The default `--max-functions 150` capped the L2 abstract layer, and the report did not say so where it matters.** `run_abstract(ast, opts.max_functions, 200000)` took the same cap as the interpreter, so on LunaFlow's own 957-function source the default analysed **150 functions — 16 %** of the module. The funnel table said `150 functions` (§3.2), but §5.2 printed `_No findings._` with no scope caveat, so a reader could not tell that 84 % of the module had never been looked at. | The abstract layer's scope is now **the whole module**: the caller passes the module's analysable functions, the layer is bounded by a new **total** step budget instead, and §5.2 states the scope in words — *"The abstract layer analysed 1411 of 1411 — every function the abstract layer can analyse, in 167271 steps."* The `--max-functions` cap now bounds the **dynamic** layer's entry points, and therefore the trace, which is what it was always for. | the scope line in §5.2; the L2 row of §3.2; §3.15's default-vs-lifted table |
| S1 | Medium | **87 deprecated-API warnings in production code**, all from the toolchain's core: 36 × `StringBuilder::new()`, 28 × `Map::new()`, 17 × `String::to_string()`, 4 × `not(x)`, 1 × `Show`, 1 × `Ref::new`. Concentrated in `report.mbt` (27), `util.mbt` (14), `lexer.mbt` (8), `analyze.mbt` (7). | All 87 migrated to the forms the compiler names: `StringBuilder()`, `Map([])`, `.to_owned()`, `!x`, `Ref(x)`, `debug_inspect`. The migration was driven by **the compiler's own site list**, not a blanket replace — only 17 of the 37 `.to_string()` calls were deprecated, because the other 20 are on a `String` and only a `StringView` receiver is. | `moon check`: **167 → 80 warnings**, 0 errors, **0 deprecated** |

**The S1 migration had to be a loop, and that is the reusable part of it.** The
compiler reports a deprecated *impl* at **one** site: fix that site and the same
warning reappears at the next site that uses that impl. A single pass over the
compiler's site list therefore leaves the tree with the same number of warnings
and a different set of sites — the count never reaches zero on its own. The
migration ran until the compiler reported none, and it needed two rounds.

The last one is worth naming, because it reads like a compiler bug and is not.
The prelude's `inspect` takes `&Show`, and `Show for X?` is deprecated in this
core, so `inspect(<an Option>)` selects a deprecated impl; `debug_inspect` takes
`&Debug` and does not. The compiler points at the **argument expression**, not at
the call — so a script that rewrote only the text the compiler highlighted would
have rewritten the wrong thing.

### Registered

| # | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| S2 | Medium | **10 public types never occur in a public signature** (`missing_priv`): `Builder`, `CState`, `CWalk`, `ConcArrays`, `ConcCycle`, `EvaState`, `Interp`, `P`, `WalkState`, `Opts`. Nine of the ten are new since 0.1.3; `Opts` was already registered then. They are published for no consumer. | `moon check` `missing_priv` |
| S3 | Medium | **The CLI layer has 0 % line coverage.** `src/command/command.mbt` contributes 394 instrumented lines and is covered by **none** of them; `src/cli/main.mbt` likewise. The CLI is exercised only end-to-end (E2E, Gherkin, fuzz), so a defect in its argument handling is invisible to `moon coverage`. | `_build/qa/coverage.xml` |
| S4 | Low | **Duplication grew from 6.5 % to 10.2 %** (2,306/22,532 code lines, 360 clusters). The largest clusters are the same 8-line `ModuleAst` literal repeated in 9–11 test files, and a 20-line clone inside `conc.mbt`. | `scripts/qa/dup.mjs` |
| S5 | Low | **Low-coverage production files**: `scan.mbt` 11 %, `report.mbt` 32 %, `util.mbt` 34 %, `interp.mbt` 35 %, `contract.mbt` 47 %, `memory.mbt` 50 %. `scan.mbt` is the module loader the self-check depends on. | `_build/qa/coverage.xml` |
| S6 | Low | **The published API grew from 204 to 293 declarations** (+43.6 %) while the CLI consumes 48 of the 125 top-level functions. 77 top-level public functions are not consumed by the CLI — the same trade the 0.1.3 pass recorded, now larger. | `src/app/pkg.generated.mbti` |
| S7 | Low | The Phase-0 spike adds **1,518 lines, 43 functions and 144 decision points** to `src/app/` (1,023 code lines). It is invisible to the CLI, to the published interface and to the peer's actionable count — but it is inside the package the CLI builds. | `metrics.mjs`; peer scan |
| S8 | Low | The **published 0.1.28 does not contain the spike**: the working tree is 51 files / 1,007 functions where the registry serves 50 / 957. The two trees are not interchangeable, and a report that says "LunaFlow @ 0.1.28" means the published one. | self-scan vs registry self-check |
| S9 | Medium | **The full abstract scope costs report size.** On doubleML the report grew from **134 KB to 445 KB** — **87 % of the documented A12 limit of 512 KB** (455,994 B of 524,288 B) — and the wall time from 11.7 s to 24.9 s (**41 % of A11's 60 s**). Both budgets still hold for the documented corpora, but the headroom is much thinner than it was, and a module 15 % larger would break A12. | the regenerated artefacts in `reports/`; the E2E run |
| S10 | Low | **The abstract layer's volume is dominated by one may-family.** On doubleML, 824 of the 1,282 L2 findings are `RANGE-VIOLATION` — *"assertion may fail on some inputs"* — because the interval domain cannot prove an `assert` holds. At module scale that family is mostly noise, and the report's §5.2 is now dominated by it. | the family table in `reports/…doubleML….md` |
| S11 | Low | **The E2E harness could test a stale binary.** It resolves `cli.exe` from the build tree and never rebuilds it, so it measured the analyser as it *was*: the abstract layer's scope change was measured against the old build and reported the old scope. The harness now **builds what it tests**, before any timed run. | `scripts/qa/e2e.mjs` |
| S12 | Medium | **The E2E harness could read a stale artefact** — the same shape as S11, one layer further out. The artefact file names carry the resolved version, so the output directory accumulates one set of files per version, and the harness picked the report with `readdirSync().find()`, which returns the **first** match. MEASURED: the run wrote `…_0.5.0.md` and the harness measured `…_0.4.45.md`, dated **nine days earlier**, because that name sorted first. Every count it reported for that module — statement count, report size, L2 finding count, even the "resolved version" — was a week-old number, and the run still passed 56/56. | `scripts/qa/e2e.mjs` |
| S13 | Low | **The abstract layer's universe includes test functions, and the code comment said it did not.** The module as scanned holds every `.mbt` file the scanner found — test files included; the scanner excludes build and vendored trees, not `_test.mbt`. The D4 fix's comment claimed the universe was "the module's functions that are **not** in test files". It is not, and the difference is not small: for doubleML, **129 of its 220 `.mbt` files are test files**. The comment now says what the code does. The finding split is what says how much of the output is about test code — measured on the committed doubleML artefact, **24 of the 926 findings shown in §5.2 (2.6 %) are in test files**, so the output is overwhelmingly about production code. | `src/command/command.mbt`; `_build/qa/l2_test_split.mjs` |

### Registered to another owner

| # | Sev | Finding | Owner |
| --- | --- | --- | --- |
| P1 | Medium | `riantr/moonbit_static_analysis` 0.5.0 reports `too many arguments to 'walk_dir': expected 5, got 6` (ArgTypeMismatch, `type`/MSA-007) on `src/app/scan.mbt:333` and `:355`. `scan.mbt` declares `walk_dir` **twice** under mutually exclusive `#cfg` predicates — six parameters at `:291`, five at `:414` — and the native variant's call site passes six, which is correct. **Reproduced in a 20-line module unrelated to LunaFlow**: the peer emits the same error while `moon check --target native` and `--target js` both report 0 errors. The peer documents this hazard itself (`src/interp/interp.mbt:280-284`: *"the arity and parameter-type checks must not run against either of them"*) and has a `duplicate_names`/`ambiguous` guard, but the finding is tagged `[type, MSA-007]`, so it comes from the type lens, whose duplicate-name fix did not suppress the arity check. **Nothing in LunaFlow should change to silence it.** | the peer |
| P2 | — | The peer's other 11 actionable findings are **not defects either**: 8 are `UnusedParam` on the js-backend stubs (`scan.mbt:414`, `:426`, `:403`), whose bodies are empty by design because the js backend has no filesystem; and 3 are on `fixtures/eva_demo/lib.mbt` (`:44` `100 / 0`, `:65` `a[-1]`, `:138` a dead store) — the **intentional vulnerability-demo fixtures**, one of which carries the comment *"the idiomatic mutable Option must NOT be reported"*. | — |
| P3 | — | The peer reads **3 of LunaFlow's files only up to their first parse error** (`src/command/command.mbt` "expected `)`", `src/app/ffi.mbt` "unexpected token `,`", `src/app/ipc.mbt` "expected loop variable"). It reports 0 findings withheld from them, so nothing is hidden — but nothing is known about them either, and 530 of its notices are its own subset boundaries (223 test declarations, 87 struct declarations, 27 const, 20 enum, 15 extend, 1 type). | — |

---

## 3. Dimension detail

### 3.1 SAST

`moon check --target native | wasm | js` → **0 errors**; `moon fmt --check` → exit 0.

| category | native | wasm | js |
| --- | ---: | ---: | ---: |
| deprecated | **0** | **0** | **0** |
| test_unqualified_package | 59 | 59 | 59 |
| missing_priv | 10 | 10 | 10 |
| unused_value | 7 | 7 | 21 |
| unused_async | 2 | 2 | 7 |
| unreachable_code | 1 | 1 | 1 |
| struct_never_constructed | 1 | 1 | 2 |
| unused_package | 0 | 0 | 3 |
| unused_field | 0 | 0 | 2 |
| **total** | **80** | **80** | **105** |

The count is the **post-fix** number. Before S1 it was **167**, of which **87 were
deprecated** core APIs (36 × `StringBuilder::new()`, 28 × `Map::new()`, 17 ×
`String::to_string()`, 4 × `not(x)`, 1 × `Show`, 1 × `Ref::new`); the 0.1.3 pass
reported 133. The js target's extra 25 are the js-backend stubs, which are dead
code there. The `test_unqualified_package` notices are the toolchain's rule for a
blackbox test reaching a package-private name, and they are catalogued rather
than hidden.

**The newest toolchain gives the same census.** Re-run against `moon 0.1.20261117`
(core `0.10.21+06da1ed44`): **80 / 80 / 105 warnings, 0 errors, 0 deprecated** — the
same categories, the same counts — and **229/229 tests** on native, wasm and js,
with `moon fmt --check` and all four builds exit 0. The S1 claim is therefore not
a claim about one toolchain: the deprecated set is the same on both, and it is
empty on both.

### 3.2 DAST

There is no HTTP surface — the product is a CLI that writes files. "DAST" here means
dynamic testing against hostile input.

| Surface | Input | Outcome |
| --- | --- | --- |
| Module sources | mutated / truncated / invalid-UTF-8 / pathological `.mbt` | 110/110 ok, 15.2 s |
| `moon.mod` manifest | `name`/`version` with `/`, `\`, `..`, control chars, quotes | 7/7 confined, 0 escape |
| Nesting depth | 10 → 5,000 nested `if` | exit 0 at every depth; degrades at 256 |
| CLI arguments | missing values, negative/huge numbers, unknown flags | graceful |
| Output directory | `--out` with/without value, traversal strings | confined |
| Vendored trees | a file planted behind every skipped directory name | only the module's own source parsed |

The nesting curve is the honest one: the guard is `MAX_PARSE_DEPTH = 256`, and past it
the frontend skips the whole construct and counts it as **one** unsupported statement,
so the coverage metric cannot read ~100 % on a file that is 99 % skipped.

| nest depth | exit | stmts | unsupported | parse issues |
| ---: | ---: | ---: | ---: | ---: |
| 250 | 0 | 251 | 0 | 0 |
| 256 | 0 | 254 | 1 | 1 |
| 5,000 | 0 | 254 | 1 | 1 |

### 3.3 Dependencies (依赖)

| Item | Value | Note |
| --- | --- | --- |
| pinned dependencies | **none** | the async runtime is the toolchain-bundled `moonbitlang/core`; `moon.mod` has an empty import block, so no pin can disagree with the toolchain that builds the artifact |
| core compatibility | ✅ 15 declarations identical in **every** core a user may have, + 1 test-only declaration identical in every core | `core_compat.mjs` |
| host contract | ✅ 108 function imports, ABI module `moonbitlang/async` | `host_requirements.mjs` |
| registry | `riantr/LunaFlow` latest **0.1.28**, `build_status: success`, not yanked, **no direct dependencies** | mooncakes API |

### 3.4 Unit / integration / component

`moon test src/app --target native | wasm | js` → **229/229 on every target**.

Integration is covered from three directions: the library→report path by
`pipeline_test.mbt`; the library→CLI→filesystem path by `e2e.mjs` (56/56) and the
Gherkin scenarios (7/7); and the registry→analyser→report path by the registry
self-check in §3.15. `root_package.mjs` adds 122 checks, including that every CLI flag
is documented in the README **and** that every flag the README documents is one the
CLI accepts (25 flags, both directions).

### 3.5 API

`src/app/pkg.generated.mbti`: **293** top-level public declarations — 125 functions
(of which 2 are `async`), 103 methods over 47 types, 65 structs. The CLI consumes
**48** of the 125 top-level functions; 77 are not consumed by it.

The Phase-0 spike adds **nothing** to the published API — which is the point of
keeping the engine in a `*_wbtest.mbt` file. The D4 fix adds exactly **one** line:
`abs_universe : Int32` on `pub(all) struct ReportInput`, a module-internal struct no
consumer can construct. It is an API-visible change and it must be declared in the
release notes.

### 3.6 Contracts (契约, L3)

Deductive verification is WP-style and three-state. The self-scan of this tree
produces **2 proved / 1 failed / 3 unknown** over 4 functions with contracts, and the
fixture's semantics are unchanged. A malformed annotation becomes a VC with
`kind = "contract-syntax"` and status `failed` — distinguishable by `kind`, but a
reader counting "failed proofs" counts typos too.

### 3.7 Gherkin

**7/7** scenarios: the pinned fixture findings, a complete renderable report,
determinism across two identical runs, the two hostile-module properties, the
malformed-command-line property, and the toolchain gates.

### 3.8 E2E

**56/56** checks. The heaviest run (doubleML 0.164.64, full analysis):

| Measurement | Value |
| --- | ---: |
| wall time | 17,510 ms (A11 limit: 60,000 ms) |
| report size | 456,985 B (A12 limit: 512 KB) |
| trace size | 67.8 MB (A12 limit: 96 MB) |
| trace events | 436,497 |
| dead-code findings | 0 |
| taint sinks | 125 |
| L2 findings | 1,282 (the documented full-scope number) |

The L2 count is the point of D4: before the fix this run reported **187**, because
the abstract layer was still bounded by the interpreter's entry-point cap. The
committed artefact is the full-scope run, and 1,282 is its number.

The E2E harness itself had a defect of its own until this pass — it could read a
**stale artefact** (S12) and report a week-old count as a fresh one. The numbers
above are from the fixed harness.

### 3.9 Coverage (覆盖率)

| Scope | Covered / valid | Rate |
| --- | ---: | ---: |
| whole report | 4,036 / 7,627 | **52.92 %** |
| production only (`src/`, non-test) | 4,036 / 7,445 | 54.21 % |

Up from **33.14 %** at 0.1.3. The lowest-covered production files are
`src/cli/main.mbt` and `src/command/command.mbt` at **0 %** (S3), `scan.mbt` at 11 %,
`report.mbt` at 32 %, `util.mbt` at 34 % and `interp.mbt` at 35 %.

### 3.10 Fuzz

**110/110** in 14.8 s, seed 20261110.

### 3.11 Performance (性能) and 3.12 Load (负载)

| Measurement | Value |
| --- | ---: |
| peak working set, doubleML full run | **451.8 MB** |
| peak working set, fixture run | 2.5 MB |
| 4 concurrent runs | 7,319 ms → 1,885 ms (**3.88×**) |

Three runs of the same harness gave 2.86×, 3.71× and 3.88×; the honest claim is
**2.9–3.9×**, not a single figure. Every run completed.

### 3.13 Duplication (重复代码)

**10.2 %** (2,306/22,532 code lines), 360 clusters of ≥6 lines. The largest clusters
are the same `ModuleAst` literal repeated in 9–11 test files; one 20-line clone sits
inside `conc.mbt`.

### 3.14 Metrics (指标)

| scope | files | lines | code | comment | blank | comment % | functions | decisions | avg code lines/fn | tests | TODO |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| all src | 44 | 27,798 | 22,059 | 4,617 | 1,122 | 17.3 % | 649 | 3,694 | 34.0 | 229 | 0 |
| production | 24 | 23,275 | 18,680 | 3,789 | 806 | 16.9 % | 598 | 3,482 | 31.2 | 6 | 0 |
| tests | 20 | 4,523 | 3,379 | 828 | 316 | 19.7 % | 51 | 212 | 66.3 | 223 | 0 |
| fixtures | 6 | 1,010 | 473 | 414 | 123 | 46.7 % | 77 | 30 | 6.1 | 0 | 0 |

The largest files are `ffi.mbt` (2,561 lines), `parser.mbt` (2,156),
`conc.mbt` (1,851), `report.mbt` (1,823) and `abs.mbt` (1,718). The longest functions
are `P` (the parser, 2,041 lines / 438 decision points), `render_report` (589),
`analyze` (435) and `abs_stmt` (406).

### 3.15 Registry self-check (new this pass)

`moonx riantr/LunaFlow@latest riantr/LunaFlow@latest` — the published tool analysing
the published module. Exit 0; report, trace and summary written.

| Measurement | Value |
| --- | ---: |
| files / functions / statements | 50 / 957 / 6,104 |
| frontend coverage | 94.7 % (340 statements unsupported) |
| parse issues | 0 |
| dead code / unreachable / infinite loop | 0 / 0 / 0 |
| taint sinks (default scope) | 7 |
| wall time | 849 ms |

The **working tree** self-scan (`--dir . --funnel`) reads 51 files / 1,007 functions /
6,388 statements and reaches the same 7 taint sinks, because the default scope cap
puts both trees' interesting code out of reach **on the dynamic layer**.

After D4 the cap and the abstract layer no longer move together, and the table says
so:

| | default (`--max-functions 150`) | `--max-functions 1000` |
| --- | ---: | ---: |
| L1 taint sinks | 7 | **39** |
| L2 abstract findings | **46** | **46** |
| trace events | 9,903 | 117,204 |

The **L2 row is the same on both sides — that is the fix.** Before it, the L2 read
**1** finding at the default and 46 at the lifted cap, because the abstract layer was
bounded by the interpreter's entry-point cap; now it reads the whole module either
way, and the cap moves the dynamic layer and the trace alone.

### 3.16 Phase-0 IFDS spike (new this pass)

The spike is a flow-sensitive taint fixpoint in IFDS style, unintegrated and
invisible to the CLI. Its harness checks four measurements and **falsifies each one
on purpose** — a check that cannot fail is not a check.

| Corpus | files / funcs / stmts | L2 sites | spike plain | spike with rule | rule added | spike-only | **L2-only (lost sinks)** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fixtures/` | 6 / 77 / 232 | 5 | 8 | 10 | 2 | 5 | **0** |
| published LunaFlow 0.1.28 | 50 / 957 / 6,104 | 14 | 40 | 70 | 30 | 56 | **0** |
| `riantr/moonbit_doubleML@0.164.64` | 220 / 2,529 / 30,258 | 81 | 1,286 | 1,316 | 30 | 1,235 | **0** |

M1 (no lost sink) holds on all three, M2 (the blanket rule's contribution is exactly its
own sites) holds, and M3 (the model's gaps never exceed the parser's unmodelled
count) holds. On the published source the 56 spike-only sites decompose into
**unknown container 29, array 24, dead allocation rule 2, allocation container 1** —
and the dead-allocation family is confirmed dead: the published tool reports **zero**
`TAINT-ALLOC` findings even at full scope, because it matches `Array::make` while the
parser renders `Array.make`.

The full verdict, with the attribution of every one of the 1,235 doubleML sites and
the three product defects the measurement found, is `docs/qa/IFDS_SPIKE.md`.

### 3.17 Peer scan (new this pass)

`moonx riantr/moonbit_static_analysis@latest …` — an independent analyzer on the same
tree.

| | published 0.1.28 | working tree |
| --- | ---: | ---: |
| files scanned | 60 | 61 |
| parsed | 57 (95.0 %) | 58 (95.0 %) |
| **actionable** | **13** | **13** |
| notices | 513 | 530 |
| unreliable | 37 | 37 |
| unchecked calls | 2,322 | 2,442 |

The actionable count did **not** move: the 47 KB spike file contributes **0**
actionable findings. All 13 are attributed in §2 (P1, P2) — none is a defect in this
module. The peer exits 0 even when it fails, so a caller must read its output rather
than its exit code.

---

## 4. Changes made in this pass

**The first pass touched no production file.** It measured, attributed and
registered. The second pass fixed the two findings that were defects in this
module and re-measured everything on the changed tree.

Production changes, all in the second pass:

* **D4 — the abstract layer's scope.** `src/app/abs.mbt` (`run_abstract` gains a
  total step budget), `src/command/command.mbt` (the caller passes the module's
  analysable functions instead of the interpreter's cap), `src/app/report.mbt`
  (`ReportInput` gains `abs_universe`, §5.2 gains a scope line),
  `src/app/ffi_test.mbt` and `src/app/repair_test.mbt` (the two `ReportInput`
  literals), `src/app/pkg.generated.mbti` (regenerated by `moon info`; **one**
  line added).
* **S1 — the 87 deprecated core APIs**, across `src/app/{abs,analyze,cfg,conc,
  contract,eva,family,interp,lexer,model,parser,report,util}.mbt` and
  `src/app/pipeline_test.mbt`.
* **S12 — the E2E harness's stale artefact**: `scripts/qa/e2e.mjs` now empties
  each output directory before the run.
* **S13 — the wrong comment about the universe**: `src/command/command.mbt`.

Harness and documentation changes:

* `scripts/verify.mjs` — the summary pin follows the artefact's new version
  (`…_0.5.0_summary.json`); the old pin still named `…_0.4.50_summary.json`, and
  the acceptance verifier failed on it.
* `scripts/qa/e2e.mjs` — builds the binary it tests (S11), empties the output
  directories (S12).
* `docs/design.md`, `README.md`, `docs/qa/REPORT.md` — the numbers in this
  report, and the README's pointer to it.
* `docs/qa/IFDS_SPIKE.md`, `scripts/qa/ifds_spike.mjs`,
  `src/app/ifds_spike_wbtest.mbt` — the Phase-0 spike (the first pass).
* The three committed artefacts under `reports/` were **regenerated**, and the
  superseded `riantr_moonbit_static_analysis@latest_0.4.50.*` set was removed.

---

## 5. What is *not* verified

* **This pass ran against the release candidate, before it was published.** The
  registry served 0.1.28 while it ran, and the tree it measured carried the
  spike, D4 and S1 on top of that. Every number above that says "working tree"
  says so.
* **The newest toolchain is a moving target.** The local toolchain is
  `moon 0.1.20261104`; the CI runner installs whatever the CDN serves as `latest`.
  The gate was re-run against `moon 0.1.20261117` in a scratch home — **green, with
  identical warning counts and 229/229 tests on all three targets** — but that is a
  measurement of *today's* `latest`, and it is re-measured before every release.
* **Performance was measured on one machine** (Windows 11, warm `.repos` cache) with
  no cold-cache and no Linux measurement. The load speedup varied 2.86–3.88× across
  three runs.
* **`src/cli` and `src/command` have no unit tests** and 0 % line coverage; their
  logic is exercised only through the E2E, Gherkin and fuzz harnesses.
* **No penetration testing of `moon fetch`'s download path** — acquisition is
  delegated to the toolchain.
* **The peer scan is one analyzer's opinion.** Three of this module's files were not
  fully parsed by it, and 530 of its notices describe its own subset boundaries.
* **The IFDS spike is measured, not integrated**: it has no CLI flag, no report line
  and no funnel place, and its four measurements are about the spike versus the L2,
  not about whether the L2 should be replaced.
* **The coverage measurement covers `src/` only.** The fixtures are instrumented and
  report 0 %, and `src/app/ifds_spike_wbtest.mbt` reports `n/a`.
* **The abstract layer's universe includes test functions** (S13). The split is
  measured on the committed doubleML artefact — 24 of 926 findings in §5.2 are in
  test files — but it is measured on **one** module, not on every module the tool
  will ever see.

---

## 6. Reproduce

```sh
# The whole suite, one driver, 30 steps, each logged separately.
node _build/qa/deepqa_driver.mjs

# Or step by step.
moon fmt --check
moon check --target native
moon test src/app --target native
moon build src/cli --target native
node scripts/verify.mjs                    # committed artefacts
node scripts/qa/e2e.mjs                    # fresh runs + determinism
node scripts/qa/gherkin.mjs                # acceptance scenarios
node scripts/qa/fuzz.mjs                   # 110 robustness cases
node scripts/qa/path_traversal.mjs         # output confinement
node scripts/qa/deep_nesting_probe.mjs     # degrade-to-gap
node scripts/qa/depth_sweep.mjs            # nesting curve
node scripts/qa/metrics.mjs                # size/shape
node scripts/qa/dup.mjs                    # clone detection
node scripts/qa/load.mjs                   # peak memory + parallel
node scripts/qa/warn_census.mjs            # warning triage
node scripts/qa/vendor_isolation.mjs        # vendored-tree isolation
node scripts/qa/core_compat.mjs            # every core a user may have
node scripts/qa/host_requirements.mjs      # the published wasm's host contract
node scripts/qa/root_package.mjs           # the root package moonx resolves
node scripts/qa/ifds_spike.mjs --corpus fixtures --label fixtures
```

The same gate against the **newest** toolchain — the one the CI runner installs — in a
scratch home beside the verified one, so nothing is replaced:

```sh
node _build/qa/newest_toolchain_gate.mjs <toolchain-root> <repo-root>
```

It bundles the core first (without that every target fails with
`... bundle/async/aqueue/aqueue.mi missing`) and then runs the same checks, the same
builds and the same tests against `moon 0.1.20261117`.

Self-scan (the current tree; needs no registry entry):

```sh
moon run src/cli -- analyze --dir . --out _build/qa/selfscan --funnel
```

Registry self-check (the **published** module analysing the **published** module) and
the peer scan — both run outside the repository, because the first materialises the
module into the current directory's `.repos/`:

```sh
moonx riantr/LunaFlow@latest riantr/LunaFlow@latest
moonx riantr/moonbit_static_analysis@latest riantr/LunaFlow@latest
```

Coverage (note the `-f simp_caret` format: the reporter's lexer is stricter than the
compiler's, and `-f caret` cannot read `report.mbt`):

```sh
moon coverage analyze -p src/app -- -f simp_caret
moon coverage report -f cobertura -o _build/qa/coverage.xml
node scripts/qa/metrics.mjs --coverage _build/qa/coverage.xml
```
