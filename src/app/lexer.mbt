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
  let toks : Array[Tok] = []
  let n = src.length()
  let mut i = 0
  let mut line = 1
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
      let start_line = line
      let start_col = col
      i = i + 2
      col = col + 2
      let start = i
      while i < n && src.get_char(i) != Some('\n') {
        i = i + 1
        col = col + 1
      }
      toks.push({
        kind: TString,
        text: src[start:i].to_owned(),
        line: start_line,
        col: start_col,
      })
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
