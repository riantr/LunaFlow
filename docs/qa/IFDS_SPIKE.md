# IFDS spike — the Phase 0 measurement

**Subject:** can LunaFlow adopt an IFDS-style taint engine — a flow-sensitive,
kill-exact, labelled may-taint fixpoint over the module's own CFG — without
losing a real sink, and without keeping the false positives the L2's blanket
loop rule creates?

**Status:** Phase 0, a MEASUREMENT. The spike is not wired into the analyser,
has no CLI flag, adds no published declaration, and changes
`src/app/pkg.generated.mbti` by zero bytes.

**Date:** 2026-11-19. **Corpora:** `fixtures/` (6 files, 77 functions, 232
statements), `riantr/moonbit_doubleML@0.164.64` (220 files, 2,529
functions, 30,258 statements) and `riantr/LunaFlow@0.1.28` — **the published
module itself** (50 files, 957 functions, 6,104 statements).

The third corpus was added by the deep-QA pass that followed, and it is the
only one of the three that is the tool's OWN source: the other two are
someone else's code and a set of small demo fixtures.

---

## 1. Verdict

**Yes, with one caveat that the measurement makes precise.**

1. **The flow-sensitive fixpoint loses no sink.** Every taint site the L2
   found on doubleML (81 of 81) is also a site the spike found — in the mode
   that carries the blanket rule. No sink was lost. (M1.) The same holds on
   the published module (14 of 14) and on the fixture corpus (5 of 5): **0
   lost sinks on all three corpora.**
2. **Without the blanket rule, the fixpoint drops exactly the blanket rule's
   sites — and nothing else.** 30 sites on doubleML, every one of them
   explained mechanically by the rule's own source, not by a coincidence.
   (M2.) The ground-truth fixture shows what those sites are: a claim that a
   loop counter is tainted, where the counter is derived from the loop's
   bound and from nothing else.
3. **The caveat: the blanket rule carries a real signal that the plain
   fixpoint does not model.** The rule is a coarse encoding of "this loop's
   bound is tainted". Deleting it removes the false claim about the counter
   *and* the true dependency on the bound. A Phase 1 engine should therefore
   **replace** the rule with an explicit relation between the counter and the
   bound — the CFG fixpoint can express that directly and precisely — rather
   than delete it.
4. **The measurement found three real defects in the product**, two of them
   in the taint path the spike was built to compare against (§7). The
   allocation-size family was **dead code**: it could not fire on any input.
   **D1 and D2 have since been repaired (2026-11-20)** — §7 says what each
   cost and what they now report. D3 is still open.

---

## 2. What was measured, and how

The spike is an engine, not a wrapper. It reads the module's AST and CFG and
computes, for every variable at every program point, the set of **sources**
that may have reached it:

* a **fact** is a pair (variable, source);
* a **source** is a labelled origin — `param:<name>`, or `rule:loop` for the
  taint the L2's blanket rule invents;
* facts are joined by **union**, so a variable's fact set says *which* origin
  put the taint there;
* the state is **per CFG node** and the fixpoint is a **worklist** over the
  module's own CFG (`build_cfg`), so the transfer functions are kill-exact
  (`let` and `=` kill, `+=` keeps and joins) and the facts are flow-sensitive
  at the level of the CFG node.

The spike runs in two modes over the same module:

* `plain` — no blanket rule;
* `with-rule` — the L2's blanket rule applied at a `while` head, on the edge
  into the body, exactly where the L2 applies it (`implicit_abs_taint`).

The two modes are compared against the L2 (`run_abstract`, the same call the
CLI makes, with the same per-function step budget of 200,000).

**The spike's sink rule has no filter.** It reports a taint sink when the
sink's *argument* is tainted. The L2 additionally requires the container to
be known to be an array and the index not to be provably inside it. Those
filters live in the L2's **value** domain — they need the container's
abstract type and the index's interval — and a taint-only engine cannot
reproduce them without becoming the L2. Every difference between the two
analyses is therefore **attributed to a cause and counted** (§7), not
waved at.

### The ground truth the measurement is read against

Five assertions in `src/app/ifds_spike_wbtest.mbt` pin the semantics. They
are the falsifiable part of this work: each one fails if the engine's
semantics move.

