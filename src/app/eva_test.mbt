///|
/// The EVOLVED VALUE ANALYSIS.
///
/// Every claim in this file was settled by RUNNING the real toolchain, not by
/// reading it:
///
///  - `Int::MAX_VALUE + 1` is `-2147483648`: MoonBit's integer arithmetic
///    WRAPS and does not trap, so an overflow is a silent wrong value.
///  - `100 / 0` is `RuntimeError: divide by zero`, and `100 % 0` is
///    `RuntimeError: remainder by zero`.
///  - `a[5]` on a three-element array is `RuntimeError: unreachable` at
///    `Array::at`, and so is `a[-1]`.
///  - `None.unwrap()` is `RuntimeError: unreachable` at `Option::unwrap`.
///  - a read of an `UninitializedArray` element before it is written returns
///    an INDETERMINATE value and does NOT panic.
///  - `Double::to_int` SATURATES: 3000000000.0 becomes 2147483647.
///
/// The tests below pin BOTH directions: the defect is reported, and the
/// ordinary shape next to it is not.

///|
fn eva_ast(src : String) -> @app.ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn eva_count(src : String, kind : @app.FindingKind) -> Int32 {
  let ast = eva_ast(src)
  let abs = @app.run_abstract(ast, 10, 1000)
  let mut n = 0
  for f in abs.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn eva_all(src : String) -> Array[@app.Finding] {
  let ast = eva_ast(src)
  let abs = @app.run_abstract(ast, 10, 1000)
  abs.findings
}

///|
test "an integer overflow is reported, because MoonBit wraps it silently" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = 2147483647
    #|  a + 1
    #|}
  inspect(eva_count(src, @app.FIntOverflow), content="1")
}

///|
test "an arithmetic that stays inside the type is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = 100
    #|  let b = 200
    #|  a + b
    #|}
  inspect(eva_count(src, @app.FIntOverflow), content="0")
}

///|
test "a division by a zero divisor is reported" {
  let src =
    #|pub fn f(n : Int) -> Int {
    #|  100 / n
    #|}
  inspect(eva_count(src, @app.FDivZero), content="1")
}

///|
test "a division by a divisor that is not zero is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let d = 10
    #|  100 / d
    #|}
  inspect(eva_count(src, @app.FDivZero), content="0")
}

///|
test "an index past the end of the array is reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  a[5]
    #|}
  inspect(eva_count(src, @app.FIndexOob), content="1")
}

///|
test "an index inside the array is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  a[0]
    #|}
  inspect(eva_count(src, @app.FIndexOob), content="0")
}

///|
test "an out-of-bounds index is filed as an evolved value finding" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  a[5]
    #|}
  let findings = eva_all(src)
  let mut eva = 0
  let mut classic = 0
  for f in findings {
    if f.kind == @app.FIndexOob {
      if f.mode == "L2-EVA" {
        eva = eva + 1
      } else {
        classic = classic + 1
      }
    }
  }
  // The class is in the roster as an EVOLVED value family, so the report has
  // to list it with the other evolved findings and not among the classic ones.
  inspect(eva, content="1")
  inspect(classic, content="0")
}

///|
test "unwrapping a None is reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let x : Option[Int] = None
    #|  x.unwrap()
    #|}
  inspect(eva_count(src, @app.FNoneDeref), content="1")
}

///|
test "the shorthand Option spelling is recognised too" {
  // `Int32?` and `Option[Int32]` are the SAME type, and `moon fmt` rewrites
  // one into the other. A check that only knows the first spelling silently
  // stops working the moment the file is formatted.
  let src =
    #|pub fn f() -> Int32 {
    #|  let x : Int32? = None
    #|  x.unwrap()
    #|}
  inspect(eva_count(src, @app.FNoneDeref), content="1")
}

///|
test "unwrapping a Some is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let x = Some(1)
    #|  x.unwrap()
    #|}
  inspect(eva_count(src, @app.FNoneDeref), content="0")
}

