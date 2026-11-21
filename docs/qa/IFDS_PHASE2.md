# IFDS Phase 2 — the SIZE of a container, and the taint of its CONTENTS

**Subject:** what changes in the abstract layer when the taint that reaches a
container's **size** is separated from the taint that reaches its
**contents**.

**Status:** Phase 2, SHIPPED. This document was written BEFORE any code
changes; the measurements in §2 are the state of the tree the plan was made
on, and the sections that were marked *to be filled* are filled in by the
commit that carried the change. §6 records that one of the plan's own
expectations was wrong, and §9 records a coverage cost the plan did not
foresee.

**Date:** 2026-11-21. **Phase 0:** `docs/qa/IFDS_SPIKE.md`. **Phase 1:**
`docs/qa/IFDS_PHASE1.md` — the labelled, kill-exact taint engine, and the
section §8 of that document left this open.

---

## 1. What Phase 2 is

Phase 1 gave the L2's taint a **label** (a set of sources) and made it
**kill-exact**. It left one thing open, and this phase is that thing.

**The length of a container inherits the container's CONTENT taint.** A cell
holds ONE source set, and for an array that set means "the elements may come
from these sources". Reading the length then produces a cell with the SAME
source set:

```moonbit
// src/app/abs.mbt, the `length` method
AArr(l, h) => AbsCell::new(AInt(l, h), t)   // t is the RECEIVER's source set
```

So an array whose element is tainted has a "tainted" length — and the count of
the elements says **nothing** about the taint of the values in them. It is the
same shape as the blanket loop rule Phase 1 removed: "the tainted value is the
bound, and the counter does not carry the bound's taint", except here the
tainted value is the *element* and the count does not carry the element's
taint.

**The honest repair is to separate the two taints**: the taint that reached a
container's **size** from the taint that reached its **contents**. That is
what this phase does.

---

## 2. The measurement, before anything changed

### 2.1 The mechanism, site by site

| site | what it computes | what it gets today |
|---|---|---|
| `abs.mbt:1252` | an array **literal** `[e1, e2]` | `AArr(n, n)` with the sources of the **elements** |
| `abs.mbt:1205` | `a.length()` | the receiver's source set — the **contents'** taint |
| `abs.mbt:1117` | `Array::make(n, x)` | `AArr(l, h)` with the sources of **all** the arguments |
| `abs.mbt:1228` | `a.push(x)` | the receiver's source set, again the **contents'** taint |
| `abs.mbt:1787` | an array **parameter** | `AArr(0, 64)` with the parameter's own source |
| `abs.mbt:1219` | `.length()` on a value the layer cannot resolve | `ATop` with the receiver's source set |

The last row is NOT this defect, and §7 says why it matters.

### 2.2 The shapes, and what the analyser claims about them today

Measured on `_build/qa/size_taint/measure.mbt`, one function per shape, with
the analyser built from this tree:

| shape | the claim today | is it TRUE? |
|---|---|---|
| `let a = [user]; Array::make(a.length(), 0)` | **no L2 claim** | the claim would be false — the count is 1 — and the `constant_size` guard suppresses it |
| the same through a binding | **no L2 claim** | as above |
| the same after a `push` | **no L2 claim** | as above, the count is 2 |
| `let a = Array::make(n, 0); let e = a[0]; Array::make(e, 0)` | **L2 claim**: "tainted value from parameter `n` may control an allocation size" | **FALSE.** `a[0]` is the zero that was put in the array; `n` says how many there are, not what they are. The claim is the SIZE's taint leaking into the CONTENTS' taint. |
| `Array::make(n, 0)` | **L2 claim**: "from parameter `n`" | TRUE — the caller chose the count |
| `Array::make(xs.length(), 0)` with `xs` a parameter | **L2 claim**: "from parameter `xs`" | TRUE — the caller chose how many elements `xs` has |
| `Array::make(s.length(), 0)` with `s` a String parameter | **L2 claim**: "from parameter `s`" | TRUE |
| `let s = "x" + user; Array::make(s.length(), 0)` | **L2 claim**: "from parameter `user`" | TRUE — the input's LENGTH decides it |

So the defect's footprint is **not** the literal case (the guard already masks
it, for the wrong reason). It is:

1. **the contents inheriting the size's taint** — the `Array::make(n, 0)`
   shape, where the elements are clean and the claim is false; and
2. **the size inheriting the contents' taint** — which the guard happens to
   mask whenever the count is provably constant, and which is the shape
   Phase 1's §8 recorded.

### 2.3 The baseline, on the three corpora

| corpus | L2 findings | of which `TAINT-ALLOC` |
|---|---:|---:|
| `fixtures/vuln_demo` | 15 | 4 |
| `riantr/moonbit_doubleML@0.164.64` | 3,321 | 959 |
| `riantr/moonbit_static_analysis@0.5.0` | 188 | 10 |

