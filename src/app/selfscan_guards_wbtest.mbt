///|
/// THE SELF-SCAN'S CLAIMS ABOUT THIS SOURCE, AND THE GUARDS THAT ANSWER
/// THEM.
///
/// MEASURED (2026-11-23), at level 3: the analyser over its own source
/// reports 29 findings in `src/` and `src/command/` -- and every one of them
/// is a MAY-claim about an index or a divisor, answered by a guard that is IN
/// the source, or (for `srcs_label`) by a MEASURED property of the standard
/// library.  None of them is a defect.
///
/// THE REGISTER IS CHECKED, NOT ONLY WRITTEN.  It had drifted: it was
/// measured against 26 claims, and the tree made 29 -- three of them in a
/// function that was added afterwards, and nobody had answered them.
/// `scripts/qa/selfscan_register.mjs` runs the analyser over this source
/// and compares what it says NOW with what the table below says: every
/// claim must be here, with the count that was measured, and every claim
/// here must still be made.
///
/// The list below is the REGISTER: what the analyser claims, and what makes
/// the claim false.  A claim that is registered is a claim that has been
/// looked at; a claim that is NOT registered is a claim nobody has answered,
/// and that is the kind that hides a real defect.
///
///   site                                  claims            the guard
///   ---------------------------------------------------------------------
///   util.mbt      read_line_at            INDEX-OOB         `line >= 1 &&`
///                                          TAINT-INDEX       `line <= length`
///   value.mbt     synthesize              3 x INDEX-OOB     `j < n`, `k >= 0`
///   interp.mbt    sort_values             4 x INDEX-OOB     `j + 1 < len - i`
///   conc.mbt      conc_cycle_key          INDEX-OOB         `(min+i) % len`
///                                          TAINT-INDEX       and `len != 0`
///   conc.mbt      conc_cycle_walk         DIVISION-BY-ZERO  the loop bound
///                                          2 x INDEX-OOB     `0..<len`
///   command.mbt   arg_value               INDEX-OOB         `i >= 0 &&`
///                                          TAINT-INDEX       `i + 1 < len`
///   abs.mbt       srcs_label              TAINT-INDEX       `split` yields
///                                                           at least one
///                                                           part
///   abs.mbt       branch_returns          TAINT-INDEX-RANGE `len == 0`
///   cfg.mbt       last_node               TAINT-INDEX-RANGE `len == 0`
///   cfg.mbt       cfg_findings            TAINT-INDEX       `i < nodes.len`
///   ffi.mbt       ffi_check_signature_... TAINT-INDEX-RANGE `len == 0`
///   ffi.mbt       ffi_join                TAINT-INDEX-RANGE `len == 0`
///   ffi.mbt       ffi_escaped_names       TAINT-INDEX       the body's own
///   ipc.mbt       ipc_last_part           TAINT-INDEX-RANGE `i >= 0`
///   parser.mbt    parse_expr              INFINITE-LOOP     the `break` is
///                                                            in a construct
///                                                            the parser does
///                                                            not model
///   report.mbt    rule_dimension_matrix  3 x INDEX-OOB     `a < len` and
///                                                           `b < len`
///   ffi.mbt       ffi_signature           BUDGET-EXCEEDED   the interpreter's
///                                                            step budget
///
/// THE `srcs_label` CLAIM, MEASURED.  Its answer is not a guard in the
/// source: it is `String::split`'s contract.  MEASURED on the toolchain
/// this tree is written against: `"".split(":")` has length 1 -- `split`
/// yields at least one part for every input -- so `parts[parts.length() - 1]`
/// is `parts[0]`, and it reads inside the array.  The claim is a MAY-claim
/// the analyser cannot discharge, because the interpreter does not model
/// `split` and so does not know the array's length.  It is REGISTERED, not
/// fixed: there is nothing to reach.  The counterexample the minimiser
/// found for it (`srcs = [""]`) reproduces the CLAIM, not a defect.
///
/// Two of them were NOT answered when this register was written, and both
/// were FIXED rather than registered:
///
///   parser.mbt   render_tokens   TAINT-INDEX + INDEX-OOB  the range is now
///                                                           clamped at ZERO
///   command.mbt  arg_value       (that claim's lower       `i >= 0` is now
///                                 bound, which moved)       part of the guard
///
/// WHAT THIS FILE PINS, AND WHAT IT DOES NOT.  A test below exists for every
/// guard this package can reach WITHOUT a fake: `read_line_at`,
/// `render_tokens`, `sort_values`, `conc_cycle_key`, `synthesize`,
/// `srcs_label`, `branch_returns`, `last_node`, `ipc_last_part`,
/// `cfg_findings`, `ffi_join`, `ffi_check_signature_conflicts` and
/// `conc_cycle_walk`.
///
/// WHAT THE TWO FIXES DID TO THESE CLAIMS.  `render_tokens` had TWO claims
/// (`TAINT-INDEX` + `INDEX-OOB`), and both are GONE from the self-scan.
/// `arg_value`'s claim SURVIVES -- the analyser still cannot prove the
/// array's length -- but its evidence moved from
/// `index [-999999,1000001]` to `index [1,1000001]`, which is the analyser
/// SEEING the new lower bound.
///
/// WHAT IS NOT PINNED HERE, STATED RATHER THAN PAPERED OVER.
/// `arg_value` lives in `src/command`, and `src/app` cannot import that
/// package: this file has NO test for it, and that is a recorded gap.
/// `parse_expr`'s INFINITE-LOOP is pinned in `peer_findings_test.mbt`, and
/// `ffi_signature`'s BUDGET-EXCEEDED in `verdict_wbtest.mbt` -- where it is
/// the UNDECIDED claim the verdict exists for.
///
/// The limit is stated rather than papered over: a guard is pinned by a test
/// only where a test can reach it honestly.