| # | Module | Asserted |
| --- | --- | --- |
| 1 | a loop counter compared against a tainted length | plain finds **0** sinks, with-rule finds **1** |
| 2 | a tainted string length used as an index | **1** sink in both modes |
| 3 | a tainted allocation size | **1** sink in both modes |
| 4 | a tainted value overwritten before it reaches the sink | **0** sinks in both modes (the kill is exact) |
| 5 | the same module as #1, run through the **L2** | the L2 finds **1** sink — the spike with the rule agrees with it |

Assertion 1 is the design question in one fixture. Assertion 5 is what makes
the comparison meaningful: the two modes differ by the rule and by nothing
else.

---

## 3. M1 — no lost sink

> Every taint site the L2 found is also a site the spike found.

| corpus | L2 taint sites | spike (with rule) | spike (plain) | **L2 sites the spike did NOT find** |
| --- | ---: | ---: | ---: | ---: |
| `fixtures/` | 5 | 10 | 8 | **0** |
| doubleML 0.164.64 | 81 | 1,316 | 1,286 | **0** |
| published LunaFlow 0.1.28 | 14 | 70 | 40 | **0** |

**The check is falsifiable, and was falsified once — by a bug in the spike.**
The first doubleML run reported two lost sinks,
`TAINT-INDEX|rdd.mbt|2869` and `TAINT-INDEX|expand_v118_test.mbt|97`. Both
were `for` loops whose *step* the CFG does not give a node of its own, and
the spike's transfer function for the initialisation node was **not binding
the loop's variable** — so the variable was never tainted, and every index
that used it was clean. The L2 binds it in the same place. The fix is in
`src/app/ifds_spike_wbtest.mbt`; the second run is the table above.

A gate that has never failed is not a gate. This one failed, and the failure
was a real defect in the engine under test.

---

## 4. M2 — the blanket rule's contribution

> Every site the plain spike found is also a site the spike with the rule
> found, and every site the rule added carries the rule's own source.

| corpus | plain | with rule | **added by the rule** | all of them carry `rule:loop` |
| --- | ---: | ---: | ---: | --- |
| `fixtures/` | 8 | 10 | 2 | yes |
| doubleML 0.164.64 | 1,286 | 1,316 | 30 | yes |
| published LunaFlow 0.1.28 | 40 | 70 | 30 | yes |

The rule only *adds* taint, so the plain set is a subset of the with-rule
set; the second half of the check is the one that says the difference is the
rule and not a coincidence: every one of the 30 added sites has `rule:loop`
among its sources and no other source.

**What those 30 sites are.** `ps_processor.mbt:552` and `rfl.mbt:568` are
representative:

```moonbit
// ps_processor.mbt:550
while i < n {
  let mut j = i + 1
  ...
  while j < n && sorted_x[j] == sorted_x[i] {
```

```moonbit
// rfl.mbt:567
let mut j = i - 1
while j >= 0 && x.get(out[j], feature) > key_val {
```

The index is a **loop counter**. The counter is not derived from anything
untrusted: it starts at another counter and is incremented. What makes the
condition tainted is the *other* operand — `n`, a length read off a tainted
parameter. The L2's blanket rule then taints every **number the condition
reads**, the counter among them, and the counter is what reaches the index.

So the claim the L2 makes at those 30 sites — *a tainted value may reach an
array index* — is false about the counter. The flow-sensitive fixpoint drops
it because the facts follow the assignments, and no assignment carries taint
into the counter.

---

## 5. M3 — the model's coverage

> The statements the spike could not model are counted, and they are exactly
> the statements the parser could not model.

| corpus | spike gaps | unmodelled statements the spike walked | unmodelled constructs the parser counted |
| --- | ---: | ---: | ---: |
| `fixtures/` | 0 | 0 | 9 |
| doubleML 0.164.64 | 35 | 35 | 281 |
| published LunaFlow 0.1.28 | 270 | 270 | 340 |

The spike handles every statement kind the parser produces. A statement the
parser did not model (`SUnsupported`) is **counted as a gap and lets its facts
through**: a may-analysis that drops facts loses sinks, and the L2 lets them
through too, so the two engines agree there.

