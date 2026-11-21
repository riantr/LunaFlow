///|
/// IFDS PHASE 3 -- the SIZE of a `+`-BUILT array.
///
/// Phase 2 separated a container's SIZE taint from its CONTENTS' taint. This
/// phase applies that separation to the one place it was still missing: the
/// CONCATENATION.
///
/// `xs + [user]` holds `xs`'s elements and then `user`'s, so its COUNT is
/// `xs`'s count plus one -- and the count is decided by `xs`, not by `user`.
/// Before the repair the concatenation had no value at all: it was TOP, and
/// `.length()` on a TOP fell back to the receiver's own sources -- the
/// ELEMENTS' taint. So the claim about the size named the element, and when
/// the count was a constant the claim was false outright: `[user] + [user]`
/// holds TWO elements, and the claim said that a tainted value from parameter
/// `user` might control the allocation size.
///
/// The assertions come in pairs on purpose. A repair that made every
/// `+`-built size clean would pass the first half and fail the second: a count
/// the caller really does choose must still be claimed -- and the claim must
/// name the caller and not the element.
///
/// The file is a whitebox test (`_wbtest.mbt`) because the first half drives
/// the abstract layer's own evaluator: the COUNT and the two taints are
/// asserted on the VALUE, not inferred from a claim. The second half goes
/// through `run_abstract` and reads the claims the layer files.
///
/// The measurements these pin are in `docs/qa/IFDS_PHASE3.md`.

// ---------------------------------------------------------------------------
// The layer's own values: the COUNT, the SIZE's taint, the CONTENTS' taint.
// ---------------------------------------------------------------------------

///|
/// A context that records nothing. These assertions are about the VALUE the
/// layer computes; the claims it files are pinned separately, end to end.
fn plus_ctx() -> AbsContext {
  {
    fn_name: "plus",
    file: "demo/plus",
    findings: [],
    ranges: Map([]),
    globals: Map([]),
    steps: 0,
    max_steps: 1000,
  }
}

///|
/// A span for an expression these tests build by hand. The span only has to
/// exist: nothing here reads it.
fn plus_span() -> Span {
  Span::new("demo/plus", 1, 0, 1, 1)
}

///|
/// Evaluate `e` with the given names bound to the value a PARAMETER of that
/// name and type starts with.
fn plus_eval(e : Expr, binds : Array[(String, String)]) -> AbsCell {
  let ctx = plus_ctx()
  let st = AbsState::new()
  for b in binds {
    st.env[b.0] = initial_cell(b.1, b.0)
  }
  let eva = EvaState::new(Map([]))
  abs_eval(ctx, st, eva, e)
}

///|
/// The COUNT the layer computed for a `+`-built array: "lo,hi" -- or "none"
/// when it computed no count at all.
fn plus_count(e : Expr, binds : Array[(String, String)]) -> String {
  let cell = plus_eval(e, binds)
  match cell.v {
    AArr(l, h, _) => l.to_string() + "," + h.to_string()
    _ => "none"
  }
}

///|
/// The SIZE's taint of a `+`-built array: the sources that decide HOW MANY
/// elements there are.
fn plus_size_srcs(e : Expr, binds : Array[(String, String)]) -> String {
  let cell = plus_eval(e, binds)
  match cell.v {
    AArr(_, _, sz) => sz.join(",")
    _ => "none"
  }
}

///|
/// The CONTENTS' taint of a `+`-built array: the sources that decide WHAT is
/// in it.
fn plus_contents_srcs(e : Expr, binds : Array[(String, String)]) -> String {
  plus_eval(e, binds).srcs.join(",")
}

///|
/// `xs + [user]`
fn plus_expr_param() -> Expr {
  Expr::new(
    plus_span(),
    EBin(
      OpAdd,
      Expr::new(plus_span(), EName("xs")),
      Expr::new(plus_span(), EArray([Expr::new(plus_span(), EName("user"))])),
    ),
  )
}