---

## 3. The change

**`AbsVal`'s array value carries the SIZE's taint, and the cell carries the
CONTENTS' taint:**

```moonbit
pub(all) enum AbsVal {
  ...
  AArr(Int32, Int32, Array[String])   // the length interval, and the size's taint
  ...
}
```

The size's taint is **the taint of what determines the COUNT**, and it is
computed where the count is produced:

| where the array comes from | the count is | the size's taint is |
|---|---|---|
| a literal `[e1, e2]` | fixed by the code | **empty** — the count is 1 whatever the elements are |
| `Array::make(n, x)` | `n` | the sources of `n` |
| a parameter `xs : Array[T]` | the caller's choice | the parameter's own source |
| `a.push(x)` | the old count plus one | the old size's taint |
| a join of two arrays | the two counts together | the union of the two size taints |

And the contents' taint — the cell's source set — stops carrying the size's:

| where the array comes from | the contents' taint is |
|---|---|
| a literal `[e1, e2]` | the union of the elements' sources (unchanged) |
| `Array::make(n, x)` | the sources of **`x`**, the element — not of `n` |
| a parameter | the parameter's own source (unchanged) |

**The size is read where the size is read.** `.length()` on an array yields a
cell whose taint is the array's **size** taint, not the array's contents' taint.

---

## 4. The published-interface cost

`AbsVal` is `pub(all)`, so the change to the `AArr` payload is **published**:

| before | after |
|---|---|
| `pub(all) enum AbsVal { … AArr(Int32, Int32) … }` | `pub(all) enum AbsVal { … AArr(Int32, Int32, Array[String]) … }` |

A consumer that **constructs** an `AbsVal::AArr` or **matches** it with two
fields does not compile against the next release. That is the honest cost of
the repair: the value domain's array case grows a third component, and the
alternative — keeping the defect — is a tool that reports a claim its own
domain refutes.

**This cost is declared, not remembered.** `scripts/qa/release_interface.mjs`
compares the `.mbti` at every release's tag against that release's notes and
fails when the version being prepared breaks the published interface without
saying so. It found its own first gap the day it was written — the
`ReportOptions.max_findings` field of 0.1.30 — so the obligation is enforced,
not trusted.

---

## 5. The acceptance criteria

1. **The size's taint is not the contents' taint.** A container whose
   elements are tainted and whose count is fixed by the code produces **no**
   allocation-size claim from its length.
2. **A size that really is the untrusted input's to choose still produces the
   claim**: a numeric parameter, the length of an array parameter, the length
   of a string parameter, and the length of a string built from untrusted
   input.
3. **The claim's label names only the sources that decide the size.** In
   `Array::make(n, x)` the sources of `x` do not appear in the size's label —
   and neither do they when the size is read back out of the array.
4. **The elements of a sized array do not carry the size's taint.**
5. **Every published number that moves is re-derived**, not remembered.
6. **The interface change is declared in the release notes**, and
   `release_interface.mjs` passes.
7. **The claims the repair removes are registered.** Every removed claim is
   named, with the reason it went, and a check fails if one of them comes
   back.

Criteria 1–4 are asserted in `src/app/size_taint_wbtest.mbt` (10 assertions)
and again end to end — the **analyser** over a module of nine shapes — by
`scripts/qa/size_taint.mjs`. Criterion 5 is `scripts/qa/readme_table.mjs`,
criterion 6 is `scripts/qa/release_interface.mjs`, and criterion 7 is the
ledger in `docs/qa/IFDS_PHASE2_LEDGER.json`, checked by the same script.

## 6. The falsifications

A check that cannot fail proves nothing. Each of these must FAIL, and the
source must come back byte-identical.

**The plan's first expectation was wrong, and the measurement said so.** The plan
expected the *literal* shape's claim to come back when the size's taint was
made to inherit the contents' again. It does not: the literal's count is a
constant (1, or 2 after a push), and the `constant_size` guard suppresses the
claim **either way** — which is what §2.2 already said about the literal shape.
The shape that tells the two taints apart is the one whose count is **not** a
constant: `Array::make(n, user)` holds `n` copies of `user`, so its length is
`n` and its length's taint must be `n`'s — never `user`'s.

MEASURED (2026-11-22), each case run against the whole suite, the source
restored afterwards and compared by SHA-256 (`_build/qa/size_taint/falsify.mjs`):

