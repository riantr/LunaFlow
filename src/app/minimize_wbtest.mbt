///|
/// THE COUNTEREXAMPLE MINIMISATION: what it claims, and what pins it.
///
/// The claim is narrow on purpose: for each finding an execution produced,
/// the smallest input -- over the analyser's OWN candidate set -- that
/// reproduces it on its own. "Smallest" is an order, and the order is the
/// order the analyser itself walks: the candidate product, with the LAST
/// parameter varying fastest.
///
/// A test that only checked "the minimiser returned something" would pin
/// nothing. These tests pin the two things that make the claim true:
///   - the returned input DOES reproduce the finding, and
///   - every input BEFORE it in the analyser's own order does NOT.
///
/// The second half is the half that matters, and it is only meaningful when
/// there IS something before it: an input that is the first of its product
/// has nothing to refute, and the refutation would be vacuous. The module
/// below GUARDS the index, so the first input -- an empty array at -1 -- does
/// not reach the read, and the minimiser has to move to the second. The pin
/// then has something to say.
fn mod_of(text : String) -> ModuleAst {
  {
    coord: "t",
    version: "0.0.0",
    root: ".",
    files: [parse_file("t.mbt", text)],
    manifest_deps: [],
    manifest_target: "t",
  }
}

///|
/// The module the tests use: an array read at an index the caller controls,
/// behind a guard that rejects a negative index. The index is TAINTED (every
/// synthesized argument is), so the read is an index finding, and an empty
/// array makes it an out-of-bounds one too.
const LOOKUP_SRC = "pub fn lookup(values : Array[Int32], index : Int32) -> Int32 {\n  if index < 0 {\n    return 0\n  }\n  values[index]\n}\n"

///|
/// Run one function on one input and say whether the finding came back.
fn reproduces_at(
  ast : ModuleAst,
  fn_name : String,
  args : Array[Value],
  kind : FindingKind,
  line : Int32,
) -> Bool {
  let funcs : Map[String, Func] = Map([])
  for f in ast.all_funcs_including_tests() {
    if !funcs.contains(f.name) {
      funcs[f.name] = f
    }
  }
  let g = match funcs.get(fn_name) {
    Some(f) => f
    None => return false
  }
  let vals : Array[Val] = []
  for v in args {
    vals.push(tainted_value(v))
  }
  let r = run_function(g, funcs, RunOptions::default(), 0, inputs=[
    { args: vals, },
  ])
  for f in r.findings {
    if f.kind == kind && f.file == "t.mbt" && f.line == line {
      return true
    }
  }
  false
}

///|
/// The function the counterexample was produced by.
fn entry_of(ast : ModuleAst, name : String) -> Func? {
  for f in ast.all_funcs_including_tests() {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
/// The value the counterexample chose for a parameter, taken back from the
/// candidate list by its INDEX -- so the test reads the analyser's own list
/// and never has to parse a rendered value.
fn chosen_value(g : Func, cx : Counterexample, p : Int32) -> Value {
  let cands = candidates_for(g.params[p].ty)
  cands[cx.indices[p]]
}

///|
/// The inputs BEFORE the counterexample's, in the analyser's own order. The
/// enumeration is the analyser's own (`synthesize`), so the test cannot
/// disagree with the analyser about what "before" means.
fn inputs_before(g : Func, cx : Counterexample) -> Array[Array[Value]] {
  let out : Array[Array[Value]] = []
  let trials = synthesize(g, cx.tried)
  let mut i = 0
  while i < trials.length() && i < cx.tried - 1 {
    let args : Array[Value] = []
    for a in trials[i].args {
      args.push(a.v)
    }
    out.push(args)
    i = i + 1
  }
  out
}

///|
test "the minimiser returns an input that reproduces the finding" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  // The run itself found the index findings: the index is untrusted.
  let mut saw_index = false
  for f in run.findings {
    if f.kind == FTaintIndex {
      saw_index = true
    }
  }
  inspect(saw_index, content="true")
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  // Three sites at the one read: the tainted index, the out-of-bounds read,
  // and the in-range tainted index.
  inspect(res.minimised, content="3")
  inspect(res.without, content="0")
  inspect(res.not_input, content="0")
  let cx = res.counterexamples[0]
  inspect(cx.entry, content="lookup")
  inspect(cx.fn_name, content="lookup")
  inspect(cx.file, content="t.mbt")
  inspect(cx.args.length(), content="2")
  // And the input it returns DOES reproduce the finding.
  let g = match entry_of(ast, cx.entry) {
    Some(f) => f
    None => return
  }
  inspect(
    reproduces_at(
      ast,
      cx.entry,
      [chosen_value(g, cx, 0), chosen_value(g, cx, 1)],
      cx.kind,
      cx.line,
    ),
    content="true",
  )
}

///|
test "the minimiser picks the smallest input that still reproduces" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  let cx = res.counterexamples[0]
  // The empty array is the FIRST candidate for an array parameter, and 0 is
  // the SECOND candidate for an Int -- 0 and not -1, because -1 is guarded
  // and so does not reach the read at all.
  inspect(cx.indices[0], content="0")
  inspect(cx.indices[1], content="1")
  inspect(cx.args[0], content="[]")
  inspect(cx.args[1], content="0")
  // The candidate index is the index in the ANALYSER'S OWN list: the check
  // reads the same list the minimisation walked, so the two cannot disagree
  // about what "the second candidate" is.
  let cands = candidates_for("Int32")
  inspect(cands[0].repr(), content="-1")
  inspect(cands[1].repr(), content="0")
}

