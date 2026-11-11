///|
/// MoonBit's multiline string literal -- the `#|` form.
///
/// The peer analyzer reported that it cannot parse `src/command/command.mbt`,
/// and the reason is on both sides: the peer models this construct with a
/// closer that the toolchain does not have, and we modelled it as a string
/// that ends at the end of its first line.
///
/// The semantics below were MEASURED against the toolchain BY VALUE. "Does
/// `moon check` accept it" settles nothing here: the toolchain accepts every
/// shape of this construct, so acceptance measures nothing.
///
///   #|AAA / #|BBB           -> "AAA\nBBB"    the chunks are joined with a NEWLINE
///   #|AAA / #| / #|BBB      -> "AAA\n\nBBB"  a bare `#|` is an EMPTY chunk
///   #| / #|BBB              -> "\nBBB"       a bare OPENING `#|` is an empty chunk
///   #|  x                   -> "  x"         a chunk is NOT trimmed
///   #|AAA / <blank> / #|BBB -> "AAA\nBBB"   a blank line is skipped
///   #|AAA / plain           -> "AAA"         `plain` is CODE and ends the literal
///
/// There is no `|#` terminator -- a bare `#` is a lexing error in MoonBit --
/// and a bare `#|` line does NOT close the literal.

///|
fn block_string_tokens(src : String) -> Array[String] {
  let out : Array[String] = []
  for t in @app.lex(src) {
    if t.kind == TString {
      out.push(t.text)
    }
  }
  out
}

///|
test "a block string is one token whose chunks are joined with a newline" {
  let src = "fn f() -> String {\n  (\n    #|AAA\n    #|BBB\n  )\n}\n"
  let strs = block_string_tokens(src)
  inspect(strs.length(), content="1")
  inspect(strs[0], content="AAA\nBBB")
}

///|
test "a bare block string marker is an empty chunk, not the end of the literal" {
  // The peer treats a `#|` with nothing after it as the CLOSER. It is not: the
  // literal carries on, and the bare marker contributes an empty chunk.
  let src = "#|AAA\n#|\n#|BBB\n"
  let strs = block_string_tokens(src)
  inspect(strs.length(), content="1")
  inspect(strs[0], content="AAA\n\nBBB")
}

///|
test "a block string chunk keeps its spaces" {
  let src = "#|  x  \n"
  let strs = block_string_tokens(src)
  inspect(strs[0], content="  x  ")
}

///|
test "a blank line inside a block string is skipped" {
  let src = "#|AAA\n\n#|BBB\n"
  let strs = block_string_tokens(src)
  inspect(strs[0], content="AAA\nBBB")
}

///|
test "a line of code ends a block string" {
  // `plain` is CODE: the literal ends before it, and the rest of the file is
  // lexed normally.
  let src = "fn f() -> String {\n  #|AAA\n  let x = 1\n  x\n}\n"
  let file = @app.parse_file("t.mbt", src)
  inspect(file.funcs.length(), content="1")
  inspect(file.funcs[0].body.length(), content="3")
}

///|
test "the statement after a block string is a statement of its own" {
  // The newline that ends the LAST chunk line is the separator before the next
  // statement. While it was swallowed, the `let` and the statement after it
  // were parsed as one expression, and the file was counted as one unsupported
  // statement instead of three understood ones.
  let src = "fn f() -> Unit {\n  let s =\n    #|AAA\n  let x = 1\n  ignore(x)\n}\n"
  let file = @app.parse_file("t.mbt", src)
  inspect(file.unsupported_stmts, content="0")
  inspect(file.funcs[0].body.length(), content="3")
}

///|
test "the tokens after a block string keep their lines" {
  let src = "#|AAA\n#|BBB\nlet x = 1\n"
  let mut line = 0
  for t in @app.lex(src) {
    if t.kind == TIdent && t.text == "let" {
      line = t.line
    }
  }
  inspect(line, content="3")
}
