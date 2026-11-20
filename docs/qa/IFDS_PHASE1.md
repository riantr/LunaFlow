# IFDS Phase 1 — the labelled, kill-exact taint engine

**Subject:** what changes in the analyser when the abstract layer's taint
becomes a *labelled* may-taint computed by a flow-sensitive fixpoint, and the
layer's blanket loop rule goes.

**Status:** Phase 1, SHIPPED in the source tree. The findings families, the
report's sections and the CLI's flags are unchanged; the taint's *meaning*
and the *evidence* a taint finding carries are not.

**Date:** 2026-11-20. **Phase 0:** `docs/qa/IFDS_SPIKE.md` — the
measurement that asked whether this was worth doing. This document records
what was done, what it cost, and what it did not settle.

---

## 1. What Phase 1 is

Phase 0 measured two things on three corpora. The first: a flow-sensitive,
kill-exact, labelled fixpoint over the module's own CFG **loses no taint
sink** the abstract layer finds — 0 lost sinks on all three corpora. The
second: the abstract layer's **blanket loop rule** — "a tainted loop
condition taints every number the condition reads" — puts a **false** claim
at every site it touches, because the number it taints is the loop's
*counter*, and the counter does not carry the bound's taint.

Phase 0's verdict was that the rule should be **replaced**, not deleted:
the rule was a coarse encoding of one true fact — *this loop's bound is
untrusted* — and deleting it would drop that fact along with the false
claim.

**What Phase 1 changed, in three parts.**

| # | The change | Where |
| --- | --- | --- |
| 1 | **Labels.** The taint is a *set of sources*, not a bit. A finding says which parameter was untrusted. | `src/app/abs.mbt` |
| 2 | **Kill-exactness.** The taint follows the assignments and is killed by them; the blanket rule is gone. | `src/app/abs.mbt` |
| 3 | **The counter/bound relation.** A number compared with another number is narrowed by it — the relation the blanket rule approximated, stated in the domain that can hold it. | `src/app/abs.mbt`, `refine_into` |

And two things the verification turned up:

| # | The change | Where |
| --- | --- | --- |
| 4 | **The CFG's merge node had no outgoing edge**, and a loop's back edge came from one branch arm only. | `src/app/cfg.mbt` |
| 5 | **The coverage line divided by the wrong universe** — the scanner's function count, which includes the test blocks the flow pass never looks at. | `src/app/report.mbt` |

---

## 2. Labels — the taint says what was untrusted

**Before.** `AbsCell` carried `t : TaintMode`, a three-valued mode:
`TClean`, `TMaybe`, `TTainted`. A finding said *"tainted value may reach an
array index"* and its evidence was the expression — `buffer[[0,0]]`. Neither
the message nor the evidence said **which** value was untrusted, so a reader
looking at a finding had to guess.

**After.** `AbsCell` carries `srcs : Array[String]` — the set of sources
the taint came from. A source is `param:<name>`. The join is a **union**,
and the union is **finite**: the set is a subset of the function's
parameters, so it grows to at most one entry per parameter and the widening
can never run away. That is the difference between this domain and the
interval domain beside it, whose bound goes to a million in either
direction.

The label reaches the reader in the message:

```
tainted value from parameter `user` may reach an array index / buffer offset
tainted value from parameters `a` and `b` may control an allocation size
```

**MEASURED on `riantr/moonbit_doubleML@0.164.64`:** **1,094 of 1,094** of the
layer's taint findings name their source. The 202 taint findings in the
same report that do **not** are the *dynamic* layer's — a different engine,
with its own (concrete) semantics, and out of Phase 1's scope.

---

## 3. The blanket rule, and what replaced it

### 3.1 The rule is gone

The rule was `implicit_abs_taint`: at a `while` head, when the condition was
tainted, every **number the condition read** was marked tainted. It was the
only reason `TMaybe` existed.

**The claim it made was false.** The tainted value is the loop's *bound*; the
number it tainted is the loop's *counter*; and the counter does not carry the
bound's taint. What the counter's *value* has is a **relation** to the
bound — and a relation between two numbers is not a taint.

