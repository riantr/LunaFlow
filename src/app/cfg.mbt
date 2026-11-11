///|
struct Builder {
  nodes : Array[CfgNode]
  edges : Array[CfgEdge]
  fn_name : String
  file : String
  mut exit : Int32
}

///|
fn Builder::new(fn_name : String, file : String) -> Builder {
  let nodes : Array[CfgNode] = []
  let edges : Array[CfgEdge] = []
  { nodes, edges, fn_name, file, exit: -1, }
}

///|
fn Builder::node(
  self : Builder,
  kind : NodeKind,
  label : String,
  span : Span,
  stmt : Int32,
) -> Int32 {
  let id = self.nodes.length()
  self.nodes.push({
    id,
    kind,
    label,
    fn_name: self.fn_name,
    file: self.file,
    line: span.start_line,
    stmt,
  })
  id
}

///|
fn Builder::edge(
  self : Builder,
  from : Int32,
  to : Int32,
  kind : EdgeKind,
) -> Unit {
  if from >= 0 && to >= 0 {
    self.edges.push({ from, to, kind, })
  }
}

///|
fn literal_bool(e : Expr) -> Bool? {
  match e.kind {
    EBool(b) => Some(b)
    EInt(n) => Some(n != 0)
    EName(n) =>
      if n == "true" {
        Some(true)
      } else if n == "false" {
        Some(false)
      } else {
        None
      }
    _ => None
  }
}

