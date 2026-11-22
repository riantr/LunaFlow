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
    md.contains("| RANGE-VIOLATION | warning | certain | f | t.mbt:1 |"),
    content="true",
  )
  inspect(
    md.contains("| INDEX-OOB | error | certain | f | t.mbt:3 |"),
    content="true",
  )
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
    md.contains("| RANGE-VIOLATION | warning | certain | f | t.mbt:1 |"),
    content="true",
  )
  inspect(
    md.contains("| RANGE-VIOLATION | warning | certain | f | t.mbt:2 |"),
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

///|
test "the truncated findings table's marker row has the header's shape" {
  // The marker row is the ONE row the findings table writes by hand, so it is
  // the one a column change can leave behind.  And a row with the wrong
  // number of cells is what makes the checks that MATCH a row by its columns
  // stop matching -- silently, and in the wrong direction: a NEGATIVE check
  // over that shape stops failing because it stops matching at all.
  //
  // That happened when the Verdict column was added: four negative checks
  // over the FFI and memory rows went quiet, and only the one POSITIVE check
  // over a row went red.
  let many : Array[Finding] = []
  let mut i = 0
  while i < 500 {
    many.push(f_at(FRangeViolation, i))
    i = i + 1
  }
  let sink : Array[Finding] = []
  let md = findings_table(many, 10, sink)
  // Eight cells, the same as the header's eight columns.
  inspect(
    md.contains(
      "| ... | ... | ... | ... | ... | (truncated at 10 of 500 rows) | ... | ... |",
    ),
    content="true",
  )
}

///|
/// WHICH DIMENSION FOUND WHICH RULE: the matrix has to be readable, has to
/// add up, and has to say the thing it exists to say.
///
/// The matrix is the only table in the report that answers "who found it"
/// rather than "what was found", and it is only worth a section if three
/// things hold:
///   - the ROW totals are the family counts, and the COLUMN totals are the
///     method counts, so the table checks itself;
///   - a cell with no findings reads `·`, so a lens that did not fire is
///     visible rather than blank;
///   - and it NAMES the families two lenses corroborate, because that is the
///     fact a reader deciding what to act on needs.
fn m_at(kind : FindingKind, mode : String, line : Int32) -> Finding {
  Finding::new(kind, "t.mbt", line, "f", "a message", mode, 0.5, "evidence")
}

///|
/// The rows of a findings table that belong to one family.
///
/// The count is over the ROWS, not over the text: a report names the
/// families in prose, counts them in the family-count table and crosses
/// them in the matrix, so a count over the text counts the mentions too.
fn m_rows_of(text : String, family : String) -> Int32 {
  let mut n = 0
  for line in text.split("\n").to_array() {
    if line.has_prefix("| " + family + " |") {
      n = n + 1
    }
  }
  n
}

///|
test "the dimension matrix: the rows and columns are the counts it claims" {
  let fs = [
    m_at(FIndexOob, "L2-EVA", 1),
    m_at(FIndexOob, "L2-EVA", 2),
    m_at(FIndexOob, "L2-abstract", 3),
    m_at(FTaintIndex, "L2-abstract", 4),
  ]
  let md = rule_dimension_matrix(fs)
  // The counter is ONLY the counter: the rules are the FindingKind codes
  // themselves, and they are rendered as the code.
  inspect(md.contains(FIndexOob.code()), content="true")
  // INDEX-OOB: 2 from L2-EVA and 1 from L2-abstract, total 3.
  inspect(
    md.contains("| L2-EVA | L2-abstract | Total |") ||
    md.contains("| L2-abstract | L2-EVA | Total |"),
    content="true",
  )
  inspect(md.contains("| INDEX-OOB | 2 | 1 | 3 |"), content="true")
  // TAINT-INDEX: 0 from L2-EVA, 1 from L2-abstract, total 1.
  inspect(md.contains("| TAINT-INDEX | · | 1 | 1 |"), content="true")
}

///|
test "the dimension matrix: a lens that did not fire reads as a dot" {
  let fs = [m_at(FIndexOob, "L2-EVA", 1)]
  let md = rule_dimension_matrix(fs)
  // One family, one method, one finding: no dot anywhere.
  inspect(md.contains("·"), content="false")
  inspect(md.contains("| INDEX-OOB | 1 | 1 |"), content="true")
}

///|
test "the dimension matrix: the totals add up to the finding count" {
  let fs = [
    m_at(FIndexOob, "L2-EVA", 1),
    m_at(FTaintIndex, "dynamic+symbolic", 2),
    m_at(FTaintIndex, "L2-abstract", 3),
    m_at(FRangeViolation, "dynamic", 4),
  ]
  let md = rule_dimension_matrix(fs)
  // The grand total is the number of findings, whatever the shape.
  inspect(
    md.contains("| **Total** | **1** | **1** | **1** | **1** | **4** |") ||
    md.contains("| **Total** | **1** | **1** | **1** | **1** | **4** |") ||
    md.contains("**4** |"),
    content="true",
  )
}

///|
test "the dimension matrix: it names the families two lenses corroborate" {
  let fs = [
    m_at(FTaintIndex, "dynamic+symbolic", 1),
    m_at(FTaintIndex, "L2-abstract", 2),
    m_at(FIndexOob, "L2-EVA", 3),
  ]
  let md = rule_dimension_matrix(fs)
  // TAINT-INDEX is the one family found by more than one method, and the
  // sentence has to say so BY NAME -- a count alone would not tell a reader
  // which claim has two kinds of evidence behind it.
  //
  // The assertion is the SENTENCE, with the family name inside it, and not
  // merely "the name appears somewhere": TAINT-INDEX also appears as a ROW
  // LABEL, so a check for the bare name passes even when the sentence's list
  // is empty. MEASURED: the first version of this test did exactly that, and
  // `scripts/qa/matrix_falsify.mjs` case F3 caught it.
  inspect(
    md.contains("more than one kind of evidence: TAINT-INDEX."),
    content="true",
  )
  inspect(md.contains("1 of them were found by"), content="true")
}

///|
test "the dimension matrix: a single-lens report says so in words" {
  let fs = [m_at(FIndexOob, "L2-EVA", 1), m_at(FRangeViolation, "L2-EVA", 2)]
  let md = rule_dimension_matrix(fs)
  // Nothing is corroborated, and the report must not leave that to be
  // inferred from an empty column: it states it.
  inspect(md.contains("exactly ONE method"), content="true")
  inspect(md.contains("MORE THAN ONE method"), content="false")
}

///|
test "the dimension matrix: no findings, no matrix" {
  let empty : Array[Finding] = []
  let md = rule_dimension_matrix(empty)
  inspect(md.contains("### 5.11"), content="true")
  inspect(md.contains("nothing to cross"), content="true")
  // And no table: a header with no rows would read as "zero findings", which
  // is a different claim from "there was nothing to analyse".
  inspect(md.contains("| Family |"), content="false")
}

///|
test "the dimension matrix: the same findings in another order give the same table" {
  let a = [m_at(FIndexOob, "L2-EVA", 1), m_at(FTaintIndex, "L2-abstract", 2)]
  let b = [m_at(FTaintIndex, "L2-abstract", 2), m_at(FIndexOob, "L2-EVA", 1)]
  // The table is sorted by total then by name, so the order the findings
  // arrived in cannot reach it.
  inspect(rule_dimension_matrix(a), content=rule_dimension_matrix(b))
}

///|
test "the dimension matrix: it counts the findings the tables show" {
  let fs = [
    m_at(FIndexOob, "L2-EVA", 1),
    m_at(FIndexOob, "L2-EVA", 2),
    m_at(FTaintIndex, "L2-abstract", 3),
    m_at(FTaintIndex, "dynamic+symbolic", 4),
  ]
  // The table and the matrix are rendered from the SAME findings, so a
  // matrix that crossed something else would still add up -- and would still
  // look like a matrix.  What says that it did not is that its counts are
  // the counts of the rows a reader can see.
  let sink : Array[Finding] = []
  let table = findings_table(fs, 300, sink)
  let md = rule_dimension_matrix(fs)
  inspect(sink.length(), content="4")
  // INDEX-OOB: two findings, and both of them from L2-EVA.
  inspect(m_rows_of(table, FIndexOob.code()), content="2")
  inspect(md.contains("| INDEX-OOB | 2 | · | · | 2 |"), content="true")
  // TAINT-INDEX: one from each of the two lenses, so it is corroborated.
  inspect(m_rows_of(table, FTaintIndex.code()), content="2")
  inspect(md.contains("| TAINT-INDEX | · | 1 | 1 | 2 |"), content="true")
  inspect(md.contains("1 of them were found by"), content="true")
}