### 3.2 What the rule cost, measured

**MEASURED on `riantr/moonbit_doubleML@0.164.64`, the full funnel run:**

| family | before | after |
| --- | ---: | ---: |
| `TAINT-INDEX` | 236 | **225** |
| `TAINT-ALLOC` | 869 | 869 |
| `RANGE-VIOLATION` | 1,403 | 1,403 |
| `INDEX-OOB` | 684 | 684 |
| `INTEGER-OVERFLOW` | 90 | 90 |
| `UNSUPPORTED` | 20 | 20 |
| `DIVISION-BY-ZERO` | 14 | 14 |
| **L2 findings in total** | **3,316** | **3,305** |

**11 findings went, and they were the rule's.** The Phase-0 spike named the
13 *sites* (file + line) at which the rule was the only source of the taint.
Eleven of them are gone. **Two survived — with a different label**, because
at those two sites the index carries a *real* taint as well: `rdd.mbt:2724`
and `rdd.mbt:2729`, where the counter `a` is derived from `lo`, which comes
from a binary search over `u_r.length()`. The rule was **adding** to a taint
that was already there; the label now says so:

```
rdd.mbt:2724  tainted value from parameter `u_r` may reach an array index / buffer offset
```

### 3.3 The honest claim survived

At **every one** of the 13 sites, the layer already reported the claim the
rule was a proxy for: an index **out of bounds**. That claim is in the
**value** domain, and it is still there:

| site | before | after |
| --- | --- | --- |
| `rdd.mbt:2724` | `TAINT-INDEX` + `INDEX-OOB` | `TAINT-INDEX` (labelled) + `INDEX-OOB` |
| `ps_processor.mbt:552` | `TAINT-INDEX` + `INDEX-OOB` | `INDEX-OOB` |

**The fixture proves it.** `fixtures/vuln_demo/lib.mbt:6` is
`copy_prefix(buffer : Array[Int32], len : Int32)` — the function the
repository exists to test. Before Phase 1 it carried a `TAINT-INDEX` whose
message was *"tainted value may reach an array index"* and whose evidence was
`buffer[[0,0]]`: no sign of what was untrusted. After Phase 1 it carries the
honest claim, `INDEX-OOB` — the counter's value may exceed the array's
length — and no tainted-index claim at all.

### 3.4 The counter/bound relation

The relation the rule approximated now exists where a relation between two
numbers can be held: the **value** domain. `refine_into` gained the case
`x < y` where **y is a variable** — the existing code narrowed a number
against a *constant* and against a *length*, and not against another
variable, so `while i < len` narrowed nothing at all.

The narrowing is sound: `x < y` with `y ≤ y.hi` gives `x ≤ y.hi − 1`, and
`x ≥ y` with `y ≥ y.lo` gives `x ≥ y.lo`. The arithmetic is done in 64 bits
and clamped back, because MoonBit's own arithmetic *wraps* — a bound that
wrapped would be a wrong bound, and a wrong bound downstream is a false
finding somewhere else.

---

## 4. The CFG defect the verification found

Phase 1's verification is the Phase-0 harness, re-run against the new layer.
The harness compares the layer with the flow-sensitive fixpoint, and the
comparison **failed at first** — for a reason that had nothing to do with the
taint.

**`build_cfg` disagreed with itself about where a block ends.** The `if`
handler sets `cur = m` — the **merge** node is the block's exit. The helper
that finds a loop body's exit node (`last_node`) went into one of the
**arms** instead. So:

* the **merge node had no outgoing edge at all** — a dead end in the middle
  of the block; and
* the **back edge of a loop whose body ends in an `if` came from one arm
  only**, so whatever the *other* arm assigned never reached the loop head.

The abstract layer walks the AST, so it was never affected — it joins the
two branches and then joins with the loop head, which is right. The **flow
fixpoint** walks the CFG, so it lost the assignment.

**MEASURED on doubleML:** the flow-sensitive fixpoint found **1,289** taint
sites after the fix and **1,286** before it. The two sites the layer had and
the fixpoint did not — `rdd.mbt:2724` and `rdd.mbt:2729` — are the
binary-search pattern, and they came back.