///|
fn has_break_or_return(stmts : Array[Stmt]) -> Bool {
  for s in stmts {
    match s.kind {
      SBreak | SContinue | SReturn(_) => return true
      SIf(_, a, b) =>
        if has_break_or_return(a) || has_break_or_return(b) {
          return true
        }
      SWhile(_, body) | SForIn(_, _, body) =>
        if has_break_or_return(body) {
          return true
        }
      SFor(_, _, _, _, body) | SBlock(body) | STry(body) =>
        if has_break_or_return(body) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
/// True when the block contains a construct the parser did not model.
///
/// Such a construct may hold a `break` or a `return` that the CFG cannot
/// see. A loop whose body holds one of them is therefore not proven infinite,
/// and the code after it is not proven unreachable. The analyzer claims what
/// it can support and discloses the gap instead of guessing -- the same rule
/// the parser follows when it folds an unmodelled tail into its statement.
fn has_gap(stmts : Array[Stmt]) -> Bool {
  for s in stmts {
    match s.kind {
      SUnsupported(_) => return true
      SIf(_, a, b) => if has_gap(a) || has_gap(b) { return true }
      SWhile(_, body) | SForIn(_, _, body) => if has_gap(body) { return true }
      SFor(_, _, _, _, body) | SBlock(body) | STry(body) =>
        if has_gap(body) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn is_infinite_loop(cond : Expr, body : Array[Stmt]) -> Bool {
  let t = literal_bool(cond)
  match t {
    Some(true) => !has_break_or_return(body)
    _ => false
  }
}

///|
fn emit_stmts(
  b : Builder,
  stmts : Array[Stmt],
  start : Int32,
  start_dead : Bool,
) -> (Int32, Bool) {
  let mut cur = start
  let mut dead = start_dead
  for s in stmts {
    if dead {
      let d = b.node(NDead, "dead: " + s.text, s.span, s.id)
      ignore(d)
    } else {
      match s.kind {
        SIf(cond, then_b, else_b) => {
          let c = b.node(NBranch, "if " + cond.render(), s.span, s.id)
          b.edge(cur, c, ESeq)
          let t_before = b.nodes.length()
          let tcur = emit_stmts(b, then_b, -1, false).0
          let tfirst = if b.nodes.length() > t_before { t_before } else { -1 }
          let e_before = b.nodes.length()
          let ecur = if else_b.length() > 0 {
            emit_stmts(b, else_b, -1, false).0
          } else {
            -1
          }
          let efirst = if b.nodes.length() > e_before { e_before } else { -1 }
          if tfirst >= 0 {
            b.edge(c, tfirst, ETrue)
          }
          if efirst >= 0 {
            b.edge(c, efirst, EFalse)
          }
          let tterm = stmts_always_exit(then_b)
          let eterm = if else_b.length() > 0 {
            stmts_always_exit(else_b)
          } else {
            false
          }
          if tterm && eterm {
            cur = -1
            dead = true
          } else {
            let m = b.node(NMerge, "merge", s.span, s.id)
            if !tterm {
              if tcur >= 0 {
                b.edge(tcur, m, ESeq)
              } else {
                b.edge(c, m, ETrue)
              }
            }
            if else_b.length() == 0 {
              b.edge(c, m, EFalse)
            } else if !eterm {
              if ecur >= 0 {
                b.edge(ecur, m, ESeq)
              } else {
                b.edge(c, m, EFalse)
              }
            }
            cur = m
          }
        }
        SWhile(cond, body) => {
          let h = b.node(NLoop, "while " + cond.render(), s.span, s.id)
          b.edge(cur, h, ESeq)
          let b_before = b.nodes.length()
          let _ = emit_stmts(b, body, -1, false)
          if b.nodes.length() > b_before {
            b.edge(h, b_before, ETrue)
          }
          let body_exit = last_node(b, body, h)
          b.edge(body_exit, h, EBack)
          let after = b.node(NMerge, "after-loop", s.span, s.id)
          match literal_bool(cond) {
            Some(true) =>
              if !has_break_or_return(body) && !has_gap(body) {
                dead = true
                cur = -1
              } else {
                // The body may hold a `break` the CFG cannot see -- inside a
                // `match` arm, for instance, which the parser does not model.
                // Then the loop may end, and the code after it is reachable.
                b.edge(h, after, EFalse)
                cur = after
              }
            _ => {
              b.edge(h, after, EFalse)
              cur = after
            }
          }
        }
        SFor(_, init, cond, step, body) => {
          let i = b.node(NStmt, "for-init " + init.render(), s.span, s.id)
          b.edge(cur, i, ESeq)
          let h = b.node(NLoop, "for " + cond.render(), s.span, s.id)
          b.edge(i, h, ESeq)
          let b_before = b.nodes.length()
          let _ = emit_stmts(b, body, -1, false)
          if b.nodes.length() > b_before {
            b.edge(h, b_before, ETrue)
          }
          ignore(step)
          b.edge(last_node(b, body, h), h, EBack)
          let after = b.node(NMerge, "after-loop", s.span, s.id)
          b.edge(h, after, EFalse)
          cur = after
        }
        SForIn(names, iter, body) => {
          let h = b.node(
            NLoop,
            "for " + names.join(", ") + " in " + iter.render(),
            s.span,
            s.id,
          )
          b.edge(cur, h, ESeq)
          let b_before = b.nodes.length()
          let _ = emit_stmts(b, body, -1, false)
          if b.nodes.length() > b_before {
            b.edge(h, b_before, ETrue)
          }
          b.edge(last_node(b, body, h), h, EBack)
          let after = b.node(NMerge, "after-loop", s.span, s.id)
          b.edge(h, after, EFalse)
          cur = after
        }
        SReturn(e) => {
          let label = match e {
            Some(x) => "return " + x.render()
            None => "return"
          }
          let r = b.node(NStmt, label, s.span, s.id)
          b.edge(cur, r, ESeq)
          if b.exit >= 0 {
            b.edge(r, b.exit, ESeq)
          }
          cur = -1
          dead = true
        }
        SBreak => {
          let r = b.node(NStmt, "break", s.span, s.id)
          b.edge(cur, r, ESeq)
          cur = -1
          dead = true
        }
        SContinue => {
          let r = b.node(NStmt, "continue", s.span, s.id)
          b.edge(cur, r, ESeq)
          cur = -1
          dead = true
        }
        SBlock(inner) => {
          let r = emit_stmts(b, inner, cur, false)
          cur = r.0
          dead = r.1
        }
        STry(inner) => {
          let r = emit_stmts(b, inner, cur, false)
          cur = r.0
          dead = r.1
        }
        SUnsupported(what) => {
          let n = b.node(NStmt, "unsupported: " + what, s.span, s.id)
          b.edge(cur, n, ESeq)
          cur = n
        }
        _ => {
          let n = b.node(NStmt, s.text, s.span, s.id)
          b.edge(cur, n, ESeq)
          cur = n
        }
      }
    }
  }
  (cur, dead)
}

///|
/// True when the statement always leaves its block.
///
/// An `if` leaves only when BOTH branches leave. An `if` without an `else`
/// has a fall-through path -- the condition may be false -- so the code after
/// it is reachable. Treating it as an exit made every statement after a
/// guarded `return` unreachable code.
fn stmt_always_exits(s : Stmt) -> Bool {
  match s.kind {
    SReturn(_) | SBreak | SContinue => true
    SIf(_, a, c) => stmts_always_exit(a) && stmts_always_exit(c)
    _ => false
  }
}

///|
/// True when the block always leaves: one of its statements always leaves, so
/// the ones after it are unreachable. An empty block never leaves.
fn stmts_always_exit(stmts : Array[Stmt]) -> Bool {
  for s in stmts {
    if stmt_always_exits(s) {
      return true
    }
  }
  false
}

///|
fn last_node(b : Builder, stmts : Array[Stmt], fallback : Int32) -> Int32 {
  if stmts.length() == 0 {
    return fallback
  }
  let last = stmts[stmts.length() - 1]
  match last.kind {
    SIf(_, then_b, else_b) =>
      if else_b.length() > 0 {
        last_node(b, else_b, fallback)
      } else {
        last_node(b, then_b, fallback)
      }
    SWhile(_, _) | SFor(_, _, _, _, _) | SForIn(_, _, _) => fallback
    SBlock(inner) | STry(inner) => last_node(b, inner, fallback)
    _ => {
      let mut found = fallback
      for n in b.nodes {
        if n.stmt == last.id {
          found = n.id
        }
      }
      found
    }
  }
}

///|
pub fn build_cfg(fn_name : Func) -> Cfg {
  let b = Builder::new(fn_name.name, fn_name.file)
  let entry = b.node(NEntry, "entry " + fn_name.name, fn_name.span, -1)
  let exit = b.node(NExit, "exit", fn_name.span, -1)
  b.exit = exit
  let (last, _) = emit_stmts(b, fn_name.body, entry, false)
  if last >= 0 {
    b.edge(last, exit, ESeq)
  }
  let n = b.nodes.length()
  let e = b.edges.length()
  {
    fn_name: fn_name.name,
    file: fn_name.file,
    nodes: b.nodes,
    edges: b.edges,
    entry,
    exit,
    cyclomatic: e - n + 2,
  }
}

///|
pub fn cfg_findings(cfg : Cfg) -> Array[Finding] {
  let out : Array[Finding] = []
  let incoming = Map::new()
  for e in cfg.edges {
    incoming[e.to] = incoming.get_or_default(e.to, 0) + 1
  }
  for n in cfg.nodes {
    if n.kind == NDead {
      out.push(
        Finding::new(
          FDead,
          n.file,
          n.line,
          n.fn_name,
          "statement is unreachable after an unconditional exit",
          "static",
          0.95,
          n.label,
        ),
      )
    } else if n.id != cfg.entry &&
      incoming.get_or_default(n.id, 0) == 0 &&
      n.kind != NExit {
      out.push(
        Finding::new(
          FUnreachable,
          n.file,
          n.line,
          n.fn_name,
          "CFG node has no incoming edge",
          "static",
          0.9,
          n.label,
        ),
      )
    }
  }
  let mut i = 0
  while i < cfg.nodes.length() {
    let n = cfg.nodes[i]
    if n.kind == NLoop {
      let mut has_back = false
      let mut has_exit = false
      for e in cfg.edges {
        if e.to == n.id && e.kind == EBack {
          has_back = true
        }
        if e.from == n.id && e.kind == EFalse {
          has_exit = true
        }
      }
      if has_back && !has_exit {
        out.push(
          Finding::new(
            FInfinite,
            n.file,
            n.line,
            n.fn_name,
            "loop has a back edge but no exit edge (condition is constant true or unparsed)",
            "static",
            0.75,
            n.label,
          ),
        )
      }
    }
    i = i + 1
  }
  out
}

///|
pub fn find_func(ast : ModuleAst, name : String) -> Func? {
  for f in ast.all_funcs() {
    if f.name == name {
      return Some(f)
    }
  }
  for f in ast.all_funcs_including_tests() {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
pub fn cfg_label_counts(cfg : Cfg) -> Map[String, Int32] {
  let m : Map[String, Int32] = Map::new()
  for n in cfg.nodes {
    let key = match n.kind {
      NEntry => "entry"
      NExit => "exit"
      NStmt => "stmt"
      NBranch => "branch"
      NLoop => "loop"
      NMerge => "merge"
      NDead => "dead"
    }
    m[key] = m.get_or_default(key, 0) + 1
  }
  m
}
