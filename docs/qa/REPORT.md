# Deep QA report — LunaFlow (`riantr/LunaFlow`) @ 0.1.1

Date: 2026-11-10
Scope: the whole repository in `D:\src\MiniMax\Projects\MoonBit\moonbit_LunaFlow`
Toolchain: `moon 0.1.20261102 (ea07287)`, `moonc v0.10.19+bee578715`, native backend, Windows 11 x64
Node: v24.17.0 (all QA harnesses are dependency-free)

Requested dimensions: SAST / DAST / 依赖 / 单元 / 集成 / API / 契约 / 组件 / Gherkin / E2E /
覆盖率 / Fuzz / 性能 / 负载 / 重复代码 / 指标.

Disposition of findings was decided by an automatically selected (unanswered)
prompt: **report everything, fix high-severity and confirmed defects, register
the rest**. Nothing was published or pushed; the tree is not a git repository, so
there is no commit history to audit and no diff to review the changes against
(see L5).

---

## 1. Verdict

| Dimension | Result | Evidence |
| --- | --- | --- |
| SAST | ✅ gates green after fixes — 0 errors, 133 warnings (167 at start), `moon fmt --check` exit 0 | `scripts/qa/warn_census.mjs` |
| DAST | ⚠️ no server to scan; the real surface is *analysing hostile input* → three write/crash/scope defects found and fixed | `scripts/qa/path_traversal.mjs`, `scripts/qa/fuzz.mjs`, `scripts/qa/vendor_isolation.mjs` |
| 依赖 (dependencies) | ✅ `moonbitlang/async@0.22.9` is the registry latest; Apache-2.0; 3 dead imports removed | mooncakes API + `moon check` |
| 单元 (unit) | ✅ 37/37 pass (24 before this pass) | `moon test src/app --target native` |
| 集成 (integration) | ✅ pipeline + CLI-vs-library paths green; funnel counters pinned | `pipeline_test.mbt`, `scripts/qa/e2e.mjs` |
| API | ⚠️ 204 public declarations, 43 consumed by the CLI — the whole engine is `pub` | `pkg.generated.mbti` |
| 契约 (contract / L3) | ✅ 6 new edge-case tests; 2 real defects found and fixed (`\nothing`, invariant-only functions) | `contract_edges_test.mbt` |
| 组件 (component) | ✅ per-engine tests exist for lexer/parser/CFG/interp/abs/contract/funnel/report/scan | `src/app/*_test.mbt` |
| Gherkin | ✅ 7/7 scenarios, new `features/acceptance.feature` + runner | `scripts/qa/gherkin.mjs` |
| E2E | ✅ 56/56 checks; committed artefacts reproduced exactly on the documented parameters | `scripts/qa/e2e.mjs` |
| 覆盖率 (coverage) | ❌ **33.14 %** line coverage (1,215/3,666); `report.mbt` 2.7 % | `moon coverage analyze -p src/app -- -f caret` |
| Fuzz | ✅ 110/110 cases after fixes (2 crashes + 1 escape before) | `scripts/qa/fuzz.mjs` |
| 性能 (performance) | ✅ far inside A11/A12; peak RSS 295.9 MB on the heaviest run | `scripts/qa/load.mjs` |
| 负载 (load) | ✅ 4 concurrent runs → 3.70× (near-linear), 0 failures | `scripts/qa/load.mjs` |
| 重复代码 (duplication) | ⚠️ 6.5 % (587/9,100 lines), 86 clusters, concentrated in `contract.mbt` | `scripts/qa/dup.mjs` |
| 指标 (metrics) | ✅ 9,037 code lines, 285 functions, 1,510 decision points, 4.7 % comments, 0 TODO/FIXME | `scripts/qa/metrics.mjs` |

Two defects were severe enough to change the product's claim: the analyzer
**crashed** on a hostile module (stack overflow) and could be steered to **write
artefacts outside `--out`**. Both are fixed and now covered by permanent
regression harnesses.

---

## 2. Findings

Severity: **High** = wrong output, crash, or security-relevant; **Medium** = a
documented promise that the code does not keep, or a gate that silently fails;
**Low** = hygiene.

### Fixed in this pass

