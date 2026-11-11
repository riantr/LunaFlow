///|
pub struct DepNode {
  key : String
  fn_name : String
  file : String
  line : Int32
  stmt : Int32
  mut name : String
  kind : String
  mut tainted : Bool
}

///|
pub struct DepEdge {
  from : String
  to : String
  label : String
}

///|
pub struct DepGraph {
  nodes : Array[DepNode]
  edges : Array[DepEdge]
  index : Map[String, Int32]
}

///|
pub fn DepGraph::new() -> DepGraph {
  { nodes: [], edges: [], index: Map::new(), }
}

///|
fn dep_key(
  fn_name : String,
  kind : String,
  stmt : Int32,
  line : Int32,
) -> String {
  fn_name + ":" + kind + ":" + stmt.to_string() + ":" + line.to_string()
}

///|
fn DepGraph::ensure(
  self : DepGraph,
  key : String,
  fn_name : String,
  file : String,
  line : Int32,
  stmt : Int32,
  name : String,
  kind : String,
  tainted : Bool,
) -> Int32 {
  match self.index.get(key) {
    Some(i) => {
      let n = self.nodes[i]
      if tainted {
        n.tainted = true
      }
      if n.name == "" && name != "" {
        n.name = name
      }
      i
    }
    None => {
      let i = self.nodes.length()
      self.nodes.push({ key, fn_name, file, line, stmt, name, kind, tainted, })
      self.index[key] = i
      i
    }
  }
}

///|
fn DepGraph::link(
  self : DepGraph,
  from : String,
  to : String,
  label : String,
) -> Unit {
  if from != to {
    for e in self.edges {
      if e.from == from && e.to == to {
        return
      }
    }
    self.edges.push({ from, to, label, })
  }
}

///|
fn use_names(detail : String) -> Array[String] {
  let out : Array[String] = []
  for part in detail.split(",") {
    let t = part.trim().to_owned()
    if t != "" && !out.contains(t) {
      out.push(t)
    }
  }
  out
}

///|
pub fn build_dep_graph(events : Array[TraceEvent]) -> DepGraph {
  let g = DepGraph::new()
  let last_def : Map[String, String] = Map::new()
  for ev in events {
    let uses = use_names(ev.detail)
    match ev.kind {
      EvSource => {
        let key = dep_key(ev.fn_name, ev.kind.tag(), ev.stmt, ev.line)
        let _ = g.ensure(
          key,
          ev.fn_name,
          ev.file,
          ev.line,
          ev.stmt,
          ev.name,
          "source",
          true,
        )
        last_def[ev.fn_name + "::" + ev.name] = key
      }
      EvDef => {
        let key = dep_key(ev.fn_name, ev.kind.tag(), ev.stmt, ev.line)
        let _ = g.ensure(
          key,
          ev.fn_name,
          ev.file,
          ev.line,
          ev.stmt,
          ev.name,
          "def",
          ev.tainted,
        )
        for u in uses {
          match last_def.get(ev.fn_name + "::" + u) {
            Some(src) => g.link(src, key, "data")
            None => ()
          }
        }
        last_def[ev.fn_name + "::" + ev.name] = key
      }
      EvCond | EvIndex | EvAlloc | EvSink | EvReturn | EvCall | EvAbort => {
        let key = dep_key(ev.fn_name, ev.kind.tag(), ev.stmt, ev.line)
        let kind = match ev.kind {
          EvCond => "cond"
          EvIndex => "index"
          EvAlloc => "alloc"
          EvSink => "sink"
          EvReturn => "return"
          EvCall => "call"
          _ => "abort"
        }
        let label = if ev.name == "" { kind } else { ev.name }
        let _ = g.ensure(
          key,
          ev.fn_name,
          ev.file,
          ev.line,
          ev.stmt,
          label,
          kind,
          ev.tainted,
        )
        for u in uses {
          match last_def.get(ev.fn_name + "::" + u) {
            Some(src) => g.link(src, key, "use")
            None => ()
          }
        }
      }
      _ => ()
    }
  }
  g
}