///|
test "the mutable Option assigned on every branch is not a None dereference" {
  // The facts are FLOW-SENSITIVE, so this is the shape that a monotone
  // accumulation would get wrong: `None` goes in, and `Some` comes out on
  // both branches.
  let src =
    #|pub fn f(flag : Bool) -> Int {
    #|  let mut x : Option[Int] = None
    #|  if flag {
    #|    x = Some(1)
    #|  } else {
    #|    x = Some(2)
    #|  }
    #|  x.unwrap()
    #|}
  inspect(eva_count(src, @app.FNoneDeref), content="0")
}

///|
test "a read of an uninitialized element is reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = UninitializedArray::make(3)
    #|  a[0]
    #|}
  inspect(eva_count(src, @app.FUninitRead), content="1")
}

///|
test "a read of an element that was written is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = UninitializedArray::make(3)
    #|  a.set(0, 7)
    #|  a[0]
    #|}
  inspect(eva_count(src, @app.FUninitRead), content="0")
}

///|
test "a conversion that saturates is reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let d = 3000000000.0
    #|  d.to_int()
    #|}
  inspect(eva_count(src, @app.FInvalidCast), content="1")
}

///|
test "a conversion that fits is not reported" {
  let src =
    #|pub fn f() -> Int {
    #|  let d = 3.5
    #|  d.to_int()
    #|}
  inspect(eva_count(src, @app.FInvalidCast), content="0")
}

///|
test "the EVA findings carry their own mode" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = 2147483647
    #|  a + 1
    #|}
  let findings = eva_all(src)
  let mut eva = 0
  for f in findings {
    if f.mode == "L2-EVA" {
      eva = eva + 1
    }
  }
  assert_true(eva >= 1)
}

///|
test "the RESERVED families are in the roster and are never produced" {
  // The defect classes MoonBit's type system makes impossible are in the
  // roster so that `--explain` can answer for them, and their contracts say
  // why they never fire.
  let reserved = [
    @app.FUseAfterFree,
    @app.FPointerArithmetic,
    @app.FMemoryLeak,
    @app.FFormatString,
  ]
  for k in reserved {
    let mut in_roster = false
    for r in @app.family_roster() {
      if r == k {
        in_roster = true
      }
    }
    assert_true(in_roster)
    assert_true(@app.family_property(k).length() > 0)
    assert_true(@app.family_assumption(k).contains("NOT APPLICABLE"))
  }
  // And they are never produced by an analysis.
  let src =
    #|pub fn f() -> Int {
    #|  let a = 2147483647
    #|  a + 1
    #|}
  let findings = eva_all(src)
  for f in findings {
    assert_true(f.kind != @app.FUseAfterFree)
    assert_true(f.kind != @app.FPointerArithmetic)
    assert_true(f.kind != @app.FMemoryLeak)
    assert_true(f.kind != @app.FFormatString)
  }
}

///|
test "every family in the roster has a contract and a code" {
  let roster = @app.family_roster()
  inspect(roster.length(), content="20")
  for k in roster {
    assert_true(k.code().length() > 0)
    assert_true(@app.family_title(k).length() > 0)
    assert_true(@app.family_property(k).length() > 0)
    assert_true(@app.family_assumption(k).length() > 0)
    assert_true(@app.family_excluded(k).length() > 0)
  }
}

///|
test "the family profile selects the EVA families by their code" {
  let findings = @app.filter_findings(
    [
      @app.Finding::new(
        @app.FIntOverflow,
        "c.mbt",
        1,
        "f",
        "m",
        "L2-EVA",
        0.9,
        "e",
      ),
      @app.Finding::new(@app.FDivZero, "c.mbt", 2, "f", "m", "L2-EVA", 0.9, "e"),
    ],
    ["INTEGER-OVERFLOW"],
    [],
  )
  inspect(findings.length(), content="1")
  assert_true(findings[0].kind == @app.FIntOverflow)
}
