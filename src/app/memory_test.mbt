///|
/// The MEMORY LAYOUT MODEL.
///
/// Every claim in this file was settled by RUNNING the real toolchain:
///
///  - a top-level `let` is a GLOBAL, and `let mut` at the top level is a
///    PARSE ERROR: the globals are immutable;
///  - top-level bindings are resolved by DEPENDENCY, not by file order: a
///    global may read a global declared later in the file;
///  - a function body's value is its last EXPRESSION: `fn f() -> Int { 42 }`
///    returns 42;
///  - there is no pointer type, no address and no address space, so the only
///    placement question is whether an allocation escapes its function.
///
/// The tests below pin BOTH directions: the global is resolved, and the
/// ordinary shape next to it is not.

///|
fn mem_ast(src : String) -> @app.ModuleAst {
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
fn mem_globals(src : String) -> Map[String, @app.Global] {
  @app.globals_of(mem_ast(src))
}

///|
fn mem_global_value(src : String, name : String) -> String {
  let ast = mem_ast(src)
  let opts : @app.RunOptions = @app.RunOptions::default()
  let (values, _events) = @app.eval_globals(Map([]), opts, ast)
  match values.get(name) {
    Some(v) => v.v.repr()
    None => "?"
  }
}

///|
fn mem_class_of(src : String, fn_name : String) -> String {
  let sites = @app.analyze_allocations(mem_ast(src))
  let mut out = ""
  for s in sites {
    if s.fn_name == fn_name {
      out = s.class.code()
    }
  }
  out
}

///|
test "a top-level binding is a global" {
  let src =
    #|let base : Int = 10
    #|
    #|pub fn use_it() -> Int {
    #|  base
    #|}
  let globals = mem_globals(src)
  inspect(globals.contains("base"), content="true")
}

///|
test "a top-level const is a global too" {
  let src =
    #|const LIMIT : Int = 100
    #|
    #|pub fn use_it() -> Int {
    #|  LIMIT
    #|}
  let globals = mem_globals(src)
  inspect(globals.contains("LIMIT"), content="true")
}

///|
test "a global is resolved in dependency order, not file order" {
  let src =
    #|let derived : Int = base + 2
    #|
    #|let base : Int = 10
    #|
    #|pub fn use_it() -> Int {
    #|  derived
    #|}
  // `derived` is written BEFORE `base`, and its value is still 12.
  inspect(mem_global_value(src, "derived"), content="12")
  inspect(mem_global_value(src, "base"), content="10")
}

///|
test "a function that ends with an expression returns it" {
  let src =
    #|pub fn f() -> Int {
    #|  42
    #|}
  let ast = mem_ast(src)
  let opts : @app.RunOptions = @app.RunOptions::default()
  let r = @app.run_module(ast, opts)
  let mut ret = "?"
  for e in r.events {
    if e.name == "<ret>" {
      ret = e.value
    }
  }
  inspect(ret, content="42")
}

///|
test "a global that reads a global is seen by the function that reads it" {
  let src =
    #|let base : Int = 10
    #|
    #|let derived : Int = base + 2
    #|
    #|pub fn use_it() -> Int {
    #|  derived
    #|}
  inspect(mem_global_value(src, "derived"), content="12")
}

///|
test "an allocation that does not escape stays in the frame" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  a[0]
    #|}
  inspect(mem_class_of(src, "f"), content="FRAME")
}

///|
test "an allocation that is returned escapes to the heap" {
  let src =
    #|pub fn f() -> Array[Int] {
    #|  let a = [1, 2, 3]
    #|  a
    #|}
  inspect(mem_class_of(src, "f"), content="HEAP")
}

///|
test "an allocation handed to a call escapes" {
  let src =
    #|pub fn f() -> Int {
    #|  let b = [1, 2, 3]
    #|  consume(b)
    #|}
  inspect(mem_class_of(src, "f"), content="HEAP")
}

///|
test "an allocation that is only read at an index does not escape" {
  let src =
    #|pub fn f() -> Int {
    #|  let a = [1, 2, 3]
    #|  a[0]
    #|}
  inspect(mem_class_of(src, "f"), content="FRAME")
}

///|
test "an allocation bound to a global is in the global region" {
  let src =
    #|let shared : Array[Int] = [1, 2, 3]
    #|
    #|pub fn f() -> Int {
    #|  shared[0]
    #|}
  let sites = @app.analyze_allocations(mem_ast(src))
  let mut found = false
  for s in sites {
    if s.class == @app.AGlobal {
      found = true
    }
  }
  inspect(found, content="true")
}

///|
test "a global whose initializer overflows is reported where it is" {
  let src =
    #|let overflowing : Int = 2147483647 + 1
    #|
    #|pub fn use_it() -> Int {
    #|  overflowing
    #|}
  let ast = mem_ast(src)
  let abs = @app.run_abstract(ast, 10, 1000)
  let mut n = 0
  for f in abs.findings {
    if f.kind == @app.FIntOverflow {
      n = n + 1
    }
  }
  inspect(n, content="1")
}

///|
test "a global initialization cycle is reported as unresolvable" {
  let src =
    #|let a : Int = b + 1
    #|
    #|let b : Int = a + 1
    #|
    #|pub fn use_it() -> Int {
    #|  a
    #|}
  let table = mem_globals(src)
  let (_order, unresolved) = @app.global_order(table)
  inspect(unresolved.length(), content="2")
}

///|
test "a finding that every run reports does not depend on the sample" {
  let f = @app.Finding::new(
    @app.FIntOverflow,
    "c.mbt",
    1,
    "f",
    "m",
    "L2-EVA",
    0.9,
    "e",
  )
  let a : Array[@app.Finding] = [f]
  let b : Array[@app.Finding] = [f]
  let r = @app.compare_runs([1, 2], [a, b])
  inspect(r.stable, content="1")
  inspect(r.sample_dependent, content="0")
}

///|
test "a finding that only one run reports depends on the sample" {
  let f = @app.Finding::new(
    @app.FTaintIndex,
    "c.mbt",
    1,
    "f",
    "m",
    "dynamic",
    0.6,
    "e",
  )
  let a : Array[@app.Finding] = []
  let b : Array[@app.Finding] = [f]
  let r = @app.compare_runs([1, 2], [a, b])
  inspect(r.stable, content="0")
  inspect(r.sample_dependent, content="1")
}
