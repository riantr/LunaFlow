///|
struct P {
  toks : Array[Tok]
  file : String
  mut i : Int32
  mut next_id : Int32
  mut paren : Int32
  issues : Array[ParseIssue]
  mut parsed : Int32
  mut unsupported : Int32
  mut depth : Int32
}

///|
/// Maximum expression/statement nesting the structural parser will descend.
/// Untrusted modules can nest `if`/`(` far enough to exhaust the native stack
/// (measured: `if` × 5000 and `(` × 2000 abort with 0xC0000409). Beyond this
/// limit the construct degrades to a recorded parse issue, not a crash.
const MAX_PARSE_DEPTH : Int32 = 256

///|
fn P::new(file : String, toks : Array[Tok]) -> P {
  {
    toks,
    file,
    i: 0,
    next_id: 0,
    paren: 0,
    issues: [],
    parsed: 0,
    unsupported: 0,
    depth: 0,
  }
}

///|
fn P::note_depth_limit(self : P) -> Unit {
  let t = self.peek()
  self.issues.push({
    file: self.file,
    line: t.line,
    message: "nesting deeper than \{MAX_PARSE_DEPTH}; the rest of the construct is skipped and counted as a gap",
  })
  self.unsupported = self.unsupported + 1
}

///|
/// Consume the rest of the current construct after a depth-limit trip: stop at a
/// newline or a `;` on the balanced level, or before a closer that belongs to an
/// enclosing construct. Skipping a *region* (not one token) is what keeps the
/// "statements understood" count honest on hostile input.
fn P::skip_rest_of_construct(self : P) -> Unit {
  let mut depth = 0
  while !self.eof() {
    let t = self.peek()
    if depth == 0 {
      if t.kind == TNewline ||
        t.text == ";" ||
        t.text == ")" ||
        t.text == "]" ||
        t.text == "}" {
        return
      }
    }
    if t.text == "(" || t.text == "[" || t.text == "{" {
      depth = depth + 1
    } else if t.text == ")" || t.text == "]" || t.text == "}" {
      depth = depth - 1
    }
    ignore(self.bump())
  }
}

///|
fn P::too_deep_expr(self : P) -> Expr {
  let t = self.peek()
  self.note_depth_limit()
  self.skip_rest_of_construct()
  Expr::unknown(span_from(t, t, self.file), "nesting-limit")
}

///|
fn P::peek(self : P) -> Tok {
  if self.i < self.toks.length() {
    self.toks[self.i]
  } else {
    { kind: TEOF, text: "", line: 0, col: 0, }
  }
}

///|
fn P::peek_at(self : P, off : Int32) -> Tok {
  let j = self.i + off
  if j >= 0 && j < self.toks.length() {
    self.toks[j]
  } else {
    { kind: TEOF, text: "", line: 0, col: 0, }
  }
}

///|
fn P::bump(self : P) -> Tok {
  let t = self.peek()
  if self.i < self.toks.length() {
    self.i = self.i + 1
  }
  t
}

///|
fn P::at(self : P, text : String) -> Bool {
  self.peek().text == text
}

///|
fn P::at_off(self : P, off : Int32, text : String) -> Bool {
  self.peek_at(off).text == text
}

///|
fn P::eof(self : P) -> Bool {
  self.peek().kind == TEOF
}

///|
fn P::skip_newlines(self : P) -> Unit {
  while self.peek().kind == TNewline || self.peek().text == ";" {
    ignore(self.bump())
  }
}

///|
fn P::skip_all_newlines(self : P) -> Unit {
  while self.peek().kind == TNewline {
    ignore(self.bump())
  }
}

///|
fn P::next_stmt_id(self : P) -> Int32 {
  let id = self.next_id
  self.next_id = self.next_id + 1
  id
}

///|
fn P::last_tok(self : P) -> Tok {
  let j = if self.i > 0 { self.i - 1 } else { 0 }
  if j < self.toks.length() {
    self.toks[j]
  } else {
    self.peek()
  }
}

///|
fn span_from(start : Tok, stop : Tok, file : String) -> Span {
  Span::new(
    file,
    start.line,
    start.col,
    stop.line,
    stop.col + stop.text.length(),
  )
}

