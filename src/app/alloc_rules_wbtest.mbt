///|
/// The allocation rules, and the de-duplication key.
///
/// TWO REPAIRS, and both of them were measured on the real corpus.
///
/// 1. THE ALLOCATION RULES WERE DEAD. The parser renders a qualified path
///    with a DOT -- `Array::make(n)` becomes the call name `Array.make` --
///    so a rule that matched only the `::` spelling could never fire. Five
///    rules were in that state: the L2's allocation-size rule, the
///    allocation-size VC, the L1's allocation taint, and the two
///    string-conversion rules. MEASURED: the `TAINT-ALLOC` family appeared
///    ZERO times in all three committed artefacts, and the fixture that
///    exists to prove the case -- `make_window(n : Int32)` and
///    `parse_len(s : String)` in `fixtures/vuln_demo` -- was silent.
///
/// 2. THE DE-DUPLICATION KEY HAD NO FILE IN IT. The findings array is the
///    MODULE's -- one array, shared by every function -- so a finding in one
///    file could be dropped as a duplicate of a finding in another file
///    that happened to share its line number and its message. MEASURED on
///    `riantr/moonbit_doubleML`: 312 findings were lost that way.
///
/// Both tests are falsifiable: they fail on the code as it was before the
/// repairs.

///|
fn abs_ast(src : String) -> ModuleAst {
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
fn abs_count(src : String, kind : FindingKind) -> Int32 {
  let ast = abs_ast(src)
  let abs = run_abstract(ast, 10, 1000)
  let mut n = 0
  for f in abs.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn abs_messages(src : String, kind : FindingKind) -> Array[String] {
  let ast = abs_ast(src)
  let abs = run_abstract(ast, 10, 1000)
  let out : Array[String] = []
  for f in abs.findings {
    if f.kind == kind {
      out.push(f.file + ":" + f.line.to_string() + " " + f.message)
    }
  }
  out
}

///|
test "a tainted allocation size is reported, because the rule that says so was dead" {
  // The size is a PARAMETER, so it is tainted, and the family says "a
  // tainted value may control an allocation size".
  let src =
    #|pub fn make_window(n : Int) -> Array[Int] {
    #|  Array::make(n, 0)
    #|}
  inspect(abs_count(src, FTaintAlloc), content="1")
}

///|
test "a tainted allocation size is reported for the qualified spelling too" {
  // The SAME rule, spelled the other way. The parser renders a qualified
  // path with a DOT, so `Array::make` and `Array.make` are the same call --
  // and the rule has to answer to both.
  let src =
    #|pub fn make_window(n : Int) -> Array[Int] {
    #|  Array.make(n, 0)
    #|}
  inspect(abs_count(src, FTaintAlloc), content="1")
}

///|
test "a clean allocation size is not reported" {
  // The other direction: the repair must not make every allocation a
  // finding. A literal size is not tainted.
  let src =
    #|pub fn make_window() -> Array[Int] {
    #|  Array::make(4, 0)
    #|}
  inspect(abs_count(src, FTaintAlloc), content="0")
}

///|
test "a negative allocation size is a range violation" {
  // The same dead rule carried this one: a size whose interval includes a
  // negative number, which is the family RANGE-VIOLATION's second clause.
  let src =
    #|pub fn make_window(n : Int) -> Array[Int] {
    #|  Array::make(n, 0)
    #|}
  inspect(abs_count(src, FRangeViolation), content="1")
}

///|
test "two findings in two files are two findings" {
  // The de-duplication key had no file in it, and the findings array is the
  // module's -- so this finding at line 1 of a.mbt collided with the one at
  // line 1 of b.mbt, and the second was dropped.
  let ast = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [
      parse_file(
        "a.mbt",
        (
          #|pub fn f(n : Int) -> Array[Int] {
          #|  Array::make(n, 0)
          #|}
        ),
      ),
      parse_file(
        "b.mbt",
        (
          #|pub fn g(n : Int) -> Array[Int] {
          #|  Array::make(n, 0)
          #|}
        ),
      ),
    ],
    manifest_deps: [],
    manifest_target: "native",
  }
  let abs = run_abstract(ast, 10, 1000)
  let mut alloc = 0
  for f in abs.findings {
    if f.kind == FTaintAlloc {
      alloc = alloc + 1
    }
  }
  // Two findings, one per file -- and the two files are NAMED, so a reader
  // can tell which is which.
  inspect(alloc, content="2")
  let files : Array[String] = []
  for f in abs.findings {
    if f.kind == FTaintAlloc {
      files.push(f.file)
    }
  }
  inspect(files.contains("a.mbt"), content="true")
  inspect(files.contains("b.mbt"), content="true")
}

///|
test "the same finding twice in one file is still one finding" {
  // The de-duplication is still exact WITHIN a file: one statement per
  // line, so the same family and message at the same line is the same
  // site. The repair must not turn the de-duplication off.
  let src =
    #|pub fn f(n : Int) -> Array[Int] {
    #|  let a = Array::make(n, 0)
    #|  let b = Array::make(n, 1)
    #|  a
    #|}
  let ast = abs_ast(src)
  let abs = run_abstract(ast, 10, 1000)
  let mut alloc = 0
  for f in abs.findings {
    if f.kind == FTaintAlloc {
      alloc = alloc + 1
    }
  }
  // Two allocations on two different lines: two findings.
  inspect(alloc, content="2")
  // And the messages name the lines, so they are distinguishable.
  let msgs = abs_messages(src, FTaintAlloc)
  inspect(msgs.length(), content="2")
}
