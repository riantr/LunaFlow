# IFDS Phase 2 acceptance — the size of a container, and the taint of its contents

This is the record of Phase 2: the separation of a container's **SIZE** taint
from its **CONTENTS'** taint. One command checks it:

```sh
node scripts/qa/size_taint.mjs
```

It builds the analyser first (a binary left over from an earlier build
measures the product as it *was*), writes a module of nine shapes into the
work directory, runs the analyser over it, and compares what it says with what
the phase claims. It exits non-zero if any check fails.

| what it checks | what it asserts |
|---|---|
| **the four NEGATIVE shapes** | a container whose contents are tainted and whose count is not the untrusted input's to choose produces **no** allocation-size claim |
| **the five POSITIVE shapes** | a size that the untrusted input really does choose still produces the claim — a numeric parameter, an array parameter's length, a string parameter's length, a string built from untrusted input, and the length read back out of a count-sized array |
| **the labels** | every claim names the sources that decide the SIZE, and none of them names the ELEMENT |
| **the coverage ledger** | the twenty doubleML claims the repair removed are named in `docs/qa/IFDS_PHASE2_LEDGER.json`, every one of them carries a verdict, and **none of them is back** in the committed doubleML artefact |
| **the falsification mode** | `--falsify` inverts one expectation on purpose and requires the check to FAIL |

The unit assertions are in `src/app/size_taint_wbtest.mbt` (10 of them) and
run as part of `moon test src/app` on all three targets.

## What the check reads on this tree

MEASURED (2026-11-22), the analyser built from this tree, over the nine
shapes. **All 21 checks agree.**

| shape | the claim | L2 allocation-size claims |
|---|---|---:|
| `size_of_literal_contents` | the count is 1 whatever the element is | **0** |
| `size_of_bound_length` | the same, through a binding | **0** |
| `size_after_push` | the count is 2 | **0** |
| `element_of_sized_array` | the elements are ZEROS, so the size is a constant | **1** — the first allocation's, whose size IS `n` |
| `size_of_made_contents` | the count is `n`, and `user` says what is in the array | **2** — both naming `n`, **neither** naming `user` |
| `size_from_parameter` | the caller chose the size | **1** — `n` |
| `size_from_parameter_length` | the caller chose how many elements | **1** — `xs` |
| `size_from_string_length` | the caller chose the string's length | **1** — `s` |
| `size_from_built_string` | the input's length decides it | **1** — `user` |

The dynamic layer (L1) filed **11** claims of its own over the same shapes.
Those are reported and not counted: the L1 has its own taint model and its own
allocation rule, and this phase changed the L2's value domain. The L2 filed
**11** findings in total, **3** of them not about an allocation size (the size's
interval reaches below zero for an `Int32` parameter, and one index may be out
of bounds — other rules' business).

**The falsification mode fails, as it must:** with one expectation inverted it
reports `1 of 22 checks FAILED` and exits 1.

## The falsifications, in the source

The shipped check proves the *behaviour*; the source-level falsifications
prove the *repair* is the thing that carries it. Four cases, each run against
the whole suite, each with the source restored byte-identically afterwards
(SHA-256 compared):

| case | what is broken | what failed |
|---|---|---|
| **F1** | the change is reverted entirely | `the ELEMENTS of a sized array do not carry the size's taint`, `the length of a sized array names only the sources that decide the COUNT` |
| **F2** | the size's taint inherits the contents' again | `the length of a sized array names only the sources that decide the COUNT` |
| **F3** | the contents' taint inherits the size's again | `the ELEMENTS of a sized array do not carry the size's taint` |
| **F4** | every size is clean | four of this phase's assertions **and four pre-existing ones** (three Phase-1, and the tainted-parameter one) |

They ship as `scripts/qa/size_taint_falsify.mjs` — a manual, local tool that
rewrites tracked files, so it refuses to run on a dirty tree and it is
deliberately not wired into CI. It was re-run against the **committed** tree
on 2026-11-21: F1 → 2 of 274 tests failed, F2 → 1, F3 → 1, F4 → 8, the source
came back byte-identical, no tracked file changed, exit 0.

`docs/qa/IFDS_PHASE2.md` §6 has the whole table, including the plan's own
expectation that the measurement corrected.

## The coverage ledger

The repair removed **20** claims from doubleML and added **none**. Every one of
them is named in `docs/qa/IFDS_PHASE2_LEDGER.json` with the class it belongs to
and the reason it went, and `scripts/qa/size_taint.mjs` fails if any of them
comes back into the committed artefact. `docs/qa/IFDS_PHASE2.md` §9 is the
adjudication: **2** of the 20 were self-refuting (the tainted parameter fixes
only a loop's trip count, so its value cannot change the index), and **18**
were in-bounds-but-data-dependent — a coverage cost, registered rather than
silent.

## The published interface

`AbsVal`'s array case grew a third component, so a consumer that constructs an
`AbsVal::AArr` or matches it with two fields does not compile against this
release. The declaration is **enforced**, not trusted:
`scripts/qa/release_interface.mjs` compares the `.mbti` at every release's tag
against that version's notes and fails when the version being prepared breaks
the published interface without saying so.

**Published as `riantr/LunaFlow@0.1.31`** (2026-11-21, checksum
`09713b24686b132bfd559efab90b3e6ba158503926187df67864a1dae2862134`). The
published module was verified from a clean consumer — `moon add` resolves and
pins 0.1.31, the consumer builds and runs, and the published library API
answers (**4 of 4**) — and over the fixture corpus the published report agrees
with the local build (**29 findings on both sides**, 11 of 11 checks). The
published page carries the declaration: the registry freezes a version's README
at publish time, and the declaration was in the tag.

