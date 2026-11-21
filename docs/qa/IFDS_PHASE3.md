# IFDS Phase 3 — the SIZE of a `+`-built array

**Status:** NOT STARTED — this is the plan, written before any code.

**Date:** 2026-11-21. **Phase 0:** `docs/qa/IFDS_SPIKE.md`. **Phase 1:**
`docs/qa/IFDS_PHASE1.md`. **Phase 2:** `docs/qa/IFDS_PHASE2.md` — the plan,
the measurement and the adjudication of the SIZE/CONTENTS separation, shipped
as `riantr/LunaFlow@0.1.31`.

**LOOP item:** 5. The LOOP's items so far: 1. bound the findings table; 2. D1
(five dead rules) + D2; 3. Phase 1 (L2-IFDS); 4. Phase 2 (a container's SIZE
taint is not its CONTENTS' taint). **Item 5 is this phase.**

**Published interface:** the expectation is that this phase changes it **not at
all** — §4 says how that is MEASURED rather than assumed, because a phase that
grows a published type costs a consumer's build, and a phase that does not must
say so with the same rigour.

---

## 1. What Phase 3 is

Phase 2 separated a container's **SIZE** taint from its **CONTENTS'** taint: a
container's size no longer inherits its elements' taint. What it left open, in
its own §7, is the shape where the container's value is **`ATop`** — because
the layer cannot compute it — and a `.length()` on an `ATop` falls back to the
receiver's source set, which for such a container is the CONTENTS' taint
again.

**The shape is an array built by `+`.** `+` on arrays is MoonBit's
concatenation (`pub impl[T] Add for Array[T]`, the core's
`builtin/array.mbt:1251`), and `abs_binop` has **no case for it**: the
function's fall-through is `ATop`. So `acc = acc + [e]` produces an `ATop`,
and the size read out of it is the contents' taint.

That is not a rounding error. Measured over six shapes (§2.2), today's
behaviour includes **two claims the layer's own value domain refutes** — the
first self-refuting claims since Phase 2 — and **three labels that name the
ELEMENT** where the count is decided by a parameter.

The scope of this phase is one case in one function:

> `abs_binop` computes the **count** of a `+`-built array, and the count's
> **taint** is the union of the two operands' **size** taints — never the
> elements' taint.

What this phase does NOT do is stated in §7, and it matters: the count of an
array grown **inside a loop** is the loop's trip count, and the model does not
carry the trip count's taint into the count. §8 says what that costs, and it
is the honest price of this phase.

---

## 2. The measurement, before anything changed

MEASURED (2026-11-21) on the tree of `6acb789`, with the analyser built from
that tree.

### 2.1 The mechanism, site by site

| site | what it computes | what it gets today |
|---|---|---|
| `abs.mbt:437` | `abs_binop`'s result taint | the union of the operands' source sets — the **contents'** taint |
| `abs.mbt:568` | `abs_binop`'s fall-through | `ATop` — **there is no `(AArr, AArr)` case** |
| `abs.mbt:1264` | `.length()` on an `AArr` | `AInt(l, h)` with the array's **size** taint (Phase 2's repair) |
| `abs.mbt:1278` | `.length()` on anything else | `ATop` with the **receiver's** source set — for a `+`-built array, its **contents'** taint |

The chain, for `let a = xs + [user]; Array::make(a.length(), 0)`:

1. `a` is `ATop`, carrying `xs`'s and `user`'s sources — the **contents'**
   taint;
2. `a.length()` is `ATop` with the receiver's source set — the same
   **contents'** taint;
3. the allocation-size rule fires on it, and the label names whatever the
   **elements** contributed.

So the size of a `+`-built array is computed **nowhere**, and the claim about
it is made from the elements.

**And the tree carries none of these today.** Measured over the three
committed artefacts: **959 / 10 / 4** `TAINT-ALLOC` findings on doubleML /
static_analysis / the fixture, and **zero** of them have a constant size — a
finding's evidence names the size's value (`Array.make([2,2])`), so a claim
whose size is a constant is visible in the artefact itself. **The three
committed artefacts carry no self-refuting allocation-size claim at all.**
The two the shapes below produce are therefore the first of their class since
Phase 2, and they are a class the tool has already learned to remove.

### 2.2 The shapes, and what the analyser claims about them today

Measured with `_build/qa/phase3/probe_plus_shapes.mjs` over
`_build/qa/phase3/shapes/shapes.mbt` — six functions, one per shape:

| shape | the claim today | is it TRUE? |
|---|---|---|
| `size_of_plus_literals` | "from parameter `user`" | **FALSE.** The count is **2** — two one-element literals — and `user` chooses nothing. **The claim refutes itself.** |
| `size_of_plus_literal_binding` | "from parameter `user`" | **FALSE**, the same, through a binding: the count is 2. |
| `size_of_plus_parameter` | "from parameters `xs` and `user`" | the count is `xs`'s length **+ 1**: `user` does not decide it. **The label names the ELEMENT.** |
| `size_of_plus_two_parameters` | "from parameters `xs`, `ys` and `user`" | the count is `xs`'s length + 1 + `ys`'s length: `user` does not decide it. **The label names the ELEMENT.** |
| `size_of_plus_bound` | "from parameters `xs` and `user`" | the same, through a binding. **The label names the ELEMENT.** |
| `element_of_plus_array` | "from parameter `xs`" | **TRUE.** The size is the element's **value**, and `xs` is untrusted. **The claim must stay.** |

**Why the self-refuting claims fire at all.** Phase 1's `constant_size` guard
suppresses an allocation-size claim whose size is provably constant — but it
can only recognise that when the size is an `AInt` with `l == h`. Here the
size is `ATop`: **the count is not modelled, so the guard cannot see that it
is constant.** The missing count is not only a precision loss; it is what
lets a false claim through.

**A corpus caveat, stated so the shape is not over-read.** The shapes are a
synthetic module, and the corpora do not all contain the self-refuting form:
a concatenation of two **literals** has a constant count (the shapes), while
doubleML's 105 sites are all `acc = acc + [x]` — a count that is the trip
count, not a constant. So on doubleML this shape produces the **misattributed
labels**, and the self-refuting case is what a **new** corpus would get.

### 2.3 The split: what the model can compute, and what it cannot

| | the count | the count's taint |
|---|---|---|
| **CAN be computed** | the sum of the two operands' counts — `a + b` has `a.len + b.len` elements | the union of the two operands' **size** taints: what decides the count is the counts, and a count is decided by what decides its operands' counts |
| **CANNOT be computed** | the **trip count** of an array grown inside a loop | the trip count's taint: the loop's bound decides how many elements there are, and the model does not carry the bound's taint into the count |

The first row is this phase. The second row is **not**, and §7 and §8 say what
that costs — it is the one thing that makes the honest repair incomplete, and
it is stated here so the plan cannot be read as claiming more than it does.

### 2.4 The baseline, on the three corpora

The footprint of the shape, measured with
`_build/qa/phase3/measure_plus_arrays.mjs` (a **textual** definition, stated
so it is reproducible: a concatenation site is an assignment whose right-hand
side contains `+ [`):

| corpus | `.mbt` files | files with a concatenation | concatenation sites | distinct variables built | variables whose SIZE is read | their `.length()` reads |
|---|---:|---:|---:|---:|---:|---:|
| `fixtures/vuln_demo` | 1 | 0 | 0 | 0 | 0 | 0 |
| `riantr/moonbit_doubleML@0.164.64` | 220 | 19 | **105** | 61 | **19** | **49** |
| `riantr/moonbit_static_analysis@0.5.0` | 254 | 0 | **0** | 0 | 0 | 0 |

**The defect's footprint is confined to doubleML**, and static_analysis has
**none** of it — so §9 predicts its counts do not move, and that prediction is
falsifiable.

The counts that will move, measured on the tree of `6acb789`:

| corpus | L2 findings | sidecar findings | L1 events | taint sinks | steps |
|---|---:|---:|---:|---:|---:|
| `fixtures/vuln_demo` | 15 | 29 | 604 | 8 | 156 |
| `riantr/moonbit_doubleML@0.164.64` | 3,301 | 3,504 | 243,528 | 195 | 47,835 |
| `riantr/moonbit_static_analysis@0.5.0` | 188 | 198 | 17,029 | 9 | 4,410 |

The self-scan row — the analyser over **this** tree, a LIVE run:

| files | functions | statements | L1 events | L2 findings | dead | taint sinks | steps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 58 | 1,084 | 6,822 | 10,201 | 46 | 0 | 8 | 3,042 |

