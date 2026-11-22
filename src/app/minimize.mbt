///|
/// THE COUNTEREXAMPLE: one finding, and the smallest input that reproduces it.
///
/// The word "smallest" here is a claim with a boundary, and the boundary is
/// this file: the input is minimal over the ANALYSER'S OWN CANDIDATE SET --
/// the values `value.mbt` synthesizes for a parameter's type, in the order
/// that file lists them. It is NOT a globally minimal program, and it is not
/// a minimal SOURCE either: it is the smallest input, in the analyser's own
/// order, that still reproduces the finding.
///
/// "In the analyser's own order" is a precise thing: the candidates of a
/// parameter form a list, and the lists of the parameters form a PRODUCT,
/// and the analyser walks that product with the LAST parameter varying
/// fastest. The counterexample is the FIRST input in that walk that
/// reproduces the finding, so every input before it was tried and did not.
///
/// The walk is the analyser's own (`synthesize`), so the order cannot drift
/// from the order the analyser itself uses.  The walk here is LONGER than
/// the analyser's: the analyser samples a bounded number of trials, and a
/// finding raised in a CALLEE can need an input past that bound.  Finding it
/// is the part of this that is worth the re-runs.
///
/// The entry is the function the finding sits in, entered on its own.  The
/// finding is raised there, so entering that function with a tainted argument
/// is what raises it again, and the reproduction is checked by the finding's
/// SITE -- its family, its file, its line and its function -- and not by its
/// message or its evidence, because the evidence carries the observed value
/// and the observed value is exactly what the smaller input changes.
pub(all) struct Counterexample {
  /// The function that was entered to reproduce the finding.
  entry : String
  /// The finding's family.
  kind : FindingKind
  /// Where the finding sits.
  file : String
  line : Int32
  /// The function the finding was raised in.
  fn_name : String
  /// The entry function's parameters, in order.
  params : Array[String]
  /// The entry function's parameter types, in order.
  types : Array[String]
  /// The analyser's own candidate list for each parameter, rendered. It is
  /// what "smaller" means here, so it travels with the counterexample: a
  /// reader can see the whole set the input was chosen from.
  candidates : Array[Array[String]]
  /// The minimal input: one rendered value per parameter.
  args : Array[String]
  /// The candidate index each argument took, in the analyser's own order.
  indices : Array[Int32]
  /// How many inputs were tried before this one reproduced the finding.  It
  /// is the position of this input in the analyser's own candidate order,
  /// plus one: every input before it was tried and did not reproduce.
  tried : Int32
}

///|
/// What the minimisation did, and what it could not do.
pub(all) struct MinimizeResult {
  counterexamples : Array[Counterexample]
  /// The findings the report shows that an EXECUTION produced: the ones a
  /// counterexample could exist for.
  requested : Int32
  /// The findings that are not claims about an input -- the CFG families
  /// (a claim about the program's shape) and the L2 families (a may-claim
  /// over the whole input set). They have no input to minimise.
  not_input : Int32
  /// The findings that got a counterexample.
  minimised : Int32
  /// The findings no single input reproduced.
  without : Int32
  /// The findings that were not attempted, because the limit was reached.
  skipped : Int32
  /// The inputs the minimisation tried, in total.
  tried : Int32
  /// Whether the run budget stopped the minimisation.
  truncated : Bool
}

///|
/// The method that means "an execution produced this". The interpreter's
/// findings carry it; the CFG pass ("static") and the abstract layers
/// ("L2-abstract", "L2-EVA") do not, and a claim that is not about an input
/// has no input to minimise.
fn is_dynamic(f : Finding) -> Bool {
  f.mode.has_prefix("dynamic")
}

///|
/// The identity of a finding ACROSS RUNS: its family, its place and the
/// function it was raised in. NOT the message and NOT the evidence -- the
/// evidence carries the observed value, and the observed value changes with
/// the input, so a counterexample would never match the finding it came from.
///
/// The comparison itself is `same_site`, the one the funnel already uses to
/// decide that two findings are the SAME finding.
fn site_key(f : Finding) -> String {
  f.kind.code() + "|" + f.file + "|" + f.line.to_string() + "|" + f.fn_name
}

///|
fn value_eq(a : Value, b : Value) -> Bool {
  match (a, b) {
    (VInt(x), VInt(y)) => x == y
    (VDouble(x), VDouble(y)) => x == y
    (VBool(x), VBool(y)) => x == y
    (VStr(x), VStr(y)) => x == y
    (VChar(x), VChar(y)) => x == y
    (VUnit, VUnit) => true
    (VUnknown, VUnknown) => true
    (VForeign(x), VForeign(y)) => x == y
    (VArr(x), VArr(y)) => value_arr_eq(x, y)
    (VTuple(x), VTuple(y)) => value_arr_eq(x, y)
    _ => false
  }
}