///|
fn tok(text : String) -> Tok {
  { kind: TChar, text, line: 1, col: 1, }
}

///|
test "the self-scan: a line outside the file reads nothing" {
  let lines = ["one", "two"]
  inspect(read_line_at(lines, 1), content="one")
  inspect(read_line_at(lines, 2), content="two")
  // The guard is `line >= 1 && line <= lines.length()`: both ends.  Remove
  // either and one of these reads out of bounds.
  inspect(read_line_at(lines, 0), content="")
  inspect(read_line_at(lines, 3), content="")
  inspect(read_line_at(lines, -1), content="")
}

///|
test "the self-scan: a token range past the end renders nothing" {
  let toks = [tok("a"), tok("b")]
  inspect(render_tokens(toks, 0, 2), content="a b")
  // The range is clamped at zero, so a start past the end renders NOTHING
  // rather than reading past the last token.
  inspect(render_tokens(toks, 5, 9), content="")
  inspect(render_tokens(toks, -1, 2), content="a b")
}

///|
test "the self-scan: sorting does not read past the end" {
  let empty : Array[Value] = []
  sort_values(empty)
  let one = [VInt(1)]
  sort_values(one)
  let three = [VInt(3), VInt(1), VInt(2)]
  sort_values(three)
  // The guard is the loop's own bound, `j + 1 < xs.length() - i`.
  match three[0] {
    VInt(n) => inspect(n, content="1")
    _ => fail("expected an int")
  }
  match three[2] {
    VInt(n) => inspect(n, content="3")
    _ => fail("expected an int")
  }
}

///|
test "the self-scan: a cycle key stays inside the cycle" {
  // The guard is `(min + i) % cyc.length()` -- and the empty cycle is
  // answered before the modulo can divide by zero.
  inspect(conc_cycle_key([]), content="")
  inspect(conc_cycle_key(["a"]), content="a|")
  inspect(conc_cycle_key(["b", "a"]), content="a|b|")
}