| # | Sev | Finding | Evidence | Fix |
| --- | --- | --- | --- | --- |
| H1 | High | **Native stack exhaustion on hostile input.** A module with 5,000 nested `if` statements or 2,000 nested `(` aborted the process with `0xC0000409` (STATUS_STACK_BUFFER_OVERRUN). For a tool whose entire job is analysing untrusted mooncakes modules, `analyze` could be killed by the module under analysis. | `fuzz.mjs` cases `nest-if-5000`, `nest-paren-2000`; `depth_sweep.mjs` | `MAX_PARSE_DEPTH = 256` in `src/app/parser.mbt`, guards in `parse_expr`, `parse_unary`, `parse_block`; deeper constructs are skipped whole and counted as `unsupported_stmts` |
| H2 | High | **Report path traversal.** The output stem is built from the analysed module's `moon.mod` (`name`, `version`). Only `/` was neutralised, so `version = "..\\..\\..\\..\\escaped"` wrote `<out>.md`, `<out>_summary.json` and `<out>_trace.jsonl` into an arbitrary directory (proven: file landed in the parent of the case directory). A hostile module could overwrite same-named artefacts anywhere the process can write. | `path_traversal.mjs` before: `ESCAPE version-backslash` | `safe_stem()` in `src/app/util.mbt` (whitelist `[A-Za-z0-9_@-]` + `.`, `..` collapsed, leading separators stripped), applied to the whole stem in `src/cli/main.mbt` |
| M1 | Medium | **`--out` with no value wrote into the working directory.** `arg_value` returned `""`, `path_join("", x)` returned `x`, so the three artefacts appeared in CWD — silently, with exit 0. | `fuzz.mjs` case `args:--out` (`ESCAPE`), Gherkin scenario 6 | `arg_or()` fallback in `src/cli/main.mbt` for `--dir/--out/--slice/--function/--coverage/--level` |
| M2 | Medium | **`//@ assigns \nothing` recorded a bogus target.** `\nothing`→`__nothing` normalisation only ran for expressions, so the documented spelling became an assignment target literally named `\nothing`. | new `contract_edges_test.mbt` | `src/app/contract.mbt` accepts both spellings |
| M3 | Medium | **Invariant-only contracts produced no VCs.** `Contract::has_spec()` counted `requires`/`ensures` only, so a function whose sole annotation was `//@ invariant` was skipped entirely — contradicting design §4.3 ("invariant is treated as an assumption"). | new test `invariant acts as an assumption for index bounds` | `has_spec()` now counts invariants |
| M4 | Medium | **`moon fmt --check` failed** on the whole tree (formatter rewrote `Int`→`Int32` annotations, brace style, call layout). Any CI gate using it would have been red before this pass. | `moon fmt --check` → exit −1 | `moon fmt` applied; `--check` now exit 0 |
| M5 | Medium | **Deprecated `derive(...)` in 12 places** (trailing `} derive(Eq)` on `BinOp`, `UnOp`, `NodeKind`, `EdgeKind`, `FindingKind`, `Finding`, `EventKind`, `TaintNodeKind`, `SliceDirection`, `TaintMode`, `VCStatus`, `TokKind`). Each also emitted `implicit_impl_as_method`. Under the `--deny-warn` gate convention this is a build failure, and the deprecation is scheduled for removal. | `moon check` warnings 0027/0079 | migrated to `#derive(Eq)` + explicit `pub extend T with Eq::{not_equal, equal}` (`scripts/qa/migrate_derive.mjs` records the transformation) |
| M9 | Medium | 3 unused package imports (`moonbitlang/core/env`, `moonbitlang/core/json`, `moonbitlang/async` in `src/app`; `moonbitlang/async/process` in `src/cli`) — dead dependency edges that widen the build surface. | `moon check` `unused_package` | imports removed |
| M10 | Medium | **A `--dir` scan ingested the vendored dependency tree.** The source walker skipped `_build`, `.git`, `.repos`, `target` and `node_modules` by directory name, but not `.mooncakes` — where the toolchain vendors a module's own dependencies. A self-scan of LunaFlow's workspace reported **384 parsed files, of which 362 came from the vendored `moonbitlang/async` module**: every file, function and statement count in that report described a third party's code. Registry targets are unaffected (the loader's root is `.repos/<owner>/<module>/<version>`, never the workspace), so the damage was confined to `--dir` mode. | self-scan: 384 files parsed vs 22 own `.mbt` files; `.mooncakes` held 362, `.repos` 939 | `.mooncakes` added to the skip list in `src/app/scan.mbt`; new harness `scripts/qa/vendor_isolation.mjs` plants one file behind every skipped directory name and asserts that exactly the module's own source is parsed |

