///|
/// The RANGE LOOP MODEL.
///
/// A range is `a..<b` or `a..<=b`, and it is not a value: the toolchain says
/// "Range operators are currently only supported in `for .. in` loops". Every
/// claim in this file was settled by RUNNING the real toolchain:
///
///  - `0..<3` yields 0, 1, 2 and `0..<=3` yields 0, 1, 2, 3, so `..<` has an
///    EXCLUSIVE end and `..<=` an INCLUSIVE one;
///  - a bare `a..b` is a parse error ("Missing `=` after `..`"), so there is
///    no two-character range to read;
///  - the bound is evaluated ONCE, before the loop: `for i in 0..<next(0)`
///    yields one value, not one per call.
///
/// The bug this file pins is the one the analyzer's own source ran into: `..<`
/// was not read as ONE operator, so the lexer produced `..` and `<`, the loop
/// had no range to read, the iterator degraded to the `0` in front of it, and
/// -- when the bound was a CALL -- the loop's body was left behind and its
/// statements became statements of the ENCLOSING function.
///
/// The tests below pin BOTH directions: the range is read and the body is
/// kept, and the ordinary shapes next to it are not reported.

///|
fn range_ast(src : String) -> @app.ModuleAst {
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
fn range_findings(src : String) -> Array[@app.Finding] {
  let ast = range_ast(src)
  let abs = @app.run_abstract(ast, 10, 1000)
  abs.findings
}

///|
fn range_count(src : String, kind : @app.FindingKind) -> Int32 {
  let mut n = 0
  for f in range_findings(src) {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
/// The value a function returns, read from the interpreter's trace.
fn range_return(src : String) -> String {
  let ast = range_ast(src)
  let opts : @app.RunOptions = @app.RunOptions::default()
  let r = @app.run_module(ast, opts)
  let mut ret = "?"
  for e in r.events {
    if e.name == "<ret>" {
      ret = e.value
    }
  }
  ret
}

///|
test "a range loop keeps its bound and its body" {
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  for k in 0..<xs.length() {
    #|    total = total + k
    #|  }
    #|  total
    #|}
  let f = @app.parse_file("t.mbt", src)
  let body = f.funcs[0].body
  // The loop is the second statement, and the statement after it is still
  // the last statement of the function: the body did not leak out of it.
  inspect(body.length(), content="3")
  match body[1].kind {
    SForIn(names, iter, loop_body) => {
      inspect(names.length(), content="1")
      inspect(names[0], content="k")
      match iter.kind {
        ERange(start, end, inclusive) => {
          inspect(start.render(), content="0")
          inspect(end.render(), content="xs.length()")
          inspect(inclusive, content="false")
        }
        _ => fail("expected a range")
      }
      // The body is the loop's own, and it is not empty.
      inspect(loop_body.length(), content="1")
    }
    _ => fail("expected for-in")
  }
}

///|
test "a range with an inclusive end says so" {
  let src =
    #|pub fn f() -> Int {
    #|  let mut n = 0
    #|  for k in 0..<=3 {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
  let f = @app.parse_file("t.mbt", src)
  match f.funcs[0].body[1].kind {
    SForIn(_, iter, _) =>
      match iter.kind {
        ERange(_, _, inclusive) => inspect(inclusive, content="true")
        _ => fail("expected a range")
      }
    _ => fail("expected for-in")
  }
}

///|
test "a range loop runs its body once per value in the range" {
  let src =
    #|pub fn f() -> Int {
    #|  let mut n = 0
    #|  for k in 0..<3 {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
  inspect(range_return(src), content="3")
}

///|
test "an inclusive range runs one more time" {
  let src =
    #|pub fn f() -> Int {
    #|  let mut n = 0
    #|  for k in 0..<=3 {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
  inspect(range_return(src), content="4")
}

///|
test "a range that starts above its end runs no times" {
  let src =
    #|pub fn f() -> Int {
    #|  let mut n = 0
    #|  for k in 3..<1 {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
  inspect(range_return(src), content="0")
}

///|
test "a defect inside a range loop's body is reported" {
  // The body used to be lost with the range, so a defect inside it was
  // never seen.
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  for k in 0..<3 {
    #|    a[5]
    #|  }
    #|  0
    #|}
  inspect(range_count(src, @app.FIndexOob), content="1")
}

///|
test "the code after a guard that always returns is not a defect" {
  // `idx` is -1, so the guard's condition is always true and the code
  // after it is unreachable -- the CFG reports that code as unreachable.
  // The abstract layer must not report a defect inside it as well.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut idx = -1
    #|  if idx < 0 {
    #|    return 0
    #|  }
    #|  xs[idx]
    #|}
  inspect(range_count(src, @app.FIndexOob), content="0")
}

///|
test "a length comparison narrows the array it compares" {
  // `obj_idx.length() != 1` says the array holds one element, so the index
  // that follows is in bounds. The array is empty here, so the guard
  // returns -- and the code after it is unreachable.
  let src =
    #|pub fn f() -> Int {
    #|  let obj_idx : Array[Int32] = []
    #|  if obj_idx.length() != 1 {
    #|    return 0
    #|  }
    #|  obj_idx[0]
    #|}
  inspect(range_count(src, @app.FIndexOob), content="0")
}

///|
test "an index into an array that may be empty is still reported" {
  // The shape next to the one above: the same array, without the guard.
  // This one is a REAL defect, and it has to keep being reported.
  let src =
    #|pub fn f() -> Int {
    #|  let obj_idx : Array[Int32] = []
    #|  obj_idx[0]
    #|}
  inspect(range_count(src, @app.FIndexOob), content="1")
}

///|
test "an index that is the array's own length less one is in bounds" {
  // `xs[xs.length() - 1]` is the last element. The two intervals -- the
  // index's and the length's -- are independent, so the comparison of them
  // cannot see it; the relation is read from the expression instead.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  if xs.length() == 0 {
    #|    return 0
    #|  }
    #|  xs[xs.length() - 1]
    #|}
  inspect(range_count(src, @app.FIndexOob), content="0")
}

///|
test "the same index into an array that may be empty is reported" {
  // Without the guard the array may be empty, and then the index is -1.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  xs[xs.length() - 1]
    #|}
  inspect(range_count(src, @app.FIndexOob), content="1")
}

///|
test "a comparison with an interval that overlaps is not always false" {
  // `x == 0` with `x` in `[0, 64]` can be true and can be false. It used
  // to read as neither, so the condition was BOTTOM and both branches were
  // reported as unreachable -- and the code after them was analysed as
  // dead.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  if xs.length() == 0 {
    #|    return 1
    #|  }
    #|  2
    #|}
  let mut dead_branches = 0
  for f in range_findings(src) {
    if f.kind == @app.FUnreachable {
      dead_branches = dead_branches + 1
    }
  }
  inspect(dead_branches, content="0")
}