///|
fn render_tokens(toks : Array[Tok], from : Int32, to : Int32) -> String {
  let out = StringBuilder::new()
  let mut started = false
  let mut j = from
  while j < to && j < toks.length() {
    let t = toks[j]
    if t.kind != TNewline {
      let prev = if j > from { Some(toks[j - 1]) } else { None }
      let kw_before = match prev {
        Some(p) =>
          p.text == "in" ||
          p.text == "for" ||
          p.text == "if" ||
          p.text == "while" ||
          p.text == "return" ||
          p.text == "let" ||
          p.text == "match" ||
          p.text == "else"
        None => false
      }
      let no_space_before = (t.text == "[" && !kw_before) ||
        t.text == "," ||
        t.text == ")" ||
        t.text == "]" ||
        t.text == "}" ||
        t.text == "." ||
        t.text == "::" ||
        t.text == "("
      let prev_open = match prev {
        Some(p) =>
          p.text == "(" ||
          p.text == "[" ||
          p.text == "." ||
          p.text == "::" ||
          p.text == "@"
        None => true
      }
      if started && !no_space_before && !prev_open {
        out.write_char(' ')
      }
      out.write_string(t.text)
      started = true
    }
    j = j + 1
  }
  out.to_string()
}

///|
fn parse_int_literal(s : String) -> Int32 {
  if s.length() > 2 &&
    s.get_char(0) == Some('0') &&
    (s.get_char(1) == Some('x') || s.get_char(1) == Some('X')) {
    let mut v = 0
    let mut i = 2
    while i < s.length() {
      let c = s.get_char(i).unwrap_or('0')
      let d = if is_digit(c) {
        c.to_int() - 48
      } else if c.to_int() >= 97 && c.to_int() <= 102 {
        c.to_int() - 87
      } else if c.to_int() >= 65 && c.to_int() <= 70 {
        c.to_int() - 55
      } else {
        0
      }
      v = v * 16 + d
      i = i + 1
    }
    v
  } else {
    parse_int(s.replace_all(old="_", new="").to_string(), 0)
  }
}

///|
fn parse_double_literal(s : String) -> Double {
  let t = s.replace_all(old="_", new="").to_string()
  let mut i = 0
  let mut sign = 1.0
  if t.get_char(0) == Some('-') {
    sign = -1.0
    i = 1
  }
  let mut int_part = 0.0
  while i < t.length() && is_digit(t.get_char(i).unwrap_or(' ')) {
    int_part = int_part * 10.0 +
      (t.get_char(i).unwrap_or('0').to_int() - 48).to_double()
    i = i + 1
  }
  let mut frac = 0.0
  let mut scale = 1.0
  if i < t.length() && t.get_char(i) == Some('.') {
    i = i + 1
    while i < t.length() && is_digit(t.get_char(i).unwrap_or(' ')) {
      frac = frac * 10.0 +
        (t.get_char(i).unwrap_or('0').to_int() - 48).to_double()
      scale = scale * 10.0
      i = i + 1
    }
  }
  let mut value = int_part + frac / scale
  if i < t.length() &&
    (t.get_char(i) == Some('e') || t.get_char(i) == Some('E')) {
    i = i + 1
    let mut esign = 1.0
    if i < t.length() && t.get_char(i) == Some('-') {
      esign = -1.0
      i = i + 1
    } else if i < t.length() && t.get_char(i) == Some('+') {
      i = i + 1
    }
    let mut e = 0.0
    while i < t.length() && is_digit(t.get_char(i).unwrap_or(' ')) {
      e = e * 10.0 + (t.get_char(i).unwrap_or('0').to_int() - 48).to_double()
      i = i + 1
    }
    let mut k = 0.0
    while k < e {
      value = value * 10.0
      k = k + 1.0
    }
    if esign < 0.0 {
      let mut k2 = 0.0
      while k2 < e {
        value = value / 10.0
        k2 = k2 + 1.0
      }
    }
  }
  sign * value
}

///|
fn binop_of(text : String) -> BinOp? {
  match text {
    "+" => Some(OpAdd)
    "-" => Some(OpSub)
    "*" => Some(OpMul)
    "/" => Some(OpDiv)
    "%" => Some(OpMod)
    "==" => Some(OpEq)
    "!=" => Some(OpNe)
    "<" => Some(OpLt)
    "<=" => Some(OpLe)
    ">" => Some(OpGt)
    ">=" => Some(OpGe)
    "&&" => Some(OpAnd)
    "||" => Some(OpOr)
    "&" => Some(OpBitAnd)
    "|" => Some(OpBitOr)
    "^" => Some(OpBitXor)
    "<<" => Some(OpShl)
    ">>" => Some(OpShr)
    _ => None
  }
}