**Regression evidence after the fixes** — every number below is from a run in
this session:

| Harness | Before | After |
| --- | --- | --- |
| `fuzz.mjs` (110 cases) | 107 ok, 2 `EXIT 3221225725`, 1 `ESCAPE` | 110/110 ok |
| `path_traversal.mjs` (7 hostile manifests) | 6 confined, 1 escape | 7/7 confined |
| `depth_sweep.mjs` at depth 5,000 | crash (5,000/2,000) | 254 statements, 1 gap, 1 issue, exit 0 |
| `moon fmt --check` | exit −1 | exit 0 |
| `moon check` warnings | 167 | 133 |
| `moon test src/app` | 24/24 | 37/37 |
| Gherkin | — (did not exist) | 7/7 |
| E2E | — (did not exist) | 56/56 |
| `vendor_isolation.mjs` | 384 files parsed (362 of them foreign) | 1 file parsed, 0 foreign |

One nuance worth recording: the *naive* depth guard was not enough. A first
version skipped one token per trip, which produced 19,236 "statements
understood" plus 18,984 parse issues on a 5,000-level input — no crash, but the
frontend-coverage metric (a headline claim, A4) would have read ~100 % on a file
that was 99 % skipped. The final guard skips the whole construct and counts it as
one unsupported statement, which is what `depth_sweep.mjs` now pins:

| nest depth | exit | stmts | unsupported | parse issues |
| ---: | ---: | ---: | ---: | ---: |
| 10 / 50 / 100 / 250 | 0 | 11 / 51 / 101 / 251 | 0 | 0 |
| 256 … 5,000 | 0 | 254 | 1 | 1 |

### Fixed in the release run (found by the Linux CI runner, 2026-11-10)

Three defects surfaced only when the gate ran on the GitHub runner. All three
produced a **green** result that described nothing, which is why they were
worth fixing rather than noting: a green result that means nothing is
indistinguishable from a green result that means something.

| # | Sev | Finding | Evidence | Fix |
| --- | --- | --- | --- | --- |
| H3 | High | **The fetched version was scanned out of the `moon fetch` log.** The log is free-form and its shape differs per platform; the version was taken as everything up to the next `" to "`. On Linux that produced `0.164.64\nSuccess\nSuccessfully fetched riantr/moonbit_doubleML@0.164.64` — a name matching no directory. The analyzer then read an empty tree and reported **0 statements, 0 coverage (NaN%), 0 findings, exit 0**. | CI run 42849113293: `doubleML A4: frontend coverage >= 95% — NaN%`, `statements — 0` | `src/app/scan.mbt`: `log_version_candidates` cuts the token at the first character that cannot be part of a version; the module name is matched without the author prefix (the Windows log prints the path with backslashes); a candidate is accepted only when the directory exists. Four tests in `src/app/scan_test.mbt` pin both log shapes. |
| H4 | Medium | **The harness looked for the built CLI under the wrong name on Linux.** The MoonBit native target names the executable `cli.exe` on *every* platform — on Linux it is an ELF binary with a Windows extension. The resolver picked the name by platform, so the CLI never ran and the failure surfaced three steps later as a missing output file. | CI run 42846198002: `ENOENT .../_build/qa/gherkin/fixture/local_module_0.0.0_summary.json`; the build log shows the artifact path ends in `cli.exe` on the runner | `scripts/qa/cli_bin.mjs`: `resolveCli` tries the names the toolchain actually produces; `requireCli` stops with "missing CLI binary" instead of letting it become a confusing error later; `scripts/qa/cli_resolver.mjs` pins both layouts and the empty case |
| M11 | Medium | **The vendored-tree regression asserted the wrong thing.** It checked that the report does not contain the string `_build/`, but the report records the analysed root and the harness's scratch directory lives under `_build/`. The assertion failed on the runner while the code was correct. | CI run 42849532063: `FAIL report never mentions _build/` | `scripts/qa/vendor_isolation.mjs` now asserts on ingested *content* (a foreign file name and a foreign function) and that the module's own function *is* present, so the run cannot pass by doing nothing. Checked against a reverted fix: 3 failures without it, none with it. |