///|
test "no input before it in the analyser's own order reproduces the finding" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  let cx = res.counterexamples[0]
  let g = match entry_of(ast, cx.entry) {
    Some(f) => f
    None => return
  }
  // The pin is only meaningful when there IS something before it: the first
  // input of the product has nothing to refute.
  inspect(cx.tried > 1, content="true")
  let earlier = inputs_before(g, cx)
  inspect(earlier.length(), content="1")
  // Every input BEFORE the counterexample's fails to reproduce the finding.
  // This is the minimality claim, checked against the analyser and not
  // against the minimiser's own bookkeeping.
  for args in earlier {
    inspect(
      reproduces_at(ast, cx.entry, args, cx.kind, cx.line),
      content="false",
    )
  }
}

///|
test "a finding no execution produced is not a target" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  // A STATIC finding: a claim about the program's shape, not about an input.
  let static_finding = Finding::new(
    FDead,
    "t.mbt",
    4,
    "lookup",
    "unreachable",
    "static",
    0.5,
    "evidence",
  )
  let res = minimize_counterexamples(ast, opts, [static_finding], 10, 500)
  inspect(res.requested, content="0")
  inspect(res.not_input, content="1")
  inspect(res.minimised, content="0")
  inspect(res.counterexamples.length(), content="0")
}

///|
test "a finding no single input reproduces is counted, not hidden" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  // A finding in a function the module does not have: nothing can reproduce
  // it, and the result says so instead of returning nothing at all.
  let ghost = Finding::new(
    FTaintIndex,
    "t.mbt",
    99,
    "no_such_function",
    "tainted value reaches an array index",
    "dynamic+symbolic",
    0.8,
    "evidence",
  )
  let res = minimize_counterexamples(ast, opts, [ghost], 10, 500)
  inspect(res.requested, content="1")
  inspect(res.minimised, content="0")
  inspect(res.without, content="1")
}

///|
test "the minimisation is bounded, and says when the bound stopped it" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  // A budget of ONE input: the first one cannot even be tried, so nothing is
  // minimised and the result says the budget stopped it.
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 1)
  inspect(res.truncated, content="true")
  inspect(res.tried, content="1")
  inspect(res.minimised, content="0")
  // And the findings that were not reached are counted, not dropped.
  inspect(res.without, content="3")
}

///|
test "the limit bounds how many findings are minimised" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let res = minimize_counterexamples(ast, opts, run.findings, 1, 500)
  inspect(res.minimised, content="1")
  inspect(res.skipped, content="2")
  inspect(res.requested, content="3")
}

///|
test "the same module gives the same counterexample twice" {
  let ast = mod_of(LOOKUP_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let a = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  let b = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  inspect(
    a.counterexamples.length() == b.counterexamples.length(),
    content="true",
  )
  inspect(a.tried == b.tried, content="true")
  inspect(
    a.counterexamples[0].input_text() == b.counterexamples[0].input_text(),
    content="true",
  )
}

///|
/// The module that WRITES INTO the array it was given, and then reads it
/// back.  MoonBit's arrays are mutable and aliased, so the write reaches the
/// caller's array -- and the caller's array is the analyser's own candidate.
const MUTATE_SRC = "pub fn write_then_read(dst : Array[Int32], index : Int32) -> Int32 {\n  dst[0] = index\n  dst[index]\n}\n"

///|
/// A function that writes into the array it was given must not change what
/// the counterexample says the INPUT was.
///
/// This is the case the minimisation used to get wrong, and it was the GATE
/// that found it: the candidate index came back as -1, because the array the
/// walk chose had been written into by the time the counterexample was
/// recorded, so the value no longer matched any candidate.  The counterexample
/// then carried an argument the analyser never chose.
test "a function that writes into its array does not change the recorded input" {
  let ast = mod_of(MUTATE_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  inspect(res.minimised > 0, content="true")
  for cx in res.counterexamples {
    let g = match entry_of(ast, cx.entry) {
      Some(f) => f
      None => return
    }
    // Every parameter's argument IS the candidate its index points at -- the
    // candidate list is the analyser's own, so this cannot disagree with it.
    for p in 0..<cx.params.length() {
      let cands = candidates_for(g.params[p].ty)
      let idx = cx.indices[p]
      inspect(idx >= 0, content="true")
      inspect(idx < cands.length(), content="true")
      inspect(cx.args[p], content=cands[idx].repr())
    }
  }
}

///|
/// And the input the counterexample names is the one that REPRODUCES: it is
/// the candidate at the recorded index, so it is the input the walk used.
test "the recorded input is the candidate the walk used, and it reproduces" {
  let ast = mod_of(MUTATE_SRC)
  let opts = RunOptions::default()
  let run = run_module(ast, opts)
  let res = minimize_counterexamples(ast, opts, run.findings, 10, 500)
  let cx = res.counterexamples[0]
  let g = match entry_of(ast, cx.entry) {
    Some(f) => f
    None => return
  }
  let args : Array[Value] = []
  for p in 0..<cx.params.length() {
    let cands = candidates_for(g.params[p].ty)
    args.push(cands[cx.indices[p]])
  }
  inspect(reproduces_at(ast, cx.entry, args, cx.kind, cx.line), content="true")
}
