///|
/// The MEMORY LAYOUT MODEL.
///
/// MoonBit has no addresses. There is no pointer type in the core, no address
/// arithmetic, no address space, no `size_of`, and the byte order is spelled
/// out in the API (`_be` / `_le`) rather than inherited from the machine. A
/// hardware memory model -- stack frames at fixed addresses, a heap, a global
/// region, MMIO registers -- therefore has no counterpart here, and a tool that
/// pretended otherwise would be drawing a picture, not analysing a program.
///
/// What IS there is a placement question with a real answer: where does a
/// value live, and does it stay where it was born?
///
///  - a GLOBAL binding lives for the whole module;
///  - an allocation that does not ESCAPE the function that made it could live
///    in that function's frame;
///  - an allocation that ESCAPES -- returned, stored into another object,
///    handed to a call the analyzer cannot see into -- outlives the frame, so
///    it is heap-allocated;
///  - a value that came from OUTSIDE the analysed module has a region the
///    analyzer cannot name.
///
/// This module computes that classification. It does it STATICALLY, over the
/// AST, so the answer does not depend on which inputs a run happened to
/// sample -- which is the property the whole memory-layout feature has to
/// have.

///|
/// A top-level binding: the module's GLOBAL REGION.
///
/// MoonBit resolves top-level `let` bindings by DEPENDENCY, not by file
/// order: a global may read a global that is declared later in the file.
/// `global_order` puts them in the order they can be evaluated in.
pub struct Global {
  name : String
  ty : String
  init : Expr
  file : String
  line : Int32
  is_const : Bool
}

///|
pub fn Global::new(
  name : String,
  ty : String,
  init : Expr,
  file : String,
  line : Int32,
  is_const : Bool,
) -> Global {
  { name, ty, init, file, line, is_const, }
}

///|
/// The module's globals, indexed by name. A name declared twice keeps the
/// first binding, which is what a module with a duplicate top-level name
/// means: the later one is unreachable.
pub fn globals_of(ast : ModuleAst) -> Map[String, Global] {
  let out : Map[String, Global] = Map([])
  for f in ast.files {
    for g in f.globals {
      if !out.contains(g.name) {
        out[g.name] = g
      }
    }
  }
  out
}

///|
/// The names a global's initializer reads.
pub fn global_deps(e : Expr) -> Array[String] {
  let out : Array[String] = []
  mem_collect_names(e, out)
  out
}

///|
fn mem_collect_names(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    EName(n) => if !out.contains(n) { out.push(n) }
    EBin(_, a, b) => {
      mem_collect_names(a, out)
      mem_collect_names(b, out)
    }
    EUn(_, a) => mem_collect_names(a, out)
    ECall(_, args) =>
      for x in args {
        mem_collect_names(x, out)
      }
    EMethod(a, _, args) => {
      mem_collect_names(a, out)
      for x in args {
        mem_collect_names(x, out)
      }
    }
    EField(a, _) => mem_collect_names(a, out)
    EIndex(a, b) => {
      mem_collect_names(a, out)
      mem_collect_names(b, out)
    }
    ESlice(a, b, c) => {
      mem_collect_names(a, out)
      match b {
        Some(x) => mem_collect_names(x, out)
        None => ()
      }
      match c {
        Some(x) => mem_collect_names(x, out)
        None => ()
      }
    }
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        mem_collect_names(x, out)
      }
    _ => ()
  }
}

///|
/// Order the globals so each one is evaluated after everything it reads.
///
/// Returns the evaluation order and the globals that could NOT be ordered --
/// the members of an initialization cycle. A cycle has no value, so those
/// globals are left unknown rather than guessed.
pub fn global_order(
  table : Map[String, Global],
) -> (Array[String], Array[String]) {
  let order : Array[String] = []
  let done : Map[String, Bool] = Map([])
  let stack : Array[String] = []
  let unresolved : Array[String] = []
  for name in sort_strings(table.keys().to_array()) {
    visit_global(table, name, done, stack, order, unresolved)
  }
  (order, unresolved)
}

