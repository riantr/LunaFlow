///|
/// THE BOOLEAN LITERAL IS EXACT.
///
/// `AbsVal`'s `ABool(t, f)` means "CAN be true" and "CAN be false". Every
/// construction of it in `abs.mbt` follows that reading -- the comparison
/// results, the conjunction, the disjunction and the negation all swap or
/// combine the two flags correctly -- except the LITERAL, which built
/// `ABool(b, b)`.
///
/// For `true` that was harmless. For `false` it was a contradiction: a value
/// that can be NEITHER true nor false. And a contradiction propagates:
///
///   * `!flag` on it could not be true either, so `if !found { ... }` was
///     PRUNED, and everything the branch assigned was lost;
///   * `while attempt < limit && !succeeded` could not be true, so the loop
///     body was never analysed;
///   * `if !succeeded { abort(...) }` reported BOTH branches as unreachable,
///     and returned an EMPTY state -- wiping every binding made before it.
///
/// MEASURED (2026-11-20) on `riantr/moonbit_doubleML@0.164.64`: the defect
/// cost two real sinks in `did_aggregation.mbt` (lines 229 and 231), and it
/// made the layer claim both branches of one `if` unreachable in
/// `riantr/moonbit_static_analysis@0.5.0`'s `moonfiles.mbt`.
///
/// These are the assertions that pin the semantics. Each one fails if the
/// literal's encoding moves back to `ABool(b, b)`.
///
/// The file is a whitebox test (`_wbtest.mbt`) because it drives the abstract
/// layer's own entry point, `run_abstract`, and reads the findings it
/// produces.

///|
/// A module built from parsed files.
fn bool_ast(src : String) -> ModuleAst {
  {
    coord: "bool/local",
    version: "0.0.0",
    root: ".",
    files: [parse_file("a.mbt", src)],
    manifest_deps: [],
    manifest_target: "",
  }
}

///|
/// The findings of one kind the abstract layer produced.
fn bool_of_kind(src : String, kind : FindingKind) -> Array[Finding] {
  let out : Array[Finding] = []
  let l2 = run_abstract(bool_ast(src), 100, 100000)
  for f in l2.findings {
    if f.kind == kind {
      out.push(f)
    }
  }
  out
}

///|
/// How many findings of one kind were filed at one line.
fn bool_at_line(src : String, kind : FindingKind, line : Int32) -> Int32 {
  let mut n = 0
  for f in bool_of_kind(src, kind) {
    if f.line == line {
      n = n + 1
    }
  }
  n
}

///|
/// A literal `true` is ALWAYS true, so a loop guarded by it never ends.
///
/// With the literal encoded as `ABool(b, b)` the condition "can be true and
/// can be false", the loop was not provably infinite, and the finding was
/// never filed.
test "bool: a `while true` loop is reported as infinite" {
  let src =
    #|pub fn spin() -> Int32 {
    #|  let mut n = 0
    #|  while true {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
    #|
  assert_eq(bool_of_kind(src, FInfinite).length(), 1)
}

///|
/// A literal `false` is ALWAYS false, so the branch it guards is never taken
/// -- and ONLY that branch.
///
/// With the literal encoded as `ABool(b, b)` the condition "can be neither",
/// and the layer filed the contradiction: it reported the THEN branch AND the
/// ELSE branch as unreachable.
test "bool: a `false` literal makes only the then-branch unreachable" {
  let src =
    #|pub fn dead() -> Int32 {
    #|  if false {
    #|    abort("never")
    #|  }
    #|  0
    #|}
    #|
  let found = bool_of_kind(src, FUnreachable)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "then-branch is unreachable for the abstract input set",
  )
}

///|
/// The MIRROR of the previous assertion: a flag that is false and never
/// changed makes `!flag` always true, so the THEN branch is the one that is
/// taken and the ELSE branch is the unreachable one.
///
/// This is the pair that the defect broke: both branches were reported
/// unreachable at once.
test "bool: a `false` flag makes only the else-branch unreachable" {
  let src =
    #|pub fn guard() -> Int32 {
    #|  let mut succeeded = false
    #|  if !succeeded {
    #|    abort("never")
    #|  }
    #|  0
    #|}
    #|
  let found = bool_of_kind(src, FUnreachable)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "else-branch is unreachable for the abstract input set",
  )
}