///|
fn prec_of(op : BinOp) -> Int32 {
  match op {
    OpOr => 1
    OpAnd => 2
    OpBitOr => 3
    OpBitXor => 4
    OpBitAnd => 5
    OpEq | OpNe => 6
    OpLt | OpLe | OpGt | OpGe => 7
    OpShl | OpShr => 8
    OpAdd | OpSub => 9
    OpMul | OpDiv | OpMod => 10
  }
}

///|
fn parse_expr(p : P, min_prec : Int32) -> Expr {
  if p.depth >= MAX_PARSE_DEPTH {
    return p.too_deep_expr()
  }
  p.depth = p.depth + 1
  let mut left = parse_unary(p)
  while true {
    if p.paren > 0 {
      p.skip_all_newlines()
    }
    let t = p.peek()
    match binop_of(t.text) {
      Some(op) => {
        let prec = prec_of(op)
        if prec < min_prec {
          break
        }
        let op_tok = p.bump()
        let right = parse_expr(p, prec + 1)
        let span = left.span.merge(right.span)
        left = Expr::new(span, EBin(op, left, right))
        ignore(op_tok)
      }
      None => break
    }
  }
  p.depth = p.depth - 1
  left
}

///|
fn parse_unary(p : P) -> Expr {
  if p.depth >= MAX_PARSE_DEPTH {
    return p.too_deep_expr()
  }
  p.depth = p.depth + 1
  let t = p.peek()
  let out = if t.text == "-" {
    let start = p.bump()
    let e = parse_unary(p)
    Expr::new(span_from(start, p.last_tok(), p.file), EUn(UnNeg, e))
  } else if t.text == "!" {
    let start = p.bump()
    let e = parse_unary(p)
    Expr::new(span_from(start, p.last_tok(), p.file), EUn(UnNot, e))
  } else {
    parse_postfix(p)
  }
  p.depth = p.depth - 1
  out
}

///|
fn parse_postfix(p : P) -> Expr {
  let mut e = parse_primary(p)
  while true {
    if p.paren > 0 {
      p.skip_all_newlines()
    }
    let t = p.peek()
    if t.text == "(" {
      let args = parse_call_args(p)
      let name = match e.kind {
        EName(n) => n
        _ => e.render()
      }
      let span = span_from(
        {
          kind: TIdent,
          text: "",
          line: e.span.start_line,
          col: e.span.start_col,
        },
        p.last_tok(),
        p.file,
      )
      e = Expr::new(span, ECall(name, args))
    } else if t.text == "[" {
      let start = p.peek()
      ignore(p.bump())
      p.paren = p.paren + 1
      let idx = parse_expr(p, 0)
      p.paren = p.paren - 1
      p.skip_all_newlines()
      if p.at("]") {
        ignore(p.bump())
      }
      let span = Span::new(
        p.file,
        start.line,
        start.col,
        p.last_tok().line,
        p.last_tok().col,
      )
      e = Expr::new(span, EIndex(e, idx))
    } else if t.text == "." {
      ignore(p.bump())
      p.skip_all_newlines()
      let f = p.bump()
      if p.at("(") {
        let args = parse_call_args(p)
        let span = Span::new(
          p.file,
          e.span.start_line,
          e.span.start_col,
          p.last_tok().line,
          p.last_tok().col,
        )
        e = Expr::new(span, EMethod(e, f.text, args))
      } else {
        let span = Span::new(
          p.file,
          e.span.start_line,
          e.span.start_col,
          f.line,
          f.col + f.text.length(),
        )
        e = Expr::new(span, EField(e, f.text))
      }
    } else if t.text == "?" {
      ignore(p.bump())
    } else {
      break
    }
  }
  e
}

///|
fn parse_call_args(p : P) -> Array[Expr] {
  let args : Array[Expr] = []
  if not(p.at("(")) {
    return args
  }
  ignore(p.bump())
  p.paren = p.paren + 1
  p.skip_all_newlines()
  while !p.at(")") && !p.eof() {
    let e = parse_expr(p, 0)
    args.push(e)
    p.skip_all_newlines()
    if p.at(",") {
      ignore(p.bump())
      p.skip_all_newlines()
    } else {
      break
    }
  }
  p.skip_all_newlines()
  if p.at(")") {
    ignore(p.bump())
  }
  p.paren = p.paren - 1
  args
}

