///|
/// THE RECURSION DEPTH BUDGET, FROM THE INSIDE.
///
/// The blackbox file (`recursion_test.mbt`) pins what the analyser SAYS: the
/// claim, its verdict, and the control beside it.  This file pins the
/// machinery the claim is made of, which a caller cannot see:
///
///   * the TRACE carries the moment the chain was cut short -- a `budget`
///     event at the call site, so the trace says where the analysis stopped
///     and not only the report;
///   * the chain is cut at EXACTLY `max_depth`, so the bound is the number
///     the caller asked for and not another one;
///   * the value the cut call would have returned is UNKNOWN, which is the
///     whole reason the claim has to be made: the value is absent, and an
///     absent value is why the findings that depend on it are missing.
///
/// The cut is ONCE per function run: a recursive function reaches the bound
/// once per trial, and a claim repeated per level would bury the one the
/// reader needs.

///|
fn wb_ast(src : String) -> ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn wb_opts(max_depth : Int32) -> RunOptions {
  { trials: 1, max_steps: 500, max_depth, max_functions: 0, entry_filter: "", }
}

///|
/// A SELF-RECURSIVE function that never returns.
fn wb_self_source() -> String {
  (
    #|pub fn countdown(n : Int) -> Int {
    #|  let next = n + 1
    #|  countdown(next)
    #|}
  )
}

///|
test "the recursion: the trace carries the moment the chain was cut short" {
  let run = run_module(wb_ast(wb_self_source()), wb_opts(6))
  let mut budget_events = 0
  for e in run.events {
    if e.kind == EvBudget {
      budget_events = budget_events + 1
      // The event names the call that was not followed, and it is at the
      // call site -- so a reader of the trace can go and look.
      assert_true(e.name == "countdown")
      assert_true(e.detail == "depth budget")
    }
  }
  inspect(budget_events, content="1")
}

///|
test "the recursion: the chain is cut at exactly max_depth" {
  let run = run_module(wb_ast(wb_self_source()), wb_opts(6))
  let mut evidence = ""
  let mut cut_at = -1
  for e in run.events {
    if e.kind == EvBudget && cut_at < 0 {
      cut_at = e.line
    }
  }
  for f in run.findings {
    if f.kind == FBudget {
      evidence = f.evidence
    }
  }
  // The evidence names BOTH numbers, and they are the same number: the bound
  // the caller asked for is the depth the chain was cut at.  The whole
  // fragment is checked, so "depth=60" cannot pass as "depth=6".
  assert_true(evidence.contains("max_depth=6 depth=6 "))
  // The event is at the CALL SITE -- the line of the recursive call.
  inspect(cut_at, content="3")
}

///|
test "the recursion: the chain is followed max_depth levels and then cut" {
  // THE MEASURE OF THE CUT.  The function is entered once per level of the
  // chain, and the chain is followed exactly `max_depth` levels deep: at the
  // next level the budget stops it.  So the number of `enter` events is the
  // bound plus one, and a bound that was ignored would show a deeper chain.
  let run = run_module(wb_ast(wb_self_source()), wb_opts(6))
  let mut enters = 0
  for e in run.events {
    if e.kind == EvEnter {
      enters = enters + 1
    }
  }
  inspect(enters, content="7")
}

///|
test "the recursion: a shallower bound cuts the chain sooner" {
  // The bound is the CALLER'S: at `max_depth` 2 the chain is three levels
  // deep -- entered once, then twice -- and the claim says so.  A bound that
  // was ignored would make the depth in the evidence the toolchain's own
  // number rather than the caller's.
  let run = run_module(wb_ast(wb_self_source()), wb_opts(2))
  let mut enters = 0
  for e in run.events {
    if e.kind == EvEnter {
      enters = enters + 1
    }
  }
  inspect(enters, content="3")
  let mut evidence = ""
  for f in run.findings {
    if f.kind == FBudget {
      evidence = f.evidence
    }
  }
  assert_true(evidence.contains("max_depth=2 depth=2 "))
}

///|
test "the recursion: the claim is made ONCE per function run" {
  // A recursive function reaches the bound once, so the claim is made once.
  // A claim per LEVEL would bury the one the reader needs.
  let run = run_module(wb_ast(wb_self_source()), wb_opts(6))
  let mut claims = 0
  for f in run.findings {
    if f.kind == FBudget {
      claims = claims + 1
    }
  }
  inspect(claims, content="1")
}

///|
test "the recursion: a flat call chain makes no claim and no event" {
  // THE CONTROL, from the inside: a call that returns makes neither the
  // claim nor the event.
  let src =
    #|pub fn helper(n : Int) -> Int {
    #|  n
    #|}
    #|pub fn caller(n : Int) -> Int {
    #|  helper(n)
    #|}
  let run = run_module(wb_ast(src), wb_opts(6))
  let mut claims = 0
  for f in run.findings {
    if f.kind == FBudget {
      claims = claims + 1
    }
  }
  let mut events = 0
  for e in run.events {
    if e.kind == EvBudget {
      events = events + 1
    }
  }
  inspect(claims, content="0")
  inspect(events, content="0")
}
