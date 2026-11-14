///|
/// The cross-check against `riantr/moonbit_static_analysis@0.4.45` reported 136
/// findings on that module. Every one of them was a false positive, and all of
/// them had the same shape: the parser shredded a construct it does not model
/// into one statement per fragment, and the fragments that followed a `return`
/// inherited its deadness.
///
/// The repairs are in two layers, and these tests pin both.
///
///  - The construct is MODELLED: a qualified path, a qualified record literal,
///    a destructuring `for`, a named argument.
///  - The construct is NOT modelled, and the parser then says so: an
///    unmodelled operator is folded into the statement it belongs to and
///    counted as unsupported, instead of becoming statements of its own.
///
/// The second layer is the one that generalises. Without it the next
/// construct the parser does not know would shred itself into statements
/// again, and the dead-code verdict would come back with it.

///|
fn stmts_of(src : String) -> Array[@app.Stmt] {
  let f = @app.parse_file("t.mbt", src)
  f.funcs[0].body
}

///|
fn dead_in(src : String) -> Int32 {
  let f = @app.parse_file("t.mbt", src)
  let findings = @app.cfg_findings(@app.build_cfg(f.funcs[0]))
  let mut dead = 0
  for x in findings {
    if x.kind == @app.FDead {
      dead = dead + 1
    }
  }
  dead
}

///|
test "a qualified path is one statement" {
  let stmts = stmts_of(
    (
      #|fn f(y : Array[Double]) -> Double {
      #|  return CART::Leaf(y.length())
      #|}
    ),
  )
  // The `return` and nothing else: `CART::Leaf(...)` is one expression.
  inspect(stmts.length(), content="1")
}

///|
test "a qualified record literal is one statement" {
  let stmts = stmts_of(
    (
      #|fn f() -> Int {
      #|  let x = Rec::{ value: 1 }
      #|  x.value
      #|}
    ),
  )
  inspect(stmts.length(), content="2")
}

///|
test "a plain record literal is one statement" {
  let stmts = stmts_of(
    (
      #|fn f() -> Int {
      #|  let x = Rec { value: 1 }
      #|  x.value
      #|}
    ),
  )
  inspect(stmts.length(), content="2")
}

///|
test "a string that spells a brace is not a brace" {
  // The scrutinee holds the string "{". Counting it as an opening brace
  // moved the end of the match, and the block ran on past the end of the
  // function -- taking the function after it with it.
  let src =
    #|fn first(x : String) -> Int {
    #|  match rsplit_at(x, "{") {
    #|    Some((head, _)) => head.length()
    #|    None => 0
    #|  }
    #|}
    #|
    #|fn second() -> Int {
    #|  2
    #|}
  let f = @app.parse_file("t.mbt", src)
  // Two functions, and the second one is whole.
  inspect(f.funcs.length(), content="2")
  inspect(f.funcs[1].body.length(), content="1")
}

///|
test "a character literal that spells a brace is not a brace" {
  let src =
    #|fn first(x : String) -> Int {
    #|  strip_outer(x, '{', '}')
    #|}
    #|
    #|fn second() -> Int {
    #|  2
    #|}
  let f = @app.parse_file("t.mbt", src)
  inspect(f.funcs.length(), content="2")
}

///|
test "a destructuring for binds every name and keeps its body" {
  let src =
    #|fn f(xs : Array[(Int, String)]) -> Int {
    #|  let mut n = 0
    #|  for i, line in xs {
    #|    n = n + i
    #|  }
    #|  n
    #|}
  let f = @app.parse_file("t.mbt", src)
  let mut names : Array[String] = []
  let mut found = false
  for s in f.funcs[0].body {
    match s.kind {
      SForIn(binders, _, body) => {
        found = true
        names = binders
        // The body belongs to the loop: it is not a block of its own.
        inspect(body.length(), content="1")
      }
      _ => ()
    }
  }
  assert_true(found)
  inspect(names.length(), content="2")
  inspect(names[0], content="i")
  inspect(names[1], content="line")
}

///|
test "a named argument keeps the call whole" {
  let stmts = stmts_of(
    (
      #|fn f() -> Int {
      #|  let x = g(name = 1)
      #|  x
      #|}
    ),
  )
  inspect(stmts.length(), content="2")
}

///|
test "an unmodelled operator is folded into its statement" {
  // `|>`, `as` and `..` have no rule in the parser. The right-hand side used
  // to be left behind, and each fragment became a statement of its own.
  let pipe = stmts_of(
    (
      #|fn f(v : Int) -> Int {
      #|  let x = v |> g
      #|  x
      #|}
    ),
  )
  inspect(pipe.length(), content="2")
  let cast = stmts_of(
    (
      #|fn f(v : Int) -> Int {
      #|  let x = v as Int
      #|  x
      #|}
    ),
  )
  inspect(cast.length(), content="2")
  let range = stmts_of(
    (
      #|fn f() -> Int {
      #|  let x = 0..10
      #|  x
      #|}
    ),
  )
  inspect(range.length(), content="2")
}