The same defect reached the report: the CFG's mermaid diagrams, the
unreachable-statement findings and the program slices are all built from
this CFG. The fix is in `src/app/cfg.mbt` — the `if` case of `last_node` is
gone, and the block's exit is the merge, as `emit_stmts` already said.

---

## 5. The coverage accounting

The report's CFG-coverage line divided by `stats.funcs` — the **scanner's**
function count, which includes the test blocks the flow pass never looks at.
On doubleML that said *"600 of 2,529 — the first 600 in file order; 1,929
functions had no CFG"*, when the flow pass was given **1,411** functions and
left **811** of them without a CFG.

The denominator is now the number of functions the flow pass was **given**
(`ReportInput.cfg_universe`), so the line says *"600 of 1,411 — the first 600
in file order; 811 functions had no CFG and can carry no CFG finding"*.

---

## 6. The measurements, after Phase 1

### 6.1 No lost sink, on all three corpora

The Phase-0 harness's M1 check — *every taint site the layer found is also a
site the flow-sensitive fixpoint found* — now compares against the **plain**
fixpoint, the one with **no blanket rule**. Before Phase 1 it had to compare
against the spike's `with-rule` mode, because the layer carried the rule too;
that made the check **vacuous** for the claim that matters, since the rule
invents taint on both sides.

| corpus | L2 taint sites | fixpoint (plain) | fixpoint (with rule) | sites the rule added | **L2 sites the fixpoint did NOT find** |
| --- | ---: | ---: | ---: | ---: | ---: |
| `fixtures/` | 7 | 8 | 10 | 2 | **0** |
| doubleML 0.164.64 | 1,094 | 1,289 | 1,317 | 28 | **0** |
| published LunaFlow 0.1.29 | 12 | 41 | 71 | 30 | **0** |

**0 lost sinks on all three corpora** — and this time the comparison is with
the fixpoint the layer is now supposed to be.

### 6.2 The scale

| corpus | L2 | fixpoint (plain) | fixpoint (with rule) |
| --- | ---: | ---: | ---: |
| doubleML | **260 ms** | 278 ms | 283 ms |

### 6.3 The reports

| artefact | report | of A12 (512 KB) | trace | of A12 (64 MB) |
| --- | ---: | ---: | ---: | ---: |
| doubleML 0.164.64 | **392,644 B** | 75 % | 39,479,846 B | 59 % |
| static_analysis 0.5.0 | **153,203 B** | 29 % | 2,618,138 B | 4 % |
| `fixtures/vuln_demo` | 35,578 B | 7 % | 80,740 B | 0 % |

The recipe is the documented one — `--funnel --trials 4` and one slice each —
and the artefacts reproduce **byte-identically** under it: all three traces and
all three findings sidecars are identical on a re-run, and the reports differ
only in their wall time.

**The recipe had drifted, and this is where it is recorded.** The artefacts
committed earlier on 2026-11-20 were generated with the **default `--trials 8`**
instead of the documented `--trials 4`, so they no longer matched the recipe,
the doubleML trace had doubled to 69.6 MB, and the 64 MB ceiling had to be
raised to 96 MB to hold it. The artefacts are back on the documented recipe, the
trace is **37.6 MB**, and the ceiling is back to **64 MB**. The L2 is unaffected
by the trial count — it is an abstract layer — so the findings in this document
are the same either way; the L1's event counts are not, and the ones above are
the ones the recipe produces.

### 6.4 The analyzer on its own source

The analyzer is one of the modules it analyses, so its own source is a corpus
like any other, and Phase 1 shows up in it.

| tree | files | statements | L1 events | L2 findings | taint sinks |
| --- | ---: | ---: | ---: | ---: | ---: |
| the 0.1.29 release (`8e50769`) | 51 | 6,388 | 9,903 | 46 | 7 |
| the D1+D2 tree (`7e35063`) | 53 | 6,579 | 9,903 | **59** | 7 |
| the Phase-1 tree | 54 | 6,644 | 10,198 | **54** | 8 |
| the repaired tree | 57 | 6,776 | 10,201 | **46** | 8 |