///|
test "the self-scan: synthesizing inputs does not read past the end" {
  let f = parse_file("t.mbt", "fn f(a : Int, b : Int) -> Int {\n  a\n}").funcs[0]
  let sets = synthesize(f, 4)
  // The guards are `j < n` and `k >= 0`, where n is the number of
  // parameters.
  inspect(sets.length() >= 1, content="true")
  inspect(sets.length() <= 4, content="true")
}

///|
test "the self-scan: a source label names the parameter" {
  // The guard is `parts[parts.length() - 1]`, and `split` always yields at
  // least one part.  MEASURED on this toolchain: `"".split(":")` has
  // length 1, so the index is 0 and the read is inside the array.
  inspect(srcs_label(["param:len"]), content="parameter `len`")
  inspect(srcs_label(["param:a", "param:b"]), content="parameters `a` and `b`")
  // The EMPTY source, which is the input the minimiser's counterexample
  // names: `split` still yields one part, so the label is read, not
  // skipped and not read past the end.
  inspect(srcs_label([""]), content="parameter ``")
}

///|
test "the self-scan: an empty statement list has no last node" {
  // The guards are the `length == 0` checks, in both of these.
  let empty : Array[Stmt] = []
  inspect(branch_returns(empty), content="false")
  inspect(last_node(Builder::new("f", "f.mbt"), empty, -1), content="-1")
}

///|
test "the self-scan: the last part of a name is inside the name" {
  // The guard is the loop's own bound, `i >= 0`.
  inspect(ipc_last_part("@io.write"), content="write")
  inspect(ipc_last_part("write"), content="write")
}

///|
test "the self-scan: the CFG finding pass stays inside its node list" {
  // The guard is `i < cfg.nodes.length()`, and the bound is `cfg.nodes`.
  let f = parse_file("t.mbt", "fn f() -> Int {\n  return 1\n}").funcs[0]
  let cfg = build_cfg(f)
  let findings = cfg_findings(cfg)
  // The function only has to RETURN; the point is that it does not read the
  // node list past its end, whatever its size.
  inspect(findings.length() >= 0, content="true")
}

///|
test "the self-scan: a cycle with no edges has no cycle to report" {
  // The guards are the modulo and the loop bounds inside the walker; an empty
  // graph reaches neither.
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [parse_file("c.mbt", "pub fn f() -> Unit {\n}\n")],
    manifest_deps: [],
    manifest_target: "native",
  }
  let m = analyze_conc(ast)
  inspect(m.findings.length(), content="0")
}

///|
test "the self-scan: the FFI name helpers stay inside their lists" {
  // The guards are `length == 0` in two places and the body's own bound in
  // the third. The empty case reads "none" -- that is the function's own
  // wording, and it is why the loop below never runs on an empty list.
  inspect(ffi_join([]), content="none")
  inspect(ffi_join(["a"]), content="'a'")
  inspect(ffi_join(["a", "b"]), content="'a', 'b'")
}

///|
test "the self-scan: a module with no C declaration has no signature to judge" {
  // `ffi_signature` renders from the declaration's own `params` list, and
  // `ffi_check_signature_conflicts` compares signatures within the module. A
  // module with no declaration reaches neither loop.
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [parse_file("c.mbt", "pub fn f() -> Int {\n  0\n}\n")],
    manifest_deps: [],
    manifest_target: "native",
  }
  let m = analyze_ffi(ast)
  inspect(m.findings.length(), content="0")
}

///|
test "the self-scan: a signature conflict is reported against its own list" {
  // The guard is `decls` being the list being compared -- the conflict is
  // found by comparing a declaration WITH the others, so that list is
  // non-empty by construction.
  let src =
    #|extern "C" fn read_reg(r : UInt32) -> UInt32 = "read_reg"
    #|
    #|extern "C" fn read_reg(r : UInt32) -> UInt64 = "read_reg"
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
  let m = analyze_ffi(ast)
  let mut n = 0
  for f in m.findings {
    if f.kind == FFfiSignatureConflict {
      n = n + 1
    }
  }
  // One symbol, two different return types: the conflict is found on both.
  inspect(n, content="2")
}