---

## 6. M4 — the scale

| corpus | engine | functions analysed | CFG nodes | worklist steps | facts held | time (min of 5) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| doubleML 0.164.64 | L2 | 1,411 | — | — | — | **172 ms** |
| doubleML 0.164.64 | spike, plain | 1,411 | 18,455 | 33,428 | 196,946 | **240 ms** |
| doubleML 0.164.64 | spike, with rule | 1,411 | 18,455 | 34,116 | 201,999 | **239 ms** |

The corpus holds 2,529 functions; both engines analyse the **1,411** that are
not test functions and not closures, because neither the L2 nor the spike
enters a test function or a closure.

The timings are the **minimum of five alternating runs**; the medians are
179 ms / 243 ms / 251 ms and the maxima 194 ms / 268 ms / 256 ms. A single
run is not a timing measurement.

**The published corpus was measured too, but it has no timing row here**: M4 was
specified on doubleML, and a timing measured once is not a timing measurement.
Its scale is in the harness's JSON — **39,324 facts over 11,926 worklist steps**,
against doubleML's 201,999 over 34,116.

**The spike costs about 1.4× the L2 on this corpus**, and it is not an
apples-to-apples comparison: the spike builds a CFG for every function and
the L2 does not. The spike's own work — 34,116 worklist steps over 18,455
CFG nodes — is not the bottleneck; the CFG is.

The worklist converges: 34,116 steps over 18,455 nodes is about 1.85 visits
per node, so the loops are visited more than once and the rest once. That is
the shape of a fixpoint that has converged — a second visit that finds
nothing new does not enqueue the node again — but it is a property of this
corpus, not a guarantee: a loop whose carried facts keep growing would visit
its head more often.

---

## 7. What the measurement found in the PRODUCT

The spike exists to answer a question about IFDS. It also turned up three
defects in the analyser it was measured against. All three are in the taint
path, and all three are **measured, not inferred**.

### D1 — the allocation-size family is dead code — **REPAIRED**

The L2's allocation rule matches `f == "Array::make"` (sic — with `::`).
**The parser never produces that name**: a qualified path is rendered with a
DOT (`Expr::render` on an `EField` gives `Array.make`), so the call's name
is `Array.make`.

Consequences, both measured:

* the `TAINT-ALLOC` family **cannot fire on any input** — the L2 reported
  **0** `TAINT-ALLOC` findings on both corpora;
* an array built by `Array::make` is `ATop` in the L2's value domain, so
  **every index into it is filtered out** by the `is_array` check.

The spike, which matches the name the parser actually produces, finds **881**
tainted allocation sizes on doubleML — out of **2,099** `Array::make` /
`FixedArray::make` calls in the corpus.

**THE REPAIR (2026-11-20).** Five rules matched only the `::` spelling and
could never fire: the L2's allocation-size rule (`abs.mbt`), the
allocation-size VC (`contract.mbt`), the L1's allocation taint
(`interp.mbt`), and the two string-conversion rules (`interp.mbt`). Each now
answers to the DOT spelling as well. The same repair covers the OTHER route
to the same call: the source spelling `Array.make(n, 0)` is a METHOD call,
not a qualified path, so a module function written that way is re-written as
the call it is before the rule sees it — otherwise the same call would be
analysed two different ways depending on how the caller spelled it.

MEASURED on `riantr/moonbit_doubleML@0.164.64`, the full funnel run:

| | before | after |
| --- | ---: | ---: |
| `TAINT-ALLOC` findings | **0** | **944** |
| `RANGE-VIOLATION` | 824 | 1,403 |
| `INDEX-OOB` | 273 | 684 |
| `TAINT-INDEX` | 199 | 354 |
| L2 findings in total | 1,282 | 3,316 |
| L1 taint sinks | 123 | 199 |

The new `RANGE-VIOLATION` findings are the dead rule's second clause — "a
size may be negative" — and the new `INDEX-OOB` findings are the SAME claim
shape the tool already made (an index interval against a length interval),
not a new kind of claim. The ground truth is the fixture that exists to
prove the case: `make_window(n : Int32)` and `parse_len(s : String)` in
`fixtures/vuln_demo` are exactly "a tainted value controls an allocation
size", and the published tool was **silent** on both. It is not now.