///|
fn visit_global(
  table : Map[String, Global],
  name : String,
  done : Map[String, Bool],
  stack : Array[String],
  order : Array[String],
  unresolved : Array[String],
) -> Unit {
  if done.contains(name) {
    return
  }
  if stack.contains(name) {
    // A cycle: everything from the repeated name upwards is unresolvable.
    let mut i = 0
    while i < stack.length() {
      if stack[i] == name {
        let mut j = i
        while j < stack.length() {
          if !unresolved.contains(stack[j]) {
            unresolved.push(stack[j])
          }
          j = j + 1
        }
        break
      }
      i = i + 1
    }
    return
  }
  stack.push(name)
  match table.get(name) {
    Some(g) =>
      for dep in global_deps(g.init) {
        if table.contains(dep) {
          visit_global(table, dep, done, stack, order, unresolved)
        }
      }
    None => ()
  }
  ignore(stack.pop())
  done[name] = true
  if !order.contains(name) {
    order.push(name)
  }
}

///|
/// The globals that are MUTATED somewhere in the module.
///
/// A mutated global's value at the point of use is not the value of its
/// initializer, so the analyzer leaves it unknown rather than report a value
/// it cannot defend.
pub fn globals_mutated(ast : ModuleAst) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  let table = globals_of(ast)
  for f in ast.all_funcs() {
    scan_assigns(f.body, table, out)
  }
  out
}

///|
fn scan_assigns(
  stmts : Array[Stmt],
  table : Map[String, Global],
  out : Map[String, Bool],
) -> Unit {
  for s in stmts {
    match s.kind {
      SAssign(lhs, _) =>
        match lhs.kind {
          EName(n) => if table.contains(n) { out[n] = true }
          _ => ()
        }
      SIf(_, a, b) => {
        scan_assigns(a, table, out)
        scan_assigns(b, table, out)
      }
      SWhile(_, body) => scan_assigns(body, table, out)
      SFor(_, _, _, _, body) => scan_assigns(body, table, out)
      SForIn(_, _, body) => scan_assigns(body, table, out)
      SBlock(body) => scan_assigns(body, table, out)
      STry(body) => scan_assigns(body, table, out)
      _ => ()
    }
  }
}

///|
/// One row of the global region table.
pub struct GlobalRow {
  name : String
  ty : String
  file : String
  line : Int32
  value : String
  note : String
}

///|
pub fn GlobalRow::new(
  name : String,
  ty : String,
  file : String,
  line : Int32,
  value : String,
  note : String,
) -> GlobalRow {
  { name, ty, file, line, value, note, }
}

///|
/// The global values, read back out of the trace.
///
/// The interpreter computes the globals once, before the functions run, and
/// records each one as a definition -- so the report does not have to
/// evaluate the module a second time to show what the global region holds.
pub fn global_values_from_events(
  events : Array[TraceEvent],
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for e in events {
    if e.fn_name == "<global>" && e.kind == EvDef {
      out[e.name] = e.value
    }
  }
  out
}

///|
/// The global region of a module, one row per top-level binding.
pub fn global_rows(
  ast : ModuleAst,
  values : Map[String, String],
) -> Array[GlobalRow] {
  let table = globals_of(ast)
  let (order, unresolved) = global_order(table)
  let mutated = globals_mutated(ast)
  let rows : Array[GlobalRow] = []
  for name in order {
    match table.get(name) {
      Some(g) => {
        let value = match values.get(name) {
          Some(v) => v
          None => "?"
        }
        let note = if unresolved.contains(name) {
          "initialization cycle: the value cannot be resolved"
        } else if mutated.contains(name) {
          "mutated in the module: the value at the point of use is unknown"
        } else {
          "resolved in dependency order"
        }
        rows.push(GlobalRow::new(g.name, g.ty, g.file, g.line, value, note))
      }
      None => ()
    }
  }
  rows
}

///|
/// Where an allocation lives.
#derive(Eq)
pub(all) enum AllocClass {
  /// Bound to a top-level name: it lives in the module's global region.
  AGlobal
  /// Created in a function and never leaves it: a frame allocation would be
  /// sound for it.
  AFrame
  /// Leaves the function that created it, so it outlives the frame.
  AHeap
  /// Came from outside the analysed module: its region is not the analyzer's
  /// to name.
  AForeign
}

///|
pub extend AllocClass with Eq::{not_equal, equal}

///|
pub fn AllocClass::code(self : AllocClass) -> String {
  match self {
    AGlobal => "GLOBAL"
    AFrame => "FRAME"
    AHeap => "HEAP"
    AForeign => "FOREIGN"
  }
}

