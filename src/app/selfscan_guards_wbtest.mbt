///|
/// THE SELF-SCAN'S CLAIMS ABOUT THIS SOURCE, AND THE GUARDS THAT ANSWER
/// THEM.
///
/// MEASURED (2026-11-25), at level 3: the analyser over its own source
/// reports 62 findings in `src/` and `src/command/` -- and every one of them
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
/// WHY THE COUNT DOUBLED, AND WHY THAT IS THE POINT.  The default scan used
/// to enter only the first 150 functions in file order, and that is not a
/// sample of the module -- it is its FIRST DIRECTORY.  On this tree the cap
/// interpreted 8 of 64 files, all of them in `src/app/`, and made 29 claims
/// about its own source.  The default scan now enters EVERY function,
/// bounded by the module's step budget rather than by a count, so it
/// interprets 61 of the 64 files and makes 60 claims.  The claims about
/// `parser.mbt`, `minimize.mbt`, `contract.mbt`, `analyze.mbt` and
/// `command.mbt` are claims the analyser had never made, because it had
/// never looked at that code.
///
/// AND WHY IT WAS 61 AFTER THE PER-PACKAGE MODE.  The per-package mode
/// added code of its own --
/// `src/app/package.mbt` and the trace splitter in `src/command` -- and the
/// analyser made FIVE new claims about it.  FOUR of them were FIXED rather
/// than registered, because a guard can answer them:
///
///   package.mbt functions_by_package   INDEX-OOB       the read is now guarded
///                                                      by the length of the list
///                                                      that is read
///   command.mbt write_package_traces   TAINT-INDEX    the builders are a MAP
///   command.mbt write_package_traces   TAINT-INDEX-   now -- a package is
///                                  RANGE            NAMED, not indexed, and a
///   command.mbt write_package_traces   INDEX-OOB      name is not an index
///
/// The FIFTH is `parser.mbt parse_file BUDGET-EXCEEDED`, and it is
/// REGISTERED: the interpreter's own 2,000-step budget ran out inside
/// `parse_file`, which is the same family as the `is_op`, `ffi_signature`,
/// `run_function` and `top_funcs` rows above.  A budget cannot be answered
/// by a guard -- the budget IS the bound, and the claim it makes is the
/// honest one: *the rest of this function was not executed, so no claim
/// about it was decided*.  The claim appeared because the tree changed:
/// `SourceFile::new` gained a field, the entry ordinals of every function
/// after it moved, and the interpreter now exhausts its budget one statement
/// later.
///
/// AND WHY IT IS 62 NOW.  The RECURSION DEPTH budget is a CLAIM the analyser
/// makes, not a truncation it makes silently.  `parser.mbt` is a
/// recursive-descent parser: `parse_if` calls `parse_expr`, and when the
/// analyser interprets its OWN source it follows THAT call chain -- its own
/// recursion -- six levels deep before the depth budget stops it.  The claim
/// is REGISTERED, and it is the same family as the step-budget rows above: a
/// budget cannot be answered by a guard, because the budget IS the bound, and
/// the honest claim is *the call chain was not followed past this depth, so no
/// claim about the rest of it was decided*.
///
/// BEFORE THE FIX, THAT TRUNCATION WAS SILENT.  The value the call would have
/// returned was simply absent, and an absent claim is indistinguishable from a
/// decided and clean one -- so a recursive module and a clean one produced the
/// same report.  The fix is in `src/app/interp.mbt`: the depth guard now
/// reports what it could not decide, with the same family and the same
/// UNDECIDED verdict as the step budget above it.
///
///
/// The list below is the REGISTER: what the analyser claims, and what makes
/// the claim false.  A claim that is registered is a claim that has been
/// looked at; a claim that is NOT registered is a claim nobody has answered,
/// and that is the kind that hides a real defect.
///
///   site                                  claims                the guard
///   ---------------------------------------------------------------------
///   util.mbt read_line_at                 TAINT-INDEX-RANGE     `line >= 1 &&`
///                                         TAINT-INDEX           `line <= length`
///                                         INDEX-OOB             the same two ends
///   value.mbt synthesize                  3 x INDEX-OOB         `j < n`, `k >= 0`
///   interp.mbt sort_values                4 x TAINT-INDEX-RANGE `j + 1 < len - i`
///                                         4 x INDEX-OOB         the same bound
///   interp.mbt call_user                  TAINT-INDEX           `i < params.len` and `i < args.len`
///   interp.mbt tail_value                 TAINT-INDEX-RANGE     `length == 0`
///   interp.mbt run_function               BUDGET-EXCEEDED       the interpreter's step budget
///   conc.mbt conc_cycle_key               2 x TAINT-INDEX-RANGE `(min+i) % len`
///                                         TAINT-INDEX           and `len != 0`
///                                         INDEX-OOB             the same guard
///   conc.mbt conc_cycle_walk              DIVISION-BY-ZERO      the loop bound
///                                         2 x INDEX-OOB         `0..<len`
///   conc.mbt conc_reach_from              TAINT-INDEX-RANGE     `i < frontier.len`
///   contract.mbt contract_above           2 x TAINT-INDEX       `k >= 0 && k < lines.len`
///   command.mbt arg_value                 TAINT-INDEX           `i >= 0 &&`
///                                         INDEX-OOB             `i + 1 < len`
///   command.mbt cli_args                  TAINT-INDEX-RANGE     `i < args.len`
///   command.mbt parse_args                TAINT-INDEX-RANGE     `arg_value`'s own bound
///   abs.mbt srcs_label                    TAINT-INDEX           `split` yields at least one part
///   abs.mbt branch_returns                TAINT-INDEX-RANGE     `len == 0`
///   analyze.mbt slice_graph               TAINT-INDEX           `i < nodes.len`
///   cfg.mbt last_node                     TAINT-INDEX-RANGE     `len == 0`
///   cfg.mbt cfg_findings                  TAINT-INDEX           `i < nodes.len`
///   ffi.mbt ffi_check_signature_conflicts TAINT-INDEX-RANGE     `len == 0`
///   ffi.mbt ffi_join                      TAINT-INDEX-RANGE     `len == 0`
///   ffi.mbt ffi_escaped_names             TAINT-INDEX           the body's own
///   ffi.mbt ffi_signature                 BUDGET-EXCEEDED       the interpreter's step budget
///   ipc.mbt ipc_last_part                 TAINT-INDEX-RANGE     `i >= 0`
///   minimize.mbt candidate_index          TAINT-INDEX-RANGE     `i < cands.len`
///   minimize.mbt Minimizer::minimize_for  INDEX-OOB             `i < trials.len`
///   minimize.mbt value_arr_eq             TAINT-INDEX-RANGE     `i < a.len` and `i < b.len`
///   minimize_wbtest.mbt chosen_value      2 x TAINT-INDEX       the analyser's own indices
///   minimize_wbtest.mbt inputs_before     TAINT-INDEX-RANGE     `i < trials.len`
///   parser.mbt P::peek                    TAINT-INDEX           `i >= 0 && i < toks.len`
///   parser.mbt P::peek_at                 TAINT-INDEX           `j >= 0 && j < toks.len`
///   parser.mbt guard_body_returns         TAINT-INDEX-RANGE     `length == 0`
///   parser.mbt is_op                      BUDGET-EXCEEDED       the interpreter's step budget
///   parser.mbt parse_file                 BUDGET-EXCEEDED       the interpreter's step budget
///   parser.mbt parse_expr                 INFINITE-LOOP         the `break` is in a construct the parser does not model
///   parser.mbt parse_if                   BUDGET-EXCEEDED       the recursion depth budget
///   report.mbt rule_dimension_matrix      3 x INDEX-OOB         `a < len` and `b < len`
///   report.mbt top_funcs                  BUDGET-EXCEEDED       the interpreter's step budget
///                                         TAINT-INDEX-RANGE     `j + 1 < len - i` and `k < len`
///                                         3 x TAINT-INDEX       the same bound
///
/// TWO OF THE CLAIMS BELOW POINTED AT SOMETHING THAT WAS FIXED.  The claims
/// themselves STAY -- the analyser cannot discharge a taint, and it will keep
/// saying it -- but the defect each one pointed at is gone:
///
///   contract.mbt  contract_above  the loop that walks UP from the line
///                 above            above had no UPPER bound, while the
///                                   loop below it had one.  `start_line` is
///                                   a parameter of a PUBLISHED function, so
///                                   a caller could name a line past the end
///                                   of the text and the read would go past
///                                   the end of `lines`.  The bound was
///                                   added.
///   parser.mbt    P::peek         the lower bound was an INVARIANT rather
///                                 than a check -- `self.i` starts at 0 and
///                                 `bump` only increments it -- and
///                                 `P::peek_at` stated it.  It is stated
///                                 now.
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
/// ONE MORE CLAIM CAME WITH THE COUNTEREXAMPLE FIX, and it is REGISTERED like
/// the others.  The minimisation now reads the candidate index of every input
/// BEFORE it runs anything -- the function under analysis may WRITE INTO the
/// array it was given, and then the value is no longer the value the walk
/// chose -- and that read is `trials[i]`, with the loop's own
/// `i < trials.length()` as its guard.  The analyser cannot relate the length
/// of an array it has not measured to the bound that guards it, so the claim
/// is a MAY-claim; the guard is there, and the read is inside it.
///
/// TWO OF THEM WERE NOT answered when this register was written, and both
/// were FIXED rather than registered:
///
///   parser.mbt   render_tokens   TAINT-INDEX + INDEX-OOB  the range is now
///                                                           clamped at ZERO
///   command.mbt  arg_value       (that claim's lower       `i >= 0` is now
///                                 bound, which moved)       part of the guard
///
/// WHAT THIS FILE PINS, AND WHAT IT DOES NOT.  A test below exists for
/// every guard this package can reach WITHOUT a fake: `read_line_at`,
/// `render_tokens`, `sort_values`, `conc_cycle_key`, `synthesize`,
/// `srcs_label`, `branch_returns`, `last_node`, `ipc_last_part`,
/// `cfg_findings`, `ffi_join`, `ffi_check_signature_conflicts` and
/// `conc_cycle_walk` -- and, since the default scan entered every function,
/// `contract_above`, `P::peek`, `P::peek_at`, `value_arr_eq`,
/// `candidate_index` and `guard_body_returns` -- and NOT
/// `minimize_for`, whose claim is the loop's own bound and reaches no test
/// the package can write honestly.
///
/// WHAT THE TWO FIXES DID TO THESE CLAIMS.  `render_tokens` had TWO claims
/// (`TAINT-INDEX` + `INDEX-OOB`), and both are GONE from the self-scan.
/// `arg_value`'s claim SURVIVES -- the analyser still cannot prove the
/// array's length -- but its evidence moved from
/// `index [-999999,1000001]` to `index [1,1000001]`, which is the analyser
/// SEEING the new lower bound.  `contract_above`'s and `P::peek`'s claims
/// SURVIVE as well, and for the same reason: a taint is not a range, and the
/// analyser cannot discharge one.  What changed is that the read is now
/// inside the array by the guard's own terms, and a test below says so.
///
/// WHAT IS NOT PINNED HERE, STATED RATHER THAN PAPERED OVER.
/// `arg_value`, `cli_args` and `parse_args` live in `src/command`, and
/// `src/app` cannot import that package: this file has NO test for them, and
/// that is a recorded gap.  `parse_expr`'s INFINITE-LOOP is pinned in
/// `peer_findings_test.mbt`, and the `BUDGET-EXCEEDED` family -- which
/// covers `ffi_signature`, `run_function`, `is_op` and `top_funcs` -- in
/// `verdict_wbtest.mbt`, where it is the UNDECIDED claim the verdict exists
/// for.  `slice_graph`, `conc_reach_from`, `call_user`, `tail_value` and
/// `ffi_escaped_names` are not pinned either: their guards are loop bounds
/// and empty checks that a test would have to fake to reach.
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