The **59 → 54** is Phase 1: the blanket rule invented **five** findings on this
tree — four in `src/app/interp.mbt` and one in `fixtures/vuln_demo` — and they
are not in the 54. The **46 → 59** is D1+D2, and it is *not* Phase 1: the EVA's
family-by-file distribution is **identical** between the D1+D2 tree and the
Phase-1 tree, 41 findings in both, the same 41 at the same places. That was
settled by building both trees side by side (`git worktree`) and diffing their
§5.3 tables, because the tempting conclusion — that the CFG repair had started
inventing `INDEX-OOB` findings — is **false**: reverting the CFG repair alone
leaves the count at 41, and reverting the three `abs.mbt` changes alone leaves
it at 41 as well.

The **54 → 46** is the value-domain repair recorded in §8: the eight false
positives in `family_count_table` are gone, the two in `conc.mbt` are gone, and
three new files (the lockstep scan and two whitebox test files) are new source.
The EVA's own count on this tree reads **32** findings, **14** of them under
`src/`.

The `git worktree` of the 0.1.29 release also **reproduced the README's
committed self-scan row exactly** — 51 files, 6,388 statements, 9,903 events,
46 L2 findings, 0 dead, 7 taint sinks, 2 / 1 / 3 VCs — which is what says the
new row was measured with the same recipe and not a different one.

**A README sentence was wrong because of this.** The Verification section said
the evolved value analysis "reports **exactly one** finding on LunaFlow's own
tree". It reported **32** at the 0.1.29 release and reports **41** now, 23 of
them in `src/`. The sentence is a 0.1.14-era figure that had been carried
forward as a present-tense claim; it is now stated with its date and its
measured value.

---

## 7. The assertions, and that they can fail

`src/app/taint_labels_wbtest.mbt` holds **10** assertions. Five of them pin
what Phase 1 *added*; five pin what it must *not* break.

The five that pin the new claims **fail on the pre-Phase-1 semantics** —
measured by reverting the three changes in `src/app/abs.mbt` and running
them:

| assertion | pre-Phase-1 |
| --- | --- |
| a tainted index names the parameter it came from | **fails** |
| a tainted allocation size names the parameter it came from | **fails** |
| a finding names every parameter that reached it | **fails** |
| a loop counter is not tainted by the bound it is compared against | **fails** |
| a counter is bounded by the number it is compared against | **fails** |

The other five — the kill, the re-bound variable, the honest out-of-bounds
claim, and the two families — hold on **both** sides by design: they are the
regression guards, and they are what says that Phase 1 did not change what
the tool claims, only what it can prove about the claim.

---

## 8. What is NOT settled

* **The 12 allocation sites the fixpoint has and the layer does not.** On
  doubleML the fixpoint finds **12** tainted allocation sizes the layer does
  not report, in one method of one corpus (`apo.mbt`, `irm.mbt`, `iivm.mbt`,
  `pliv.mbt`, `plpr.mbt`, `did_cs_binary.mbt`). The layer's allocation rule
  did not fire at those sites. The mechanism is **not characterised**: the
  shapes were reproduced in isolation and each of them reports the finding
  correctly, so it is something about the surrounding code that has not been
  found yet. It is **pre-existing** — the D1+D2 tree does it too — and it is
  **not** a lost sink (M1 is about the other direction).
* **The fixpoint is not the layer.** Phase 1 did **not** replace the
  abstract layer's walk with a CFG worklist. The layer's own walk is already
  a join-based fixpoint at the loop heads, and the measurement says the two
  agree on every sink; replacing it would be a rewrite with no measurable
  gain. The CFG fixpoint remains the **reference** the layer is measured
  against.
* **The L1 still has its implicit flow.** The dynamic layer marks the
  numbers a tainted loop condition reads as tainted. That is a different
  engine with different semantics — it reports what it *observed* — and
  Phase 1 left it alone.