### D2 — the finding de-duplication omits the file — **REPAIRED**

`add_finding` compares a candidate against the findings already collected on
**(kind, line, message)** — and not on the file. Two files with a taint
finding on the same line therefore collide, and the second one is dropped
without a word.

Measured on doubleML: **23** taint-index sites share a line with a site the
L2 has in another file. `kde.mbt:77` keeps the line; `did_aggregation.mbt:77`
is silently dropped. The corpus has 220 files and 30,258 statements, so line
collisions are common, not exotic.

**THE REPAIR (2026-11-20).** The file is part of the key, in the L2's
`add_finding` (`abs.mbt`) and in the EVA's (`eva.mbt`) — the findings array
is the MODULE's, one array shared by every function, so a key without the
file let a finding in one file be dropped as a duplicate of a finding in
another. Within one file the key is still exact, because a file has one
statement per line.

MEASURED on doubleML, with D2 alone and D1's repair switched off: **+312**
findings (RANGE-VIOLATION +229, INDEX-OOB +60, INTEGER-OVERFLOW +20,
TAINT-INDEX +3), L2 findings 1,282 → 1,594.

### D3 — an exact array length prunes loop bodies

The L2 gives an array literal `[]` the length **exactly 0**, and prunes a
loop whose condition is then impossible. In `did_aggregation.mbt` this
cascades:

* `e_set_acc` starts as `[]`, so `for k = 0; k < e_set_acc.length(); ...`
  is pruned — the L2's findings for `aggregate_event` stop at line **187**,
  the statement *before* that loop (measured);
* so `found = true` is never seen, so `e_set_acc = e_set_acc + [e]` is
  "unreachable", so the array's length stays 0;
* so `for ei = 0; ei < n_e; ...` is pruned too — and the two real sinks
  inside it (`did_aggregation.mbt:229` and `:231`) go with it.

The CFG-based fixpoint does not prune, and finds both. This is the one
difference in the whole corpus that is **not** a defect of the sink filter
or of the de-duplication: it is the L2's value domain deciding that code is
dead when it is not.

**It accounts for 2 of the 1,235 sites**, and it is counted inside the harness's
`array` cause rather than as a cause of its own — the two sites are
`did_aggregation.mbt:229` and `:231`, and the other two `array` sites
(`did_cs.mbt:1684`, `resampling.mbt:78`) are not pruning cases. The attribution
table above is the harness's, and the harness does not have a "pruned" cause:
it can see that the container is an array, and it cannot see that the L2 decided
the code was dead.

### The complete attribution

Every one of the **1,235** sites the spike has and the L2 does not is
attributed to a cause, by the harness:

| cause | doubleML | published LunaFlow | fixtures |
| --- | ---: | ---: | ---: |
| **D1** — the L2's dead allocation rule (`alloc`) | 881 | 2 | 2 |
| **D1** — the container is an allocation (`made`) | 140 | 1 | 1 |
| **D2** — the L2's file-less de-duplication dropped it (`dedupe`) | 23 | 0 | 0 |
| the container's type is unknown (`unknown`) | 187 | 29 | 1 |
| the container IS an array by type (`array`) | 4 | 24 | 1 |
| **total** | **1,235** | **56** | **5** |

**1,021 of the 1,235 (83 %) trace to D1 alone.** On the published module the split
is different: **53 of the 56 (95 %) are the L2's value-domain filters** — 29 where
the container's type is unknown, and 24 where the container *is* an array by type
and the L2's own taint or length bound stopped the site — and only 2 are the dead
allocation rule. That is the expected difference between a module of demo
fixtures, a module of dense numeric code, and a module that is itself an
analyser.

**The last row is where D3 lives, and it is smaller than it looks.** The harness's
`array` cause is the mechanical one — *the L2 agrees the container is an array, so
whatever stopped it was its taint or its length bound*. The **D3** case study
below (the L2 pruning a loop body) is **2 of doubleML's 4 `array` sites**:
`did_aggregation.mbt:229` and `:231`. The other two, `did_cs.mbt:1684` and
`resampling.mbt:78`, are ordinary array-container sites. On the fixtures corpus
the single `array` site is `ipc_demo/lib.mbt:94`, and it is **not** a pruning
case. So D3 accounts for **2** sites, not 4.