///|
fn parse_primary(p : P) -> Expr {
  let t = p.peek()
  match t.kind {
    TInt => {
      ignore(p.bump())
      Expr::new(span_from(t, t, p.file), EInt(parse_int_literal(t.text)))
    }
    TDouble => {
      ignore(p.bump())
      Expr::new(span_from(t, t, p.file), EDouble(parse_double_literal(t.text)))
    }
    TString => {
      ignore(p.bump())
      Expr::new(span_from(t, t, p.file), EString(t.text))
    }
    TChar => {
      ignore(p.bump())
      Expr::new(span_from(t, t, p.file), EString(t.text))
    }
    TIdent =>
      if t.text == "true" || t.text == "false" {
        ignore(p.bump())
        Expr::new(span_from(t, t, p.file), EBool(t.text == "true"))
      } else if t.text == "if" {
        ignore(p.bump())
        Expr::unknown(span_from(t, t, p.file), "if-expression")
      } else if t.text == "match" {
        ignore(p.bump())
        Expr::unknown(span_from(t, t, p.file), "match-expression")
      } else {
        ignore(p.bump())
        Expr::new(span_from(t, t, p.file), EName(t.text))
      }
    _ =>
      if t.text == "(" {
        ignore(p.bump())
        p.paren = p.paren + 1
        p.skip_all_newlines()
        let first = parse_expr(p, 0)
        let items : Array[Expr] = [first]
        p.skip_all_newlines()
        while p.at(",") {
          ignore(p.bump())
          p.skip_all_newlines()
          if p.at(")") {
            break
          }
          items.push(parse_expr(p, 0))
          p.skip_all_newlines()
        }
        p.paren = p.paren - 1
        if p.at(")") {
          ignore(p.bump())
        }
        let span = span_from(t, p.last_tok(), p.file)
        if items.length() == 1 {
          Expr::new(span, items[0].kind)
        } else {
          Expr::new(span, ETuple(items))
        }
      } else if t.text == "[" {
        ignore(p.bump())
        p.paren = p.paren + 1
        p.skip_all_newlines()
        let items : Array[Expr] = []
        while !p.at("]") && !p.eof() {
          items.push(parse_expr(p, 0))
          p.skip_all_newlines()
          if p.at(",") {
            ignore(p.bump())
            p.skip_all_newlines()
          } else {
            break
          }
        }
        p.paren = p.paren - 1
        if p.at("]") {
          ignore(p.bump())
        }
        Expr::new(span_from(t, p.last_tok(), p.file), EArray(items))
      } else if t.text == "@" {
        let start = p.bump()
        let name = p.bump()
        let span = span_from(start, name, p.file)
        Expr::new(span, EName("@" + name.text))
      } else if t.kind == TEOF ||
        t.text == "}" ||
        t.text == ")" ||
        t.text == "]" {
        Expr::unknown(span_from(t, t, p.file), "")
      } else {
        ignore(p.bump())
        Expr::unknown(span_from(t, t, p.file), t.text)
      }
  }
}

///|
fn collect_type(p : P, stop_at_paren : Bool) -> String {
  let start = p.i
  let mut depth = 0
  while !p.eof() {
    let t = p.peek()
    if t.kind == TNewline && depth == 0 {
      break
    }
    if t.text == "," && depth == 0 {
      break
    }
    if t.text == ")" && depth == 0 && stop_at_paren {
      break
    }
    if t.text == "{" && depth == 0 {
      break
    }
    if t.text == "(" || t.text == "[" || t.text == "<" {
      depth = depth + 1
    } else if t.text == ")" || t.text == "]" || t.text == ">" {
      if depth == 0 {
        break
      }
      depth = depth - 1
    }
    ignore(p.bump())
  }
  let t = render_tokens(p.toks, start, p.i)
  if t == "" {
    "Unknown"
  } else {
    t
  }
}

///|
fn skip_balanced_braces(p : P) -> Unit {
  if !p.at("{") {
    return
  }
  let mut depth = 0
  while !p.eof() {
    let t = p.bump()
    if t.text == "{" {
      depth = depth + 1
    } else if t.text == "}" {
      depth = depth - 1
      if depth == 0 {
        return
      }
    }
  }
}