### Registered, not fixed

| # | Sev | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| M6 | Medium | **Line coverage 33.14 %** (1,215/3,666). Worst: `report.mbt` 2.7 %, `abs.mbt` 12.0 %, `util.mbt` 24.8 %, `interp.mbt` 28.3 %. The two crashes above sat in the uncovered part of `parser.mbt`. | `moon coverage analyze -p src/app -- -f caret` + `moon coverage report -f cobertura` | target 60 % on `report.mbt`/`abs.mbt` first; the new `e2e.mjs`/`gherkin.mjs` already exercise the report path end to end but are not measured by `moon coverage` |
| M7 | Medium | **Committed artefacts are pinned to stale versions.** `reports/*` and `verify.mjs` hard-code `0.164.62` / `0.4.43`; today `@latest` is `0.164.64` / `0.4.45`. `verify.mjs` therefore validates yesterday's files, not a fresh run. | `verify.mjs` required[] list; `e2e.mjs` A3 | derive the expected version from `summary.json` instead of the filename, or add a `--latest` mode |
| M8 | Medium | **A12 trace ceiling has a thin margin.** Default `--trials 8` on doubleML produces a **56.5 MB** trace against the documented **64 MB** ceiling (88 % of budget). The documented recipe (`--trials 4`) yields 27.4 MB. One more code growth in the analysed module crosses the threshold. | `e2e.mjs` doubleML-full; design §10.2 | stream the trace (design §11 item 4) or raise the ceiling deliberately |
| L1 | Low | **133 warnings remain**: 64 `deprecated` (`Map::new()`→`Map([], capacity=…)`, `StringBuilder::new()`→`StringBuilder()`, `Ref::new`→`Ref(x)`, view `.to_string()`→`.to_owned()`), 56 `test_unqualified_package` (tests call `parse_file` instead of `@app.parse_file`), 5 `unused_value` (`is_infinite_loop`, `funcs_with_findings`, `name_list`, +2), 4 `missing_priv` (`Builder`, `WalkState`, +2), 2 `reserved_keyword` (field named `abstract` in `ReportInput`), 1 `struct_never_constructed`, 1 `unreachable_code` (intentional, in the fixture). | `warn_census.mjs` | clearing these is a mechanical pass; it makes `--deny-warn` feasible, which is the only durable defence against the toolchain drift that already broke `moon fmt` |
| L2 | Low | **API surface is the implementation.** 204 public declarations (162 `pub fn`, 42 `pub struct`, 2 `pub async fn`) for a single-binary tool; the CLI consumes 43. `src/cli/pkg.generated.mbti` exports `type Opts`. | `pkg.generated.mbti` | either declare the package explicitly non-library (documentation) or move engine internals to `priv` and give tests a whitebox package |
| L3 | Low | **6.5 % duplication** (587/9,100 lines, 86 clusters). Largest clusters are the repeated `collect_expr_vcs(`/`facts, fn_name, file,` call shapes in `contract.mbt` (an artefact of one-argument-per-line formatting) and the repeated `ModuleAst` literal in tests. | `dup.mjs` | extract a `VCBuilder`/`ModuleAst` test helper; not worth churn elsewhere |
| L4 | Low | **Large functions**: `render_report` 351 lines / 32 decisions, `exec_stmt` 273 / 30, `analyze` (CLI) 271 / 43, `lex` 265 / 94, `parse_for` 261 / 60. | `metrics.mjs` | `lex` and `render_report` are the two that would benefit from splitting |
| L5 | Low | **No version control.** The directory is not a git repository and has no `.gitignore`; `_build/` (hundreds of MB incl. 56 MB traces), `.repos/`, `.mooncakes/` and IDE artefacts (`.arts/`, `.codeartsdoer/`) are inside the tree. Changes from this pass cannot be reviewed as a diff. | filesystem | `git init` + ignore `_build`, `.repos`, `.mooncakes`, `.arts`, `.codeartsdoer` |
| L6 | Low | **`moon_cove` cannot parse `report.mbt`** ("1 lexical error(s)"), so coverage only works with the fallback `-- -f caret`. | `moon coverage analyze` without the flag | upstream toolchain limitation to watch; documented in this report |
| L7 | Low | **`--trials` has no upper clamp.** Trial count is bounded by the candidate product per function (5^n for `n` `Int` parameters), so `--trials 999999` on an 8-parameter function attempts 390,625 trials × 2,000 steps. | `value.mbt::synthesize`; `fuzz.mjs` `args:--trials_999999` (benign on the fixture) | clamp to something like 64 and report the clamp |
| L8 | Low | **`abstract` is a reserved keyword** used as a field name in `ReportInput`/CLI struct literal. It compiles with a warning today. | `moon check` 0035 | rename to `abstract_result` before it becomes an error |
| L9 | Low | **Parser leniency on truncated specs**: `//@ requires n >=` (no right operand) is accepted as an expression rather than recorded as a malformed clause; only an *empty* body is rejected. | `contract_edges_test.mbt` | reject an expression that ends on a binary operator |
| L10 | Low | **CFG cap 600 is undocumented**: `src/cli/main.mbt` stops building CFGs at 600 functions while the report documents no such limit (the documented caps are 8 diagrams / 90 nodes). Not reachable on today's targets (2,520 functions in doubleML, but only the first 600 get CFG findings). | `main.mbt` `while i < funcs.length() && i < 600` | state the cap in design §6.3, or make it `--max-cfg-functions` |