///|
pub fn AllocClass::title(self : AllocClass) -> String {
  match self {
    AGlobal => "global region"
    AFrame => "frame (does not escape)"
    AHeap => "heap (escapes the frame)"
    AForeign => "foreign (outside the analysed module)"
  }
}

///|
/// One allocation site.
///
/// A site has ONE class: the strongest one it reached. An allocation that is
/// first seen in the frame and later escapes is a heap allocation, and the
/// reason recorded is the escape.
pub struct AllocSite {
  file : String
  line : Int32
  fn_name : String
  kind : String
  mut class : AllocClass
  mut reason : String
}

///|
pub fn AllocSite::new(
  file : String,
  line : Int32,
  fn_name : String,
  kind : String,
  class : AllocClass,
  reason : String,
) -> AllocSite {
  { file, line, fn_name, kind, class, reason, }
}

///|
/// The allocation sites of a module, classified.
///
/// The analysis is a scope analysis over the AST: it tracks which local names
/// hold an allocation, and marks an allocation as ESCAPING when it is
/// returned, stored into another object, or handed to a call the analyzer
/// cannot see into. An allocation that never escapes stays in the frame.
pub fn analyze_allocations(ast : ModuleAst) -> Array[AllocSite] {
  let out : Array[AllocSite] = []
  let globals = globals_of(ast)
  for g in globals.keys().to_array() {
    match globals.get(g) {
      Some(gl) =>
        if is_allocation(gl.init) {
          out.push(
            AllocSite::new(
              gl.file,
              gl.line,
              "<global>",
              alloc_kind(gl.init),
              AGlobal,
              "bound to the top-level name " + gl.name,
            ),
          )
        }
      None => ()
    }
  }
  for f in ast.all_funcs() {
    if f.body.length() == 0 {
      continue
    }
    // The scope maps a local name to the INDEX of its allocation site, so
    // that a later escape can upgrade the site in place.
    let scope : Map[String, Int32] = Map([])
    let params : Array[String] = []
    for p in f.params {
      params.push(p.name)
    }
    walk_alloc_stmts(f.name, f.file, f.body, scope, params, out)
    // A function body ends with its last EXPRESSION, and that expression is
    // the function's value. When the value IS the allocation, the allocation
    // is returned and outlives the frame. When the last expression is an
    // INDEX or a FIELD, the function returns a COPY of the element, and the
    // container stays where it was.
    if f.body.length() > 0 {
      let last = f.body[f.body.length() - 1]
      match last.kind {
        SExpr(e) =>
          match e.kind {
            EName(n) =>
              match scope.get(n) {
                Some(idx) =>
                  mark_escape(
                    out, idx, "returned as the last expression of the function, so it outlives the frame",
                  )
                None => ()
              }
            _ => ()
          }
        _ => ()
      }
    }
  }
  out
}

///|
/// Is this expression an allocation?
fn is_allocation(e : Expr) -> Bool {
  match e.kind {
    EArray(_) => true
    ECall(name, args) => is_alloc_call(name, args)
    EMethod(_, name, args) => is_alloc_method(name, args)
    _ => false
  }
}

///|
fn is_alloc_call(name : String, args : Array[Expr]) -> Bool {
  ignore(args)
  // The parser reads a qualified path as a field read, so a call on
  // `UninitializedArray::make` comes out as the name `UninitializedArray.make`.
  // Both spellings are accepted, because a caller may build the expression
  // itself.
  let n = name.replace(old="::", new=".")
  n == "Array.make" ||
  n == "FixedArray.make" ||
  n == "UninitializedArray.make" ||
  n == "Ref.new" ||
  n == "RefCell.new" ||
  n == "Array.from_array" ||
  n == "Bytes.make"
}

///|
fn is_alloc_method(name : String, args : Array[Expr]) -> Bool {
  ignore(args)
  name == "make" ||
  name == "new" ||
  name == "from_array" ||
  name == "copy" ||
  name == "clone"
}

///|
/// What kind of allocation is this?
fn alloc_kind(e : Expr) -> String {
  match e.kind {
    EArray(_) => "array literal"
    ECall(name, _) => name
    EMethod(_, name, _) => name
    _ => "allocation"
  }
}