///|
pub fn build_taint(
  events : Array[TraceEvent],
  findings : Array[Finding],
) -> TaintGraph {
  let g = TaintGraph::new()
  let known : Map[String, Int32] = Map::new()
  for ev in events {
    let k = ev.fn_name + "::" + ev.name
    if ev.kind == EvSource {
      let id = g.add_node(
        TSource,
        "source: " + ev.name,
        ev.fn_name,
        ev.file,
        ev.line,
      )
      known[k] = id
    } else if ev.kind == EvDef && ev.tainted {
      let uses = use_names(ev.detail)
      let mut has_known = false
      for u in uses {
        if known.contains(ev.fn_name + "::" + u) {
          has_known = true
        }
      }
      if has_known {
        let id = g.add_node(
          TStep,
          ev.name + " = " + truncate(ev.value, 28),
          ev.fn_name,
          ev.file,
          ev.line,
        )
        known[k] = id
        for u in uses {
          match known.get(ev.fn_name + "::" + u) {
            Some(src) => g.add_edge(src, id, "propagates")
            None => ()
          }
        }
      }
    } else if (ev.kind == EvIndex || ev.kind == EvAlloc) && ev.tainted {
      let id = g.add_node(
        TSink,
        (if ev.kind == EvIndex { "index: " } else { "alloc: " }) +
        ev.name +
        "[" +
        ev.value +
        "]",
        ev.fn_name,
        ev.file,
        ev.line,
      )
      let uses = use_names(ev.detail)
      let mut linked = false
      for u in uses {
        match known.get(ev.fn_name + "::" + u) {
          Some(src) => {
            g.add_edge(src, id, "reaches-sink")
            linked = true
          }
          None => ()
        }
      }
      if !linked {
        for pair in known.to_array() {
          if pair.0.has_prefix(ev.fn_name + "::") {
            g.add_edge(pair.1, id, "reaches-sink")
            break
          }
        }
      }
    }
  }
  for f in findings {
    if f.kind == FTaintIndex ||
      f.kind == FTaintAlloc ||
      f.kind == FTaintIndexRange {
      // Dedupe by SITE, not by the whole finding: the same index read is
      // observed once per trial and once per loop iteration, each with its
      // own observed value in the evidence, so a structural comparison never
      // matched and one site became dozens of rows. The in-range note and
      // the witnessed out-of-bounds risk are the SAME site: the risk wins.
      let key = taint_site_key(f)
      let mut at = -1
      let mut i = 0
      while i < g.sinks.length() {
        if taint_site_key(g.sinks[i]) == key {
          at = i
          break
        }
        i = i + 1
      }
      if at < 0 {
        g.sinks.push(f)
      } else if f.kind == FTaintIndex && g.sinks[at].kind == FTaintIndexRange {
        g.sinks[at] = f
      }
    }
  }
  g
}

///|
/// The identity of a taint sink's site. The in-range note and the witnessed
/// out-of-bounds risk share one key: they are one site, two verdicts.
fn taint_site_key(f : Finding) -> String {
  let cls = if f.kind == FTaintIndex || f.kind == FTaintIndexRange {
    "index"
  } else {
    f.kind.code()
  }
  cls + "|" + f.file + "|" + f.line.to_string() + "|" + f.fn_name
}

///|
pub fn stmt_index(ast : ModuleAst) -> Map[String, String] {
  let m : Map[String, String] = Map::new()
  for f in ast.files {
    for fn_name in f.funcs {
      index_stmts(m, fn_name.name, fn_name.body)
    }
  }
  m
}

///|
fn index_stmts(
  m : Map[String, String],
  fn_name : String,
  stmts : Array[Stmt],
) -> Unit {
  for s in stmts {
    m[fn_name + "|" + s.id.to_string()] = s.text
    match s.kind {
      SIf(_, a, b) => {
        index_stmts(m, fn_name, a)
        index_stmts(m, fn_name, b)
      }
      SWhile(_, body)
      | SForIn(_, _, body)
      | SFor(_, _, _, _, body)
      | SBlock(body)
      | STry(body) => index_stmts(m, fn_name, body)
      _ => ()
    }
  }
}

///|
pub fn node_text(texts : Map[String, String], n : DepNode) -> String {
  let key = n.fn_name + "|" + n.stmt.to_string()
  match texts.get(key) {
    Some(t) => if t == "" { n.kind } else { t }
    None => if n.name != "" { n.name } else { n.kind }
  }
}

///|
fn matches_criterion(n : DepNode, criterion : String) -> Bool {
  let at = criterion.find("@")
  match at {
    Some(i) => {
      let cvar = criterion[:i].to_owned()
      let fn_name = criterion[i + 1:].to_owned()
      n.name == cvar && n.fn_name == fn_name
    }
    None => {
      let colon = criterion.rev_find(":")
      match colon {
        Some(i) => {
          let fn_name = criterion[:i].to_owned()
          let line = parse_int(criterion[i + 1:].to_owned(), -1)
          n.fn_name == fn_name && n.line == line
        }
        None => n.name == criterion
      }
    }
  }
}