**The self-scan row WILL move** — this phase edits `src/app/abs.mbt`, and the
statements it adds are statements the analyser counts. That is expected, and
it is why §9 names it.

### 2.5 M1's baseline

MEASURED (2026-11-21) with `scripts/qa/ifds_spike.mjs` over doubleML
(`_build/qa/ifds_spike/doubleML-phase3-baseline.json`). The spike exits **1**:
that is M1's verdict, not a harness error.

| | value |
|---|---:|
| files / functions / statements | 220 / 2,529 / 30,258 |
| L2 taint sites | **1,090** |
| spike (plain) taint sites | 1,289 |
| spike (with rule) taint sites | 1,317 |
| sites the rule added | 28 |
| sites the flow-sensitive fixpoint has and the L2 does not | 202 |
| … of which the L2's allocation rule did not fire | 1 |
| … of which the container is an allocation | 16 |
| … of which the container's type is unknown | 178 |
| … of which the container is an array by type | 7 |
| **sites the L2 has and the flow-sensitive fixpoint does not** | **3** |
| spike gaps / walked unmodelled / parser unmodelled | 35 / 35 / 281 |
| L2 time / spike time (ms) | 380 / 258 |

The three sites, from the committed doubleML artefact:

```
TAINT-ALLOC|did_aggregation.mbt|202   tainted value from parameters `groups` and `periods` may control an allocation size
TAINT-ALLOC|did_aggregation.mbt|203   (the same)
TAINT-ALLOC|did_aggregation.mbt|204   (the same)
```

and the source they come from (`.repos/riantr/moonbit_doubleML/0.164.64/did_aggregation.mbt`):

```moonbit
176:  let n_groups = groups.length()        // a tainted parameter's length
177:  let n_periods = periods.length()      // a tainted parameter's length
182:  let e_set : Array[Int32] = []         // the empty literal
183:  let mut e_set_acc = e_set
184:  for i = 0; i < n_groups; i = i + 1 {
186:    for pi = 0; pi < n_periods; pi = pi + 1 {
196:        e_set_acc = e_set_acc + [e]     // THE CONCATENATION
201:  let n_e = e_set_acc.length()          // the SIZE, read
202:  let theta : Array[Double] = Array::make(n_e, 0.0)
203:  let se : Array[Double] = Array::make(n_e, 0.0)
204:  let names : Array[String] = Array::make(n_e, "")
```

**The claim there is TRUE.** The count of distinct event times is bounded by
`n_groups * n_periods`, and both are the lengths of tainted parameters. So
whatever this phase does to these three sites, the honest outcome is either
"the claim stays and is now labelled by what decides the count" or "the claim
goes and the loss is registered" — and §8 says which, and why.

**Why the reference loses these three.** The flow-sensitive fixpoint models a
binary operation as the union of its operands' taint (`spike_taint_of`,
`EBin(_, a, b) => spike_union(...)`) — which is right for `+` on arrays — but
its container inference does not recognise a `+`-built array as an array, so
it classifies the container as `made`/`unknown` and its array filter stops the
site. **The reference is the coarse one here**, exactly as Phase 2 concluded
for the twenty claims it removed.

---

## 3. The change

**`abs_binop` gets a case for the concatenation.** For `OpAdd` on two arrays:

| | the result |
|---|---|
| the **count** | the sum of the two counts — `AArr(al + bl, ah + bh, …)` |
| the **size's taint** | the union of the two operands' **size** taints — the sources that decide the COUNT |
| the **contents' taint** | the union of the two operands' **contents** taints — the sources that decide the VALUES |

The size's taint and the contents' taint are **different sets**, and that is
the whole point: `xs + [user]` has a count that `xs` decides and a content
that `user` decides, and the claim about the size must name the first and not
the second.

Phase 2's `AbsVal::AArr` already carries the size's taint as its third
component, so **no new value-domain shape is needed** — this is a case in a
match, not a change to a type.

---

## 4. The published-interface cost

**MEASURED, not assumed.** `src/app/pkg.generated.mbti` — the published
interface — contains, of what this phase touches:

* `AbsVal`, with `AArr(Int32, Int32, Array[String])` — **unchanged** by this
  phase;
* `AbsCell::new(AbsVal, Array[String])` — **unchanged**;
* `abs_binop` — **not there**. It is a private `fn`, so a case in it cannot
  reach a consumer's build.

