///|
fn ast_of(files : Array[SourceFile]) -> ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files,
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn count_status(vcs : Array[VC], status : VCStatus) -> Int32 {
  let mut n = 0
  for vc in vcs {
    if vc.status == status {
      n = n + 1
    }
  }
  n
}

///|
test "contract annotations attach to the following function" {
  let src =
    #|//@ requires n >= 0;
    #|//@ requires n < values.length();
    #|//@ ensures \result >= 0;
    #|pub fn get(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let f = parse_file("c.mbt", src)
  inspect(f.funcs.length(), content="1")
  inspect(f.funcs[0].contract.requires.length(), content="2")
  inspect(f.funcs[0].contract.ensures.length(), content="1")
  inspect(f.funcs[0].contract.errors.length(), content="0")
}

///|
test "well-specified index is proved by L3" {
  let src =
    #|//@ requires n >= 0;
    #|//@ requires n < values.length();
    #|//@ ensures \result >= 0;
    #|pub fn get(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let ast = ast_of([parse_file("c.mbt", src)])
  let proof = check_contracts(ast, ["get"])
  inspect(proof.functions_with_contract, content="1")
  assert_true(proof.vcs.length() >= 1)
  assert_true(count_status(proof.vcs, VCProved) >= 1)
  inspect(count_status(proof.vcs, VCFailed), content="0")
}

///|
test "contradictory precondition exposes an out-of-bounds index" {
  let src =
    #|//@ requires n < 0;
    #|pub fn bad(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let ast = ast_of([parse_file("c.mbt", src)])
  let proof = check_contracts(ast, ["bad"])
  assert_true(count_status(proof.vcs, VCFailed) >= 1)
}

///|
test "ensures over a linear expression is proved" {
  let src =
    #|//@ requires n >= 0;
    #|//@ ensures \result >= 0;
    #|pub fn double(n : Int) -> Int {
    #|  n + n
    #|}
  let ast = ast_of([parse_file("c.mbt", src)])
  let proof = check_contracts(ast, ["double"])
  assert_true(count_status(proof.vcs, VCProved) >= 1)
}

///|
test "abstract interpretation reports tainted index and may-range" {
  let src =
    #|pub fn f(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let ast = ast_of([parse_file("a.mbt", src)])
  let abs = run_abstract(ast, 10, 1000)
  inspect(abs.functions, content="1")
  let mut tainted = 0
  for f in abs.findings {
    if f.kind == FTaintIndex {
      tainted = tainted + 1
    }
    inspect(f.mode, content="L2-abstract")
  }
  assert_true(tainted >= 1)
  assert_true(abs.ranges.contains("f::n"))
}

///|
test "funnel deduplicates level 2 against level 1" {
  let src =
    #|pub fn f(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let ast = ast_of([parse_file("a.mbt", src)])
  let abs = run_abstract(ast, 10, 1000)
  let proof = check_contracts(ast, ["f"])
  let fresh = build_funnel([], abs, proof, ["f"])
  inspect(fresh.new_level2.length(), content=fresh.level2.to_string())
  let known = build_funnel(abs.findings, abs, proof, ["f"])
  inspect(known.new_level2.length(), content="0")
  inspect(known.spec_gaps.length(), content="1")
}