///|
/// THE STATE SURVIVES THE GUARD.
///
/// The defect did not only prune the branch: an `if` whose condition "can be
/// neither true nor false" returned an EMPTY state, so every binding made
/// before it was wiped and the code after it was analysed with nothing
/// known. The index finding below is the visible consequence: the array is a
/// local of unknown length and the index is the loop counter, so the access
/// may be out of bounds.
test "bool: the bindings before a guard are still known after it" {
  let src =
    #|pub fn after_guard(limit : Int32) -> Int32 {
    #|  let acc : Array[Int32] = Array::make(limit, 0)
    #|  let mut succeeded = false
    #|  if !succeeded {
    #|    abort("never")
    #|  }
    #|  let mut total = 0
    #|  for i = 0; i < limit; i = i + 1 {
    #|    total = total + acc[i]
    #|  }
    #|  total
    #|}
    #|
  assert_eq(bool_of_kind(src, FIndexOob).length(), 1)
}

///|
/// THE BRANCH A NEGATED FLAG GUARDS IS ANALYSED.
///
/// This is the shape the defect was found in: an `if !found { ... }` whose
/// body grows an array. The array starts EMPTY, a loop reads its length (so
/// the loop is decided impossible and pruned), the array is grown by the
/// guarded branch, and a SECOND loop reads the array's length again to drive
/// an index into a matrix. The sink inside that second loop is the one the
/// layer lost.
test "bool: the branch a negated flag guards is analysed" {
  let src =
    #|pub fn aggregate(
    #|  groups : Array[Int32],
    #|  periods : Array[Int32],
    #|  coef_matrix : Array[Double],
    #|) -> Double {
    #|  let n_groups = groups.length()
    #|  let n_periods = periods.length()
    #|  let mut e_set_acc : Array[Int32] = []
    #|  for i = 0; i < n_groups; i = i + 1 {
    #|    let g_value = groups[i]
    #|    for pi = 0; pi < n_periods; pi = pi + 1 {
    #|      let e = periods[pi] - g_value
    #|      let mut found = false
    #|      for k = 0; k < e_set_acc.length(); k = k + 1 {
    #|        if e_set_acc[k] == e {
    #|          found = true
    #|        }
    #|      }
    #|      if !found {
    #|        e_set_acc = e_set_acc + [e]
    #|      }
    #|    }
    #|  }
    #|  let n_e = e_set_acc.length()
    #|  let mut sum = 0.0
    #|  for ei = 0; ei < n_e; ei = ei + 1 {
    #|    sum = sum + coef_matrix[ei]
    #|  }
    #|  sum
    #|}
    #|
  // The sink is the index into the matrix on line 27 -- the one the defect
  // lost, because the array it reads its length from stayed empty.
  assert_eq(bool_at_line(src, FIndexOob, 27), 1)
}

///|
/// THE LOOP BODY IS ANALYSED.
///
/// A loop whose condition contains a negated boolean could not be true when
/// the boolean was "can be neither", so the body was never analysed and the
/// allocation inside it was never seen. The allocation size here is the
/// parameter, so the claim is a true one -- and it is INSIDE the body, so
/// the assertion fails when the body is pruned.
test "bool: a loop whose condition holds a negated boolean is analysed" {
  let src =
    #|pub fn looped(limit : Int32) -> Array[Int32] {
    #|  let mut out : Array[Int32] = []
    #|  let mut succeeded = false
    #|  let mut attempt = 0
    #|  while attempt < limit && !succeeded {
    #|    attempt = attempt + 1
    #|    out = Array::make(limit, 0)
    #|    succeeded = true
    #|  }
    #|  out
    #|}
    #|
  assert_eq(bool_of_kind(src, FTaintAlloc).length(), 1)
}