---

## 3. Dimension detail

### 3.1 SAST

* `moon check --target native`: **0 errors**, 133 warnings (baseline 167).
* `moon fmt --check`: **exit 0** (baseline exit −1 — the formatter disagreed with
  every file, mostly `Int`→`Int32` annotations).
* Secrets: no `sk-…`, `ghp_…`, `AKIA…`, private-key blocks, `api_key=`/`password=`/
  `secret=`/`token=` assignments in `src/`, `scripts/`, `docs/`, `moon.mod`, or the
  root files. The `moon.mod` dependency block contains no credentials.
* Dangerous patterns reviewed by hand: `@process.collect_output("moon", [...])`
  is an argv array (no shell), so module coordinates cannot inject a command;
  `@env.args()` is only read for the CLI's own arguments; all file writes go
  through one `write_text` wrapper that swallows errors (see M1, now bounded by
  `safe_stem`).
* Note: the fixture's `unreachable_code` warning is intentional — it is the
  finding the fixture exists to produce.

### 3.2 DAST

There is no HTTP surface — the product is a CLI that writes files. "DAST" here
means dynamic testing against hostile inputs, which is where the two high-severity
defects came from. The attack surface that was exercised:

| Surface | Input | Outcome |
| --- | --- | --- |
| Module sources | mutated/truncated/invalid-UTF-8/pathological `.mbt` | robust (110 cases) after H1 |
| `moon.mod` manifest | `name`/`version` with `/`, `\`, `..`, control chars, quotes | confined after H2 |
| CLI arguments | missing values, negative/huge numbers, unknown flags, empty criteria | graceful; M1 fixed |
| Child process | `moon fetch <coord>` | argv-array invocation, no shell interpretation |
| Output directory | `--out` with/without value, traversal strings | confined after H2/M1 |

Residual risk: a module can still make analysis *expensive* (L7) and can still
fill the output directory (56.5 MB per full run), but neither is silent.

### 3.3 Dependencies (依赖)

| Item | Value | Note |
| --- | --- | --- |
| `moonbitlang/async` | `0.22.9` pinned in `moon.mod` | registry `latest_version` is also **0.22.9** — the pin is current (bumped from 0.22.7 at release time with `moon add --upgrade`; `moon update` alone does **not** change the pin) |
| licence | Apache-2.0 | compatible with the project's MIT |
| `moonbitlang/core/*` | implicit (toolchain-bundled) | `moonbitlang/core/env`, `/json` were imported but unused → removed |
| transitive footprint | `moonbitlang/async` pulls the IO/event-loop stack (the build log compiles `iocp.c`, `fs.c`, `process.c`, `socket.c`, …) | acceptable; the alternative (`riantr/tesseract`, ~28 MB) was already rejected in the README |
| advisories | none published for MoonBit modules; mooncakes exposes `yanked` flags and the pin is not yanked | `mooncakes.io/api/v0/modules/moonbitlang/async` |

### 3.4 Unit / integration / component

`moon test src/app --target native` → **33/33**. Composition:

| File | Tests | Covers |
| --- | --- | --- |
| `cfg_test.mbt` | 5 | dead code, unreachable, infinite loop (A6/A7 pins) |
| `parser_test.mbt` | 5 | statement/expression extraction |
| `pipeline_test.mbt` | 8 | taint graph, backward/forward slices, Mermaid validator, Cobertura parser, range union, fixture pipeline |
| `levels_test.mbt` | 6 | contract attachment, L3 proved/failed, L2 taint + may-range, funnel dedup |
| `hardening_test.mbt` (new) | 3 | nesting below/above the guard, honest gap counting |
| `contract_edges_test.mbt` (new) | 6 | `assigns` forms, unknown clause, multi-clause line, invariant assumption, loop-havocked `unknown`, contract enumeration |

Integration: the library→report pipeline is exercised by `pipeline_test.mbt`; the
library→CLI→filesystem path by `scripts/qa/e2e.mjs` (artefact presence, section
completeness, funnel/slice diagrams, thresholds) and by the Gherkin scenarios.

### 3.5 API

`src/app/pkg.generated.mbti`: 204 declarations (162 `pub fn`, 42 `pub struct`, 2
`pub async fn`). The CLI consumes 43 of the 162 functions. 119 are exported for
the test suite's benefit (MoonBit blackbox tests only see `pub`), which is a
defensible trade-off but means the module publishes an API it never promised.
`src/cli/pkg.generated.mbti` exposes `type Opts`, i.e. an internal CLI struct is
part of a generated public surface (warning: not `priv`).

### 3.6 Contracts (契约, L3)

The engine's own three-state semantics were tested directly (see
`contract_edges_test.mbt`): `proved`, `failed`, and `unknown` are all reachable;
a loop-havocked postcondition correctly lands in `unknown`; `proof_counts` sums
to `vcs.length()`. Two real defects were found (M2, M3). The fixture still
produces 2 proved / 1 failed / 3 unknown (A16). Registered observation: a
malformed annotation becomes a VC with `kind = "contract-syntax"` and status
`failed` — it is distinguishable by `kind`, but a reader counting "failed proofs"
will count typos too.

### 3.7 Gherkin

New: `features/acceptance.feature` (7 scenarios) + `scripts/qa/gherkin.mjs`, a
dependency-free runner for the `Feature/Scenario/Given/When/Then/And` subset with
an explicit step table. Unknown steps fail loudly, so the feature file cannot
drift away from the code. Scenarios: pinned fixture findings, report completeness
(10 sections / funnel / slice / size), determinism (summary + byte-identical
trace), hostile nesting, hostile manifest, malformed `--out`, and the toolchain
gates (`moon fmt --check`, `moon test`, `verify.mjs`). Result: **7/7**.

The runner caught a real class of bug in the process: the first version asserted
`md.split('## 3.')`, and `## 3.` is a substring of `### 3.2` — the section was
truncated and the funnel assertion failed. Section lookups now use full headings.

### 3.8 E2E

`scripts/qa/e2e.mjs` → **56/56**. Highlights:

| Run | Result |
| --- | --- |
| fixture `--funnel --slice i@copy_prefix` | exit 0, 3 dead / 1 unreachable / 1 infinite / 28 sinks / 11 L2 / 2 proved / 1 failed / 3 unknown, 24,924 B report |
| determinism (same `--out`, twice) | summaries identical except `elapsed_ms`; trace JSONL **byte-identical**; report identical except timing figures |
| doubleML `@latest` → 0.164.64, full | 5.7–6.2 s, 141.7 KB report, 56.5 MB trace, 350,994 events, 137 dead, 128 sinks, 152 L2 |
| static_analysis `@latest` → 0.4.45 | 1.0–1.8 s, 52.7 KB report, 97.28 % frontend coverage, 41 L2 |
| reproduction with documented parameters (`--trials 4 --max-functions 120`) | 162,708 events (**exact**), 102 sinks (**exact**), 137 dead (**exact**), 2,520 functions (**exact**), 2.9 s; L2 126 vs committed 127 |
| self-scan: `analyze --dir .` over the whole workspace | exit 0, 22 files, 337 functions, 3,497 statements, 96.9 % frontend coverage, 24 dead / 3 unreachable / 3 infinite / 3 sinks, 24 L2 findings, 2 proved / 1 failed / 3 unknown VCs, **153 ms** |

The reproduction row is the strongest reproducibility evidence in this report,
and also the one open question: one L2 finding differs from the committed 127
while every other counter matches exactly. It is recorded as unresolved rather
than explained away.

The self-scan is the run that needs no registry entry at all, and it is the run
that caught M10: before the fix it reported 384 parsed files, 362 of them
belonging to the vendored `moonbitlang/async` module. After the fix the same
command reports 22 files — the module's own 21 `.mbt` files plus the fixture —
and 3,497 statements.

### 3.9 Coverage (覆盖率)

`moon coverage analyze -p src/app -- -f caret` + `moon coverage report -f cobertura`:

* overall **33.14 %** (1,215/3,666 instrumented lines in `src/app`);
* worst files: `report.mbt` 2.7 % (12/444), `abs.mbt` 12.0 % (58/484),
  `util.mbt` 24.8 %, `interp.mbt` 28.3 %, `lexer.mbt` 44.0 %, `contract.mbt` ~38 %;
* `src/cli` is not covered at all (it is not part of the instrumented package) —
  which is exactly where M1 lived.

### 3.10 Fuzz

`scripts/qa/fuzz.mjs`: 110 cases, seeded (`--seed 20261110`), each executed in a
private working directory so any write outside `--out` is detected. Categories:
6 truncations, 12 byte flips, 24 token insertions, 6 unbalanced-closer cases,
pathological syntax (200 K single line, 1 MB string, `if`×100/1000/5000,
`(`×100/2000, index×500, 2,000 functions, 40-deep directories), encodings
(invalid UTF-8, NUL, BOM+CRLF, unicode identifiers, empty/comment-only/whitespace
files, no manifest), 7 hostile manifests, 8 contract-annotation fuzz cases, 25
malformed CLI argument combinations, 3 directory failures.

Result: **110/110 ok** (was 107/110 with 2 crashes and 1 escape). Wall time
11 s per full corpus, so it is cheap enough for CI.

### 3.11 Performance (性能)

| Measurement | Value | Threshold |
| --- | --- | --- |
| fixture, full funnel | 62–204 ms | A11 ≤ 60 s |
| doubleML full (`--trials 8 --max-functions 150`) | 5.7–6.2 s | A11 ≤ 60 s |
| doubleML documented (`--trials 4 --max-functions 120`) | 2.9 s | — |
| static_analysis full | 1.0–1.8 s | A11 ≤ 60 s |
| peak working set, doubleML full | **295.9 MB** | not specified |
| peak working set, fixture | 7.5 MB | not specified |
| report size, doubleML | 141.7 KB | A12 ≤ 512 KB |
| trace size, doubleML (default trials) | 56.5 MB | A12 ≤ 64 MB (**88 % of budget**) |

Peak memory ≈ 5× trace size because the JSONL is materialised as a single String
before writing — the same root cause as design §11 item 4.

### 3.12 Load (负载)

No server exists, so load = concurrent processes. 4 parallel analyses of the same
module: **5,145 ms sequential → 1,392 ms parallel (3.70×)**, zero failures, no
contention artefacts in the outputs. Scaling is near-linear because each run is
CPU-bound and writes to its own directory; the shared read-only `.repos` cache
was not a bottleneck at this concurrency.

### 3.13 Duplication (重复代码)

`scripts/qa/dup.mjs` (token-normalised, ≥6-line windows, greedy extension):
**6.5 %** (587/9,100 code lines), 86 clusters. The largest are `contract.mbt`
call-argument shapes (9–11 lines, 2–8 occurrences) and the repeated `ModuleAst`
literal in tests. Nothing here is a design smell; the `contract.mbt` clusters are
a formatting artefact of one-argument-per-line calls.

### 3.14 Metrics (指标)

| Metric | Production (`src/`) | Tests | Fixture |
| --- | ---: | ---: | ---: |
| files | 15 (+6 test files) | 6 | 1 |
| lines / code / comment / blank | 9,142 / 8,383 / 393 / 366 | 748 / 654 / 53 / 41 | 98 / 63 / 20 / 15 |
| comment ratio | 4.5 % | 7.5 % | 24.1 % |
| functions | 278 | 7 helpers | 12 |
| decision points (if/while/for/match/`&&`/`||`) | 1,472 | 38 | 6 |
| avg code lines per function | 30.2 | — | 5.3 |
| TODO/FIXME/XXX/HACK | 0 | 0 | 0 |
| longest line | ≤ 200 K (fuzz input only); sources are formatter-bounded | | |

Six functions exceed 60 lines; the three worth splitting are `render_report`
(351), `lex` (265, 94 decision points) and `parse_for` (261).

---

## 4. Changes made in this pass

Code (production):

| File | Change |
| --- | --- |
| `src/app/parser.mbt` | `MAX_PARSE_DEPTH = 256`; `P.depth`; guards in `parse_expr`, `parse_unary`, `parse_block`; `skip_rest_of_construct`; depth trips recorded as one issue and one unsupported statement |
| `src/app/util.mbt` | new `pub fn safe_stem` (output-stem sanitiser) |
| `src/app/contract.mbt` | `has_spec` counts invariants; `assigns \nothing` accepted (both spellings) |
| `src/app/*.mbt`, `src/app/lexer.mbt`, `src/app/model.mbt` | `#derive(Eq)` + explicit `Eq` extension (12 types) |
| `src/app/moon.pkg`, `src/cli/moon.pkg` | removed 4 unused imports |
| `src/cli/main.mbt` | `arg_or` fallback for value-taking options; stem routed through `safe_stem`; usage banner renamed to `LunaFlow` |
| `src/app/scan.mbt` | `.mooncakes` added to the walker skip list (vendored dependencies) |
| `src/app/report.mbt` | report header and reproduction command renamed to `LunaFlow` |

Tests and harnesses (new): `src/app/hardening_test.mbt`,
`src/app/contract_edges_test.mbt`, `features/acceptance.feature`,
`scripts/qa/{e2e,fuzz,path_traversal,deep_nesting_probe,depth_sweep,metrics,dup,load,gherkin,warn_census,migrate_derive,vendor_isolation}.mjs`.

Module identity (same pass): the module coordinate moved from `moonflow/moonflow`
to `riantr/LunaFlow` (never published, so no consumer was broken), `moon.mod`
now carries the GitHub repository, and every remaining `moonflow` occurrence in
the source, the docs and the committed reports was renamed to `LunaFlow`. The
one surviving occurrence is the historical sentence in `README.md` that explains
the rename.

Docs: `README.md` (badges 33/33 + Gherkin 7/7, gate list, layout, reproduction
status, nesting guard, `moonx` / backend constraint), `docs/design.md` (§3.3
nesting limit, §6.3 cap row, §4.3 invariant semantics, §7.2 deep-QA
measurements, §10.2 re-measurement note), this report.

Formatting: `moon fmt` was applied to the whole tree; `moon fmt --check` is green.

Backups of the pre-change files: `_build/qa/backup/` (`model.mbt`, `contract.mbt`,
`lexer.mbt`, `abs.mbt`, `moon.pkg`).

## 5. What is *not* verified

* The one-finding L2 discrepancy (126 vs 127) against the committed doubleML
  report is unexplained; everything else reproduces exactly.
* `src/cli` has no unit tests and no coverage; its logic was exercised only
  through the E2E/Gherkin/fuzz harnesses.
* Performance was measured on one machine (Windows 11, warm `.repos` cache) with
  no cold-cache or Linux measurement.
* The published module set in `reports/` was not regenerated: doing so would
  break `verify.mjs`'s pinned filenames (M7) and is a release decision, not a QA
  one.
* No penetration testing of `moon fetch`'s own download path — the analyzer
  delegates acquisition to the toolchain.

## 6. Reproduce

```sh
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
node scripts/qa/metrics.mjs                # size/shape/coverage
node scripts/qa/dup.mjs                    # clone detection
node scripts/qa/load.mjs                   # peak memory + parallel
node scripts/qa/warn_census.mjs            # warning triage
node scripts/qa/vendor_isolation.mjs        # vendored-tree isolation
```

Self-scan (needs no registry entry — the run that needs no published version):

```sh
moon run src/cli -- analyze --dir . --out _build/qa/selfscan --funnel
```

Coverage (note the `-f caret` fallback, required because `moon_cove` cannot parse
`report.mbt`):

```sh
moon coverage analyze -p src/app -- -f caret
moon coverage report -f cobertura -o _build/qa/coverage.xml
```