///|
/// The names an expression mentions, so that an allocation can be followed
/// from the place it was made to the place it is stored.
fn alloc_names(e : Expr, out : Array[String]) -> Unit {
  mem_collect_names(e, out)
}

///|
fn walk_alloc_stmts(
  fn_name : String,
  file : String,
  stmts : Array[Stmt],
  scope : Map[String, Int32],
  params : Array[String],
  out : Array[AllocSite],
) -> Unit {
  for s in stmts {
    walk_alloc_stmt(fn_name, file, s, scope, params, out)
  }
}

///|
/// Mark an allocation as ESCAPING: it outlives the frame it was made in, so
/// it is heap-allocated. The first escape found is the reason recorded.
fn mark_escape(out : Array[AllocSite], idx : Int32, reason : String) -> Unit {
  if idx < 0 || idx >= out.length() {
    return
  }
  if out[idx].class == AFrame {
    out[idx].class = AHeap
    out[idx].reason = reason
  }
}

///|
fn walk_alloc_stmt(
  fn_name : String,
  file : String,
  s : Stmt,
  scope : Map[String, Int32],
  params : Array[String],
  out : Array[AllocSite],
) -> Unit {
  match s.kind {
    SLet(name, _, e) =>
      if is_allocation(e) {
        out.push(
          AllocSite::new(
            file,
            s.span.start_line,
            fn_name,
            alloc_kind(e),
            AFrame,
            "bound to the local " + name + " and never leaves the frame",
          ),
        )
        scope[name] = out.length() - 1
      } else {
        // The name may hold an allocation that arrived from somewhere else.
        let names : Array[String] = []
        alloc_names(e, names)
        for n in names {
          match scope.get(n) {
            Some(prev) => scope[name] = prev
            None => ()
          }
        }
      }
    SAssign(lhs, rhs) => {
      let names : Array[String] = []
      alloc_names(rhs, names)
      for n in names {
        match scope.get(n) {
          Some(idx) =>
            if is_store_into(lhs) {
              mark_escape(
                out, idx, "stored into another object, so it outlives the frame",
              )
            } else if is_name(lhs) && params.contains(as_name(lhs)) {
              mark_escape(
                out,
                idx,
                "assigned to the parameter " +
                as_name(lhs) +
                ", which the caller owns",
              )
            }
          None => ()
        }
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => {
          let names : Array[String] = []
          alloc_names(x, names)
          for n in names {
            match scope.get(n) {
              Some(idx) =>
                mark_escape(out, idx, "returned, so it outlives the frame")
              None => ()
            }
          }
        }
        None => ()
      }
    SExpr(e) => {
      // A call's RECEIVER is not an escape: `a.set(0, 7)` mutates the
      // allocation in place and does not hand it to anybody. An ARGUMENT is.
      let names : Array[String] = []
      escaping_names(e, names)
      for n in names {
        match scope.get(n) {
          Some(idx) =>
            mark_escape(
              out, idx, "passed to a call the analyzer cannot see into, so it may outlive the frame",
            )
          None => ()
        }
      }
    }
    SIf(_, then_stmts, else_stmts) => {
      walk_alloc_stmts(fn_name, file, then_stmts, scope, params, out)
      walk_alloc_stmts(fn_name, file, else_stmts, scope, params, out)
    }
    SWhile(_, body) => walk_alloc_stmts(fn_name, file, body, scope, params, out)
    SFor(_, _, _, _, body) =>
      walk_alloc_stmts(fn_name, file, body, scope, params, out)
    SForIn(_, _, body) =>
      walk_alloc_stmts(fn_name, file, body, scope, params, out)
    SBlock(body) => walk_alloc_stmts(fn_name, file, body, scope, params, out)
    STry(body) => walk_alloc_stmts(fn_name, file, body, scope, params, out)
    _ => ()
  }
}

///|
fn is_store_into(lhs : Expr) -> Bool {
  match lhs.kind {
    EIndex(_, _) => true
    EField(_, _) => true
    _ => false
  }
}

///|
fn is_name(e : Expr) -> Bool {
  match e.kind {
    EName(_) => true
    _ => false
  }
}

///|
fn as_name(e : Expr) -> String {
  match e.kind {
    EName(n) => n
    _ => ""
  }
}

///|
/// The names an expression HANDS to a call: the arguments, and for a plain
/// call everything it mentions.
///
/// The RECEIVER of a method call is not one of them: `a.set(0, 7)` mutates
/// the allocation in place and does not hand it to anybody, while `f(a)`
/// hands the allocation over. A call NESTED inside a larger expression still
/// hands its arguments over, so `consume(b) + x` does make `b` escape.
fn escaping_names(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    ECall(_, args) =>
      for x in args {
        alloc_names(x, out)
        escaping_names(x, out)
      }
    EMethod(recv, _, args) => {
      for x in args {
        alloc_names(x, out)
        escaping_names(x, out)
      }
      nested_escaping(recv, out)
    }
    EBin(_, a, b) => {
      escaping_names(a, out)
      escaping_names(b, out)
    }
    EUn(_, a) => escaping_names(a, out)
    EIndex(a, b) => {
      escaping_names(a, out)
      escaping_names(b, out)
    }
    EField(a, _) => escaping_names(a, out)
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        escaping_names(x, out)
      }
    _ => ()
  }
}