* **Nothing here was published.** The published `.mbti` changed (see
  below), and the release notes for the next release have to declare it.

---

## 8a. The three defects this section listed, and what they were

The three items above were recorded as open. They were **root-caused and
repaired** on 2026-11-20, and the measurement is below. The repairs are in
`src/app/abs.mbt` (the value domain), `src/app/relation.mbt` (the relations),
`src/app/lockstep.mbt` (a new file: the function-level scan) and
`src/app/eva.mbt` (the per-function facts).

### 8a.1 The boolean literal was not exact — this was D3, and it was all three

`AbsVal`'s `ABool(t, f)` means "CAN be true" and "CAN be false". Every
construction of it in `abs.mbt` follows that reading — the comparisons, the
conjunction, the disjunction and the negation all swap or combine the two
flags correctly — **except the literal**, which built `ABool(b, b)`.

For `true` that was harmless. For `false` it was a **contradiction**: a value
that can be neither true nor false. And a contradiction propagates:

* `!flag` on it could not be true either, so `if !found { ... }` was
  **pruned**, and everything the branch assigned was lost;
* `while attempt < max_attempts && !succeeded` could not be true, so the
  **loop body was never analysed**;
* `if !succeeded { abort(...) }` reported **both** branches as unreachable,
  and returned an **empty** state — wiping every binding made before it.

**MEASURED (2026-11-20) on `riantr/moonbit_doubleML@0.164.64`:** the defect
cost two real sinks in `did_aggregation.mbt` (lines **229** and **231**), and
it made the layer claim both branches of one `if` unreachable in
`riantr/moonbit_static_analysis@0.5.0`'s `moonfiles.mbt` (line 1142). The
repair is one line — `EBool(b) => AbsCell::new(ABool(b, !b), [])` — and the
assertions that pin it are in `src/app/bool_literal_wbtest.mbt` (**6** of
them; **all 6 fail** when the repair is reverted, and all 6 pass when it is
restored).

**And the "12 allocation sites" were the same defect.** The spike's
attribution counts the sites the fixpoint has and the layer does not, by
cause; the `alloc` cause reads:

| tree | `alloc` cause |
| --- | ---: |
| the 0.1.29-era spike | 12 |
| the Phase-1 tree | 12 |
| the repaired tree | **1** |

The allocations the layer could not see were the ones **inside the pruned
loop bodies** — `apo.mbt:606`, `irm.mbt:801`, `iivm.mbt:895`,
`pliv.mbt:613`, `plpr.mbt:135` and `did_aggregation.mbt:202`, and their
siblings. The same repair brought **14** `TAINT-ALLOC` findings back on
doubleML.

### 8a.2 The EVA could not relate two arrays' lengths

`family_count_table` in `src/app/report.mbt` pushes `codes` and `counts` in
lockstep, so `counts.length()` is always `codes.length()`, and every
`counts[at]` in it is in range. The layer reported **8** `INDEX-OOB` findings
there, and the paired fixture showed it could not tell the safe shape from
the unsafe one: `safe_counts` (lockstep) and `unsafe_counts` (`counts` never
grows) produced the same two findings.

**The repair is four things, all of them in the value domain:**

1. **The length-equality relation** (`src/app/lockstep.mbt`,
   `src/app/relation.mbt`). Two arrays pushed in the **same statement list**,
   **once each**, with no other resize and no `return`/`break`/`continue` in
   that list, have the same length. The relation is established when the two
   are bound with the **same known length**, and it is dropped when either is
   rebound.
2. **The bound is inherited** (`inherit_length_bound`). `at = j` gives `at`
   the value `j` has, so a bound below `j` is a bound below `at`. Without it
   the bound was lost at the assignment.
3. **A smaller index is still below the length** (`index_is_bounded_by`). `j - 1`
   is below `j`, so a bound below `j` is a bound below `j - 1`.
4. **The relation survives the loop's join** (`prune_length_bounds`). The index
   keeps the value it had before the loop when the loop never ran, so the
   relation holds after the loop when that value is below the length too — and
   a **negative** index is below every length, because a length is never
   negative.

