///|
/// THE VERDICT: a claim that could not be decided, said so.
///
/// Before this, a finding was a CLAIM or it was nothing.  A claim the
/// analyser could not decide simply did not exist, and a report that does
/// not mention a claim reads exactly like a report about a module with no
/// claims to make.  The verdict is the difference between "there is nothing
/// here" and "we could not tell".
///
/// The three things that have to hold together, and each of them is checked
/// here:
///
///   1. the VOCABULARY    a finding carries a verdict, and the two verdicts
///                         are distinguishable;
///   2. the POLICY        an undecided claim's severity comes from the
///                         POLICY, and an undecided SAFETY claim is an
///                         error -- "we could not decide" is not "it is
///                         fine";
///   3. the REPORTING     the findings table shows the verdict, and the
///                         report says how many claims could not be decided.

///|
fn verdict_ast(src : String) -> ModuleAst {
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
fn undecided_of(fs : Array[Finding]) -> Array[Finding] {
  let out : Array[Finding] = []
  for f in fs {
    if f.verdict == VerdictUnknown {
      out.push(f)
    }
  }
  out
}

///|
test "the verdict: the two verdicts are different verdicts" {
  let certain = Finding::new(
    FRangeViolation,
    "t.mbt",
    1,
    "f",
    "m",
    "static",
    0.5,
    "e",
  )
  let unknown = Finding::undecided(
    FRangeViolation,
    "t.mbt",
    1,
    "f",
    "m",
    "static",
    0.5,
    "e",
  )
  inspect(certain.verdict == VerdictCertain, content="true")
  inspect(unknown.verdict == VerdictUnknown, content="true")
  inspect(certain.verdict == unknown.verdict, content="false")
  inspect(certain.verdict.code(), content="certain")
  inspect(unknown.verdict.code(), content="unknown")
}

///|
test "the verdict: the budget finding is a claim the analyser could not decide" {
  // A budget of three steps: the analyser gives up almost at once, and what
  // it gives up on is a claim it could NOT DECIDE -- not a defect in the
  // module.  Before the verdict existed, this finding and a clean function
  // looked the same to a reader.
  let src =
    #|pub fn wide(user : String) -> Int32 {
    #|  let a = user.length()
    #|  let b = a + 1
    #|  let c = b + 1
    #|  let d = c + 1
    #|  d
    #|}
  let abs = run_abstract(verdict_ast(src), 10, 3)
  let budget = undecided_of(abs.findings)
  let families : Array[String] = []
  for f in budget {
    families.push(f.kind.code())
  }
  inspect(families.contains("BUDGET-EXCEEDED"), content="true")
}

///|
test "the verdict: a claim the analyser DID decide is a certain claim" {
  let src =
    #|pub fn make_window(n : Int32) -> Array[Int32] {
    #|  Array::make(n, 0)
    #|}
  let abs = run_abstract(verdict_ast(src), 10, 1000)
  let mut tainted = 0
  let mut decided = 0
  for f in abs.findings {
    if f.kind == FTaintAlloc {
      tainted = tainted + 1
      if f.verdict == VerdictCertain {
        decided = decided + 1
      }
    }
  }
  inspect(tainted, content="1")
  inspect(decided, content="1")
}

///|
test "the verdict: the policy decides what an undecided claim means" {
  // FAIL-CLOSED.  An undecided SAFETY claim is an error, because the
  // module's safety is then not established.  An undecided claim of any
  // other family is a warning: worth knowing, and not by itself a safety
  // claim.  And an undecided claim is never merely informational.
  inspect(undecided_severity(FTaintAlloc), content="error")
  inspect(undecided_severity(FIndexOob), content="error")
  inspect(undecided_severity(FBudget), content="warning")
  inspect(undecided_severity(FParseGap), content="warning")
}

///|
test "the verdict: a finding's severity is the policy's, when the claim was not decided" {
  let decided = Finding::new(FBudget, "t.mbt", 1, "f", "m", "static", 0.5, "e")
  let undecided = Finding::undecided(
    FBudget,
    "t.mbt",
    1,
    "f",
    "m",
    "static",
    0.5,
    "e",
  )
  // The family's own severity when the claim was decided...
  inspect(decided.severity(), content="warning")
  // ... and the POLICY's when it was not.
  inspect(undecided.severity(), content="warning")
  // The two differ in their VERDICT even where the severity agrees: the
  // severity is what a reader acts on, the verdict is what they know.
  inspect(decided.verdict == undecided.verdict, content="false")
  let safety = Finding::undecided(
    FTaintAlloc,
    "t.mbt",
    1,
    "f",
    "m",
    "static",
    0.5,
    "e",
  )
  inspect(safety.severity(), content="error")
}

///|
test "the verdict: the findings table shows the verdict of every claim" {
  let fs = [
    Finding::new(
      FRangeViolation,
      "t.mbt",
      1,
      "f",
      "a message",
      "static",
      0.5,
      "e",
    ),
    Finding::undecided(
      FBudget,
      "t.mbt",
      2,
      "f",
      "a message",
      "static",
      0.5,
      "e",
    ),
  ]
  let sink : Array[Finding] = []
  let md = findings_table(fs, 10, sink)
  inspect(md.contains("| Verdict |"), content="true")
  inspect(
    md.contains("| RANGE-VIOLATION | warning | certain | f | t.mbt:1 |"),
    content="true",
  )
  inspect(
    md.contains("| BUDGET-EXCEEDED | warning | unknown | f | t.mbt:2 |"),
    content="true",
  )
}

///|
test "the verdict: the report says how many claims could not be decided" {
  let fs = [
    Finding::new(
      FRangeViolation,
      "t.mbt",
      1,
      "f",
      "a message",
      "static",
      0.5,
      "e",
    ),
    Finding::undecided(
      FBudget,
      "t.mbt",
      2,
      "f",
      "the rest of this function was not analysed",
      "static",
      0.5,
      "e",
    ),
  ]
  let md = undecided_section(fs)
  inspect(
    md.contains("### 5.10 Claims that could not be decided"),
    content="true",
  )
  inspect(md.contains("1 claim(s) could not be decided"), content="true")
  inspect(
    md.contains(
      "| BUDGET-EXCEEDED | warning | f | t.mbt:2 | the rest of this function was not analysed |",
    ),
    content="true",
  )
  // The DECIDED claim is not in this section: it was decided.
  inspect(md.contains("RANGE-VIOLATION"), content="false")
}

///|
test "the verdict: a report with nothing undecided says so" {
  let fs = [
    Finding::new(
      FRangeViolation,
      "t.mbt",
      1,
      "f",
      "a message",
      "static",
      0.5,
      "e",
    ),
  ]
  let md = undecided_section(fs)
  inspect(md.contains("nothing was left unverified"), content="true")
}

///|
test "the verdict: a finding in two tables is counted once" {
  // The report's tables OVERLAP -- a taint finding is in the taint table AND
  // in the L2 table -- and the sidecar's sink holds every copy.  A count
  // taken over the sink without de-duplicating would report twice what the
  // report shows.
  let one = Finding::undecided(
    FBudget,
    "t.mbt",
    2,
    "f",
    "not analysed",
    "static",
    0.5,
    "e",
  )
  let fs = [one, one]
  inspect(undecided_findings(fs).length(), content="1")
  inspect(count_undecided(fs), content="1")
  // A decided claim at the SAME site is a different claim, and it does not
  // swallow the undecided one.
  let decided = Finding::new(
    FBudget,
    "t.mbt",
    2,
    "f",
    "not analysed",
    "static",
    0.5,
    "e",
  )
  inspect(count_undecided([decided, one]), content="1")
}