///|
/// The calls inside an expression, and what THEY hand over. The expression
/// itself is not handed over: this is used for the receiver of a method call,
/// which is not an escape on its own.
fn nested_escaping(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    ECall(_, args) =>
      for x in args {
        alloc_names(x, out)
        escaping_names(x, out)
      }
    EMethod(_, _, args) =>
      for x in args {
        alloc_names(x, out)
        escaping_names(x, out)
      }
    EBin(_, a, b) => {
      nested_escaping(a, out)
      nested_escaping(b, out)
    }
    EUn(_, a) => nested_escaping(a, out)
    EIndex(a, b) => {
      nested_escaping(a, out)
      nested_escaping(b, out)
    }
    EField(a, _) => nested_escaping(a, out)
    _ => ()
  }
}

///|
/// How many allocation sites fall in each class.
pub fn alloc_tally(sites : Array[AllocSite]) -> Map[String, Int32] {
  let out : Map[String, Int32] = Map([])
  for s in sites {
    let k = s.class.code()
    let n = match out.get(k) {
      Some(v) => v
      None => 0
    }
    out[k] = n + 1
  }
  out
}

///|
/// One finding class, and how its rows behaved across the re-samples.
pub struct StabilityRow {
  code : String
  mode : String
  rows : Int32
  stable_rows : Int32
  runs : Int32
}

///|
pub fn StabilityRow::new(
  code : String,
  mode : String,
  rows : Int32,
  stable_rows : Int32,
  runs : Int32,
) -> StabilityRow {
  { code, mode, rows, stable_rows, runs, }
}

///|
pub fn StabilityRow::stable(self : StabilityRow) -> Bool {
  self.stable_rows == self.rows
}

///|
/// The result of the stability self-check: the same analysis, re-sampled.
pub struct StabilityResult {
  runs : Array[Int32]
  rows : Array[StabilityRow]
  stable : Int32
  sample_dependent : Int32
}

///|
pub fn StabilityResult::new(
  runs : Array[Int32],
  rows : Array[StabilityRow],
) -> StabilityResult {
  let mut stable = 0
  let mut sample = 0
  for r in rows {
    if r.stable() {
      stable = stable + 1
    } else {
      sample = sample + 1
    }
  }
  { runs, rows, stable, sample_dependent: sample, }
}

///|
/// The key a finding is identified by in the comparison: its class, its
/// engine, its function and its line. The message text is deliberately NOT
/// part of the key, because a message that embeds an observed value changes
/// with the sample while the finding itself did not.
fn stability_key(f : Finding) -> String {
  f.kind.code() +
  "|" +
  f.mode +
  "|" +
  f.fn_name +
  "|" +
  f.file +
  ":" +
  f.line.to_string()
}