///|
pub fn slice_graph(
  graph : DepGraph,
  ast : ModuleAst,
  criterion : String,
  direction : SliceDirection,
  cap : Int32,
) -> SliceResult {
  let res = SliceResult::new(criterion, direction)
  let texts = stmt_index(ast)
  let starts : Array[String] = []
  for n in graph.nodes {
    if matches_criterion(n, criterion) && n.kind != "source" {
      starts.push(n.key)
    }
  }
  if starts.length() == 0 {
    for n in graph.nodes {
      if matches_criterion(n, criterion) {
        starts.push(n.key)
      }
    }
  }
  let node_by_key : Map[String, Int32] = Map::new()
  let mut i = 0
  while i < graph.nodes.length() {
    node_by_key[graph.nodes[i].key] = i
    i = i + 1
  }
  let seen : Map[String, Bool] = Map::new()
  let queue : Array[(String, Int32)] = []
  for s in starts {
    queue.push((s, 0))
  }
  let mut head = 0
  while head < queue.length() && res.nodes.length() < cap {
    let item = queue[head]
    head = head + 1
    let key = item.0
    let depth = item.1
    if seen.contains(key) {
      continue
    }
    seen[key] = true
    match node_by_key.get(key) {
      Some(idx) => {
        let n = graph.nodes[idx]
        res.add({
          key: n.key,
          fn_name: n.fn_name,
          file: n.file,
          line: n.line,
          text: node_text(texts, n),
          kind: n.kind,
          depth,
        })
      }
      None => ()
    }
    for e in graph.edges {
      let next = if direction == SliceBackward {
        if e.to == key {
          Some(e.from)
        } else {
          None
        }
      } else if e.from == key {
        Some(e.to)
      } else {
        None
      }
      match next {
        Some(nk) =>
          if !seen.contains(nk) {
            res.edges.push({
              from: if direction == SliceBackward {
                nk
              } else {
                key
              },
              to: if direction == SliceBackward {
                key
              } else {
                nk
              },
              label: e.label,
            })
            queue.push((nk, depth + 1))
          }
        None => ()
      }
    }
  }
  res
}

///|
pub fn count_calls(f : Func) -> Int32 {
  let r = Ref::new(0)
  count_calls_in(f.body, r)
  r.val
}

///|
fn count_calls_in(stmts : Array[Stmt], r : Ref[Int32]) -> Unit {
  for s in stmts {
    match s.kind {
      SExpr(e) => count_expr_calls(e, r)
      SLet(_, _, e) => count_expr_calls(e, r)
      SAssign(a, b) => {
        count_expr_calls(a, r)
        count_expr_calls(b, r)
      }
      SAssignOp(_, a, b) => {
        count_expr_calls(a, r)
        count_expr_calls(b, r)
      }
      SReturn(Some(e)) => count_expr_calls(e, r)
      SIf(c, a, b) => {
        count_expr_calls(c, r)
        count_calls_in(a, r)
        count_calls_in(b, r)
      }
      SWhile(c, body) => {
        count_expr_calls(c, r)
        count_calls_in(body, r)
      }
      SFor(_, a, b, c, body) => {
        count_expr_calls(a, r)
        count_expr_calls(b, r)
        count_expr_calls(c, r)
        count_calls_in(body, r)
      }
      SForIn(_, e, body) => {
        count_expr_calls(e, r)
        count_calls_in(body, r)
      }
      SBlock(body) | STry(body) => count_calls_in(body, r)
      _ => ()
    }
  }
}

///|
fn count_expr_calls(e : Expr, r : Ref[Int32]) -> Unit {
  match e.kind {
    ECall(_, args) => {
      r.val = r.val + 1
      for a in args {
        count_expr_calls(a, r)
      }
    }
    EMethod(rec, _, args) => {
      r.val = r.val + 1
      count_expr_calls(rec, r)
      for a in args {
        count_expr_calls(a, r)
      }
    }
    EBin(_, a, b) => {
      count_expr_calls(a, r)
      count_expr_calls(b, r)
    }
    EUn(_, a) => count_expr_calls(a, r)
    EIndex(a, b) => {
      count_expr_calls(a, r)
      count_expr_calls(b, r)
    }
    EField(a, _) => count_expr_calls(a, r)
    EArray(xs) | ETuple(xs) =>
      for a in xs {
        count_expr_calls(a, r)
      }
    _ => ()
  }
}
