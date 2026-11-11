///|
#derive(Eq)
pub(all) enum TokKind {
  TOk
  TIdent
  TInt
  TDouble
  TString
  TChar
  TOp
  TNewline
  TEOF
}

///|
pub extend TokKind with Eq::{not_equal, equal}

///|
pub struct Tok {
  kind : TokKind
  text : String
  line : Int32
  col : Int32
}

///|
pub fn Tok::is_text(self : Tok, text : String) -> Bool {
  self.text == text
}

///|
pub fn Tok::is_ident(self : Tok) -> Bool {
  self.kind == TIdent
}

///|
pub fn lex(src : String) -> Array[Tok] {
  lex_at(src, 1)
}

///|
/// Lex `src` as if it started on source line `base_line`.
///
/// A contract clause is parsed out of ONE line of a file, so its tokens have to
/// carry the absolute line of that clause. Lexing the clause text on its own
/// gave every token line 1, and every contract expression then claimed to be
/// on line 1 of the file -- which is where a reader looked and did not find it.
pub fn lex_at(src : String, base_line : Int32) -> Array[Tok] {
  let toks : Array[Tok] = []
  let n = src.length()
  let mut i = 0
  let mut line = base_line
  let mut col = 1
  while i < n {
    let c = src.get_char(i).unwrap_or(' ')
    if c == '\n' {
      toks.push({ kind: TNewline, text: "\n", line, col, })
      i = i + 1
      line = line + 1
      col = 1
      continue
    }
    if is_space(c) {
      i = i + 1
      col = col + 1
      continue
    }
    if c == '/' && i + 1 < n && src.get_char(i + 1) == Some('/') {
      while i < n && src.get_char(i) != Some('\n') {
        i = i + 1
        col = col + 1
      }
      continue
    }
    if c == '/' && i + 1 < n && src.get_char(i + 1) == Some('*') {
      i = i + 2
      col = col + 2
      let mut depth = 1
      while i < n && depth > 0 {
        let d = src.get_char(i).unwrap_or(' ')
        if d == '/' && i + 1 < n && src.get_char(i + 1) == Some('*') {
          depth = depth + 1
          i = i + 2
          col = col + 2
        } else if d == '*' && i + 1 < n && src.get_char(i + 1) == Some('/') {
          depth = depth - 1
          i = i + 2
          col = col + 2
        } else if d == '\n' {
          line = line + 1
          col = 1
          i = i + 1
        } else {
          i = i + 1
          col = col + 1
        }
      }
      continue
    }
    if c == '#' && i + 1 < n && src.get_char(i + 1) == Some('|') {
      let (ni, nline, ncol) = lex_block_string(src, i, line, col, toks)
      i = ni
      line = nline
      col = ncol
      continue
    }
    if c == '"' {
      let start_line = line
      let start_col = col
      i = i + 1
      col = col + 1
      let buf = StringBuilder::new()
      let mut closed = false
      while i < n && not(closed) {
        let d = src.get_char(i).unwrap_or(' ')
        if d == '\\' && i + 1 < n {
          let e = src.get_char(i + 1).unwrap_or(' ')
          if e == 'n' {
            buf.write_char('\n')
          } else if e == 't' {
            buf.write_char('\t')
          } else if e == 'r' {
            buf.write_char('\r')
          } else if e == '"' {
            buf.write_char('"')
          } else if e == '\\' {
            buf.write_char('\\')
          } else if e == 'u' || e == 'U' {
            buf.write_char('?')
          } else {
            buf.write_char('\\')
            buf.write_char(e)
          }
          i = i + 2
          col = col + 2
        } else if d == '"' {
          closed = true
          i = i + 1
          col = col + 1
        } else if d == '\n' {
          closed = true
        } else {
          buf.write_char(d)
          i = i + 1
          col = col + 1
        }
      }
      toks.push({
        kind: TString,
        text: buf.to_string(),
        line: start_line,
        col: start_col,
      })
      continue
    }
    if c == '\'' {
      let start_col = col
      let start_line = line
      i = i + 1
      col = col + 1
      let mut ch = ' '
      if i < n {
        ch = src.get_char(i).unwrap_or(' ')
        if ch == '\\' && i + 1 < n {
          i = i + 1
          col = col + 1
          let e = src.get_char(i).unwrap_or(' ')
          ch = if e == 'n' { '\n' } else if e == 't' { '\t' } else { e }
        }
        i = i + 1
        col = col + 1
      }
      if i < n && src.get_char(i) == Some('\'') {
        i = i + 1
        col = col + 1
      }
      toks.push({
        kind: TChar,
        text: ch.to_string(),
        line: start_line,
        col: start_col,
      })
      continue
    }
    if is_digit(c) {
      let start = i
      let start_col = col
      if c == '0' &&
        i + 1 < n &&
        (src.get_char(i + 1) == Some('x') || src.get_char(i + 1) == Some('X')) {
        i = i + 2
        col = col + 2
        while i < n {
          let d = src.get_char(i).unwrap_or(' ')
          if is_digit(d) ||
            (d.to_int() >= 97 && d.to_int() <= 102) ||
            (d.to_int() >= 65 && d.to_int() <= 70) {
            i = i + 1
            col = col + 1
          } else {
            break
          }
        }
        toks.push({
          kind: TInt,
          text: src[start:i].to_string(),
          line,
          col: start_col,
        })
      } else {
        let mut is_double = false
        while i < n {
          let d = src.get_char(i).unwrap_or(' ')
          if is_digit(d) || d == '_' {
            i = i + 1
            col = col + 1
          } else if d == '.' && i + 1 < n && src.get_char(i + 1) != Some('.') {
            is_double = true
            i = i + 1
            col = col + 1
          } else if d == 'e' || d == 'E' {
            is_double = true
            i = i + 1
            col = col + 1
            if i < n &&
              (src.get_char(i) == Some('+') || src.get_char(i) == Some('-')) {
              i = i + 1
              col = col + 1
            }
          } else {
            break
          }
        }
        let text = src[start:i].to_string()
        toks.push({
          kind: if is_double {
            TDouble
          } else {
            TInt
          },
          text,
          line,
          col: start_col,
        })
      }
      continue
    }
    if is_ident_start(c) {
      let start = i
      let start_col = col
      while i < n {
        let d = src.get_char(i).unwrap_or(' ')
        if is_ident_char(d) {
          i = i + 1
          col = col + 1
        } else {
          break
        }
      }
      // The effect marker `~` belongs to the name it follows: `x~` is ONE
      // identifier, not an identifier and an operator. Left as a separate
      // token it became a statement of its own -- and a statement that
      // follows a `return` is unreachable code.
      if i < n && src.get_char(i).unwrap_or(' ') == '~' {
        i = i + 1
        col = col + 1
      }
      toks.push({
        kind: TIdent,
        text: src[start:i].to_string(),
        line,
        col: start_col,
      })
      continue
    }
    let start_col = col
    let two = if i + 1 < n { src[i:i + 2].to_string() } else { "" }
    let is_two = two == "==" ||
      two == "!=" ||
      two == "<=" ||
      two == ">=" ||
      two == "&&" ||
      two == "||" ||
      two == "<<" ||
      two == ">>" ||
      two == "+=" ||
      two == "-=" ||
      two == "*=" ||
      two == "/=" ||
      two == "%=" ||
      two == "=>" ||
      two == "->" ||
      two == ".." ||
      two == "::" ||
      two == "??" ||
      two == "|>"
    if is_two {
      toks.push({ kind: TOp, text: two, line, col: start_col, })
      i = i + 2
      col = col + 2
    } else {
      toks.push({ kind: TOp, text: c.to_string(), line, col: start_col, })
      i = i + 1
      col = col + 1
    }
  }
  toks.push({ kind: TEOF, text: "", line, col, })
  toks
}