///|
fn parse_block(p : P) -> Array[Stmt] {
  let out : Array[Stmt] = []
  p.skip_all_newlines()
  if !p.at("{") {
    return out
  }
  if p.depth >= MAX_PARSE_DEPTH {
    p.note_depth_limit()
    skip_balanced_braces(p)
    return out
  }
  p.depth = p.depth + 1
  ignore(p.bump())
  while !p.eof() && !p.at("}") {
    p.skip_newlines()
    if p.at("}") || p.eof() {
      break
    }
    let before = p.i
    match parse_stmt(p) {
      Some(s) => out.push(s)
      None => ()
    }
    if p.i == before {
      ignore(p.bump())
    }
  }
  if p.at("}") {
    ignore(p.bump())
  }
  p.depth = p.depth - 1
  out
}

///|
fn parse_stmt(p : P) -> Stmt? {
  p.skip_newlines()
  if p.at("}") || p.eof() {
    return None
  }
  let start = p.peek()
  let start_i = p.i
  let t = p.peek()
  let kind : StmtKind = if t.text == "let" {
    parse_let(p)
  } else if t.text == "if" {
    parse_if(p)
  } else if t.text == "while" {
    parse_while(p)
  } else if t.text == "for" {
    parse_for(p)
  } else if t.text == "return" {
    ignore(p.bump())
    p.skip_all_newlines()
    let e = if p.at("}") || p.peek().kind == TNewline || p.eof() || p.at(";") {
      None
    } else {
      Some(parse_expr(p, 0))
    }
    SReturn(e)
  } else if t.text == "break" {
    ignore(p.bump())
    SBreak
  } else if t.text == "continue" {
    ignore(p.bump())
    SContinue
  } else if t.text == "match" {
    ignore(p.bump())
    while not(p.at("{") && !p.eof() && p.peek().kind != TNewline) {
      ignore(p.bump())
    }
    skip_balanced_braces(p)
    p.unsupported = p.unsupported + 1
    SUnsupported("match")
  } else if t.text == "try" {
    ignore(p.bump())
    p.skip_all_newlines()
    let body = parse_block(p)
    p.skip_all_newlines()
    if p.at("catch") {
      ignore(p.bump())
      p.skip_all_newlines()
      skip_balanced_braces(p)
    }
    STry(body)
  } else if t.text == "struct" ||
    t.text == "enum" ||
    t.text == "impl" ||
    t.text == "trait" {
    skip_balanced_braces(p)
    p.unsupported = p.unsupported + 1
    SUnsupported(t.text)
  } else {
    let lhs = parse_expr(p, 0)
    if p.at("=") {
      ignore(p.bump())
      p.skip_all_newlines()
      let rhs = parse_expr(p, 0)
      SAssign(lhs, rhs)
    } else if p.at("+=") || p.at("-=") || p.at("*=") || p.at("/=") || p.at("%=") {
      let op_tok = p.bump()
      let op = if op_tok.text == "+=" {
        OpAdd
      } else if op_tok.text == "-=" {
        OpSub
      } else if op_tok.text == "*=" {
        OpMul
      } else if op_tok.text == "/=" {
        OpDiv
      } else {
        OpMod
      }
      p.skip_all_newlines()
      let rhs = parse_expr(p, 0)
      SAssignOp(op, lhs, rhs)
    } else {
      SExpr(lhs)
    }
  }
  let stop = p.last_tok()
  let span = span_from(start, stop, p.file)
  let text = render_tokens(p.toks, start_i, p.i)
  p.parsed = p.parsed + 1
  if kind is SUnsupported(_) {
    p.unsupported = p.unsupported + 0
  }
  Some(Stmt::new(p.next_stmt_id(), span, kind, text))
}

///|
fn parse_let(p : P) -> StmtKind {
  ignore(p.bump())
  if p.at("mut") {
    ignore(p.bump())
  }
  if p.at("(") || p.at("[") {
    skip_balanced_braces(p)
    if p.at("=") {
      ignore(p.bump())
      let e = parse_expr(p, 0)
      SLet("_destructured", "", e)
    } else {
      SUnsupported("let-destructure")
    }
  } else {
    let name = p.bump()
    let mut ty = ""
    if p.at(":") {
      ignore(p.bump())
      ty = collect_type(p, false)
    }
    if p.at("=") {
      ignore(p.bump())
      p.skip_all_newlines()
      let e = parse_expr(p, 0)
      SLet(name.text, ty, e)
    } else if p.peek().kind == TNewline || p.at("}") {
      SLet(name.text, ty, Expr::unknown(span_from(name, name, p.file), ""))
    } else {
      p.skip_all_newlines()
      let e = parse_expr(p, 0)
      SLet(name.text, ty, e)
    }
  }
}

