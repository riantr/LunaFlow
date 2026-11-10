///|
/// Contract-engine (L3) edge cases: the clause parser must accept the documented
/// ACSL-like surface, must *record* malformed input instead of guessing, and the
/// prover's third state (`unknown`) must stay reachable for havocked goals.

///|
fn contract_of(raw : Array[String]) -> @app.Contract {
  @app.parse_contract(raw, "c.mbt", 1)
}

///|
test "assigns accepts the nothing form and named targets" {
  let nothing = contract_of(["assigns \\nothing"])
  inspect(nothing.assigns.length(), content="0")
  inspect(nothing.errors.length(), content="0")
  let names = contract_of(["assigns a, b, c"])
  inspect(names.assigns.length(), content="3")
  inspect(names.assigns[0], content="a")
  inspect(names.errors.length(), content="0")
}

///|
test "unknown clause and empty clause body are recorded, not guessed" {
  let c = contract_of(["frobnicate x > 0; requires ; ensures ;"])
  inspect(c.requires.length(), content="0")
  inspect(c.ensures.length(), content="0")
  assert_true(c.errors.length() >= 2)
  // an unsupported clause must not silently become a precondition
  assert_true(c.has_spec() == false)
}

///|
test "multiple clauses on one line are split" {
  let c = contract_of([
    "requires n >= 0; requires n < 10; ensures \\result >= 0;",
  ])
  inspect(c.requires.length(), content="2")
  inspect(c.ensures.length(), content="1")
  inspect(c.errors.length(), content="0")
}

///|
test "invariant acts as an assumption for index bounds" {
  let src =
    #|//@ invariant n >= 0;
    #|//@ invariant n < values.length();
    #|pub fn get(values : Array[Int], n : Int) -> Int {
    #|  values[n]
    #|}
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
  let proof = @app.check_contracts(ast, ["get"])
  let mut proved = 0
  for vc in proof.vcs {
    if vc.status == @app.VCProved {
      proved = proved + 1
    }
  }
  assert_true(proved >= 1)
}

///|
test "postcondition over a loop-havocked variable stays unknown" {
  let src =
    #|//@ ensures \result >= 0;
    #|pub fn f(n : Int) -> Int {
    #|  let mut t = n
    #|  while t > 100 {
    #|    t = t - 1
    #|  }
    #|  t
    #|}
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
  let proof = @app.check_contracts(ast, ["f"])
  let (proved, failed, unknown) = @app.proof_counts(proof.vcs)
  // a havocked goal is not silently proved and not reported as a failure
  inspect(proved, content="0")
  inspect(failed, content="0")
  assert_true(unknown >= 1)
  inspect(proved + failed + unknown, content=proof.vcs.length().to_string())
}

///|
test "functions carrying a contract are enumerated" {
  let src =
    #|//@ requires n >= 0;
    #|pub fn a(n : Int) -> Int {
    #|  n
    #|}
    #|
    #|pub fn b(n : Int) -> Int {
    #|  n
    #|}
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
  let names = @app.funcs_with_contracts(ast)
  inspect(names.length(), content="1")
  inspect(names[0], content="a")
}