///|
/// Lex a MoonBit multiline string literal -- the `#|` form.
///
/// `#|` opens the literal and the text after the marker is the first chunk.
/// Every following line whose first non-blank characters are `#|` is one more
/// chunk, and the value is the chunks joined with "\n".
///
/// Measured against the toolchain BY VALUE. "Does `moon check` accept it"
/// settles nothing here: the toolchain accepts every shape of this construct.
///
///   #|AAA / #|BBB           -> "AAA\nBBB"    the join is a NEWLINE
///   #|AAA / #| / #|BBB      -> "AAA\n\nBBB"  a bare `#|` is an EMPTY chunk
///   #| / #|BBB              -> "\nBBB"       a bare OPENING `#|` is an empty chunk
///   #|  x                   -> "  x"         the chunk is NOT trimmed
///   #|AAA / <blank> / #|BBB -> "AAA\nBBB"   a blank line is skipped
///   #|AAA / plain           -> "AAA"         `plain` is CODE and ends the literal
///
/// There is no `|#` terminator -- a bare `#` is a lexing error in MoonBit --
/// and a bare `#|` line does NOT close the literal: it is an empty chunk, and
/// the literal carries on to the next `#|` line.
///
/// The newline that ends the LAST chunk line is the statement separator before
/// whatever follows the literal, so it is emitted as a `TNewline` token. The
/// newlines between chunk lines are string content, and are not.
fn lex_block_string(
  src : String,
  start : Int32,
  start_line : Int32,
  start_col : Int32,
  toks : Array[Tok],
) -> (Int32, Int32, Int32) {
  let n = src.length()
  let mut pos = start + 2
  let mut line = start_line
  let mut col = start_col + 2
  let buf = StringBuilder()
  // The rest of the opening line is the first chunk, even when it is empty.
  while pos < n && src.get_char(pos) != Some('\n') {
    let d = src.get_char(pos).unwrap_or(' ')
    buf.write_char(d)
    pos = pos + 1
    col = col + 1
  }
  // The newline that ended the opening line: a chunk separator while the
  // literal continues, the end of the literal when it does not. `nl_pending`
  // tracks exactly that.
  let mut nl_line = line
  let mut nl_col = col
  let mut nl_pending = false
  if pos < n {
    nl_line = line
    nl_col = col
    nl_pending = true
    pos = pos + 1
    col = 1
    line = line + 1
  }
  while pos < n {
    // At the start of a line. A blank line is skipped: it is neither a chunk
    // nor the end of the literal.
    let mut j = pos
    let mut jcol = col
    while j < n {
      let d = src.get_char(j).unwrap_or(' ')
      if d == ' ' || d == '\t' {
        j = j + 1
        jcol = jcol + 1
      } else {
        break
      }
    }
    if j >= n {
      pos = j
      col = jcol
      break
    }
    let d = src.get_char(j).unwrap_or(' ')
    if d == '\n' {
      // A blank line. The newline before it was a separator, not the end of
      // the literal; the blank line's own newline is the one in play now.
      nl_pending = false
      nl_line = line
      nl_col = jcol
      nl_pending = true
      pos = j + 1
      col = 1
      line = line + 1
      continue
    }
    if !(d == '#' && j + 1 < n && src.get_char(j + 1) == Some('|')) {
      // The first non-blank character is not `#|`: this line is CODE, and the
      // literal ends before it. `pos` still points at the start of that line,
      // so the caller lexes it normally.
      break
    }
    // A chunk line: skip the leading whitespace and the marker, and take the
    // rest of the line as the chunk text. The newline before it was a chunk
    // separator, not the end of the literal.
    nl_pending = false
    buf.write_char('\n')
    let mut k = j + 2
    let mut kcol = jcol + 2
    while k < n && src.get_char(k) != Some('\n') {
      let e = src.get_char(k).unwrap_or(' ')
      buf.write_char(e)
      k = k + 1
      kcol = kcol + 1
    }
    pos = k
    col = kcol
    if k < n {
      nl_line = line
      nl_col = kcol
      nl_pending = true
      pos = k + 1
      col = 1
      line = line + 1
    }
  }
  toks.push({
    kind: TString,
    text: buf.to_string(),
    line: start_line,
    col: start_col,
  })
  if nl_pending {
    // The newline that ended the literal: the separator before whatever comes
    // next. Without it the statement after the literal ran into it.
    toks.push({ kind: TNewline, text: "\n", line: nl_line, col: nl_col, })
  }
  (pos, line, col)
}