**The expectation is therefore a cost of ZERO**, and §9 names the check that
proves it: `scripts/qa/release_interface.mjs` compares the `.mbti` at every
release's tag against that release's notes and fails when the version being
prepared breaks the published interface without saying so. **If the expectation
is wrong, that checker says so** — it is the same checker that caught Phase
2's missing declaration, and it is the same checker that found its own first
gap (0.1.30's `ReportOptions.max_findings`) the day it was written.

A phase that costs nothing is still a phase that must SAY so, and the notes
must state it: the release notes will say that the published interface is
**unchanged**, and that check is part of the release.

---

## 5. The acceptance criteria

1. **The count of a `+`-built array is computed.** The layer knows how many
   elements `a + b` has: the sum of the two counts.
2. **The count's taint is not the elements' taint.** A `+`-built array whose
   elements are tainted and whose count is fixed by the code produces **no**
   allocation-size claim from its length — the self-refuting case of §2.2 is
   gone.
3. **A count that really is the caller's to choose still produces the claim**,
   and its label names **only** the sources that decide the COUNT — never the
   element's sources. `size_of_plus_parameter` must name `xs` and not `user`.
4. **A size derived from a tainted value still must claim.** The change cannot
   silently drop a true claim: `element_of_plus_array`'s claim is true and
   must survive.
5. **Every published number that moves is re-derived**, not remembered, and
   updated in the same commit — in **every place it appears**, the live table
   *and* the prose.
6. **The published interface is unchanged**, and `release_interface.mjs` says
   so rather than the notes claiming it.
7. **The claims the repair removes are registered.** Every removed claim is
   named, with the reason it went, and a check fails if one of them comes
   back.

Criteria 1–4 are asserted in `src/app/plus_size_wbtest.mbt` (both directions)
and again end to end — the **analyser** over the six shapes — by
`scripts/qa/plus_size.mjs`. Criterion 5 is `scripts/qa/readme_table.mjs`,
criterion 6 is `scripts/qa/release_interface.mjs`, and criterion 7 is a
ledger in `docs/qa/IFDS_PHASE3_LEDGER.json`, checked by the same script.

---

## 6. The falsifications

A check that cannot fail proves nothing. Each of these must FAIL, and the
source must come back byte-identically.

| what is broken | what must fail |
|---|---|
| the change is reverted entirely | the count assertions, and the self-refuting claim returns |
| the count's taint inherits the **contents'** again | the label assertions — the label names the element |
| the count is dropped (every count is `ATop` again) | the two self-refuting claims return |
| the count's taint is dropped (the count is clean) | the positive claims stop firing |
| the release notes' declaration is removed | `release_interface.mjs` fails |

**The source comes back byte-identically, and the hash recorded is the
COMMITTED tree's.** Phase 2 shipped a hash that matched no commit — it was the
working tree's, before `moon fmt` rewrote the file's bytes — so the claim was
unverifiable from the repository. The falsification is therefore re-run
**against the committed tree**, and the hashes in §6 are the ones
`git show HEAD:<file>` produces.

---

## 7. What Phase 3 does NOT settle

* **The trip count of a loop.** The count of an array grown inside a loop is
  the trip count, and the model does not carry the loop condition's taint into
  the count. The L2 analyses a loop body **once** and joins the entry state
  with the body's, so the count of an array grown in a loop is bounded but not
  tied to the bound's taint. **This is why §8's trade is what it is.**
* **The value-flow behind a permutation or a derived count.** Unchanged from
  Phase 2: the L2 models what a value's taint is, not where a value's VALUE
  comes from.
* **The L1's own claim.** The dynamic layer has its own taint model and its
  own allocation rule (`src/app/interp.mbt`); this phase does not touch it.
* **Strings.** Unchanged: a string's length is not a function of its
  characters' taint either, and no shape was found where the string case
  produces a claim the domain refutes.
* **`-` on arrays.** MoonBit's `Sub` for `Array[T]` does not exist, so only
  `OpAdd` is in scope.

---

## 8. M1's status — what will be stated, and how it is decided

M1 is **"no lost sink"**: every taint site the L2 found must also be a site
the flow-sensitive fixpoint found (`checkM1(l2, plain)` in
`scripts/qa/ifds_spike.mjs`). It fails over doubleML because the L2 has
**3** sites the reference does not.

There are exactly two paths, and **which one this phase took is a
MEASUREMENT, not a decision**:

* **(a) the three claims STAY.** Then the reference's blindness at a
  `+`-built container must be repaired — M1 asks the reference to find the
  L2's sites, so the reference has to gain them — and the layer's claim
  becomes **provable**: the label names what decides the count.
* **(b) the three claims DROP.** Then that is a **registered coverage cost**,
  in a ledger, like Phase 2's eighteen. M1 going green is a **consequence**,
  not the goal, and the phase's value is the two self-refuting claims and the
  three labels it fixed.

**The plan's expectation, stated so the measurement can correct it: (b).**
The size's taint of a `+`-built array is the union of its operands' size
taints, and for `e_set_acc = e_set_acc + [e]` those are clean — the empty
literal's count is fixed by the code, and the accumulated array's count is the
trip count, whose taint the model does not carry (§7). So the count's taint
would be clean, the claim would not fire, and the three true claims would go.

**If the measurement says otherwise, the plan is wrong and the record says
so.** Phase 2's own plan had one expectation the measurement corrected
(`IFDS_PHASE2.md` §6); that is the point of writing the expectation down.

**The harness is not weakened either way.** M1's definition is not changed,
the reference is not taught to ignore the three sites, and no site is removed
from either side of the comparison to make the check pass.

---

## 9. The numbers this change is expected to move

**These are EXPECTATIONS, written down so the measurement can correct them.**
Every one of them is falsifiable.

| corpus | expectation | why |
|---|---|---|
| `riantr/moonbit_static_analysis@0.5.0` | **188 L2 findings — unchanged** | it has **zero** concatenation sites (§2.4) |
| `fixtures/vuln_demo` | **15 L2 findings — unchanged** | it has **zero** concatenation sites (§2.4) |
| `riantr/moonbit_doubleML@0.164.64` | the L2 findings move by a **small** number, and the **only** family that can move is `TAINT-ALLOC` | the shape's claims are all allocation-size claims; the 105 concatenation sites can only produce a claim where the size is read back (19 variables, 49 reads) |
| `riantr/moonbit_doubleML@0.164.64` | the **three** M1 sites **drop** | §8's path (b) |
| the self-scan row | the **statements** move | this phase edits `src/app/abs.mbt` |
| the published interface | **unchanged** | §4 |

The three committed artefacts are regenerated with the same recipe
(`--funnel --trials 4`, one slice each) and the numbers are updated in the
same commit that changes them.

---

## 10. The LOOP steps

1. **This document**, committed before any code.
2. **Measure the defect first** — §2 is that measurement; the six shapes are
   re-measured after the change and the two tables compared.
3. **Baseline every number that will move** — §2.4 and §2.5.
4. **Decide and record the change** — §3; and the published-interface cost is
   MEASURED (§4), not assumed.
5. **Implement it** in `src/app/abs.mbt`.
6. **Assert both directions** — criteria 1–4 in §5.
7. **Falsify it** — §6, on the committed tree, byte-identically.
8. **Settle M1's status by measurement** and state it — §8.
9. **Re-measure and update in the same commit** — every number §9 predicted,
   re-derived by `readme_table.mjs`, in every place it appears.
10. **Ship the acceptance check** — `scripts/qa/plus_size.mjs`, with a
    `--falsify` mode, wired into the gate and CI; the acceptance record in
    `docs/qa/IFDS_PHASE3_ACCEPTANCE.md`; the ledger in
    `docs/qa/IFDS_PHASE3_LEDGER.json`.
11. **Commit and release-gate** — the local gate and the **newest-toolchain**
    gate are green. The CI runner installs the newest MoonBit, so a green
    local gate on an older toolchain does not prove the release compiles.
12. **Release** — bump, declare the (unchanged) interface in the notes, tag,
    push gitee then github, CI publishes, verify the published artefact, and
    point the published-version row at **the version being published**.

---

## 11. Reproduction

```sh
# the defect, as it is today
node _build/qa/phase3/probe_plus_shapes.mjs

# the footprint, per corpus
node _build/qa/phase3/measure_plus_arrays.mjs

# M1's baseline
node scripts/qa/ifds_spike.mjs --corpus .repos/riantr/moonbit_doubleML/0.164.64 \
  --label doubleML-phase3-baseline --json _build/qa/ifds_spike/doubleML-phase3-baseline.json

# the published numbers, re-derived
node scripts/qa/readme_table.mjs
node scripts/qa/release_interface.mjs
```