**MEASURED (2026-11-20):** the eight findings in `family_count_table` are
gone, and so are two more in `conc.mbt` (`min` really is below
`cyc.length()`) and one in `ifds_tabulate` (`work_fact` and `work_node` are
parallel worklists). On doubleML three `INDEX-OOB` findings went, and all
three were checked against the source and were wrong: two of them are reads a
short-circuiting guard means never happens, and the third is an index that is
provably inside the array. The paired fixture now **tells the two shapes
apart**: `safe_counts` reports nothing, `unsafe_counts` reports its one true
finding. The assertions are in `src/app/lockstep_wbtest.mbt` (**5**), and
each mechanism is falsifiable on its own — reverting the relation fails one
assertion, reverting the inheritance fails two, reverting the subtraction
rule fails one.

### 8a.3 The short-circuit was not modelled

`&&` and `||` short-circuit in MoonBit, and the layer evaluated **both**
sides in the same state. So `acc[acc.length() - 1]` was read in a state the
guard had already ruled out — the array was empty, so the index was exactly
minus one, and the finding said the access was **provably** out of bounds: a
claim about a read that never happens. The repair evaluates the right side in
the state the left side's refinement gives.

**MEASURED (2026-11-20):** two such findings went on doubleML
(`did_cs.mbt:118` and `:125`). The evidence for this one is the corpus, not
a unit fixture: the shape needs the whole function around it — the array that
stays empty, the loop over a parameter and the second array beside it.

### 8a.4 What the repair cost

| measurement | before | after |
| --- | ---: | ---: |
| doubleML L2 findings | 3,305 | **3,321** |
| doubleML L2 steps | 167,211 | **185,766** |
| static_analysis L2 findings | 190 | **188** |
| this tree's L2 findings | 54 | **46** |
| this tree's EVA findings | 41 | **32** |

The step count is the deterministic measure: the repair analyses the loop
bodies the defective literal used to prune, and that is **more** work by
design. The wall clock is machine-dependent — the same tree measured 8.4 s,
10.1 s and 17.6 s for the *previous* commit's tree in one session — so the
table in the README is the committed artefact's own `elapsed_ms`, and the
comparison that counts is the step count.

---

## 9. The published interface

Phase 1 changes the published surface of the `app` package:

| before | after |
| --- | --- |
| `pub struct AbsCell { v : AbsVal, t : TaintMode }` | `pub struct AbsCell { v : AbsVal, srcs : Array[String] }` |
| `pub fn AbsCell::new(AbsVal, TaintMode) -> Self` | `pub fn AbsCell::new(AbsVal, Array[String]) -> Self` |
| `pub(all) enum TaintMode { TClean, TMaybe, TTainted }` | **removed** |
| `pub fn TaintMode::{code, equal, join, not_equal}` | **removed** |
| `pub(all) struct ReportInput { … abs_universe : Int32 }` | `… abs_universe : Int32, cfg_universe : Int32` |

`TaintMode` is gone because the taint is a set of sources and a mode is not
one. `AbsCell` and `AbsState` have **private** fields, so a consumer can
build an `AbsCell` but cannot read it — the practical break is
`AbsCell::new`'s second argument and the disappearance of `TaintMode`.

---

## 10. Reproduce

```sh
# The measurement, over the fixture corpus (this is the one CI runs).
node scripts/qa/ifds_spike.mjs --corpus fixtures --label fixtures

# ... and over the two fetched corpora.
moon fetch riantr/moonbit_doubleML --no-update
node scripts/qa/ifds_spike.mjs --corpus .repos/riantr/moonbit_doubleML/0.164.64 --label doubleML

moon fetch riantr/LunaFlow --no-update
node scripts/qa/ifds_spike.mjs --corpus .repos/riantr/LunaFlow/0.1.29 --label lunaflow

# The falsification: revert the three Phase-1 changes and watch the
# assertions fail.
node _build/qa/falsify_phase1.mjs break
moon test src/app --target native -f "phase1*"
node _build/qa/falsify_phase1.mjs restore
```