///|
fn parse_if(p : P) -> StmtKind {
  ignore(p.bump())
  let cond = parse_expr(p, 0)
  p.skip_all_newlines()
  let then_body = parse_block(p)
  let else_body : Array[Stmt] = []
  p.skip_all_newlines()
  if p.at("else") {
    ignore(p.bump())
    p.skip_all_newlines()
    if p.at("if") {
      let nested = parse_if(p)
      else_body.push(
        Stmt::new(
          p.next_stmt_id(),
          span_from(p.peek(), p.peek(), p.file),
          nested,
          "else if",
        ),
      )
    } else {
      let b = parse_block(p)
      for s in b {
        else_body.push(s)
      }
    }
  }
  SIf(cond, then_body, else_body)
}

///|
fn parse_while(p : P) -> StmtKind {
  ignore(p.bump())
  let cond = parse_expr(p, 0)
  p.skip_all_newlines()
  let body = parse_block(p)
  SWhile(cond, body)
}

///|
fn parse_update(p : P) -> Expr {
  let lhs = parse_expr(p, 0)
  if p.at("=") {
    ignore(p.bump())
    p.skip_all_newlines()
    let rhs = parse_expr(p, 0)
    let span = lhs.span.merge(rhs.span)
    Expr::unknown(span, lhs.render() + " = " + rhs.render())
  } else if p.at("+=") || p.at("-=") || p.at("*=") || p.at("/=") || p.at("%=") {
    let op = p.bump()
    p.skip_all_newlines()
    let rhs = parse_expr(p, 0)
    let span = lhs.span.merge(rhs.span)
    Expr::unknown(span, lhs.render() + " " + op.text + " " + rhs.render())
  } else {
    lhs
  }
}

///|
fn parse_for(p : P) -> StmtKind {
  ignore(p.bump())
  p.skip_all_newlines()
  let first = p.bump()
  if p.at("in") {
    ignore(p.bump())
    let iter = parse_expr(p, 0)
    p.skip_all_newlines()
    let body = parse_block(p)
    SForIn(first.text, iter, body)
  } else if p.at("=") {
    ignore(p.bump())
    let init = parse_expr(p, 0)
    if p.at(",") {
      p.skip_all_newlines()
      skip_balanced_braces(p)
      p.unsupported = p.unsupported + 1
      return SUnsupported("functional-for")
    }
    if !p.at(";") {
      p.unsupported = p.unsupported + 1
      skip_balanced_braces(p)
      return SUnsupported("for-header")
    }
    ignore(p.bump())
    let cond = parse_expr(p, 0)
    p.skip_all_newlines()
    let step = if p.at(";") {
      ignore(p.bump())
      parse_update(p)
    } else if p.at("{") {
      Expr::unknown(span_from(first, first, p.file), "")
    } else {
      parse_update(p)
    }
    p.skip_all_newlines()
    let body = parse_block(p)
    SFor(first.text, init, cond, step, body)
  } else {
    p.unsupported = p.unsupported + 1
    skip_balanced_braces(p)
    SUnsupported("for")
  }
}

///|
fn parse_params(p : P) -> Array[Param] {
  let out : Array[Param] = []
  if not(p.at("(")) {
    return out
  }
  ignore(p.bump())
  p.paren = p.paren + 1
  while !p.at(")") && !p.eof() {
    p.skip_all_newlines()
    if p.at(")") || p.eof() {
      break
    }
    if p.at(",") {
      ignore(p.bump())
      continue
    }
    let name = p.bump()
    if name.kind != TIdent {
      if p.at(")") {
        break
      }
      continue
    }
    let mut param_name = name.text
    if p.at("~") || p.at("?") {
      ignore(p.bump())
    }
    let mut ty = ""
    if p.at(":") {
      ignore(p.bump())
      ty = collect_type(p, true)
    }
    let mut default : Expr? = None
    if p.at("=") {
      ignore(p.bump())
      default = Some(parse_expr(p, 0))
    }
    out.push(Param::new(param_name, ty, default))
    ignore(param_name)
    param_name = ""
    if p.at(",") {
      ignore(p.bump())
    }
  }
  p.paren = p.paren - 1
  if p.at(")") {
    ignore(p.bump())
  }
  out
}