///|
/// `[user] + [user]`
fn plus_expr_literals() -> Expr {
  Expr::new(
    plus_span(),
    EBin(
      OpAdd,
      Expr::new(plus_span(), EArray([Expr::new(plus_span(), EName("user"))])),
      Expr::new(plus_span(), EArray([Expr::new(plus_span(), EName("user"))])),
    ),
  )
}

///|
/// `xs + [user] + ys`
fn plus_expr_two_params() -> Expr {
  Expr::new(
    plus_span(),
    EBin(
      OpAdd,
      Expr::new(
        plus_span(),
        EBin(
          OpAdd,
          Expr::new(plus_span(), EName("xs")),
          Expr::new(
            plus_span(),
            EArray([Expr::new(plus_span(), EName("user"))]),
          ),
        ),
      ),
      Expr::new(plus_span(), EName("ys")),
    ),
  )
}

// ---------------------------------------------------------------------------
// The VALUE half: the count is computed, and the two taints stay apart.
// ---------------------------------------------------------------------------

///|
/// THE COUNT IS THE SUM. `xs` is a caller's array, so its count is somewhere
/// between 0 and 64; the literal adds ONE element. The concatenation holds
/// between 1 and 65 of them -- the SUM, and not the larger of the two.
test "phase3: the count of a `+`-built array is the sum of the two counts" {
  assert_eq(plus_count(plus_expr_param(), [("xs", "Array[String]")]), "1,65")
}

///|
/// The same with TWO caller's arrays: the literal adds one, and `ys` adds its
/// own count.
test "phase3: the count of a `+`-built array of two caller's arrays is the sum of both" {
  assert_eq(
    plus_count(plus_expr_two_params(), [
      ("xs", "Array[String]"),
      ("ys", "Array[String]"),
    ]),
    "1,129",
  )
}

///|
/// Two LITERALS: one element each, so TWO -- and a constant, which is what
/// the `constant_size` guard needs to see to know the claim is false.
test "phase3: the count of a `+`-built array of two literals is a constant" {
  assert_eq(plus_count(plus_expr_literals(), []), "2,2")
}

///|
/// THE TWO TAINTS STAY APART. `xs` decides HOW MANY elements there are; `user`
/// decides only WHAT one of them is. Before the repair the size's taint was
/// the elements' taint, so it named `user` as well -- a source that cannot
/// decide how many elements there are.
test "phase3: the size's taint of a `+`-built array names the COUNT's sources and not the element's" {
  let binds = [("xs", "Array[String]"), ("user", "String")]
  assert_eq(plus_size_srcs(plus_expr_param(), binds), "param:xs")
  assert_eq(plus_contents_srcs(plus_expr_param(), binds), "param:xs,param:user")
}

///|
/// And the two caller's arrays are BOTH named -- the count is their sum, so
/// both decide it -- while the element still is not.
test "phase3: the size's taint of a `+`-built array names every source that decides the COUNT" {
  let binds = [
    ("xs", "Array[String]"),
    ("ys", "Array[String]"),
    ("user", "String"),
  ]
  assert_eq(plus_size_srcs(plus_expr_two_params(), binds), "param:xs,param:ys")
}

///|
/// The count of two literals is fixed by the CODE, so no tainted value decides
/// it and the size's taint is empty.
test "phase3: the size's taint of a `+`-built array of two literals is empty" {
  assert_eq(plus_size_srcs(plus_expr_literals(), []), "")
  assert_eq(
    plus_contents_srcs(plus_expr_literals(), [("user", "String")]),
    "param:user",
  )
}

// ---------------------------------------------------------------------------
// The CLAIM half: end to end, through the findings the layer files.
// ---------------------------------------------------------------------------

///|
/// A module built from parsed files.
fn plus_ast(src : String) -> ModuleAst {
  {
    coord: "phase3/local",
    version: "0.0.0",
    root: ".",
    files: [parse_file("a.mbt", src)],
    manifest_deps: [],
    manifest_target: "",
  }
}

