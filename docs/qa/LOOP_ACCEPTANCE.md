# LOOP acceptance — the three items, and how to re-check them

This is the record of the LOOP: three items, each checked by **running** the
thing it claims. One command checks all three:

```sh
node scripts/qa/loop_acceptance.mjs
```

It builds the analyser first (a binary left over from an earlier build
measures the product as it *was*), then checks the three items below and
prints one line per check. It exits non-zero if any check fails.

| item | what it runs | what it asserts |
|---|---|---|
| **1. Bound the findings table** | the analyser over `fixtures/vuln_demo` with `--max-findings 3`, and the committed doubleML artefact | every findings table carries a marker row naming the cap and the whole set; the count table above it **sums** to that whole set; the `_findings.jsonl` sidecar holds every finding the count tables name — the bound may cost the reader a row, never a finding |
| **2. D1 (five dead rules) + D2** | the analyser over the fixture, over a two-file module, and the unit assertions | D1: a tainted allocation size **is** reported, for the parser's spelling and the qualified one (the rule was dead code and fired on no input). D2: the same finding in two files is **two** findings (the key had no file in it, so the second was dropped), and the same finding twice in one file is still one |
| **3. Phase 1 (L2-IFDS)** | `scripts/qa/ifds_spike.mjs` over the fixture corpus, and its `--falsify` mode | M1 (no lost sink), M2 (the blanket rule's contribution), M3 (the model's coverage) — and the harness's own falsification mode, which breaks each check on purpose and requires it to fail |

And the **published** artefact carries the same three items:

```sh
node scripts/qa/published_items.mjs 0.1.30
```


## What the checks read on this tree

Measured on the tree this commit names.

**Item 1.** The fixture scan with `--max-findings 3` produced **4** bounded
tables — of 6, 8, 9 and 6 findings — and the sidecar kept all **29** fixture
findings. The committed doubleML artefact shows the cap of **300 of 2,535**,
its count table sums to **2,535**, and its sidecar holds **3,524** findings.

**Item 2.** The fixture carries **4** `TAINT-ALLOC` findings, and both
spelling assertions pass. The two-file module (`a.mbt` and `b.mbt`, the same
tainted allocation at the same line) yields **2** L2 findings, named `a.mbt`
and `b.mbt`.

**Item 3.** The spike over the fixture corpus: **7** L2 taint sites, all of
them also sites of the flow-sensitive fixpoint; the plain spike's **8** sites
are all sites of the spike with the rule; the rule added **2**, both carrying
the rule's own source; **0** gaps. The falsification mode is OK.

## The PUBLISHED artefact carries them too

Every check above measures the **local** build. The registry serves a different
artefact — the wasm one, built by CI — and that is the one a consumer actually
runs. `scripts/qa/published_items.mjs` runs the **published** module over the
fixture corpus (`moonx riantr/LunaFlow@0.1.30`, from a scratch directory of its
own, because `moonx` materialises the source into the current directory's
`.repos/`) and checks the same three items in *its* report:

| what it checks | what the published 0.1.30 does |
|---|---|
| the findings table is bounded | **4** bounded tables at `--max-findings 3` — of 6, 8, 9 and 6 findings — each count table summing to the whole set it names |
| the sidecar is lossless | **29** findings in the sidecar, **12** shown |
| D1: the allocation-size rule fires | **4** `TAINT-ALLOC` findings |
| D2: two files, two findings | **2** L2 findings, named `a.mbt` and `b.mbt` |
| the published report against the local build | **identical** — 29 findings, the same 7 families |

The published CLI accepts `--max-findings`, which is part of the release: the
bound is in the artefact the registry serves, not only in the repository.

## Each item is falsifiable — and was

A check that cannot fail proves nothing. Each item was broken on purpose and
had to fail:

| what was broken | what the check said |
|---|---|
| the cap raised so that no table is truncated | `every count table has a bounded findings table — 0 of 0` |
| the analyser's DOT spelling removed from the allocation-size rule (D1 is dead code again) | `D1: the allocation-size rule fires for the parser's spelling and the qualified one — 2 matched, 2 failed` |
| the file dropped from the de-duplication key (D2 again) | `D2: the same finding in two files is two findings — 1 L2 TAINT-ALLOC finding(s)` |

The source came back byte-identical after each case, and the check rebuilds
the analyser, so every case measured the product it had broken.

## The commits

| item | commit |
|---|---|
| 1. Bound the findings table | `8fbc2bf` |
| 2. D1 (five dead rules) + D2 | `7e35063` |
| 3. Phase 1 (L2-IFDS) | `d838c0d`, `ec1e79a` |
| the four defects the repairs turned up | `ec1e79a`, `e288eba` |
| this check | the commit that adds `scripts/qa/loop_acceptance.mjs` |
| the same check against the published artefact | the commit that adds `scripts/qa/published_items.mjs` |

The items' own records are in `docs/qa/IFDS_SPIKE.md` (what the measurement
found in the product), `docs/qa/IFDS_PHASE1.md` (the engine and the
re-measured tables) and `docs/design.md` (the transfer functions and the
acceptance rows).
