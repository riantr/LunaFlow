# IFDS Phase 3 acceptance — the size of a `+`-built array

This is the record of Phase 3: the **SIZE** of an array built by `+`. One
command checks it:

```sh
node scripts/qa/plus_size.mjs
```

It builds the analyser first (a binary left over from an earlier build
measures the product as it *was*), writes a module of six shapes into the
work directory, runs the analyser over it, and compares what it says with what
the phase claims. It exits non-zero if any check fails.

| what it checks | what it asserts |
|---|---|
| **the two NEGATIVE shapes** | a `+`-built array whose count is fixed by the code produces **no** allocation-size claim — the claim that refuted itself is gone |
| **the four POSITIVE shapes** | a count the caller really does choose still produces the claim, and the claim's **evidence carries the sum** of the two counts |
| **the labels** | every claim names the sources that decide the **COUNT**, and none of them names the **ELEMENT** |
| **the coverage ledger** | `docs/qa/IFDS_PHASE3_LEDGER.json` names the **fourteen** doubleML claims the repair removed (none may be back in the committed artefact) **and the twenty-nine it added** (every one of them must be there), so both halves of the trade are registered |
| **the falsification mode** | `--falsify` inverts one expectation on purpose and requires the check to FAIL |

The unit assertions are in `src/app/plus_size_wbtest.mbt` (12 of them) and run
as part of `moon test src/app` on all three targets.

## What the check reads on this tree

MEASURED (2026-11-21), the analyser built from this tree, over the six shapes.
**All 22 checks agree.**

| shape | the claim | L2 allocation-size claims |
|---|---|---:|
| `size_of_plus_literals` | the count is 2, fixed by the code | **0** |
| `size_of_plus_literal_binding` | the same, through a binding | **0** |
| `size_of_plus_parameter` | the count is `xs`'s length plus ONE | **1** — naming `xs`, **not** `user` |
| `size_of_plus_two_parameters` | the count is two caller's lengths plus ONE | **1** — naming `xs` and `ys`, **not** `user` |
| `size_of_plus_bound` | the same, through a binding | **1** — naming `xs`, **not** `user` |
| `element_of_plus_array` | the size is the ELEMENT's value | **1** — naming `xs` |

The claim's evidence carries the sum: `Array.make([1,65])` is a caller's array
(count 0–64) plus the literal's ONE.

The dynamic layer (L1) filed **6** claims of its own over the same shapes.
Those are reported and not counted: the L1 has its own taint model and its own
allocation rule, and this phase changed the L2's value domain. The L2 filed
**4** findings in total, **0** of them not about an allocation size.

**The falsification mode fails, as it must:** with one expectation inverted it
reports the one inverted check as `FAIL  size_of_plus_parameter: 0 L2
allocation-size claim(s) — got 1`, then
`PASS  the falsification mode broke the check, as it must — 1 failure(s)`, and
exits 0.

## `+` and `push` build the same array, and now the model says so

The phase's central measurement is a **parity** one. `acc + [x]` and
`acc.push(x)` append the same element to the same array, and the model has
always known the count of a **push**-built one — the `push` case grows the
count by one. Before this phase a `+`-built array had **no value at all**: it
was TOP, and `.length()` on a TOP fell back to the receiver's own sources —
the **elements'** taint.

MEASURED over two shapes that build the same array the two ways
(`_build/qa/phase3/probe_plus_vs_push.mjs`):

| shape | the L2 says |
|---|---|
| `plus_shape` (`acc = acc + [i]`) | `INDEX-OOB … index [0,0] vs length [0,6]` |
| `push_shape` (`acc.push(i)`) | `INDEX-OOB … index [0,0] vs length [0,6]` |

**Identical.** The phase does not invent a rule for `+`; it makes the model
treat the two ways of building an array the same. That is also why the phase
**ADDS** claims on doubleML: the index rules already reached every
push-built array (682 `INDEX-OOB` claims on that corpus, measured), and they
now reach the `+`-built ones too.

## The falsifications, in the source

The shipped check proves the *behaviour*; the source-level falsifications
prove the *repair* is the thing that carries it. Four cases, each run against
the whole suite, each with the source restored byte-identically afterwards
(SHA-256 compared):

