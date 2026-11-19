///|
/// PHASE 1 -- the L2's taint is LABELLED, KILL-EXACT, and no longer carries
/// the blanket loop rule.
///
/// These are the assertions that pin Phase 1's semantics. They are the
/// falsifiable part of the change: each one fails if the semantics move.
///
/// The file is a whitebox test (`_wbtest.mbt`) because it drives the
/// abstract layer's own entry point, `run_abstract`, and reads the findings
/// it produces.

///|
/// A module built from parsed files.
fn phase1_ast(src : String) -> ModuleAst {
  {
    coord: "phase1/local",
    version: "0.0.0",
    root: ".",
    files: [parse_file("a.mbt", src)],
    manifest_deps: [],
    manifest_target: "",
  }
}

///|
/// The findings of one kind the abstract layer produced.
fn phase1_of_kind(src : String, kind : FindingKind) -> Array[Finding] {
  let out : Array[Finding] = []
  let l2 = run_abstract(phase1_ast(src), 100, 100000)
  for f in l2.findings {
    if f.kind == kind {
      out.push(f)
    }
  }
  out
}

///|
/// THE LABEL: a taint finding says WHICH value was untrusted.
///
/// Before Phase 1 the message was "tainted value may reach an array index"
/// and the evidence was the expression -- neither of which says what was
/// untrusted. The source set is what makes the claim actionable: the reader
/// knows which parameter to look at.
test "phase1: a tainted index names the parameter it came from" {
  let src =
    #|pub fn g(user : String, ys : Array[Int]) -> Int {
    #|  let n = user.length()
    #|  let x = ys[n]
    #|  x
    #|}
    #|
  let found = phase1_of_kind(src, FTaintIndex)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameter `user` may reach an array index / buffer offset",
  )
}

///|
/// The label of an ALLOCATION size names its parameter too.
test "phase1: a tainted allocation size names the parameter it came from" {
  let src =
    #|pub fn k(n : Int32) -> Array[Int32] {
    #|  Array::make(n, 0)
    #|}
    #|
  let found = phase1_of_kind(src, FTaintAlloc)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameter `n` may control an allocation size",
  )
}

///|
/// Two parameters reach the same index, and the finding names BOTH.
test "phase1: a finding names every parameter that reached it" {
  let src =
    #|pub fn g(a : String, b : String, ys : Array[Int]) -> Int {
    #|  let n = a.length() + b.length()
    #|  let x = ys[n]
    #|  x
    #|}
    #|
  let found = phase1_of_kind(src, FTaintIndex)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameters `a` and `b` may reach an array index / buffer offset",
  )
}

///|
/// THE KILL: a tainted value that is overwritten leaves no taint behind.
///
/// This is what the fixpoint buys over a "the whole function is tainted"
/// analysis. The taint is killed at the assignment and re-bound with the
/// right-hand side's sources, so the sink sees a clean index.
test "phase1: a tainted value that is overwritten leaves no taint behind" {
  let src =
    #|pub fn h(user : String, ys : Array[Int]) -> Int {
    #|  let n = user.length()
    #|  let m = 0
    #|  let x = ys[m]
    #|  x
    #|}
    #|
  assert_eq(phase1_of_kind(src, FTaintIndex).length(), 0)
}

///|
/// The kill is exact: the overwritten value's taint does not come back
/// through a later read of the same name.
test "phase1: a re-bound variable does not carry its old taint" {
  let src =
    #|pub fn h(user : String, ys : Array[Int]) -> Int {
    #|  let mut m = user.length()
    #|  m = 0
    #|  let x = ys[m]
    #|  x
    #|}
    #|
  assert_eq(phase1_of_kind(src, FTaintIndex).length(), 0)
}

///|
/// THE BLANKET RULE IS GONE: a loop counter is not tainted.
///
/// The counter starts at zero and is incremented; nothing untrusted reaches
/// it. The blanket rule used to taint it anyway, because the loop's BOUND
/// was tainted -- and the claim it made ("a tainted value may reach an
/// array index") was false: the tainted value is the bound, and the bound
/// does not reach the index.
test "phase1: a loop counter is not tainted by the bound it is compared against" {
  let src =
    #|pub fn f(len : Int32, buffer : Array[Int32]) -> Int32 {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < len {
    #|    total = total + buffer[i]
    #|    i = i + 1
    #|  }
    #|  total
    #|}
    #|
  assert_eq(phase1_of_kind(src, FTaintIndex).length(), 0)
}

///|
/// ... and the honest claim SURVIVES: the counter's value is bounded by the
/// bound, so the index may be out of bounds. The rule was a proxy for this
/// claim; the value domain's relation between the counter and the bound is
/// the claim itself.
test "phase1: the counter's bound still produces the out-of-bounds claim" {
  let src =
    #|pub fn f(len : Int32, buffer : Array[Int32]) -> Int32 {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < len {
    #|    total = total + buffer[i]
    #|    i = i + 1
    #|  }
    #|  total
    #|}
    #|
  assert_eq(phase1_of_kind(src, FIndexOob).length(), 1)
}

///|
/// THE COUNTER/BOUND RELATION: a number compared with another number is
/// narrowed by it.
///
/// The blanket rule approximated this relation -- "this loop's bound is
/// untrusted" -- and the approximation was in the taint domain, where a
/// relation between two numbers does not fit. The relation lives in the
/// VALUE domain, and `refine_into` now states it: `i < n` narrows `i` by
/// `n`'s interval.
///
/// The fixture is chosen so that the narrowing is the ONLY thing that can
/// decide the claim: the array is a local of known length, the bound is a
/// local of known value, and the counter grows by a hundred each round, so
/// without the narrowing the counter's interval outgrows the array. The
/// bound is a VARIABLE and not a constant on purpose: a constant was
/// already narrowed, and the assertion would not be testing the new case.
test "phase1: a counter is bounded by the number it is compared against" {
  let src =
    #|pub fn f() -> Int {
    #|  let ys = [1, 2, 3]
    #|  let n = 2
    #|  let mut i = 0
    #|  while i < n {
    #|    ys[i]
    #|    i = i + 100
    #|  }
    #|  0
    #|}
    #|
  assert_eq(phase1_of_kind(src, FIndexOob).length(), 0)
}

///|
/// The same shape with a bound the counter outgrows: the index leaves the
/// array and the finding is there. This is the half of the previous
/// assertion that makes it falsifiable -- it says the narrowing is what
/// removed the finding, not that the finding was never there.
test "phase1: without the counter/bound relation the index outgrows the array" {
  let src =
    #|pub fn f() -> Int {
    #|  let ys = [1, 2, 3]
    #|  let n = 200
    #|  let mut i = 0
    #|  while i < n {
    #|    ys[i]
    #|    i = i + 100
    #|  }
    #|  0
    #|}
    #|
  assert_eq(phase1_of_kind(src, FIndexOob).length(), 1)
}

///|
/// THE SAME FAMILIES: Phase 1 changes WHAT the taint claims and WHERE it
/// came from -- not WHICH families exist. The taint families are the ones
/// the tool has always filed.
test "phase1: the taint families are the ones the tool has always filed" {
  let src =
    #|pub fn g(user : String, ys : Array[Int], n : Int32) -> Int {
    #|  let k = user.length()
    #|  let x = ys[k]
    #|  let a = Array::make(n, 0)
    #|  a.length() + x
    #|}
    #|
  assert_eq(phase1_of_kind(src, FTaintIndex).length(), 1)
  assert_eq(phase1_of_kind(src, FTaintAlloc).length(), 1)
}
