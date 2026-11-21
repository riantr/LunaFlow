# IFDS Phase 2 — the SIZE of a container, and the taint of its CONTENTS

**Subject:** what changes in the abstract layer when the taint that reaches a
container's **size** is separated from the taint that reaches its
**contents**.

**Status:** Phase 2, PLANNED. This document is written BEFORE any code
changes; the measurements in §2 are the state of the tree the plan was made
on, and the sections marked *to be filled* are filled in by the commit that
carries the change.

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
   `Array::make(n, x)` the sources of `x` do not appear in the size's label.
4. **The elements of a sized array do not carry the size's taint.**
5. **Every published number that moves is re-derived**, not remembered.
6. **The interface change is declared in the release notes**, and
   `release_interface.mjs` passes.

## 6. The falsifications

A check that cannot fail proves nothing. Each of these must FAIL, and the
source must come back byte-identical:

| what is broken | what must happen |
|---|---|
| the size's taint is made to inherit the contents' again | the literal case's claim returns, and the assertion that it does not fire fails |
| the contents' taint is made to inherit the size's again | the `Array::make(n, 0)` element case's false claim returns |
| the size's taint is dropped entirely (every size clean) | the true claims stop firing — the assertions that they MUST fire fail |
| the release notes' declaration is removed | `release_interface.mjs` fails |

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

---

## 8. M1's status, to be filled

*To be filled by the commit that carries the change: what M1 reads over
doubleML after it, and whether the three sites of §6.1 are inside this
phase's footprint at all.*
