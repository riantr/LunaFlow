///|
/// The cross-check against `riantr/moonbit_static_analysis@0.4.45` reported 37
/// dead-code findings on that module. Every one of them was a false positive,
/// and all of them had the same cause: the parser shredded a construct it does
/// not model into one statement per fragment, and the fragments that followed
/// a `return` inherited its deadness. These rows pin the three shapes, so the
/// next construct that is not modelled cannot shred itself into statements
/// again.
///
/// The cross-check's own module is the evidence: it is 185 files of real code
/// that another analyzer reads every day, and it found nothing in LunaFlow.

///|
test "a struct literal is one statement, not one statement per field" {
  let src =
    #|fn f(x : Int) -> Int {
    #|  return {
    #|    a: x,
    #|    b: 2,
    #|  }
    #|}
  let f = @app.parse_file("t.mbt", src)
  // The return, and nothing else: the fields belong to the literal.
  inspect(f.funcs[0].body.length(), content="1")
}

///|
test "a binary expression continues on the line after the operator" {
  let src =
    #|fn f(a : Int, b : Int) -> Int {
    #|  if b == 0 {
    #|    return 1 +
    #|      a +
    #|      2
    #|  }
    #|  0
    #|}
  let f = @app.parse_file("t.mbt", src)
  match f.funcs[0].body[0].kind {
    SIf(_, then_body, _) => inspect(then_body.length(), content="1")
    _ => fail("expected an if")
  }
}

///|
test "a match expression keeps its arms" {
  let src =
    #|fn f(x : Int) -> Int {
    #|  return g(match x {
    #|    Some(d) => d
    #|    None => 0
    #|  })
    #|}
  let f = @app.parse_file("t.mbt", src)
  // The scrutinee and the arms belong to the match, so the return is the only
  // statement of the body.
  inspect(f.funcs[0].body.length(), content="1")
}

///|
test "the cross-check's dead-code shape reports nothing" {
  let src =
    #|fn f(x : Int) -> Int {
    #|  if x > 0 {
    #|    return { span: x, kind: 1, }
    #|  }
    #|  let y = x + 1
    #|  { span: y, kind: 2, }
    #|}
  let f = @app.parse_file("t.mbt", src)
  let findings = @app.cfg_findings(@app.build_cfg(f.funcs[0]))
  let mut dead = 0
  for x in findings {
    if x.kind == @app.FDead {
      dead = dead + 1
    }
  }
  // The `if` has no `else`, so what follows it is reached whenever the
  // condition is false.
  inspect(dead, content="0")
}

///|
test "a multi-line return is not dead code" {
  let src =
    #|fn f(a : Int, b : Int) -> String {
    #|  if b == 0 {
    #|    return "not an upper bound at " +
    #|      a.to_string() +
    #|      " and " +
    #|      b.to_string()
    #|  }
    #|  ""
    #|}
  let f = @app.parse_file("t.mbt", src)
  let findings = @app.cfg_findings(@app.build_cfg(f.funcs[0]))
  let mut dead = 0
  for x in findings {
    if x.kind == @app.FDead {
      dead = dead + 1
    }
  }
  inspect(dead, content="0")
}

///|
test "one taint site is one sink, however many times it is observed" {
  let first = @app.Finding::new(
    @app.FTaintIndex,
    "a.mbt",
    10,
    "f",
    "tainted value reaches an array index / buffer offset",
    "dynamic+symbolic",
    0.8,
    "buf[0]",
  )
  let second = @app.Finding::new(
    @app.FTaintIndex,
    "a.mbt",
    10,
    "f",
    "tainted value reaches an array index / buffer offset",
    "dynamic+symbolic",
    0.8,
    "buf[1]",
  )
  let other = @app.Finding::new(
    @app.FTaintIndex,
    "a.mbt",
    20,
    "g",
    "tainted value reaches an array index / buffer offset",
    "dynamic+symbolic",
    0.8,
    "buf[2]",
  )
  let g = @app.build_taint([], [first, second, other])
  // The same read observed in two trials is ONE site. Before this, the
  // comparison was over the whole finding, the observed value made every
  // trial its own finding, and one read became dozens of rows.
  inspect(g.sinks.length(), content="2")
}

///|
test "the witnessed risk outranks the in-range note at the same site" {
  let note = @app.Finding::new(
    @app.FTaintIndexRange,
    "a.mbt",
    10,
    "f",
    "untrusted input determines an array index",
    "dynamic+symbolic",
    0.5,
    "buf[0] of length 4",
  )
  let risk = @app.Finding::new(
    @app.FTaintIndex,
    "a.mbt",
    10,
    "f",
    "tainted value reaches an array index / buffer offset",
    "dynamic+symbolic",
    0.8,
    "buf[9] of length 4",
  )
  let g = @app.build_taint([], [note, risk])
  inspect(g.sinks.length(), content="1")
  assert_true(g.sinks[0].kind == @app.FTaintIndex)
}

///|
test "the two taint verdicts are told apart" {
  inspect(@app.FTaintIndex.code(), content="TAINT-INDEX")
  inspect(@app.FTaintIndex.severity(), content="error")
  inspect(@app.FTaintIndexRange.code(), content="TAINT-INDEX-RANGE")
  inspect(@app.FTaintIndexRange.severity(), content="warning")
}

///|
test "the CFG coverage line says what was not looked at" {
  // A module with more functions than the window leaves the rest with no CFG,
  // and a file's findings then depend on how many functions precede it. The
  // report has to say so, or "no findings" reads as "clean".
  let line = @app.cfg_coverage(600, 900)
  assert_true(line.contains("600"))
  assert_true(line.contains("900"))
  assert_true(line.contains("no CFG"))
  let whole = @app.cfg_coverage(900, 900)
  assert_true(whole.contains("every function"))
}