///|
fn parse_fn(p : P, is_test : Bool, test_name : String) -> Func? {
  let start = p.peek()
  if p.at("fn") {
    ignore(p.bump())
  }
  p.skip_all_newlines()
  if p.at("[") {
    skip_balanced_brackets(p)
  }
  let mut name = if is_test { "test " + test_name } else { "" }
  if !is_test {
    let first = p.bump()
    if first.kind != TIdent {
      return None
    }
    name = first.text
    while p.at("::") {
      ignore(p.bump())
      let part = p.bump()
      name = name + "::" + part.text
    }
    if p.at("[") {
      skip_balanced_brackets(p)
    }
  }
  let params = parse_params(p)
  let mut ret_ty = "Unit"
  p.skip_all_newlines()
  if p.at("->") {
    ignore(p.bump())
    ret_ty = collect_type(p, false)
  }
  p.skip_all_newlines()
  if !p.at("{") {
    p.issues.push({
      file: p.file,
      line: start.line,
      message: "function '\{name}' has no body (declaration or extern)",
    })
    return None
  }
  let body = parse_block(p)
  let stop = p.last_tok()
  let span = span_from(start, stop, p.file)
  Some({
    name,
    params,
    ret_ty,
    body,
    span,
    file: p.file,
    is_test,
    start_line: start.line,
    end_line: stop.line,
    contract: Contract::empty(),
  })
}

///|
fn skip_balanced_brackets(p : P) -> Unit {
  if !p.at("[") {
    return
  }
  let mut depth = 0
  while !p.eof() {
    let t = p.bump()
    if t.text == "[" {
      depth = depth + 1
    } else if t.text == "]" {
      depth = depth - 1
      if depth == 0 {
        return
      }
    }
  }
}

///|
pub fn parse_file(path : String, text : String) -> SourceFile {
  let toks = lex(text)
  let p = P::new(path, toks)
  let funcs : Array[Func] = []
  let mut depth = 0
  while !p.eof() {
    let t = p.peek()
    if t.text == "{" {
      depth = depth + 1
      ignore(p.bump())
    } else if t.text == "}" {
      if depth > 0 {
        depth = depth - 1
      }
      ignore(p.bump())
    } else if depth == 0 && t.kind == TIdent && t.text == "fn" {
      p.skip_all_newlines()
      match parse_fn(p, false, "") {
        Some(f) => {
          f.contract = contract_above(text, path, f.start_line)
          funcs.push(f)
        }
        None => ignore(p.bump())
      }
    } else if depth == 0 && t.kind == TIdent && t.text == "test" {
      ignore(p.bump())
      p.skip_all_newlines()
      let nt = p.peek()
      let tname = if nt.kind == TString {
        ignore(p.bump())
        nt.text
      } else {
        ignore(p.bump())
        nt.text
      }
      p.skip_all_newlines()
      match parse_fn(p, true, tname) {
        Some(f) => funcs.push(f)
        None => ignore(p.bump())
      }
    } else {
      ignore(p.bump())
    }
  }
  let issues = p.issues.copy()
  let parsed = p.parsed
  let unsupported = p.unsupported
  let f = SourceFile::new(path, text)
  f.funcs.clear()
  for fn_name in funcs {
    f.funcs.push(fn_name)
  }
  for issue in issues {
    f.issues.push(issue)
  }
  f.parsed_stmts = parsed
  f.unsupported_stmts = unsupported
  f
}

///|
pub fn parse_manifest_version(text : String) -> String {
  for line in split_lines(text) {
    let t = line.trim().to_owned()
    if t.has_prefix("version") {
      let parts = split_commas(t)
      if parts.length() > 0 && parts[0] == "version = \"\"" {
        ()
      }
      let mut i = 0
      while i < t.length() {
        if t.get_char(i) == Some('"') {
          let mut j = i + 1
          while j < t.length() && t.get_char(j) != Some('"') {
            j = j + 1
          }
          return t[i + 1:j].to_string()
        }
        i = i + 1
      }
    }
  }
  "0.0.0"
}