| case | what is broken | what failed |
|---|---|---|
| **F1** | the change is reverted entirely | **11** of this phase's assertions |
| **F2** | the count's taint inherits the **contents'** again | **5** — the label assertions |
| **F3** | the count is dropped (it falls back to the unknown range) | **11** — and the two self-refuting claims return |
| **F4** | the count's taint is dropped (the count is clean) | **5** — the positive claims stop firing |

They ship as `scripts/qa/plus_size_falsify.mjs` — a manual, local tool that
rewrites tracked files, so it refuses to run on a dirty tree and it is
deliberately not wired into CI. It was re-run against the **committed** tree on
2026-11-21: F1 → 11 of 286 tests failed, F2 → 5, F3 → 11, F4 → 5, the source
came back byte-identically
(`dc0357e52d48f1495f70742c92c606d7d61ac9a41b9c2510b96284efec032514`, the
committed tree's hash), no tracked file changed, exit 0.

**The harness caught a vacuous assertion of mine on the way.** The first run
reported that one assertion "should have failed and did not" — the assertion
that the size's taint of a `+`-built array of two literals is EMPTY did not
bind the element, so the *contents'* taint was empty as well and the assertion
could not distinguish the repair from its opposite. It binds the element now,
and the falsification passes.

## The coverage ledger — both directions

The repair **removed fourteen** allocation-size claims from doubleML and
**added twenty-nine**, and six findings stayed with a sharper length. Every
one of them is named in `docs/qa/IFDS_PHASE3_LEDGER.json` with the class it
belongs to and the reason, and `scripts/qa/plus_size.mjs` fails if a removed
claim comes back **or** an added claim goes missing.

**The fourteen removed claims were TRUE.** Their count is the **trip count**
of a loop that grows a `+`-built array — the number of distinct ids, the
number of kept units, the number of distinct event times — and the trip count
is a function of the tainted input. The model does not carry the loop bound's
taint into the count, so the count's taint comes out clean and the claim is
lost. **That is a coverage cost of fourteen findings, registered rather than
silent, and the trip count is the next phase's work.**

**The twenty-nine added claims are the index rules reaching a class of arrays
they could not reach before.** The container is now *known* to be an array, so
`INDEX-OOB` and `TAINT-INDEX` apply to it. The index is in bounds in the
source — the counter is bounded by the array's **own** length, through a
binding (`n = arr.length()`) the model does not relate to the array — and the
count's lower bound is 0, so the model's own value domain **cannot refute**
the claim. It is a limitation of the model, not a false reading of the program,
and it is the same limitation the push-built arrays have always had.

## M1's status

M1 is **"no lost sink"**: every taint site the L2 found must also be a site
the flow-sensitive fixpoint found. MEASURED over doubleML with the same
harness and the same definition:

| | before | after |
|---|---:|---:|
| the L2's taint sites | 1,090 | **1,078** |
| sites the L2 has and the fixpoint does not | **3** | **0** |
| sites the fixpoint has and the L2 does not | 202 | 211 |

**M1 now PASSES**, and it was failing at the three sites the plan named
(`did_aggregation.mbt:202/203/204`). The harness is **not** weakened: M1's
definition is unchanged, the reference fixpoint is unchanged, and no site was
removed from either side of the comparison. The reference's own surplus grew
by nine, which is the other side of the same trade and is measured, not
asserted.

**The plan's expectation was right about the PATH and wrong about the SIZE.**
It expected the three claims to drop and a registered coverage cost to follow
— that is what happened. The cost is **fourteen** claims, not three: the
eleven others are the same shape in other files, and the measurement is what
says so.

## The numbers the change moved

MEASURED (2026-11-21), the analyser built from this tree, over the three
committed corpora, before and after the change, with the same flags
(`--funnel --trials 4` and one slice each):

| corpus | measurement | before | after |
|---|---|---:|---:|
| `fixtures/vuln_demo` | everything | 29 sidecar / 9 L2 rows | **unchanged** |
| `riantr/moonbit_static_analysis@0.5.0` | everything | 198 sidecar / 93 L2 rows | **unchanged** |
| `riantr/moonbit_doubleML@0.164.64` | sidecar rows | 3,504 | **3,519** |
| `riantr/moonbit_doubleML@0.164.64` | L2 table rows | 2,515 | **2,503** |
| `riantr/moonbit_doubleML@0.164.64` | `TAINT-ALLOC` | 959 | **945** |
| `riantr/moonbit_doubleML@0.164.64` | `TAINT-INDEX` | 326 | **328** |
| `riantr/moonbit_doubleML@0.164.64` | `INDEX-OOB` | 682 | **709** |
| `riantr/moonbit_doubleML@0.164.64` | the L2's steps | 185,516 | **272,316** |

**The plan's §9 expectation that "the only family that can move is
`TAINT-ALLOC`" was REFUTED by the measurement**, and the correction is
recorded in `docs/qa/IFDS_PHASE3.md` §9 rather than fixed in advance. The
`INDEX-OOB` and `TAINT-INDEX` families move because the container is now
known to be an array — the parity measurement above is why.

**The L2's steps rose by 47 %**, and the cause is named: the count of a
`+`-built array grows inside the loop fixpoint, so the fixpoint does not
converge early — exactly as it does not for a `push`-built array, which the
model has always modelled this way. The L2's own step budget did **not**
bind: the artefact still analyses all **1,411** functions and files no
`BUDGET-EXCEEDED` finding of the L2's own.

**The static-analysis corpus was measured at the version the committed
artefact names.** `riantr/moonbit_static_analysis@latest` served **0.5.2** on
the day of the measurement while the committed artefact is 0.5.0, and a diff
between two corpora measures the corpus rather than the change — so the
measurement was taken against 0.5.0, the committed version, and it shows
**nothing moved**. Upgrading the committed artefact to 0.5.2 is a corpus
upgrade with its own published numbers, and it is **not** this phase's work.

## The published interface

**The published interface is UNCHANGED**, and that is measured rather than
assumed: `abs_binop` is a private `fn` and is absent from
`src/app/pkg.generated.mbti`, and `AbsVal`'s shape — `AArr(Int32, Int32,
Array[String])` — is not touched by this phase. The declaration is **enforced**,
not trusted: `scripts/qa/release_interface.mjs` compares the `.mbti` at every
release's tag against that version's notes and fails when the version being
prepared breaks the published interface without saying so. Against `v0.1.31` the
checker reports **0 break(s) a consumer can see**, and the release notes declare
none, because there is none to declare.

## The publish

**Published as `riantr/LunaFlow@0.1.32`** (2026-11-21, checksum
`17b292826f4067de5691241348abf9d5124c33725e1e4e8383366dee7313cb02`). MEASURED
after the publish:

| what | the reading |
|---|---|
| the registry | `latest_version` **0.1.32**, `build_status` **success**, checksum `17b2928…313cb02` |
| a clean consumer | `moon add` resolves and **pins 0.1.32**, the consumer builds and runs, and the published library API answers — **4 of 4** |
| the published artefact | over the fixture corpus the published report agrees with the local build — **29 findings on both sides**, **11 of 11** checks |
| the published wasm | `moonx riantr/LunaFlow@latest` runs from a scratch directory outside the repository — exit 0 |
| the published page | the registry froze the README at publish time, and the frozen page carries the **0.1.32** section, the install line at 0.1.32, the Verification row at 0.1.32, and the measured numbers |

**The Verification row was right in the tag.** The registry takes a version's
README at the moment it publishes it, so the page is the README as it stood at
`v0.1.32` — and at that tag the Verification table's row already named
**0.1.32**, because the row was written before the publish, not after it. The
0.1.25 → 0.1.26 and 0.1.30 → 0.1.31 corrections did not have to be made here.

**CI, on the runner's own toolchain:** `check master` (run 44906177384) and
`publish LunaFlow v0.1.32` (run 44906188297) both **succeeded**, and both ran
on **MoonBit 0.1.20261119** — the toolchain the CDN serves as `latest`, the one
the local newest-toolchain gate was run against (11/11 green, `deprecated` 0).