///|
/// Compare the findings of several runs of the same analysis.
///
/// A class whose rows appear in EVERY run does not depend on the sample. A
/// class with rows that appear in only SOME of them does, and the report says
/// so rather than letting a reader assume the row is a property of the
/// program.
///
/// `constant` holds the findings that do NOT depend on the sample by
/// construction -- the abstract layer's, which is a may-analysis over the
/// input abstraction rather than a sample of it. They are added to every run,
/// so the comparison states what is already known instead of re-measuring it.
pub fn compare_runs(
  sizes : Array[Int32],
  runs : Array[Array[Finding]],
  constant~ : Array[Finding] = [],
) -> StabilityResult {
  let counts : Map[String, Int32] = Map([])
  let codes : Map[String, String] = Map([])
  let modes : Map[String, String] = Map([])
  let total = runs.length()
  for r in runs {
    let seen : Map[String, Bool] = Map([])
    for f in r {
      let k = stability_key(f)
      seen[k] = true
      codes[k] = f.kind.code()
      modes[k] = f.mode
    }
    for f in constant {
      let k = stability_key(f)
      seen[k] = true
      codes[k] = f.kind.code()
      modes[k] = f.mode
    }
    for k in seen.keys().to_array() {
      let n = match counts.get(k) {
        Some(v) => v
        None => 0
      }
      counts[k] = n + 1
    }
  }
  // The rows are grouped by class and engine: a class is what a reader
  // recognises, and the engine says whether it is an observed row or a
  // proved one.
  let rows : Array[StabilityRow] = []
  let groups : Map[String, Array[Int32]] = Map([])
  for k in sort_strings(counts.keys().to_array()) {
    let n = match counts.get(k) {
      Some(v) => v
      None => 0
    }
    let code = match codes.get(k) {
      Some(v) => v
      None => ""
    }
    let mode = match modes.get(k) {
      Some(v) => v
      None => ""
    }
    let gk = code + "|" + mode
    let prev = match groups.get(gk) {
      Some(v) => v
      None => [0, 0]
    }
    let stable = if n == total { prev[1] + 1 } else { prev[1] }
    groups[gk] = [prev[0] + 1, stable]
  }
  for gk in sort_strings(groups.keys().to_array()) {
    let v = match groups.get(gk) {
      Some(x) => x
      None => [0, 0]
    }
    let gk_parts = gk.split("|")
    let mut code = ""
    let mut mode = ""
    let mut i = 0
    for part in gk_parts {
      if i == 0 {
        code = part.to_owned()
      } else if i == 1 {
        mode = part.to_owned()
      }
      i = i + 1
    }
    rows.push(StabilityRow::new(code, mode, v[0], v[1], total))
  }
  StabilityResult::new(sizes, rows)
}

///|
/// A collection that only ever grows.
///
/// MoonBit's type system makes the MEMORY-LEAK class inexpressible in safe
/// code: there is no `free`, and every allocation is the garbage
/// collector's business. There is one shape the type system does NOT save
/// the module from, and it is the one this family reports:
///
///   - a MODULE-LEVEL collection -- a top-level `let` -- lives for as long
///     as the module does;
///   - it is only ever ADDED to: nothing in the module ever removes an
///     element from it, and nothing ever replaces it with a fresh one;
///   - and it is added to inside a LOOP whose trip count the analyzer cannot
///     bound.
///
/// The last clause is what makes the claim a proof rather than a guess: the
/// loop can run any number of times, every iteration adds an element, and
/// nothing ever takes one away, so the collection grows without bound.
///
/// What the family does NOT claim, and says so in its contract: a
/// collection that is filled once at start-up, or once per call, is not
/// reported -- the analyzer cannot see how often the module is called; a
/// collection that is trimmed somewhere is not reported either; and a LOCAL
/// collection is not reported, because it dies with the function that made
/// it.
pub fn analyze_growth(ast : ModuleAst) -> Array[Finding] {
  let out : Array[Finding] = []
  let table = globals_of(ast)
  // A module with no top-level binding has no module-level collection, and
  // the walk over every function would find nothing.
  if table.length() == 0 {
    return out
  }
  // What the module does to its globals, over the WHOLE module: the globals
  // something is added to, the globals something is taken from, and the
  // globals something is added to inside a loop the analyzer cannot bound.
  let added : Array[String] = []
  let removed : Array[String] = []
  let in_loop : Array[String] = []
  for f in ast.all_funcs() {
    let ops = growth_ops(f)
    for n in ops.added {
      if !added.contains(n) {
        added.push(n)
      }
    }
    for n in ops.removed {
      if !removed.contains(n) {
        removed.push(n)
      }
    }
    for n in ops.in_loop {
      if !in_loop.contains(n) {
        in_loop.push(n)
      }
    }
  }
  for name in table.keys().to_array() {
    let g = match table.get(name) {
      Some(x) => x
      None => continue
    }
    if g.is_const {
      continue
    }
    if !growth_is_collection(g) {
      continue
    }
    if removed.contains(g.name) {
      continue
    }
    if !in_loop.contains(g.name) {
      continue
    }
    out.push(
      Finding::new(
        FUnboundedGrowth,
        g.file,
        g.line,
        "",
        "the module-level collection '" +
        g.name +
        "' is only ever added to, and it is added to inside a loop whose trip count the analyzer cannot bound. Nothing in the module ever removes an element from it, so it holds every element it is given for as long as the module lives.",
        "L2-memory",
        0.6,
        g.name,
      ),
    )
  }
  out
}