///|
fn value_arr_eq(a : Array[Value], b : Array[Value]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if !value_eq(a[i], b[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The index of a value in the candidate list, or -1 when it is not one of
/// them. The index is what "smaller" means here: the candidate list has an
/// order, and the minimisation walks it.
fn candidate_index(v : Value, cands : Array[Value]) -> Int32 {
  let mut i = 0
  while i < cands.length() {
    if value_eq(cands[i], v) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// THE MINIMISER: the functions it may run, the budget it may spend, and the
/// runs it has spent.
struct Minimizer {
  funcs : Map[String, Func]
  opts : RunOptions
  globals : Map[String, Val]
  ffi : Map[String, FfiDecl]
  mut runs : Int32
  budget : Int32
  /// How many inputs ONE finding may spend. The budget is shared out, so
  /// that one finding whose reproduction is far away cannot spend it all
  /// and leave the others with nothing.
  per_finding : Int32
}

///|
/// Does this input reproduce the finding ON ITS OWN? One function, one input,
/// one execution -- and the finding has to come back at the same site.
///
/// When the budget is spent the answer is NO, and the caller says so: a
/// budget that ran out is not a reproduction that failed.
fn Minimizer::reproduces(
  self : Minimizer,
  g : Func,
  input : InputSet,
  target : Finding,
) -> Bool {
  if self.runs >= self.budget {
    return false
  }
  let r = run_function(
    g,
    self.funcs,
    self.opts,
    0,
    global_values=self.globals,
    ffi=self.ffi,
    inputs=[input],
  )
  self.runs = self.runs + 1
  for f in r.findings {
    if same_site(f, target) {
      return true
    }
  }
  false
}

///|
/// One counterexample, or None when no input in the analyser's candidate
/// order reproduced the finding.
///
/// The walk is the analyser's own: `synthesize` produces the candidate
/// product in the analyser's order, with the last parameter varying fastest.
/// The counterexample is the first of those inputs that reproduces the
/// finding, so every input before it was tried and did not.
fn Minimizer::minimize_for(
  self : Minimizer,
  target : Finding,
) -> Counterexample? {
  let g = match self.funcs.get(target.fn_name) {
    Some(f) => f
    None => return None
  }
  // The walk.  It is the analyser's own enumeration -- `synthesize` produces
  // the candidate product in the analyser's order, with the last parameter
  // varying fastest -- capped by this finding's share of the budget.
  let before = self.runs
  let trials = synthesize(g, self.per_finding)
  let mut found : InputSet? = None
  let mut tried = 0
  let mut i = 0
  while i < trials.length() {
    if self.runs >= self.budget {
      break
    }
    if self.reproduces(g, trials[i], target) {
      found = Some(trials[i])
      tried = self.runs - before
      break
    }
    i = i + 1
  }
  match found {
    None => None
    Some(best) => {
      let params : Array[String] = []
      let types : Array[String] = []
      let candidates : Array[Array[String]] = []
      let args : Array[String] = []
      let indices : Array[Int32] = []
      let mut p = 0
      while p < g.params.length() && p < best.args.length() {
        let cands = candidates_for(g.params[p].ty)
        let rendered : Array[String] = []
        for c in cands {
          rendered.push(c.repr())
        }
        params.push(g.params[p].name)
        types.push(g.params[p].ty)
        candidates.push(rendered)
        args.push(best.args[p].v.repr())
        indices.push(candidate_index(best.args[p].v, cands))
        p = p + 1
      }
      Some({
        entry: g.name,
        kind: target.kind,
        file: target.file,
        line: target.line,
        fn_name: target.fn_name,
        params,
        types,
        candidates,
        args,
        indices,
        tried,
      })
    }
  }
}

///|
/// THE COUNTEREXAMPLE MINIMISATION.
///
/// For every finding an execution produced, the smallest input -- over the
/// analyser's own candidate set -- that reproduces it on its own.
///
/// `targets` are the findings the report shows. They are the right targets
/// because a counterexample is only useful for a claim the reader can see.
///
/// `max_findings` bounds how many findings are minimised and `max_runs`
/// bounds how many inputs the minimisation may try. Both bounds are
/// reported, because a bound that is reached is a fact about the result and
/// not a detail of the implementation.
pub fn minimize_counterexamples(
  ast : ModuleAst,
  opts : RunOptions,
  targets : Array[Finding],
  max_findings : Int32,
  max_runs : Int32,
) -> MinimizeResult {
  let funcs : Map[String, Func] = Map([])
  for f in ast.all_funcs_including_tests() {
    if !funcs.contains(f.name) {
      funcs[f.name] = f
    }
  }
  let (globals, _) = eval_globals(funcs, opts, ast)
  // The targets: the report's own findings, deduped by site and in the order
  // the report shows them. A finding an execution did not produce is not a
  // claim about an input, and it is counted apart.
  let wanted : Array[Finding] = []
  let seen : Array[String] = []
  let seen_static : Array[String] = []
  let mut not_input = 0
  for t in targets {
    let key = site_key(t)
    if !is_dynamic(t) {
      if !seen_static.contains(key) {
        seen_static.push(key)
        not_input = not_input + 1
      }
      continue
    }
    if !seen.contains(key) {
      seen.push(key)
      wanted.push(t)
    }
  }
  let mz = {
    funcs,
    opts,
    globals,
    ffi: ffi_map(ast),
    runs: 0,
    budget: max_runs,
    per_finding: if wanted.length() == 0 {
      1
    } else {
      let share = max_runs / wanted.length()
      if share < 1 {
        1
      } else {
        share
      }
    },
  }
  let counterexamples : Array[Counterexample] = []
  let mut without = 0
  let mut skipped = 0
  let mut i = 0
  while i < wanted.length() {
    if counterexamples.length() >= max_findings {
      skipped = wanted.length() - i
      break
    }
    let t = wanted[i]
    i = i + 1
    match mz.minimize_for(t) {
      Some(cx) => counterexamples.push(cx)
      None => without = without + 1
    }
  }
  {
    counterexamples,
    requested: wanted.length(),
    not_input,
    minimised: counterexamples.length(),
    without,
    skipped,
    tried: mz.runs,
    truncated: mz.runs >= mz.budget,
  }
}

///|
/// The input, rendered for a reader: one `name = value` per parameter.
pub fn Counterexample::input_text(self : Counterexample) -> String {
  if self.params.length() == 0 {
    return "_no arguments_"
  }
  let parts : Array[String] = []
  let mut i = 0
  while i < self.params.length() && i < self.args.length() {
    parts.push("`" + self.params[i] + " = " + self.args[i] + "`")
    i = i + 1
  }
  parts.join(", ")
}