///|
/// The allocation-size findings the abstract layer produced.
fn plus_alloc_findings(src : String) -> Array[Finding] {
  let out : Array[Finding] = []
  let l2 = run_abstract(plus_ast(src), 100, 100000)
  for f in l2.findings {
    if f.kind == FTaintAlloc {
      out.push(f)
    }
  }
  out
}

///|
/// THE SELF-REFUTING CLAIM IS GONE. The count of `[user] + [user]` is TWO --
/// one element each -- and `user` chooses nothing about it. The claim used to
/// say that a tainted value from parameter `user` might control the
/// allocation size, and the layer's own value domain refutes it: the size is
/// a constant.
test "phase3: the count of a `+`-built array of literals is not the element's taint" {
  let src =
    #|pub fn size_of_plus_literals(user : String) -> Array[Int32] {
    #|  let a = [user] + [user]
    #|  Array::make(a.length(), 0)
    #|}
    #|
  assert_eq(plus_alloc_findings(src).length(), 0)
}

///|
/// ... and the same through a binding: the length read into a variable is the
/// same length.
test "phase3: the count of a `+`-built array of literals is not the element's taint through a binding" {
  let src =
    #|pub fn size_of_plus_literal_binding(user : String) -> Array[Int32] {
    #|  let a = [user] + [user]
    #|  let n = a.length()
    #|  Array::make(n, 0)
    #|}
    #|
  assert_eq(plus_alloc_findings(src).length(), 0)
}

///|
/// THE TRUE CLAIM SURVIVES. The count of `xs + [user]` is `xs`'s count plus
/// one, so the caller really does choose how many elements there are -- and
/// the claim must name `xs` and NOT `user`, who is only the element.
test "phase3: a `+`-built array's size claim names the COUNT's sources and not the element's" {
  let src =
    #|pub fn size_of_plus_parameter(xs : Array[String], user : String) -> Array[Int32] {
    #|  let a = xs + [user]
    #|  Array::make(a.length(), 0)
    #|}
    #|
  let found = plus_alloc_findings(src)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameter `xs` may control an allocation size",
  )
}

///|
/// ... and through a binding, and with TWO caller's arrays: both are named,
/// and the element still is not.
test "phase3: a `+`-built array's size claim names every source that decides the COUNT" {
  let src =
    #|pub fn size_of_plus_two_parameters(
    #|  xs : Array[String],
    #|  ys : Array[String],
    #|  user : String,
    #|) -> Array[Int32] {
    #|  let a = xs + [user] + ys
    #|  Array::make(a.length(), 0)
    #|}
    #|
  let found = plus_alloc_findings(src)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameters `xs` and `ys` may control an allocation size",
  )
}

///|
/// THE SUM IS VISIBLE IN THE CLAIM. The evidence carries the size's interval,
/// and [1,65] is `xs`'s count plus the literal's ONE -- the sum, measured.
test "phase3: the claim's evidence carries the sum of the two counts" {
  let src =
    #|pub fn size_of_plus_parameter(xs : Array[String], user : String) -> Array[Int32] {
    #|  let a = xs + [user]
    #|  Array::make(a.length(), 0)
    #|}
    #|
  let found = plus_alloc_findings(src)
  assert_eq(found.length(), 1)
  assert_eq(found[0].evidence, "Array.make([1,65])")
}

///|
/// THE OTHER TRUE CLAIM SURVIVES: a size that is the ELEMENT of a `+`-built
/// array. `a[0]` is `xs`'s first element -- the size is that element's VALUE,
/// and `xs` is untrusted -- so the claim is true and must stay.
test "phase3: a size that is the ELEMENT of a `+`-built array still claims" {
  let src =
    #|pub fn element_of_plus_array(xs : Array[String]) -> Array[Int32] {
    #|  let a = xs + [0]
    #|  let e = a[0]
    #|  Array::make(e, 0)
    #|}
    #|
  let found = plus_alloc_findings(src)
  assert_eq(found.length(), 1)
  assert_eq(
    found[0].message,
    "tainted value from parameter `xs` may control an allocation size",
  )
}
