///|
/// The peer review of our OWN source.
///
/// `moonx riantr/moonbit_static_analysis@latest riantr/LunaFlow@latest` pointed
/// the peer analyzer at this module. It reported three actionable defects, and
/// all three were true: an unused parameter and two unused locals, each
/// confirmed by the MoonBit compiler's own `unused_value` warning.
///
/// Running OUR analyzer over OUR source then showed five more false positives,
/// and the MoonBit compiler contradicted every one of them -- the compiler
/// reported unreachable code in the fixture and nowhere else. They had two
/// causes, and both are pinned here.
///
///  - A contract clause was parsed out of its own text, so every expression in
///    it claimed to be on line 1 of the file.
///  - A slice `a[i:j]` was not modelled, so the statement it belonged to was
///    shredded, and the fragments that followed a `return` inherited its
///    deadness.
///  - A `while true` whose body holds a construct the parser does not model
///    was called infinite, because the `break` inside that construct was
///    invisible. The loop may end, so neither the loop nor the code after it
///    is what the analyzer claimed it was.

///|
fn peer_stmts(src : String) -> Array[@app.Stmt] {
  let f = @app.parse_file("t.mbt", src)
  f.funcs[0].body
}

///|
fn peer_findings(src : String) -> Array[@app.Finding] {
  let f = @app.parse_file("t.mbt", src)
  @app.cfg_findings(@app.build_cfg(f.funcs[0]))
}

///|
fn peer_count(src : String, kind : @app.FindingKind) -> Int32 {
  let mut n = 0
  for x in peer_findings(src) {
    if x.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn peer_dead(src : String) -> Int32 {
  peer_count(src, @app.FDead)
}

///|
fn peer_infinite(src : String) -> Int32 {
  peer_count(src, @app.FInfinite)
}

///|
fn peer_unreachable(src : String) -> Int32 {
  peer_count(src, @app.FUnreachable)
}

///|
test "a contract clause carries the line it was written on" {
  let e = @app.parse_spec_expr("x > 0", "f.mbt", 42)
  match e {
    Some(expr) => inspect(expr.span.start_line, content="42")
    None => fail("expected an expression")
  }
}

///|
test "each clause of a contract carries its own line" {
  let src =
    #|//@ requires n >= 0;
    #|//@ requires n < 10;
    #|fn f(n : Int) -> Int {
    #|  n
    #|}
  let c = @app.contract_above(src, "f.mbt", 3)
  inspect(c.requires.length(), content="2")
  // The two clauses are on lines 1 and 2, not on the line of the function.
  inspect(c.requires[0].span.start_line, content="1")
  inspect(c.requires[1].span.start_line, content="2")
}

///|
test "a slice is one expression" {
  let stmts = peer_stmts(
    (
      #|fn f(t : String) -> String {
      #|  return t[i + 1:j].to_string()
      #|}
    ),
  )
  // The `return` and nothing else: the slice belongs to the expression.
  inspect(stmts.length(), content="1")
  match stmts[0].kind {
    SReturn(Some(e)) =>
      match e.kind {
        EMethod(recv, _, _) =>
          match recv.kind {
            ESlice(_, _, _) => inspect(1, content="1")
            _ => fail("expected a slice")
          }
        _ => fail("expected a method call")
      }
    _ => fail("expected a return")
  }
}

///|
test "a slice leaves no dead fragments behind" {
  // The shape that produced three false dead-code rows: the fragments of the
  // shredded slice followed a `return`, so they inherited its deadness.
  let src =
    #|fn f(t : String) -> String {
    #|  return t[i + 1:j].to_string()
    #|}
  inspect(peer_dead(src), content="0")
}

///|
test "an if expression is still one statement" {
  let stmts = peer_stmts(
    (
      #|fn f(x : Int) -> Int {
      #|  let y = if x > 0 { 1 } else { 2 }
      #|  y
      #|}
    ),
  )
  inspect(stmts.length(), content="2")
}

///|
test "a loop with an unmodelled body is not proven infinite" {
  let src =
    #|fn f(items : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  while true {
    #|    match items.length() {
    #|      0 => break
    #|      _ => {
    #|        total = total + 1
    #|        break
    #|      }
    #|    }
    #|  }
    #|  total
    #|}
  // The `break` is inside a `match` arm, and the parser does not model `match`
  // arms. The loop may end, so the code after it is reachable and the loop is
  // not proven infinite.
  inspect(peer_dead(src), content="0")
  inspect(peer_infinite(src), content="0")
  inspect(peer_unreachable(src), content="0")
}

///|
test "a fully modelled infinite loop is still reported" {
  let src =
    #|fn f() -> Int {
    #|  let mut n = 0
    #|  while true {
    #|    n = n + 1
    #|  }
    #|  n
    #|}
  // Nothing here is unmodelled, so the loop really never ends and the code
  // after it really is dead. Refusing to guess must not cost the real finding.
  inspect(peer_dead(src), content="1")
  inspect(peer_infinite(src), content="1")
}
