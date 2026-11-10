///|
/// Regression tests for the untrusted-input hardening added in the deep QA pass:
/// the parser must degrade pathologically nested input into *recorded gaps*
/// instead of aborting the process (measured crash: 0xC0000409 at `if`×5000 and
/// `(`×2000), and must not inflate the "statements understood" metric while
/// doing so.
fn nested_if_source(depth : Int32) -> String {
  let open = "if x > 0 { "
  let close = " }"
  let out = StringBuilder()
  out.write_string("pub fn f(x : Int) -> Int {\n")
  let mut i = 0
  while i < depth {
    out.write_string(open)
    i = i + 1
  }
  out.write_string("x")
  let mut j = 0
  while j < depth {
    out.write_string(close)
    j = j + 1
  }
  out.write_string("\n}\n")
  out.to_string()
}

///|
fn nested_paren_source(depth : Int32) -> String {
  let out = StringBuilder()
  out.write_string("pub fn g(x : Int) -> Int {\n  let y = ")
  let mut i = 0
  while i < depth {
    out.write_char('(')
    i = i + 1
  }
  out.write_char('x')
  let mut j = 0
  while j < depth {
    out.write_char(')')
    j = j + 1
  }
  out.write_string("\n  y\n}\n")
  out.to_string()
}

///|
test "shallow nesting is parsed without gaps" {
  let f = @app.parse_file("a.mbt", nested_if_source(8))
  inspect(f.funcs.length(), content="1")
  inspect(f.issues.length(), content="0")
  assert_true(f.parsed_stmts >= 8)
}

///|
test "statement nesting beyond the guard is recorded as a gap, not a crash" {
  let f = @app.parse_file("deep_if.mbt", nested_if_source(3000))
  inspect(f.funcs.length(), content="1")
  assert_true(f.issues.length() >= 1)
  // the skipped region must be counted as unsupported, not as understood code
  assert_true(f.unsupported_stmts >= 1)
  // and the inflated-statement artefact must stay bounded well below the input size
  assert_true(f.parsed_stmts < 600)
  inspect(f.issues.length() > 0, content="true")
}

///|
test "expression nesting beyond the guard is recorded as a gap, not a crash" {
  let f = @app.parse_file("deep_paren.mbt", nested_paren_source(3000))
  inspect(f.funcs.length(), content="1")
  assert_true(f.issues.length() >= 1)
  assert_true(f.unsupported_stmts >= 1)
  assert_true(f.parsed_stmts < 600)
}