///|
test "an if without an else does not make the code after it dead" {
  // The condition may be false, so the code after the `if` is reached. This
  // is the shape that produced the false dead-code rows.
  let dead = dead_in(
    (
      #|fn f(x : Int) -> Int {
      #|  if x > 0 {
      #|    return 1
      #|  }
      #|  let y = x + 1
      #|  y
      #|}
    ),
  )
  inspect(dead, content="0")
}

///|
test "an if whose else branch falls through does not make the code after it dead" {
  // The `else` ends in a `return`, but the `then` branch falls through
  // through an inner `if` that has no `else` of its own.
  let dead = dead_in(
    (
      #|fn f(x : Int) -> Int {
      #|  if x > 0 {
      #|    if x > 1 {
      #|      return 1
      #|    }
      #|  } else {
      #|    return 2
      #|  }
      #|  let y = x + 1
      #|  y
      #|}
    ),
  )
  inspect(dead, content="0")
}

///|
test "an if whose two branches both exit does make the code after it dead" {
  // The other half of the rule: when both branches leave, the code after the
  // `if` is unreachable, and saying otherwise would lose a real finding.
  let dead = dead_in(
    (
      #|fn f(x : Int) -> Int {
      #|  if x > 0 {
      #|    return 1
      #|  } else {
      #|    return 2
      #|  }
      #|  let y = x + 1
      #|  y
      #|}
    ),
  )
  inspect(dead, content="2")
}

///|
test "a return inside a match arm is not dead code" {
  let dead = dead_in(
    (
      #|fn f(x : Int) -> Int {
      #|  match x {
      #|    Some(d) => {
      #|      return d
      #|    }
      #|    None => 0
      #|  }
      #|  0
      #|}
    ),
  )
  inspect(dead, content="0")
}

///|
/// The report's own REPRODUCTION command has to be runnable.
///
/// The defect: the coordinate a run was asked for may already carry a version
/// marker -- `riantr/LunaFlow@latest` -- and the report appended `@latest` to
/// it unconditionally. The printed command was therefore
/// `riantr/LunaFlow@latest@latest`, which the registry refuses with "must
/// contain a single version marker". It was found by running the PUBLISHED
/// 0.1.13 over the published coordinate and then running the command the
/// report printed: a report that prints a command which does not work is
/// worse than one that prints none.
fn report_for(coord : String) -> String {
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [
      @app.parse_file("c.mbt", "pub fn f(x : Int) -> Int {\n  x + 1\n}\n"),
    ],
    manifest_deps: [],
    manifest_target: "native",
  }
  let opts : @app.RunOptions = @app.RunOptions::default()
  let run = @app.run_module(ast, opts)
  let input : @app.ReportInput = {
    coord,
    version: "0.1.13",
    pinning: "none",
    root: ".",
    target: "native",
    deps: [],
    files: 1,
    funcs: 1,
    stmts: 1,
    unsupported: 0,
    issues: 0,
    cfgs: [],
    cfg_findings: [],
    run,
    taint: @app.TaintGraph::new(),
    slices: [],
    coverage: None,
    opts: @app.ReportOptions::default(),
    elapsed_ms: 0,
    level: 1,
    funnel: None,
    abstract: None,
    proof: None,
  }
  @app.render_report(input)
}

///|
test "a coordinate with a version marker loses exactly that marker" {
  inspect(
    @app.coord_without_version("riantr/LunaFlow@latest"),
    content="riantr/LunaFlow",
  )
  inspect(
    @app.coord_without_version("riantr/LunaFlow@0.1.13"),
    content="riantr/LunaFlow",
  )
  inspect(
    @app.coord_without_version("riantr/LunaFlow"),
    content="riantr/LunaFlow",
  )
  inspect(@app.coord_without_version(""), content="")
}

///|
test "the reproduction command is a coordinate that resolves" {
  // The coordinate the reader was asked for, carrying a version marker.
  let md = report_for("riantr/LunaFlow@latest")
  inspect(
    md.contains(
      "LunaFlow analyze riantr/LunaFlow@latest --out reports/ --funnel",
    ),
    content="true",
  )
  // The doubled marker is the defect: a coordinate may carry only ONE.
  inspect(md.contains("@latest@latest"), content="false")
  // The title is a coordinate too, and it used to carry two markers.
  inspect(
    md.contains("# LunaFlow analysis report — riantr/LunaFlow@0.1.13"),
    content="true",
  )
}

///|
test "a coordinate without a version marker still gets one" {
  let md = report_for("riantr/LunaFlow")
  inspect(
    md.contains(
      "LunaFlow analyze riantr/LunaFlow@latest --out reports/ --funnel",
    ),
    content="true",
  )
  inspect(md.contains("@latest@latest"), content="false")
  inspect(
    md.contains("# LunaFlow analysis report — riantr/LunaFlow@0.1.13"),
    content="true",
  )
}
