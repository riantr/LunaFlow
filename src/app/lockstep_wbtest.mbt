///|
/// THE ARRAYS THAT GROW TOGETHER.
///
/// Two arrays that are pushed in the same statement list -- once each, and
/// with no other resize in between -- have the SAME LENGTH. That is what
/// makes an index into one of them safe when the index is below the other's
/// length.
///
/// MEASURED (2026-11-20): before the relation existed, this repository's own
/// `family_count_table` in `src/app/report.mbt` collected EIGHT false
/// positives, and `riantr/moonbit_static_analysis@0.5.0`'s `ifds_tabulate`
/// one more: two parallel worklists, one index, and no way to say that the
/// index was below both.
///
/// The two assertions below are a PAIR, and that is the point: the first
/// says the safe shape is not reported, the second says the unsafe shape
/// still is. A relation that was too coarse -- one that related arrays that
/// do NOT grow together -- would pass the first and fail the second.

///|
/// A module built from parsed files.
fn lock_ast(src : String) -> ModuleAst {
  {
    coord: "lock/local",
    version: "0.0.0",
    root: ".",
    files: [parse_file("a.mbt", src)],
    manifest_deps: [],
    manifest_target: "",
  }
}

///|
/// The out-of-bounds findings the abstract layer produced.
fn lock_index_oob(src : String) -> Array[Finding] {
  let out : Array[Finding] = []
  let l2 = run_abstract(lock_ast(src), 100, 100000)
  for f in l2.findings {
    if f.kind == FIndexOob {
      out.push(f)
    }
  }
  out
}

///|
/// The SAFE shape: `counts` is pushed every time `codes` is, so the two are
/// as long as each other, and the index into `counts` is an index into
/// `codes`.
///
/// The index `at` is found by a search in `codes`, so it is below `codes`'s
/// length -- and `counts` is as long as `codes`.
test "lockstep: an index into an array that grows with the one it is below is in bounds" {
  let src =
    #|pub fn safe_counts(n : Int) -> Array[Int32] {
    #|  let codes : Array[Int32] = []
    #|  let counts : Array[Int32] = []
    #|  for i in 0..<n {
    #|    let mut at = -1
    #|    let mut j = 0
    #|    while j < codes.length() {
    #|      if codes[j] == i {
    #|        at = j
    #|        break
    #|      }
    #|      j = j + 1
    #|    }
    #|    if at < 0 {
    #|      codes.push(i)
    #|      counts.push(1)
    #|    } else {
    #|      counts[at] = counts[at] + 1
    #|    }
    #|  }
    #|  counts
    #|}
    #|
  assert_eq(lock_index_oob(src).length(), 0)
}

///|
/// The UNSAFE shape: `counts` is never pushed, so it stays empty while
/// `codes` grows, and the index into `counts` is out of range on every path.
///
/// This is the half of the previous assertion that makes it falsifiable: a
/// relation that related arrays which do NOT grow together would pass the
/// first assertion and fail this one.
test "lockstep: an array that does not grow with the one it is below is still reported" {
  let src =
    #|pub fn unsafe_counts(n : Int) -> Array[Int32] {
    #|  let codes : Array[Int32] = []
    #|  let counts : Array[Int32] = []
    #|  for i in 0..<n {
    #|    let mut at = 0
    #|    let mut j = 0
    #|    while j < codes.length() {
    #|      if codes[j] == i {
    #|        at = j
    #|        break
    #|      }
    #|      j = j + 1
    #|    }
    #|    if at < 0 {
    #|      codes.push(i)
    #|    } else {
    #|      counts[at] = counts[at] + 1
    #|    }
    #|  }
    #|  counts
    #|}
    #|
  assert_eq(lock_index_oob(src).length(), 1)
}

///|
/// THE BOUND IS INHERITED: an index that takes another index's value is
/// below the same length.
///
/// `at = j` gives `at` the value `j` has, and `j` is below `xs`'s length --
/// so `at` is too. Without the inheritance the bound was lost at the
/// assignment, and the index was reported as one that may be past the end.
///
/// The guard is a comparison, not a loop: a loop would join the state it
/// entered with the state it left, and the value the index had BEFORE the
/// loop -- zero, which may be past the end of an empty array -- would keep
/// the finding, correctly.
test "lockstep: an index that takes another index's value keeps the bound" {
  let src =
    #|pub fn inherited(xs : Array[Int32]) -> Int32 {
    #|  let mut j = 0
    #|  if j < xs.length() {
    #|    let at = j
    #|    xs[at]
    #|  } else {
    #|    0
    #|  }
    #|}
    #|
  assert_eq(lock_index_oob(src).length(), 0)
}

///|
/// A SMALLER INDEX IS STILL BELOW THE LENGTH: `j - 1` is below `j`, so a
/// bound below `j` is a bound below `j - 1`.
test "lockstep: an index that is one below a bounded index is bounded too" {
  let src =
    #|pub fn smaller(xs : Array[Int32]) -> Int32 {
    #|  let mut j = 1
    #|  let mut total = 0
    #|  while j < xs.length() {
    #|    total = total + xs[j - 1]
    #|    j = j + 1
    #|  }
    #|  total
    #|}
    #|
  assert_eq(lock_index_oob(src).length(), 0)
}

///|
/// THE GUARD SHORT-CIRCUITS: `acc[acc.length() - 1]` is only read when the
/// array is not empty, so the index is never below zero.
///
/// Without the short-circuit the layer read the index in the state the
/// guard had already ruled out: the array was empty, so the index was
/// exactly minus one, and the finding said the access was PROVABLY out of
/// bounds -- a claim about a read that never happens.
///
/// MEASURED (2026-11-20) on `riantr/moonbit_doubleML@0.164.64`: the same
/// shape in `did_cs.mbt` produced two such findings, and both are gone.
///
/// The evidence for this one is the CORPUS, not this assertion: the shape
/// needs the whole function around it -- the array that stays empty, the
/// loop over a parameter, and the second array beside it -- and a fixture
/// that reproduces the shape is not smaller than the code it comes from.
/// The assertion below still holds the line: the guarded read is not
/// reported.
test "lockstep: a guarded length-relative index is not read below zero" {
  let src =
    #|pub fn guarded(v : Int32) -> Int32 {
    #|  let mut acc : Array[Int32] = []
    #|  for i in 0..<3 {
    #|    if acc.length() == 0 || acc[acc.length() - 1] != v {
    #|      acc = acc + [v]
    #|    }
    #|  }
    #|  0
    #|}
    #|
  assert_eq(lock_index_oob(src).length(), 0)
}