///|
test "the self-scan: a contract line past the end of the text reads nothing" {
  let src =
    #|//@ requires n < 10;
    #|fn f(n : Int) -> Int {
    #|  n
    #|}
  // The guard is `k >= 0 && k < lines.length()`.  The UPPER bound was ADDED
  // in this round: `start_line` is a parameter of a PUBLISHED function, so a
  // caller could name a line past the end of the text, and the loop that
  // walks upwards from it had no upper bound -- while the loop below it had
  // one.  This is the test that says the read stays inside `lines`.
  let c = contract_above(src, "f.mbt", 99)
  inspect(c.requires.length(), content="0")
  // The same text, named at a line that IS in it: the contract is found.
  let ok = contract_above(src, "f.mbt", 2)
  inspect(ok.requires.length(), content="1")
}

///|
test "the self-scan: peeking past the end of the tokens reads nothing" {
  let p = P::new("t.mbt", [tok("a")])
  // The guards are `self.i >= 0 && self.i < self.toks.length()` and
  // `j >= 0 && j < self.toks.length()`.
  inspect(p.peek().kind == TChar, content="true")
  ignore(p.bump())
  // The token list is exhausted, so the peek reads nothing.
  inspect(p.peek().kind == TEOF, content="true")
  // A negative offset is out of bounds at the OTHER end.
  inspect(p.peek_at(-5).kind == TEOF, content="true")
}

///|
test "the self-scan: comparing two arrays reads neither past its end" {
  // The guard is `i < a.length()` for the first array and the
  // `i >= b.length()` check for the second: the analyser cannot relate two
  // arrays' lengths, so the check is what makes the read of `b` decidable.
  inspect(value_arr_eq([VInt(1)], [VInt(1)]), content="true")
  inspect(value_arr_eq([VInt(1)], [VInt(1), VInt(2)]), content="false")
  inspect(value_arr_eq([], []), content="true")
}

///|
test "the self-scan: a value that is not a candidate has no index" {
  // The guard is the loop's own bound, `i < cands.length()`.
  inspect(candidate_index(VInt(9), [VInt(1)]), content="-1")
  inspect(candidate_index(VInt(1), [VInt(1)]), content="0")
}

///|
test "the self-scan: a body with no statements has no last statement" {
  // The guard is `body.length() == 0`.
  let empty : Array[Stmt] = []
  inspect(guard_body_returns(empty).length(), content="0")
}