///|
/// What the module does to its globals, in one function.
priv struct GrowthOps {
  /// The globals something is ADDED to.
  added : Array[String]
  /// The globals something is TAKEN FROM.
  removed : Array[String]
  /// The globals something is ADDED to inside a loop the analyzer cannot
  /// bound.
  in_loop : Array[String]
}

///|
fn growth_ops(f : Func) -> GrowthOps {
  let out : GrowthOps = { added: [], removed: [], in_loop: [], }
  for s in f.body {
    growth_stmt(s, false, out)
  }
  out
}

///|
/// One statement, with the loop context it was written in.
///
/// `unbounded` says that an enclosing loop can run any number of times.
fn growth_stmt(s : Stmt, unbounded : Bool, out : GrowthOps) -> Unit {
  match s.kind {
    SExpr(e) => growth_expr(e, unbounded, out)
    SLet(_, _, init) => growth_expr(init, unbounded, out)
    SAssign(lhs, rhs) => {
      growth_expr(rhs, unbounded, out)
      // A global REPLACED by a fresh collection is not a growth: the old one
      // is gone. (A top-level `let` is immutable in MoonBit, so the
      // toolchain rejects this -- the analyzer does not compile the target,
      // and it leaves the global's value unknown rather than guess.)
      match lhs.kind {
        EName(n) =>
          if growth_is_fresh_collection(rhs) && !out.removed.contains(n) {
            out.removed.push(n)
          }
        _ => ()
      }
    }
    SAssignOp(_, _, rhs) => growth_expr(rhs, unbounded, out)
    SReturn(e) =>
      match e {
        Some(x) => growth_expr(x, unbounded, out)
        None => ()
      }
    SIf(cond, then_body, else_body) => {
      growth_expr(cond, unbounded, out)
      for x in then_body {
        growth_stmt(x, unbounded, out)
      }
      for x in else_body {
        growth_stmt(x, unbounded, out)
      }
    }
    SWhile(cond, body) => {
      growth_expr(cond, unbounded, out)
      let un = unbounded || growth_while_unbounded(cond)
      for x in body {
        growth_stmt(x, un, out)
      }
    }
    SFor(_, from, to, step, body) => {
      growth_expr(from, unbounded, out)
      growth_expr(to, unbounded, out)
      growth_expr(step, unbounded, out)
      let un = unbounded || !growth_for_bounded(from, to, step)
      for x in body {
        growth_stmt(x, un, out)
      }
    }
    SForIn(_, iter, body) => {
      growth_expr(iter, unbounded, out)
      let un = unbounded || !growth_iterable_bounded(iter)
      for x in body {
        growth_stmt(x, un, out)
      }
    }
    SBlock(body) =>
      for x in body {
        growth_stmt(x, unbounded, out)
      }
    STry(body) =>
      for x in body {
        growth_stmt(x, unbounded, out)
      }
    _ => ()
  }
}

///|
/// The names an expression ADDS to and TAKES FROM.
fn growth_expr(e : Expr, unbounded : Bool, out : GrowthOps) -> Unit {
  match e.kind {
    EMethod(recv, name, args) => {
      let n = root_name(recv)
      if n != "" {
        let m = name.to_lower()
        if growth_is_add_method(m) {
          if !out.added.contains(n) {
            out.added.push(n)
          }
          if unbounded && !out.in_loop.contains(n) {
            out.in_loop.push(n)
          }
        }
        if growth_is_remove_method(m) && !out.removed.contains(n) {
          out.removed.push(n)
        }
      }
      for a in args {
        growth_expr(a, unbounded, out)
      }
      growth_expr(recv, unbounded, out)
    }
    ECall(_, args) =>
      for a in args {
        growth_expr(a, unbounded, out)
      }
    EBin(_, a, b) => {
      growth_expr(a, unbounded, out)
      growth_expr(b, unbounded, out)
    }
    EUn(_, a) => growth_expr(a, unbounded, out)
    EIndex(a, b) => {
      growth_expr(a, unbounded, out)
      growth_expr(b, unbounded, out)
    }
    EField(a, _) => growth_expr(a, unbounded, out)
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        growth_expr(x, unbounded, out)
      }
    _ => ()
  }
}