---

## 8. What the spike does NOT do

* **It is not interprocedural.** Both the L2 and the spike are
  intraprocedural: a call joins its arguments' taint and the callee is not
  entered. This is IFDS **piece A**. Piece B — the supergraph, the call and
  return edges, the k-limited call strings — is **not** built, and the
  measurement says nothing about it.
* **It does not model the heap.** `elem_is_tainted` in the L1 returns
  `false`, and the spike inherits that: a write into an array or a field
  carries no taint. Neither engine sees taint move through memory.
* **It does not model path infeasibility.** A may-fixpoint joins the two
  branches of an `if`; the loop-head join is inherent to the analysis and is
  not something IFDS removes.
* **It does not replace the L2's filters.** The spike reports a sink when the
  argument is tainted; the L2 also requires a known array container and an
  index that is not provably inside it. A production engine would need the
  value domain for that, or it would report more.
* **It says nothing about the `@env.args` / `@process` sources.** The L2's
  source set is the parameters; the L1 has two more. The spike models the
  L2's set, because a like-for-like comparison is the point of the
  measurement.

---

## 9. What is *not* verified

* **The numbers are for three corpora.** `fixtures/` is six small demo
  modules; doubleML 0.164.64 is one large real module; the published
  `riantr/LunaFlow@0.1.28` is the tool's own source. The trend is consistent
  across the three, but it is three points — and the two big ones are the two
  largest modules this user happens to publish.
* **The CI gate runs only the fixture corpus.** The doubleML and published
  corpora need a fetched module, so they are documented and reproducible but
  not on the runner's critical path.
* **The 30 rule sites were characterised, not adjudicated.** The measurement
  shows *why* the L2 reports them (the blanket rule) and the fixture shows
  *that the claim is false about the counter*. Whether every one of the 30
  is a false positive in the product's sense — a may-taint claim about the
  counter's **bound** rather than its value — is a judgement about the
  family's contract, and this document does not make it.
* **The spike is not integrated and not benchmarked as a product.** It has
  no CLI flag, no report line and no place in the funnel. The 1.4× cost in
  §6 is the cost of a measurement harness that also builds a CFG, not the
  cost of a shipping engine.
* **The L2's per-function step budget was not hit** (`budget=0` on both
  corpora), so no comparison was truncated. On a larger corpus it might be,
  and the harness reports the budget count for that reason.
* **Nothing here was published.** The spike is a source file in the
  repository; the published `.mbti` is unchanged, so no consumer can reach
  it.

---

## 10. Reproduce

```sh
# The measurement over the fixture corpus, with the four checks.
node scripts/qa/ifds_spike.mjs --corpus fixtures --label fixtures

# The same over doubleML. Fetch the corpus first:
moon fetch riantr/moonbit_doubleML --no-update
node scripts/qa/ifds_spike.mjs --corpus .repos/riantr/moonbit_doubleML/0.164.64 --label doubleML

# And over the PUBLISHED module -- the tool's own source:
moon fetch riantr/LunaFlow --no-update
node scripts/qa/ifds_spike.mjs --corpus .repos/riantr/LunaFlow/0.1.28 --label published

# The falsification: each check is broken on purpose and has to fail.
node scripts/qa/ifds_spike.mjs --corpus fixtures --label fixtures-falsify --falsify

# The ground-truth assertions on their own.
moon test src/app --target native -f "ifds_spike*"
```

The raw measurement is written to `_build/qa/ifds_spike/<label>.json`: the
corpus statistics, both engines' counters, the four checks, the attribution
of every difference, and every site with its sources.

**Where the code is**

| file | what it is |
| --- | --- |
| `src/app/ifds_spike_wbtest.mbt` | the engine, the driver and the five ground-truth assertions. Private items only: the published API does not grow by a line. It is compiled as part of the package (so it can read the AST's private fields) but holds `test` blocks, so it is not part of the published library. |
| `scripts/qa/ifds_spike.mjs` | the harness: the four checks, the attribution, the falsification. |
| `docs/qa/IFDS_SPIKE.md` | this document. |
