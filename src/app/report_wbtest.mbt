///|
/// The findings table is BOUNDED, and the bound costs no finding.
///
/// The findings table was the report's only section that grew with the
/// MODULE rather than with the reader: a module with many findings produced
/// a report nobody could scroll. Every other section has a legible element
/// count (design.md §6.3); this one now has one too.
///
/// The bound is only honest if three things hold at once, and these tests
/// hold them:
///   - the table shows at most the cap's rows;
///   - it says how many it left out, and how many of each family there are
///     in the WHOLE set, so a reader can tell 300 findings from 2,357;
///   - and the findings the table did not show are still AVAILABLE -- the
///     sink receives every one of them, before the bound is applied.
fn f_at(kind : FindingKind, line : Int32) -> Finding {
  Finding::new(kind, "t.mbt", line, "f", "a message", "static", 0.5, "evidence")
}

///|
test "a findings table shows every finding when they fit" {
  let fs = [
    f_at(FRangeViolation, 1),
    f_at(FRangeViolation, 2),
    f_at(FIndexOob, 3),
  ]
  let sink : Array[Finding] = []
  let md = findings_table(fs, 10, sink)
  // Three rows, no truncation marker, and no count table: the table IS the
  // whole set, so a count table would only repeat it.
  inspect(md.contains("truncated"), content="false")
  inspect(md.contains("| Family |"), content="false")
  inspect(
    md.contains("| RANGE-VIOLATION | warning | f | t.mbt:1 |"),
    content="true",
  )
  inspect(md.contains("| INDEX-OOB | error | f | t.mbt:3 |"), content="true")
  inspect(sink.length(), content="3")
}

///|
test "a findings table is bounded, and says what it left out" {
  let fs = [
    f_at(FRangeViolation, 1),
    f_at(FRangeViolation, 2),
    f_at(FRangeViolation, 3),
    f_at(FIndexOob, 4),
    f_at(FIndexOob, 5),
  ]
  let sink : Array[Finding] = []
  let md = findings_table(fs, 2, sink)
  // The bound holds: two rows of findings, and the marker says which rows.
  inspect(
    md.contains("| RANGE-VIOLATION | warning | f | t.mbt:1 |"),
    content="true",
  )
  inspect(
    md.contains("| RANGE-VIOLATION | warning | f | t.mbt:2 |"),
    content="true",
  )
  inspect(md.contains("t.mbt:3"), content="false")
  inspect(md.contains("(truncated at 2 of 5 rows)"), content="true")
  // The count table is the shape of the WHOLE set, family by family.
  inspect(md.contains("| Family | Findings |"), content="true")
  inspect(md.contains("| RANGE-VIOLATION | 3 |"), content="true")
  inspect(md.contains("| INDEX-OOB | 2 |"), content="true")
  // And the notice names the number that was left out.
  inspect(md.contains("first 2 of 5 findings"), content="true")
  inspect(md.contains("the 3 not shown here"), content="true")
  // The sink has EVERY finding: the bound hides rows, not findings.
  inspect(sink.length(), content="5")
}

///|
test "the count table is sorted by count, then by family code" {
  let fs = [
    f_at(FIndexOob, 1),
    f_at(FRangeViolation, 2),
    f_at(FRangeViolation, 3),
    f_at(FRangeViolation, 4),
  ]
  let sink : Array[Finding] = []
  let md = findings_table(fs, 1, sink)
  // RANGE-VIOLATION has three and INDEX-OOB one, so RANGE-VIOLATION is
  // first -- and the order does not depend on the order the findings came
  // in, or the same report would read differently on two runs.
  inspect(
    md.contains("| RANGE-VIOLATION | 3 |\n| INDEX-OOB | 1 |"),
    content="true",
  )
}

///|
test "a findings table of none says so" {
  let fs : Array[Finding] = []
  let sink : Array[Finding] = []
  let md = findings_table(fs, 10, sink)
  inspect(md.contains("_No findings._"), content="true")
  inspect(sink.length(), content="0")
}

///|
test "the report's findings are collected, not just its tables" {
  // The sink is how the `_findings.jsonl` sidecar stays lossless. It has to
  // hold the findings the tables did NOT show, or the bound would lose them.
  let many : Array[Finding] = []
  let mut i = 0
  while i < 500 {
    many.push(f_at(FRangeViolation, i))
    i = i + 1
  }
  let sink : Array[Finding] = []
  let md = findings_table(many, 10, sink)
  inspect(md.contains("(truncated at 10 of 500 rows)"), content="true")
  inspect(sink.length(), content="500")
}