///|
/// True when the method ADDS an element to the collection it is called on.
///
/// The list is the growing methods of MoonBit's collections. `set` is NOT in
/// it: `arr.set(i, v)` replaces an element and does not make the collection
/// longer, and the analyzer cannot see the type of the receiver well enough
/// to tell the two apart.
fn growth_is_add_method(name : String) -> Bool {
  name == "push" ||
  name.has_prefix("push_") ||
  name == "add" ||
  name.has_prefix("add_") ||
  name == "append" ||
  name == "insert" ||
  name.has_prefix("insert_") ||
  name == "extend" ||
  name == "concat"
}

///|
/// True when the method TAKES an element out of the collection it is called
/// on.
///
/// `filter`, `take` and `drop` are not in it: they RETURN a new collection
/// and leave the original alone.
fn growth_is_remove_method(name : String) -> Bool {
  name == "pop" ||
  name.has_prefix("pop_") ||
  name == "popn" ||
  name == "remove" ||
  name.has_prefix("remove_") ||
  name == "clear" ||
  name == "shift" ||
  name == "truncate" ||
  name == "drain" ||
  name == "delete" ||
  name == "unset" ||
  name == "retain"
}

///|
/// True when the expression builds a FRESH collection, so that binding it to
/// a global REPLACES what was there.
fn growth_is_fresh_collection(e : Expr) -> Bool {
  match e.kind {
    EArray(_) => true
    ECall(name, _) => {
      let n = name.to_lower()
      n.contains("new") &&
      (
        n.contains("array") ||
        n.contains("map") ||
        n.contains("set") ||
        n.contains("list") ||
        n.contains("buffer") ||
        n.contains("builder")
      )
    }
    _ => false
  }
}

///|
/// True when the global holds a COLLECTION: something that can hold more
/// elements than it does now.
fn growth_is_collection(g : Global) -> Bool {
  let t = g.ty.to_lower()
  for w in growth_collection_types() {
    if t.has_prefix(w) {
      return true
    }
  }
  match g.init.kind {
    EArray(_) => true
    ECall(name, _) => {
      let n = name.to_lower()
      if !n.contains("new") {
        return false
      }
      for w in growth_collection_types() {
        if n.contains(w) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// The collection types the analyzer knows by name.
fn growth_collection_types() -> Array[String] {
  [
    "array", "map", "set", "hashmap", "stringbuilder", "arraybuffer", "linkedlist",
    "vec", "deque", "list", "queue", "stack", "buffer",
  ]
}

///|
/// True when the `while` loop can run any number of times.
///
/// A condition that is the literal `false` never runs the body; anything
/// else is a loop the analyzer cannot bound.
fn growth_while_unbounded(cond : Expr) -> Bool {
  match cond.kind {
    EBool(v) => v
    _ => true
  }
}

///|
/// True when the `for` loop's trip count is a number the analyzer can name.
///
/// The count is known when the start, the bound and the step are all
/// constants. A bound the module reads -- a parameter, a length -- is not.
fn growth_for_bounded(from : Expr, to : Expr, step : Expr) -> Bool {
  match (const_of_expr(from), const_of_expr(to), const_of_expr(step)) {
    (Some(_), Some(_), Some(_)) => true
    _ => false
  }
}

///|
/// True when the `for .. in` loop's trip count is a number the analyzer can
/// name.
///
/// Three shapes have a length the analyzer knows: a literal list, a RANGE
/// whose two ends are constants, and nothing else. Every other iterable's
/// length is data, so the loop can run any number of times.
fn growth_iterable_bounded(iter : Expr) -> Bool {
  match iter.kind {
    EArray(_) => true
    ERange(a, b, _) =>
      match (const_of_expr(a), const_of_expr(b)) {
        (Some(_), Some(_)) => true
        _ => false
      }
    _ => false
  }
}
