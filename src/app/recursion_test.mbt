///|
/// THE RECURSION DEPTH BUDGET, AND THE CLAIM IT NOW MAKES.
///
/// The interpreter FOLLOWS calls, so a recursive function sends it down a
/// chain that has no end.  The depth budget is what stops it: at `max_depth`
/// the chain is not followed any further, and the value the call would have
/// returned is unknown.
///
/// BEFORE THIS, THAT TRUNCATION WAS SILENT.  The value was simply ABSENT, and
/// an absent claim is indistinguishable from a decided and clean one -- so a
/// recursive module and a clean one produced the same report, and the findings
/// that depended on the unknown value were missing with no word about why.
/// MEASURED on a recursive module: the claim that the index is out of bounds
/// was made for the plain function and NOT made for the recursive one, and
/// nothing in the report said the analysis had been cut short.
///
/// The analyser now says what it could NOT decide, with the same family and
/// the same UNDECIDED verdict as the step budget above it.  These tests pin
/// that, and they pin the CONTROL beside it: a function that CALLS another
/// function is not a recursion, and the analyser must not claim a depth
/// budget for it.
///
/// THE RECURSIVE SHAPES HERE RECURSE UNCONDITIONALLY.  A recursion guarded by
/// a condition recurses only when the condition is false, and the interpreter
/// SYNTHESISES the inputs -- so a shape that recursed for one input may not
/// recurse for another, and a test that depends on the synthesised value is a
/// test that measures the input synthesis and not the recursion.

///|
fn rec_ast(src : String) -> @app.ModuleAst {
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
/// One trial, and no cap on the number of functions: the claim has to come
/// from the recursion and not from a budget running out somewhere else.
fn rec_opts() -> @app.RunOptions {
  {
    trials: 1,
    max_steps: 500,
    max_depth: 6,
    max_functions: 0,
    entry_filter: "",
  }
}

///|
/// The BUDGET claims the analyser makes about this module.
fn rec_budget(src : String) -> Array[@app.Finding] {
  let run = @app.run_module(rec_ast(src), rec_opts())
  let out : Array[@app.Finding] = []
  for f in run.findings {
    if f.kind == @app.FBudget {
      out.push(f)
    }
  }
  out
}

///|
/// A SELF-RECURSIVE function.  It never returns, so the chain is endless and
/// the depth budget is the only thing that stops it.
fn rec_self_source() -> String {
  (
    #|pub fn countdown(n : Int) -> Int {
    #|  let next = n + 1
    #|  countdown(next)
    #|}
  )
}

///|
/// A MUTUALLY RECURSIVE pair.  Neither function returns on its own.
fn rec_mutual_source() -> String {
  (
    #|pub fn ping(n : Int) -> Int {
    #|  pong(n)
    #|}
    #|
    #|pub fn pong(n : Int) -> Int {
    #|  ping(n)
    #|}
  )
}

///|
/// THE CONTROL: a function that CALLS another function.  The call is
/// followed for one level and then returns.
fn rec_flat_source() -> String {
  (
    #|pub fn helper(n : Int) -> Int {
    #|  n
    #|}
    #|
    #|pub fn caller(n : Int) -> Int {
    #|  helper(n)
    #|}
  )
}

///|
test "a self-recursive function makes the analyser report the depth budget" {
  let claims = rec_budget(rec_self_source())
  inspect(claims.length(), content="1")
}

///|
test "the depth budget claim is UNDECIDED, not a claim about the module" {
  // The claim is "the analyser could not decide", and the VERDICT is what
  // says so.  A claim with a certain verdict would say the module has a
  // defect, and it does not.
  let claims = rec_budget(rec_self_source())
  inspect(claims.length(), content="1")
  // The read is GUARDED: without the fix there is no claim at all, and an
  // unguarded read would abort the whole test binary instead of failing this
  // test -- which would take the other tests' results with it.
  if claims.length() > 0 {
    inspect(claims[0].verdict.code(), content="unknown")
  }
}

///|
test "the depth budget claim names the recursion depth budget" {
  // The family is shared with the step budget, so the MESSAGE has to say
  // WHICH budget ran out: a reader who cannot tell the two apart cannot tell
  // what was not decided.
  let claims = rec_budget(rec_self_source())
  inspect(claims.length(), content="1")
  if claims.length() > 0 {
    assert_true(claims[0].message.contains("recursion depth budget"))
    assert_true(claims[0].evidence.contains("max_depth=6"))
  }
}

///|
test "the depth budget claim names the call that was not followed" {
  // The claim has to point at the CALL SITE, so a reader can go and look at
  // the function whose chain was cut short.
  let claims = rec_budget(rec_self_source())
  inspect(claims.length(), content="1")
  if claims.length() > 0 {
    assert_true(claims[0].evidence.contains("call=countdown"))
    inspect(claims[0].fn_name, content="countdown")
  }
}

///|
test "a function that CALLS another function is not a recursion" {
  // THE CONTROL.  A call is followed for one level and then returns; the
  // depth budget is about a chain that has no end.  An analyser that claimed
  // a depth budget here would be claiming it of every module.
  inspect(rec_budget(rec_flat_source()).length(), content="0")
}

///|
test "a mutually recursive pair makes the analyser report the depth budget" {
  // Two functions that call each other: the chain is infinite, and the budget
  // stops it.  Each function is an entry point of its own, so each one
  // reports where ITS call was not followed.
  let claims = rec_budget(rec_mutual_source())
  inspect(claims.length(), content="2")
}