| what is broken | what must fail | what failed |
|---|---|---|
| **F1** the change is reverted entirely | the element shape's false claim returns, and the size's label names the ELEMENT | `the ELEMENTS of a sized array do not carry the size's taint`, `the length of a sized array names only the sources that decide the COUNT` |
| **F2** the size's taint inherits the contents' again | the size's label names the ELEMENT again | `the length of a sized array names only the sources that decide the COUNT` |
| **F3** the contents' taint inherits the size's again | the `Array::make(n, 0)` element shape's false claim returns | `the ELEMENTS of a sized array do not carry the size's taint` |
| **F4** every size is clean (the size's taint is dropped where it is made) | the true claims that go through a SIZE stop firing | `the length of an array PARAMETER …`, `the length of a string PARAMETER …`, `the length of a string BUILT …`, `the length of a sized array names only the sources that decide the COUNT`, **and three pre-existing Phase-1 assertions** |
| the release notes' declaration is removed | `release_interface.mjs` fails | the check that enforces the declaration |

**F4 caught more than this phase's own assertions:** three Phase-1 assertions
(`phase1: a tainted index names the parameter it came from`, `phase1: a finding
names every parameter that reached it`, `phase1: the taint families are the
ones the tool has always filed`) and the pre-existing `the length of a tainted
parameter is still an allocation size untrusted input chose` fail as well — so
the tree already had guards on this shape, and the new ones add the direction
the old ones did not cover.

The three literal-shape assertions (`the length of a container whose ELEMENTS
are tainted …`, `the same holds through a binding`, `the same holds after a
push`) pass in **every** case, including F1 and F2. They are not vacuous — they
pin that the `constant_size` guard keeps masking the literal shape — but they
do **not** detect the separation, and the table above says so rather than
claiming them as the falsification.

The source came back **byte-identical** after every case:
`src/app/abs.mbt` `771d479628970ffceddb581cf083ebfd67f92ff7b40a301ba5d8825d873b9f51`,
`src/app/relation.mbt` `ab499f72367cd33e99e5dac9801b755e4f7495f230b9d252efa60ddcdb4ffe09`.

---

## 7. What Phase 2 does NOT settle

* **The length of a value the layer cannot resolve.** `abs_binop` has no
  `AArr` case, so an array built by `+` is `ATop`, and `.length()` on an
  `ATop` yields `ATop` with the receiver's source set. That is **not** this
  defect: the claim there is a *may*-claim about a length the layer cannot
  compute, and it is TRUE — the count of distinct event times is a function of
  the tainted inputs. This is where the three doubleML sites of
  `IFDS_PHASE1.md` §6.1 live, and §8 says what that means for M1.
* **The trip count of a loop.** The count of an array grown inside a loop is
  the trip count, and the model does not carry the loop condition's taint into
  the count's taint. A loop-built array's count is therefore modelled as
  clean, which is a **coverage** limit, not a false claim.
* **The L1's own claim.** The dynamic layer has its own taint model and its
  own allocation rule (`src/app/interp.mbt`); Phase 1 left it alone, and so
  does this phase. The L1's claim on the literal shape is a different engine's
  semantics, not the L2's value domain.
* **Strings.** A string's length is not a function of its characters' taint
  either, but the shapes that reach it are different: a string parameter's
  length IS the caller's choice, and a concatenation's length IS the
  operands' lengths. The L2's string model carries the samples, not a
  separate size taint, and no shape was found where the string case produces
  a claim the domain refutes.
* **The value-flow behind a permutation or a derived count.** The L2 models
  what a value's taint is, not where a value's VALUE comes from: a permutation
  computed by sorting on tainted keys, and a count derived from comparing
  tainted values, are both opaque to it. §9 says what that costs.

---

## 8. M1's status

**M1 still FAILS over doubleML, at the same three sites, for the same reason.
The harness is not weakened: it still fails on doubleML, it still passes on the
other two corpora, and the three sites are still named.**

MEASURED (2026-11-22), the spike over doubleML 0.164.64, on the tree of this
phase and on the tree `IFDS_PHASE1.md` §8a.6 measured:

| | Phase 1 (published) | Phase 2 (measured) |
| --- | ---: | ---: |
| L2 taint sites | 1,110 | **1,090** |
| fixpoint (plain) taint sites | 1,289 | 1,289 |
| fixpoint (with rule) taint sites | 1,317 | 1,317 |
| sites the rule added | 28 | 28 |
| sites the fixpoint has and the L2 does not | 182 | **202** |
| sites the L2 has and the fixpoint does not | 3 | **3** |
| **M1 over doubleML** | **FAIL** (3 sites) | **FAIL** (the same 3 sites) |

The three sites are still `TAINT-ALLOC|did_aggregation.mbt|202`, `:203` and
`:204`, and they are **outside this phase's footprint**:

```moonbit
// .repos/riantr/moonbit_doubleML/0.164.64/did_aggregation.mbt:196-204
e_set_acc = e_set_acc + [e]          // an array built by `+`
...
let n_e = e_set_acc.length()         // the count of DISTINCT event times
let theta : Array[Double] = Array::make(n_e, 0.0)
```

`abs_binop` has no `AArr` case, so an array built by `+` is `ATop`, and
`.length()` on an `ATop` yields `ATop` with the receiver's source set — a
**different rule** from the one this phase repaired. The claim there is a
*may*-claim about a length the layer cannot compute, and it is **true**: the
count of distinct event times is a function of the tainted inputs. The layer is
therefore still **more complete** than the reference on that shape, and the
reference is still not a complete reference — which is exactly what M1 says when
it fails.

**The repair does not make the two engines agree on doubleML, and it does not
make the layer's claim provable.** What it does is this: the L2 lost **20**
taint sites, and the fixpoint — which does not read the L2's value domain —
still has **all 20**. So the count of "sites the fixpoint has and the L2 does
not" grew from 182 to **202**, and the two engines now disagree in the
direction where the **reference** is the coarse one. §9 says why.

---

## 9. The twenty claims the repair removed, and what each one was

The repair removed **20** claims from doubleML and added **none**. Every one of
them was carried by the same flow — the **count's** taint reaching the
**contents** of a count-sized array, and a read of that array's element
reaching an index — and every one of them is named in
`docs/qa/IFDS_PHASE2_LEDGER.json`, which `scripts/qa/size_taint.mjs` checks
against the committed artefact.

**The independent engine corroborates all 20, for the same reason.** The
flow-sensitive fixpoint (the Phase-1 spike) has no value domain: it models a
call's result as tainted by **all** of its arguments, and an array read as
tainted by the array. So `Array::make(n, x)` gives it an array whose contents
carry `n`'s taint, and the 20 sites are in its set too. That is not
corroboration of the CLAIM; it is the same modelling shortcut in a second
engine.

Per site, the source was read, and the sites fall into two classes:

| class | sites | what it is |
|---|---:|---|
| **self-refuting** | 2 | `dgp_pliv_cluster.mbt:121,122`. The tainted parameter is `n_obs`, and it fixes **only the loop's trip count**: the index is `cluster_a[i]`, whose value is `(rng.int(limit=n_clusters_a) + 1) % n_clusters_a` — the RNG's and `n_clusters_a`'s, not `n_obs`'s. `n_obs`'s VALUE cannot change the index's value at all. The claim was false; the repair removed a false claim. |
| **in bounds, but data-dependent** | 18 | `rdd.mbt` (10) and `p_adjust.mbt` (8). The index's value IS influenced by the parameter's values — the order of a permutation, or the size of a group of equal elements — so the claim was **not vacuous**. But the index is always inside the array it indexes: a permutation index into an array of the same length, or a group offset the code guards itself (`if pos + rpos + 1 >= n`, `if pos - lpos - 1 < 0`). The layer's own bar is that such an index is not a finding: *"an index that is PROVABLY inside the array it indexes is not a risk: not an out-of-bounds access, and not an offset that untrusted input chose."* The L2 could not prove the bound, and the count's taint was the only path it had to the index. |

**So the honest statement is a coverage cost of 18 findings on doubleML**, and
it is registered rather than silent: the ledger names every site, the class it
belongs to, and the reason; `scripts/qa/size_taint.mjs` fails if any of them
comes back into the committed artefact. The two self-refuting claims are the
repair working as intended.

---

## 10. The numbers this change moved

MEASURED (2026-11-22), the analyser built from this tree, over the three
committed corpora, before and after the change, with the same flags
(`--funnel --trials 4` and one slice each):

| corpus | measurement | before | after |
|---|---|---:|---:|
| `fixtures/vuln_demo` | L2 findings | 15 | **15** |
| `riantr/moonbit_doubleML@0.164.64` | L2 findings | 3,321 | **3,301** |
| `riantr/moonbit_doubleML@0.164.64` | findings in the sidecar | 3,524 | **3,504** |
| `riantr/moonbit_doubleML@0.164.64` | `TAINT-INDEX` | 227 | **207** |
| `riantr/moonbit_doubleML@0.164.64` | `TAINT-ALLOC` | 883 | **883** |
| `riantr/moonbit_static_analysis@0.5.0` | L2 findings | 188 | **188** |

Nothing else moved: the L1 events, the steps, the dead-code counts, the VCs and
the taint sinks are identical on all three corpora, and the fixture's artefact
is byte-identical apart from the wall clock. The **only** family that moved is
`TAINT-INDEX`, and it moved by exactly the twenty claims §9 names.

The self-scan row moved because this tree gained a file: **57 → 58 files**,
**6,780 → 6,822 statements**, and the L2 findings, the events, the dead-code
count and the taint sinks are unchanged (46 / 10,201 / 0 / 8).

The published interface changed too — `AbsVal`'s array case grew a third
component — and §4 says what that costs and who enforces the declaration.
