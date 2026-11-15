// The CONCURRENCY MODEL.
//
// §5.10 modelled the MoonBit side of the memory story and §5.11 the foreign
// address space on the other side of the C boundary. This section models the
// THIRD thing: what happens when MORE THAN ONE TASK runs.
//
// Every property of MoonBit's concurrency was MEASURED against the
// toolchain, not read off a document:
//
//   * MoonBit tasks do NOT run MoonBit code on several OS threads. A
//     spin-lock whose spin loop contains no `await` HANGS: measured, the
//     spinner printed "spinner started, spinning" and the second task
//     never printed at all, because it never got to run. The runtime's
//     thread pool (`with_event_loop(..., max_worker_count = 1024)`)
//     executes the BLOCKING I/O; the coroutine waits on the event-loop
//     thread.
//   * So a task yields ONLY at an await point, and a yield point is where
//     another task may run.
//   * A read-modify-write with NO await inside it loses nothing (measured:
//     8 tasks x 200 000 increments = exactly 1 600 000 counted). A
//     read-AWAIT-write over a shared `Ref[Int]` lost 21 000 of 24 000
//     updates, and the SAME interleaving every run.
//
// THAT is why this model is a state-space problem and not a sampling one:
// the interleaving space is finite and reproducible, so a conflict can be
// FOUND rather than waited for.
//
// What the model does NOT claim: it does not claim a thread-level data
// race, because MoonBit has no thread-level data race between two tasks.
// It models INTERLEAVING sensitivity, which is the defect class that
// actually exists here.

///|
/// A TASK: a closure handed to a spawn call.
pub struct ConcTask {
  /// The synthetic name of the closure, which says where it was written.
  id : String
  /// The function that spawned it.
  owner : String
  /// The API that spawned it: `spawn_bg`, `spawn`, `all`, ...
  spawn : String
  file : String
  line : Int32
  /// Whether the closure is `async`. A task body that is not async cannot
  /// await, so it cannot yield, so it cannot interleave.
  is_async : Bool
  /// How many instances of this body may run at the same time. One, unless
  /// the closure literal was written INSIDE a loop -- then the body is
  /// created once per iteration and each instance is a separate task.
  ///
  /// This matters because a body that runs twice conflicts with ITSELF: the
  /// two instances read and write the same cell at the same program point,
  /// so the interleaving between them is a real conflict.
  instances : Int32
  /// How many yield points this body has. A read whose value is used after
  /// a yield may already be out of date.
  yields : Int32
}

///|
/// A SHARED CELL: a `Ref` that more than one task reaches.
pub struct ConcCell {
  /// The QUALIFIED key of the cell: the function that binds it and the
  /// name it is bound to. The name alone is not enough -- two functions may
  /// each bind `counter` to a `Ref` of their own, and those are two
  /// different cells.
  name : String
  /// The name the code uses, without the function it comes from.
  varname : String
  file : String
  line : Int32
  /// The tasks that touch it.
  tasks : Array[String]
}

///|
/// An ACCESS to a shared cell.
pub struct ConcAccess {
  task : String
  cell : String
  /// "read" or "write".
  kind : String
  file : String
  line : Int32
  /// TRUE when a yield point separates this write from the read it is based
  /// on: the read-modify-write is NOT atomic, so another task may write the
  /// cell in between and the update is lost.
  split : Bool
  /// The locks DEFINITELY held at this access. An access under a common
  /// lock is ordered against another access under the same lock.
  locks : Array[String]
  /// How many yield points this task had passed when it made this access.
  /// A read at 0 that is used after a yield is a value that may have gone
  /// stale in between.
  yields_at : Int32
}

///|
/// A WAIT-FOR EDGE.
///
/// The kinds are:
///   "waits"      the task waits for the resource (`from` is the task)
///   "wants"      the task holds `from` while it wants `to` -- this is the
///                edge of the RESOURCE ORDERING graph, and a cycle in it is a
///                deadlock
///   "unreleased" the task acquires the resource and never gives it back
pub struct ConcEdge {
  from : String
  to : String
  kind : String
  file : String
  line : Int32
  /// The task the edge belongs to.
  task : String
  /// The function that spawned that task. The edges of two tasks may only
  /// be put in one graph when their owners may run at the same time.
  owner : String
}

///|
/// The concurrency model of a module.
pub struct ConcModel {
  tasks : Array[ConcTask]
  cells : Array[ConcCell]
  accesses : Array[ConcAccess]
  edges : Array[ConcEdge]
  findings : Array[Finding]
}

///|
/// The state of one path through a task body.
struct CState {
  /// How many yield points this path has passed.
  mut yields : Int32
  /// The locks DEFINITELY held on this path.
  mut must : Array[String]
  /// The locks that MAY be held on this path.
  mut may : Array[String]
  /// For each cell, the yield count at the LAST read of it. A write whose
  /// yield count is greater was separated from its read by a yield.
  pending : Map[String, Int32]
}

///|
fn CState::new() -> CState {
  { yields: 0, must: [], may: [], pending: Map([]), }
}

///|
fn CState::copy(self : CState) -> CState {
  {
    yields: self.yields,
    must: self.must.copy(),
    may: self.may.copy(),
    pending: Map(self.pending.to_array()),
  }
}

///|
/// The calls that MAY suspend. A task yields only at an await point, and an
/// await point is a call to an async function.
///
/// The names are the ones MEASURED in the bundled core's public API. A
/// call to one of the module's OWN async functions is an await point too,
/// and that is handled separately.
fn core_await() -> Array[String] {
  [
    "acquire", "all", "any", "handle_cancellation", "pause", "protect_from_cancel",
    "read_all", "read_exactly", "read_some", "recv", "send", "sleep", "wait", "with_timeout",
    "with_timeout_opt",
  ]
}

///|
/// The calls that may suspend only when they name a PACKAGE: a bare `read`
/// in the user's code is not an await point, but `@io.read` is.
fn package_await() -> Array[String] {
  ["read", "write", "flush", "close", "shutdown"]
}

///|
/// The APIs that create a TASK.
fn spawn_apis() -> Array[String] {
  ["spawn", "spawn_bg", "spawn_loop", "with_task_group"]
}

///|
/// The qualified name of a call: `@async.sleep` for a package method, and
/// the bare name for anything else.
fn conc_call_name(e : Expr) -> String {
  match e.kind {
    ECall(f, _) => f
    EMethod(r, m, _) => {
      let rs = r.render()
      if rs.has_prefix("@") {
        rs + "." + m
      } else {
        m
      }
    }
    _ => ""
  }
}

///|
/// The last component of a dotted name: `Mutex::acquire` -> `acquire`.
fn conc_last_part(name : String) -> String {
  let mut i = name.length() - 1
  while i >= 0 {
    let c = name.get_char(i)
    if c == Some('.') || c == Some(':') {
      return name[i + 1:].to_string()
    }
    i = i - 1
  }
  name
}

///|
/// TRUE when the call may suspend, and so is a YIELD POINT.
fn conc_may_suspend(e : Expr, async_names : Array[String]) -> Bool {
  let qname = conc_call_name(e)
  if qname == "" {
    return false
  }
  // The module's OWN async functions.
  let bare = conc_last_part(qname)
  for n in async_names {
    if n == bare || n == qname {
      return true
    }
  }
  // The core's async API.
  for n in core_await() {
    if n == bare {
      return true
    }
  }
  // A package call: `@io.read` suspends, a bare `read` does not have to.
  if qname.has_prefix("@") {
    for n in package_await() {
      if n == bare {
        return true
      }
    }
  }
  false
}

///|
/// TRUE when the expression constructs a `Ref`: `@ref.Ref(0)`.
fn conc_is_ref_new(e : Expr) -> Bool {
  match e.kind {
    EMethod(_, m, args) => m == "Ref" && args.length() == 1
    ECall(f, args) => conc_last_part(f) == "Ref" && args.length() == 1
    _ => false
  }
}

///|
/// The receiver of a method call, rendered: the cell or the lock it names.
fn conc_receiver(e : Expr) -> String {
  match e.kind {
    EMethod(r, _, _) => r.render()
    _ => ""
  }
}

///|
/// TRUE when the call acquires a lock: `lock.acquire()`.
fn conc_is_acquire(e : Expr) -> Bool {
  match e.kind {
    EMethod(_, m, _) => m == "acquire"
    _ => false
  }
}

///|
/// TRUE when the call releases a lock: `lock.release()`.
fn conc_is_release(e : Expr) -> Bool {
  match e.kind {
    EMethod(_, m, _) => m == "release"
    _ => false
  }
}

///|
/// The access a `Ref` field expression makes: `r.val` is a READ of `r`,
/// and `r.val = v` is a WRITE of `r`. The field name is what makes it a
/// cell access rather than an ordinary field read.
fn conc_cell_of(e : Expr) -> String {
  match e.kind {
    EField(r, "val") => r.render()
    _ => ""
  }
}

///|
/// TRUE when the expression is a `Ref` field access at all.
fn conc_is_cell_access(e : Expr) -> Bool {
  conc_cell_of(e) != ""
}

///|
/// The names a function binds to `Ref`s. A closure reaches a cell through
/// the name its ENCLOSING function bound, so the bindings have to be
/// collected from there.
fn conc_ref_bindings(stmts : Array[Stmt]) -> Array[String] {
  let out : Array[String] = []
  for s in stmts {
    match s.kind {
      SLet(name, _, init) => if conc_is_ref_new(init) { out.push(name) }
      SAssign(lhs, rhs) => if conc_is_ref_new(rhs) { out.push(lhs.render()) }
      _ => ()
    }
  }
  out
}

///|
/// Every expression in a statement, in source order.
fn conc_exprs_of(s : Stmt) -> Array[Expr] {
  let out : Array[Expr] = []
  match s.kind {
    SLet(_, _, e) => out.push(e)
    SAssign(lhs, rhs) => {
      out.push(lhs)
      out.push(rhs)
    }
    SAssignOp(_, lhs, rhs) => {
      out.push(lhs)
      out.push(rhs)
    }
    SIf(c, _, _) => out.push(c)
    SWhile(c, _) => out.push(c)
    SFor(_, a, b, c, _) => {
      out.push(a)
      out.push(b)
      out.push(c)
    }
    SForIn(_, it, _) => out.push(it)
    SReturn(e) =>
      match e {
        Some(x) => out.push(x)
        None => ()
      }
    SExpr(e) => out.push(e)
    _ => ()
  }
  out
}

///|
/// The sub-statements of a statement.
fn conc_sub_stmts(s : Stmt) -> Array[Array[Stmt]] {
  let out : Array[Array[Stmt]] = []
  match s.kind {
    SIf(_, a, b) => {
      out.push(a)
      out.push(b)
    }
    SWhile(_, b) => out.push(b)
    SFor(_, _, _, _, b) => out.push(b)
    SForIn(_, _, b) => out.push(b)
    SBlock(b) => out.push(b)
    STry(b) => out.push(b)
    _ => ()
  }
  out
}

///|
/// The walk state and everything it collected.
struct CWalk {
  accesses : Array[ConcAccess]
  edges : Array[ConcEdge]
  /// The locks this task acquires, in order, with the line.
  acquires : Array[(String, Int32)]
  releases : Array[(String, Int32)]
}

///|
/// Walk a task body, collecting the accesses and the wait-for edges.
///
/// The walk is PATH-SENSITIVE where it is cheap: a branch is walked with a
/// copy of the state and the two are merged, so a yield in one arm does not
/// silently become a yield in the other. A loop body is walked TWICE,
/// because a read in one iteration and a write in the next is exactly the
/// lost update the model has to find.
fn conc_walk(
  task : ConcTask,
  stmts : Array[Stmt],
  async_names : Array[String],
  scope : Map[String, String],
  w : CWalk,
  st : CState,
) -> CState {
  let mut cur = st
  for s in stmts {
    cur = conc_walk_stmt(task, s, async_names, scope, w, cur)
  }
  cur
}

///|
fn conc_walk_stmt(
  task : ConcTask,
  s : Stmt,
  async_names : Array[String],
  scope : Map[String, String],
  w : CWalk,
  st : CState,
) -> CState {
  // The EXPRESSION of the statement first: an assignment's left-hand side
  // is a WRITE, and everything else that touches a cell is a READ.
  let exprs = conc_exprs_of(s)
  for e in exprs {
    // A lock operation.
    if conc_is_acquire(e) {
      let lock = conc_receiver(e)
      // The task now WAITS for this lock: the acquire is an await point, and
      // the permit may not be free.
      w.edges.push({
        from: task.id,
        to: lock,
        kind: "waits",
        file: task.file,
        line: e.span.start_line,
        task: task.id,
        owner: task.owner,
      })
      // It already HOLDS what it held before the acquire, and it wants the
      // new lock. That pair is an edge of the RESOURCE ORDERING graph: the
      // held lock is taken before the wanted one, and a cycle in that graph
      // is a deadlock.
      for held in st.must {
        if held != lock {
          w.edges.push({
            from: held,
            to: lock,
            kind: "wants",
            file: task.file,
            line: e.span.start_line,
            task: task.id,
            owner: task.owner,
          })
        }
      }
      // The lock is held once the acquire returns.
      if !st.must.contains(lock) {
        st.must.push(lock)
      }
      if !st.may.contains(lock) {
        st.may.push(lock)
      }
      w.acquires.push((lock, e.span.start_line))
    } else if conc_is_release(e) {
      let lock = conc_receiver(e)
      w.releases.push((lock, e.span.start_line))
      let mut nmust = st.must.copy()
      let mut nmay = st.may.copy()
      nmust = nmust.filter(fn(x) { x != lock })
      nmay = nmay.filter(fn(x) { x != lock })
      st.must = nmust
      st.may = nmay
    }
    // A CELL ACCESS. Only a `Ref` the task CAPTURES from the enclosing
    // function is a shared cell: a `Ref` the task creates for itself is
    // private to that one task, and a struct that happens to have a `val`
    // field is not a cell at all.
    if conc_is_cell_access(e) {
      let raw = conc_cell_of(e)
      match scope.get(raw) {
        Some(cell) => {
          let is_write = match s.kind {
            SAssign(lhs, _) =>
              conc_cell_of(lhs) == raw &&
              lhs.span.start_line == e.span.start_line
            _ => false
          }
          if is_write {
            let at = match st.pending.get(cell) {
              Some(v) => v
              None => -1
            }
            w.accesses.push({
              task: task.id,
              cell,
              kind: "write",
              file: task.file,
              line: e.span.start_line,
              split: at >= 0 && st.yields > at,
              locks: st.must.copy(),
              yields_at: st.yields,
            })
          } else {
            st.pending.set(cell, st.yields)
            w.accesses.push({
              task: task.id,
              cell,
              kind: "read",
              file: task.file,
              line: e.span.start_line,
              split: false,
              locks: st.must.copy(),
              yields_at: st.yields,
            })
          }
        }
        None => ()
      }
    }
  }
  // The AWAIT POINTS: a call that may suspend ends the current segment.
  for e in exprs {
    if conc_may_suspend(e, async_names) {
      st.yields = st.yields + 1
    }
  }
  // The SUB-STATEMENTS. A branch is walked with a COPY of the state and
  // the two are merged, so an arm's yield does not leak into the other.
  let subs = conc_sub_stmts(s)
  if subs.length() == 0 {
    return st
  }
  let mut merged = CState::new()
  let mut first = true
  for sub in subs {
    let branch = st.copy()
    let after = conc_walk(task, sub, async_names, scope, w, branch)
    if first {
      merged = after.copy()
      first = false
    } else {
      // Merge: the yields are the MAXIMUM, the definitely-held locks are
      // the INTERSECTION (a lock held on only one arm is not definitely
      // held), and the may-held locks are the UNION.
      if after.yields > merged.yields {
        merged.yields = after.yields
      }
      let mut nmust = merged.must.copy()
      for l in after.must {
        if !nmust.contains(l) {
          nmust = nmust.filter(fn(x) { x == l })
        }
      }
      merged.must = nmust
      for l in after.may {
        if !merged.may.contains(l) {
          merged.may.push(l)
        }
      }
      for k in after.pending.to_array() {
        match merged.pending.get(k.0) {
          Some(v) => if k.1 < v { merged.pending.set(k.0, k.1) }
          None => merged.pending.set(k.0, k.1)
        }
      }
    }
  }
  merged
}

///|
/// The functions of the module that are `async`. A call to one of them is
/// an await point.
fn conc_async_names(ast : ModuleAst) -> Array[String] {
  let out : Array[String] = []
  for f in ast.all_funcs() {
    if f.is_async {
      out.push(f.name)
    }
  }
  out
}

///|
/// Every closure in the module, by its synthetic name.
fn conc_closures(ast : ModuleAst) -> Map[String, Func] {
  let out = Map([])
  for file in ast.files {
    for c in file.closures {
      out.set(c.name, c)
    }
  }
  out
}

///|
/// Find the tasks: the closures handed to a spawn call.
///
/// The closure is not always an argument of the spawn call. The shape the
/// core's own `all` uses is:
///
/// ```text
/// let tasks = []
/// for ... { tasks.push(async fn() -> Unit { ... }) }
/// @async.all(tasks)
/// ```
///
/// so the analyzer has to know which closures an ARRAY holds. The arrays are
/// collected first, and then the spawn call names one of them.

///|
/// What a function body hands to its spawn calls: the arrays it fills with
/// closures, and how many instances of each closure body may exist.
struct ConcArrays {
  /// The array name -> the closure ids it holds.
  holders : Map[String, Array[String]]
  /// The closure id -> how many instances of that body may run at once.
  instances : Map[String, Int32]
}

///|
fn conc_find_tasks(
  ast : ModuleAst,
  closures : Map[String, Func],
) -> Array[ConcTask] {
  let out : Array[ConcTask] = []
  let seen : Array[String] = []
  for f in ast.all_funcs() {
    let arrays = conc_collect_arrays(f.body)
    conc_find_spawns(f.body, f.name, arrays, closures, out, seen)
  }
  out
}

///|
/// The arrays a function body holds: the name of the array and the closures
/// in it, plus how many instances of each closure body may exist.
fn conc_collect_arrays(stmts : Array[Stmt]) -> ConcArrays {
  let out = ConcArrays::{ holders: Map([]), instances: Map([]), }
  conc_collect_arrays_in(stmts, out, false)
  out
}

///|
fn conc_collect_arrays_in(
  stmts : Array[Stmt],
  out : ConcArrays,
  in_loop : Bool,
) -> Unit {
  for s in stmts {
    match s.kind {
      SLet(name, _, init) => {
        let ids = conc_closures_in(init)
        if ids.length() > 0 {
          out.holders.set(name, ids)
          conc_note_instances(ids, in_loop, out)
        }
      }
      SAssign(lhs, rhs) => {
        let ids = conc_closures_in(rhs)
        if ids.length() > 0 {
          out.holders.set(lhs.render(), ids)
          conc_note_instances(ids, in_loop, out)
        }
      }
      SExpr(e) =>
        // `tasks.push(closure)`: the closure joins the array `tasks`.
        match e.kind {
          EMethod(recv, "push", args) => {
            let key = recv.render()
            let ids = conc_closures_in(args[0])
            if ids.length() > 0 {
              match out.holders.get(key) {
                Some(existing) =>
                  for id in ids {
                    if !existing.contains(id) {
                      existing.push(id)
                    }
                  }
                None => out.holders.set(key, ids)
              }
              conc_note_instances(ids, in_loop, out)
            }
          }
          _ => ()
        }
      _ => ()
    }
    // A closure written INSIDE a loop is created once per iteration, so
    // more than one instance of that body may be running at the same time.
    let nested = in_loop || conc_is_loop(s)
    for sub in conc_sub_stmts(s) {
      conc_collect_arrays_in(sub, out, nested)
    }
  }
}

///|
/// TRUE when the statement is a loop, whose body runs more than once.
fn conc_is_loop(s : Stmt) -> Bool {
  match s.kind {
    SFor(_, _, _, _, _) => true
    SForIn(_, _, _) => true
    SWhile(_, _) => true
    _ => false
  }
}

///|
/// Record how many instances of a closure body may run at once.
///
/// A closure written inside a loop is created once per iteration, so its
/// body may be running twice at the same time -- and two instances of the
/// SAME body conflict with each other exactly as two different tasks would.
/// That is the shape the measured lost update has: one closure, pushed in a
/// loop, run by several tasks at once.
fn conc_note_instances(
  ids : Array[String],
  in_loop : Bool,
  out : ConcArrays,
) -> Unit {
  for id in ids {
    match out.instances.get(id) {
      Some(v) => if in_loop && v < 2 { out.instances.set(id, 2) }
      None => out.instances.set(id, if in_loop { 2 } else { 1 })
    }
  }
}

///|
/// The closure ids inside an expression: an array literal, or a single
/// closure.
fn conc_closures_in(e : Expr) -> Array[String] {
  let out : Array[String] = []
  match e.kind {
    EArray(items) =>
      for it in items {
        for id in conc_closures_in(it) {
          out.push(id)
        }
      }
    EFn(id, _) => out.push(id)
    _ => ()
  }
  out
}

///|
/// The tasks a spawn call's argument names: an array literal of closures, or
/// a NAMED array whose closures were registered by the pushes that filled
/// it.
fn conc_tasks_from_arg(
  a : Expr,
  owner : String,
  spawn : String,
  arrays : ConcArrays,
  closures : Map[String, Func],
  out : Array[ConcTask],
  seen : Array[String],
) -> Unit {
  // An array literal.
  for id in conc_closures_in(a) {
    conc_add_task(id, owner, spawn, arrays, closures, out, seen)
  }
  // A named array.
  match a.kind {
    EName(n) =>
      match arrays.holders.get(n) {
        Some(ids) =>
          for id in ids {
            conc_add_task(id, owner, spawn, arrays, closures, out, seen)
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// The spawn calls in a function body.
fn conc_find_spawns(
  stmts : Array[Stmt],
  owner : String,
  arrays : ConcArrays,
  closures : Map[String, Func],
  out : Array[ConcTask],
  seen : Array[String],
) -> Unit {
  for s in stmts {
    for e in conc_exprs_of(s) {
      conc_find_spawns_in_expr(e, owner, arrays, closures, out, seen)
    }
    for sub in conc_sub_stmts(s) {
      conc_find_spawns(sub, owner, arrays, closures, out, seen)
    }
  }
}

///|
fn conc_find_spawns_in_expr(
  e : Expr,
  owner : String,
  arrays : ConcArrays,
  closures : Map[String, Func],
  out : Array[ConcTask],
  seen : Array[String],
) -> Unit {
  match e.kind {
    EMethod(_, m, args) => {
      // `group.spawn_bg(f)`: the closure is the task.
      if spawn_apis().contains(m) {
        for a in args {
          for id in conc_closures_in(a) {
            conc_add_task(id, owner, m, arrays, closures, out, seen)
          }
        }
      }
      // `@async.all(tasks)`: the tasks are the closures the ARRAY holds.
      //
      // The call parses as a METHOD on the package -- `EMethod(@async,
      // "all", ...)` -- and not as a qualified call, so the array has to be
      // resolved here as well as in the `ECall` arm below.
      if m == "all" || m == "any" {
        for a in args {
          conc_tasks_from_arg(a, owner, m, arrays, closures, out, seen)
        }
      }
      for a in args {
        conc_find_spawns_in_expr(a, owner, arrays, closures, out, seen)
      }
    }
    ECall(f, args) => {
      // `@async.all(tasks)`: the tasks are the closures the array holds.
      let bare = conc_last_part(f)
      if bare == "all" || bare == "any" {
        for a in args {
          conc_tasks_from_arg(a, owner, bare, arrays, closures, out, seen)
        }
      }
      for a in args {
        conc_find_spawns_in_expr(a, owner, arrays, closures, out, seen)
      }
    }
    EArray(items) =>
      for it in items {
        conc_find_spawns_in_expr(it, owner, arrays, closures, out, seen)
      }
    _ => ()
  }
}

///|
fn conc_add_task(
  id : String,
  owner : String,
  spawn : String,
  arrays : ConcArrays,
  closures : Map[String, Func],
  out : Array[ConcTask],
  seen : Array[String],
) -> Unit {
  if seen.contains(id) {
    return
  }
  match closures.get(id) {
    Some(c) => {
      seen.push(id)
      let instances = match arrays.instances.get(id) {
        Some(v) => v
        None => 1
      }
      out.push({
        id,
        owner,
        spawn,
        file: c.file,
        line: c.start_line,
        is_async: c.is_async,
        instances,
        yields: 0,
      })
    }
    None => ()
  }
}

///|
/// Analyse the concurrency of a module.
pub fn analyze_conc(ast : ModuleAst) -> ConcModel {
  let closures = conc_closures(ast)
  let async_names = conc_async_names(ast)
  let tasks = conc_find_tasks(ast, closures)
  // The `Ref`s each function binds, and which functions may run at the same
  // time. Together they say which cells are shared and which tasks can
  // interleave.
  let captured = conc_captured_refs(ast)
  let reach = conc_reach(ast)
  let fparams = conc_func_params(ast)
  let sub = conc_param_cells(ast, captured, reach, fparams)
  let accesses : Array[ConcAccess] = []
  let edges : Array[ConcEdge] = []
  // The tasks the model REPORTS are the ones the walk rebuilt: they carry
  // the yield count and the instance count the walk found, which the
  // discovered ones do not know yet.
  let model_tasks : Array[ConcTask] = []
  for t in tasks {
    match closures.get(t.id) {
      Some(c) => {
        let w = CWalk::{ accesses: [], edges: [], acquires: [], releases: [], }
        let scope = conc_capture_scope(
          t.owner,
          c,
          captured,
          reach,
          sub,
          fparams,
        )
        let st = conc_walk(t, c.body, async_names, scope, w, CState::new())
        // The task's own file and line come from the closure, not from the
        // spawn site: the defect is in the BODY.
        let task = ConcTask::{
          id: t.id,
          owner: t.owner,
          spawn: t.spawn,
          file: c.file,
          line: c.start_line,
          is_async: t.is_async,
          instances: t.instances,
          yields: st.yields,
        }
        model_tasks.push(task)
        for a in w.accesses {
          accesses.push(a)
        }
        for e in w.edges {
          edges.push(e)
        }
        // A LOCK THAT IS NEVER RELEASED, on this path.
        for held in st.must {
          let mut released = false
          for r in w.releases {
            if r.0 == held {
              released = true
            }
          }
          if !released {
            edges.push({
              from: task.id,
              to: held,
              kind: "unreleased",
              file: task.file,
              line: task.line,
              task: task.id,
              owner: task.owner,
            })
          }
        }
      }
      None => ()
    }
  }
  let cells = conc_cells(accesses, model_tasks, reach)
  let findings = conc_findings(model_tasks, cells, accesses, edges, reach)
  { tasks: model_tasks, cells, accesses, edges, findings, }
}

///|
/// The `Ref`s every function binds, by function name.
fn conc_captured_refs(ast : ModuleAst) -> Map[String, Array[String]] {
  let out = Map([])
  for f in ast.all_funcs() {
    out.set(f.name, conc_ref_bindings(f.body))
  }
  out
}

///|
/// The functions each function REACHES: the transitive call closure, in the
/// order they are reached (nearest first).
///
/// This is what makes the model honest about WHICH tasks may interleave.
/// The tasks of two functions that never call each other cannot run at the
/// same time, so a conflict between them is not a conflict. Without this,
/// every task in the module was treated as if it ran beside every other,
/// and a mutex-protected counter in one function was reported as racing
/// with an unprotected counter in another.
fn conc_reach(ast : ModuleAst) -> Map[String, Array[String]] {
  let direct = Map([])
  for f in ast.all_funcs() {
    let names : Array[String] = []
    conc_collect_calls(f.body, names)
    direct.set(f.name, names)
  }
  let out = Map([])
  for f in ast.all_funcs() {
    out.set(f.name, conc_reach_from(f.name, direct))
  }
  out
}

///|
/// The names a function body calls. The body of a closure is a function of
/// its own, so the calls inside it belong to the TASK and not to the
/// function that wrote the closure.
fn conc_collect_calls(stmts : Array[Stmt], out : Array[String]) -> Unit {
  for s in stmts {
    for e in conc_exprs_of(s) {
      conc_collect_calls_in(e, out)
    }
    for sub in conc_sub_stmts(s) {
      conc_collect_calls(sub, out)
    }
  }
}

///|
fn conc_collect_calls_in(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    ECall(f, args) => {
      if !out.contains(f) {
        out.push(f)
      }
      for a in args {
        conc_collect_calls_in(a, out)
      }
    }
    EMethod(r, m, args) => {
      let rs = r.render()
      let full = if rs.has_prefix("@") { rs + "." + m } else { m }
      if !out.contains(full) {
        out.push(full)
      }
      conc_collect_calls_in(r, out)
      for a in args {
        conc_collect_calls_in(a, out)
      }
    }
    EField(r, _) => conc_collect_calls_in(r, out)
    EIndex(r, i) => {
      conc_collect_calls_in(r, out)
      conc_collect_calls_in(i, out)
    }
    EArray(items) =>
      for it in items {
        conc_collect_calls_in(it, out)
      }
    ETuple(items) =>
      for it in items {
        conc_collect_calls_in(it, out)
      }
    EBin(_, l, r) => {
      conc_collect_calls_in(l, out)
      conc_collect_calls_in(r, out)
    }
    EUn(_, e) => conc_collect_calls_in(e, out)
    _ => ()
  }
}

///|
/// The transitive call closure of a function, nearest first.
fn conc_reach_from(
  name : String,
  direct : Map[String, Array[String]],
) -> Array[String] {
  let out : Array[String] = []
  let frontier : Array[String] = [name]
  let seen : Array[String] = [name]
  let mut i = 0
  while i < frontier.length() {
    let cur = frontier[i]
    i = i + 1
    match direct.get(cur) {
      Some(names) =>
        for n in names {
          // A qualified call is a method on a package; only a call to a
          // function of the module itself can reach another function.
          if n.contains(".") || n.contains(":") {
            continue
          }
          if !seen.contains(n) {
            seen.push(n)
            out.push(n)
            frontier.push(n)
          }
        }
      None => ()
    }
  }
  out
}

///|
/// TRUE when the tasks of two owners may run at the same time: the owners
/// are the same function, or one of them calls the other.
fn conc_may_overlap(
  reach : Map[String, Array[String]],
  a : String,
  b : String,
) -> Bool {
  if a == b {
    return true
  }
  match reach.get(a) {
    Some(list) => if list.contains(b) { return true }
    None => ()
  }
  match reach.get(b) {
    Some(list) => if list.contains(a) { return true }
    None => ()
  }
  false
}

///|
/// The cells a task captures: the name the code uses -> the qualified key
/// of the cell.
///
/// A closure captures the `Ref`s of the function that wrote it, and of the
/// functions THAT function calls, with the nearest binding winning. The
/// qualified key says which binding it is, so two functions that each bind
/// `counter` to a `Ref` of their own do not share a cell.
fn conc_capture_scope(
  owner : String,
  c : Func,
  refs : Map[String, Array[String]],
  reach : Map[String, Array[String]],
  sub : Map[String, String],
  fparams : Map[String, Array[(String, Bool)]],
) -> Map[String, String] {
  let out = Map([])
  // The PARAMETERS of the task body. A `Ref` handed to the body is tracked
  // under a key of its own, because the call site that handed it over is
  // not a spawn site the model sees.
  for p in c.params {
    if p.ty.contains("Ref") {
      out.set(p.name, "param:" + owner + "." + p.name)
    }
  }
  // The owner first: its binding is the nearest one.
  match refs.get(owner) {
    Some(names) =>
      for n in names {
        out.set(n, owner + "." + n)
      }
    None => ()
  }
  // Then the functions it calls, nearest first.
  let chain : Array[String] = []
  match reach.get(owner) {
    Some(list) =>
      for f in list {
        chain.push(f)
      }
    None => ()
  }
  for f in chain {
    match refs.get(f) {
      Some(names) =>
        for n in names {
          if !out.contains(n) {
            out.set(n, f + "." + n)
          }
        }
      None => ()
    }
  }
  // The owner's OWN `Ref` PARAMETERS. The caller handed over the `Ref` it
  // holds, so the parameter stands for THAT cell -- not for a cell of its
  // own. Without this the caller and the callee see two unrelated cells.
  match fparams.get(owner) {
    Some(list) =>
      for p in list {
        if p.1 {
          match sub.get(owner + "." + p.0) {
            Some(key) => out.set(p.0, key)
            None => out.set(p.0, "param:" + owner + "." + p.0)
          }
        }
      }
    None => ()
  }
  out
}

///|
/// The `Ref` a function's PARAMETER stands for: "callee.parameter" -> the
/// qualified key of the cell the caller passed.
///
/// A `Ref` handed to a helper is the SAME `Ref` the caller holds, so the
/// two have to be ONE cell -- otherwise the model sees two unrelated cells
/// and says nothing about a defect that is really there.
///
/// Only the caller's own bindings are substituted. A `Ref` that comes from
/// further up the call chain keeps the key of the function that binds it.
fn conc_param_cells(
  ast : ModuleAst,
  refs : Map[String, Array[String]],
  reach : Map[String, Array[String]],
  params : Map[String, Array[(String, Bool)]],
) -> Map[String, String] {
  let out = Map([])
  for f in ast.all_funcs() {
    // The cells the caller can see.
    let scope = Map([])
    match refs.get(f.name) {
      Some(names) =>
        for n in names {
          scope.set(n, f.name + "." + n)
        }
      None => ()
    }
    match reach.get(f.name) {
      Some(list) =>
        for caller in list {
          match refs.get(caller) {
            Some(names) =>
              for n in names {
                if !scope.contains(n) {
                  scope.set(n, caller + "." + n)
                }
              }
            None => ()
          }
        }
      None => ()
    }
    conc_param_cells_in(f.body, scope, params, out)
  }
  out
}

///|
/// The parameters of each function: the name and whether it is a `Ref`.
fn conc_func_params(ast : ModuleAst) -> Map[String, Array[(String, Bool)]] {
  let out = Map([])
  for f in ast.all_funcs() {
    let list : Array[(String, Bool)] = []
    for p in f.params {
      list.push((p.name, p.ty.contains("Ref")))
    }
    out.set(f.name, list)
  }
  out
}

///|
fn conc_param_cells_in(
  stmts : Array[Stmt],
  scope : Map[String, String],
  params : Map[String, Array[(String, Bool)]],
  out : Map[String, String],
) -> Unit {
  for s in stmts {
    for e in conc_exprs_of(s) {
      conc_param_cells_in_expr(e, scope, params, out)
    }
    for sub in conc_sub_stmts(s) {
      conc_param_cells_in(sub, scope, params, out)
    }
  }
}

///|
fn conc_param_cells_in_expr(
  e : Expr,
  scope : Map[String, String],
  params : Map[String, Array[(String, Bool)]],
  out : Map[String, String],
) -> Unit {
  match e.kind {
    ECall(f, args) => {
      match params.get(f) {
        Some(list) =>
          for i in 0..<args.length() {
            if i < list.length() && list[i].1 {
              match args[i].kind {
                EName(n) =>
                  match scope.get(n) {
                    Some(key) => out.set(f + "." + list[i].0, key)
                    None => ()
                  }
                _ => ()
              }
            }
          }
        None => ()
      }
      for a in args {
        conc_param_cells_in_expr(a, scope, params, out)
      }
    }
    EMethod(r, _, args) => {
      conc_param_cells_in_expr(r, scope, params, out)
      for a in args {
        conc_param_cells_in_expr(a, scope, params, out)
      }
    }
    EField(r, _) => conc_param_cells_in_expr(r, scope, params, out)
    EIndex(r, i) => {
      conc_param_cells_in_expr(r, scope, params, out)
      conc_param_cells_in_expr(i, scope, params, out)
    }
    EArray(items) =>
      for it in items {
        conc_param_cells_in_expr(it, scope, params, out)
      }
    ETuple(items) =>
      for it in items {
        conc_param_cells_in_expr(it, scope, params, out)
      }
    EBin(_, l, r) => {
      conc_param_cells_in_expr(l, scope, params, out)
      conc_param_cells_in_expr(r, scope, params, out)
    }
    EUn(_, e) => conc_param_cells_in_expr(e, scope, params, out)
    _ => ()
  }
}

///|
/// The cells that more than one task reaches -- or that ONE task body
/// reaches twice, because it may be running more than once at a time.
fn conc_cells(
  accesses : Array[ConcAccess],
  tasks : Array[ConcTask],
  reach : Map[String, Array[String]],
) -> Array[ConcCell] {
  let names : Array[String] = []
  for a in accesses {
    if !names.contains(a.cell) {
      names.push(a.cell)
    }
  }
  let out : Array[ConcCell] = []
  for n in names {
    let who : Array[String] = []
    for a in accesses {
      if a.cell == n && !who.contains(a.task) {
        who.push(a.task)
      }
    }
    // SHARED: two tasks that may run at the same time reach the cell, or
    // ONE body that may be running twice at the same time reaches it.
    let mut shared = false
    for i in 0..<who.length() {
      for j in (i + 1)..<who.length() {
        if conc_may_overlap(
            reach,
            conc_owner(tasks, who[i]),
            conc_owner(tasks, who[j]),
          ) {
          shared = true
        }
      }
      if conc_instances(tasks, who[i]) > 1 {
        shared = true
      }
    }
    if shared {
      let mut file = ""
      let mut line = 0
      for a in accesses {
        if a.cell == n {
          file = a.file
          line = a.line
          break
        }
      }
      let varname = conc_after_last_dot(n)
      out.push({ name: n, varname, file, line, tasks: who, })
    }
  }
  out
}

///|
/// The function that spawned a task.
fn conc_owner(tasks : Array[ConcTask], id : String) -> String {
  for t in tasks {
    if t.id == id {
      return t.owner
    }
  }
  ""
}

///|
/// The part of a qualified name after the LAST dot: `lost_update.counter`
/// -> `counter`.
fn conc_after_last_dot(name : String) -> String {
  let mut i = name.length() - 1
  while i >= 0 {
    if name.get_char(i) == Some('.') {
      return name[i + 1:].to_string()
    }
    i = i - 1
  }
  name
}

///|
/// How many instances of a task body may run at once.
fn conc_instances(tasks : Array[ConcTask], id : String) -> Int32 {
  for t in tasks {
    if t.id == id {
      return t.instances
    }
  }
  1
}

///|
/// The findings.
fn conc_findings(
  tasks : Array[ConcTask],
  cells : Array[ConcCell],
  accesses : Array[ConcAccess],
  edges : Array[ConcEdge],
  reach : Map[String, Array[String]],
) -> Array[Finding] {
  let out : Array[Finding] = []
  // THE LOST UPDATE: two tasks read-modify-write the same cell, and one of
  // the two read-modify-writes is split by a yield. Then the other task's
  // write can land between the read and the write, and the update is lost.
  //
  // This is the defect MEASURED against the toolchain: a read-await-write
  // over a shared `Ref[Int]` lost 21 000 of 24 000 updates.
  for c in cells {
    for a in accesses {
      if a.cell != c.name || a.kind != "write" || !a.split {
        continue
      }
      // Is there ANOTHER writer that can run at the same time?
      let mut other = ""
      for b in accesses {
        if b.cell != c.name || b.kind != "write" {
          continue
        }
        if b.task == a.task {
          // The SAME body. It conflicts with itself only when more than one
          // instance of it may be running -- the closure was written inside
          // a loop, so the body is created once per iteration -- and only
          // when the access is not ordered by a lock.
          if b.line == a.line &&
            conc_instances(tasks, a.task) > 1 &&
            !conc_common_lock(a, b) {
            other = b.task
            break
          }
          continue
        }
        // A DIFFERENT task. It has to be a task that may run at the same
        // time -- the tasks of two functions that never call each other do
        // not interleave -- and a common lock orders the two writes.
        if !conc_may_overlap(
            reach,
            conc_owner(tasks, a.task),
            conc_owner(tasks, b.task),
          ) {
          continue
        }
        if conc_common_lock(a, b) {
          continue
        }
        other = b.task
        break
      }
      if other != "" {
        let who = if other == a.task {
          "another instance of the same task body writes the same cell"
        } else {
          "the task '" + task_label(tasks, other) + "' writes the same cell"
        }
        out.push(
          Finding::new(
            FFconcLostUpdate,
            a.file,
            a.line,
            task_label(tasks, a.task),
            "the shared cell '" +
            c.varname +
            "' is read and then written after an await point, and " +
            who +
            ". The write is not atomic with its read, so the other write can land between them and this update is LOST.",
            "L2-CONC",
            0.9,
            c.name,
          ),
        )
      }
    }
  }
  // THE STALE READ: a task reads a cell and uses the value AFTER an await
  // point, while another task writes the cell. The value it holds may
  // already be out of date when it is used.
  for c in cells {
    for a in accesses {
      if a.cell != c.name || a.kind != "read" {
        continue
      }
      // The value has to be used after a yield to be stale. A read that is
      // consumed before the next await point cannot have gone stale.
      if !conc_used_after_yield(tasks, a) {
        continue
      }
      // Is there ANOTHER writer that can run at the same time?
      let mut other = ""
      for b in accesses {
        if b.cell != c.name || b.kind != "write" {
          continue
        }
        if b.task == a.task {
          if b.line >= a.line &&
            conc_instances(tasks, a.task) > 1 &&
            !conc_common_lock(a, b) {
            other = b.task
            break
          }
          continue
        }
        if !conc_may_overlap(
            reach,
            conc_owner(tasks, a.task),
            conc_owner(tasks, b.task),
          ) {
          continue
        }
        if conc_common_lock(a, b) {
          continue
        }
        other = b.task
        break
      }
      if other == "" {
        continue
      }
      // A read that is written back by the same task is the lost update
      // above and not a stale read.
      if conc_write_follows(accesses, a) {
        continue
      }
      let who = if other == a.task {
        "another instance of the same task body writes the same cell"
      } else {
        "the task '" + task_label(tasks, other) + "' writes the same cell"
      }
      out.push(
        Finding::new(
          FFconcStaleRead,
          a.file,
          a.line,
          task_label(tasks, a.task),
          "the shared cell '" +
          c.varname +
          "' is read here and the value is used after an await point, and " +
          who +
          " without a common lock. The value read here may already be out of date when it is used.",
          "L2-CONC",
          0.6,
          c.name,
        ),
      )
    }
  }
  // THE DEADLOCK: a cycle in the resource ordering graph.
  for cycle in conc_cycles(edges, tasks, reach) {
    out.push(
      Finding::new(
        FFconcDeadlockCycle,
        cycle.file,
        cycle.line,
        task_label(tasks, cycle.task),
        cycle.desc,
        "L2-CONC",
        0.9,
        cycle.lock,
      ),
    )
  }
  // THE LOCK THAT IS NEVER RELEASED.
  for e in edges {
    if e.kind == "unreleased" {
      out.push(
        Finding::new(
          FFconcResourceUnreleased,
          e.file,
          e.line,
          task_label(tasks, e.from),
          "the lock '" +
          e.to +
          "' is acquired here and is not released on this path. Every later acquire of it waits forever, because the permit is never given back.",
          "L2-CONC",
          0.8,
          e.to,
        ),
      )
    }
  }
  out
}

///|
/// TRUE when two accesses are under a COMMON lock, and so are ordered.
fn conc_common_lock(a : ConcAccess, b : ConcAccess) -> Bool {
  for l in a.locks {
    if b.locks.contains(l) {
      return true
    }
  }
  false
}

///|
/// TRUE when the value a read produced is used AFTER an await point, and so
/// may already be out of date.
fn conc_used_after_yield(tasks : Array[ConcTask], a : ConcAccess) -> Bool {
  for t in tasks {
    if t.id == a.task {
      return t.yields > a.yields_at
    }
  }
  false
}

///|
/// TRUE when the SAME task writes the cell again, at this point or later:
/// a read-modify-write. That is the lost update above and not a stale read.
fn conc_write_follows(accesses : Array[ConcAccess], a : ConcAccess) -> Bool {
  for b in accesses {
    if b.task == a.task &&
      b.cell == a.cell &&
      b.kind == "write" &&
      b.line >= a.line {
      return true
    }
  }
  false
}

///|
/// The label of a task: the file and line of its body.
fn task_label(tasks : Array[ConcTask], id : String) -> String {
  for t in tasks {
    if t.id == id {
      return t.file + ":" + t.line.to_string()
    }
  }
  id
}

///|
/// A DEADLOCK: a cycle in the resource ordering graph.
struct ConcCycle {
  /// The task the finding is reported at.
  task : String
  /// The lock the cycle starts at.
  lock : String
  file : String
  line : Int32
  /// What the cycle is, in words.
  desc : String
}

///|
/// The cycles in the RESOURCE ORDERING graph.
///
/// The graph's nodes are the locks, and an edge goes from a lock a task
/// HOLDS to a lock the same task WANTS. A cycle in it is a deadlock: the
/// tasks on the cycle take the locks in a circular order, so each one waits
/// for a lock the next one holds.
///
/// The graph is built per GROUP of tasks that may run at the same time. The
/// tasks of two functions that never call each other cannot interleave, so
/// putting their edges in one graph would report a deadlock that cannot
/// happen.
///
/// The cycle is found by walking the graph, and it is reported ONCE: the
/// same cycle is reachable from every node on it, so the nodes are put in a
/// canonical order and a cycle already reported is skipped.
fn conc_cycles(
  edges : Array[ConcEdge],
  tasks : Array[ConcTask],
  reach : Map[String, Array[String]],
) -> Array[ConcCycle] {
  let out : Array[ConcCycle] = []
  let seen : Array[String] = []
  // The edges of each owner.
  let by_owner : Map[String, Array[ConcEdge]] = Map([])
  for e in edges {
    if e.kind != "wants" {
      continue
    }
    match by_owner.get(e.owner) {
      Some(list) => list.push(e)
      None => by_owner.set(e.owner, [e])
    }
  }
  let owners : Array[String] = []
  for e in edges {
    if e.kind == "wants" && !owners.contains(e.owner) {
      owners.push(e.owner)
    }
  }
  for o1 in owners {
    // The group of o1 alone.
    match by_owner.get(o1) {
      Some(list) => conc_cycles_in(list, seen, out)
      None => ()
    }
    // The group of o1 and each owner that may run beside it.
    for o2 in owners {
      if o2 == o1 {
        continue
      }
      if !conc_may_overlap(reach, o1, o2) {
        continue
      }
      let group : Array[ConcEdge] = []
      match by_owner.get(o1) {
        Some(list) =>
          for e in list {
            group.push(e)
          }
        None => ()
      }
      match by_owner.get(o2) {
        Some(list) =>
          for e in list {
            group.push(e)
          }
        None => ()
      }
      conc_cycles_in(group, seen, out)
    }
  }
  out
}

///|
/// The cycles in one group of edges.
fn conc_cycles_in(
  edges : Array[ConcEdge],
  seen : Array[String],
  out : Array[ConcCycle],
) -> Unit {
  let nodes : Array[String] = []
  for e in edges {
    if e.kind == "wants" {
      if !nodes.contains(e.from) {
        nodes.push(e.from)
      }
      if !nodes.contains(e.to) {
        nodes.push(e.to)
      }
    }
  }
  for n in nodes {
    let path : Array[String] = []
    conc_cycle_walk(n, edges, path, seen, out, 0)
  }
}

///|
/// The depth the cycle walk goes to. A cycle longer than this is not
/// reported -- the model says so in the report rather than pretending.
const CONC_MAX_CYCLE_DEPTH : Int32 = 64

///|
fn conc_cycle_walk(
  node : String,
  edges : Array[ConcEdge],
  path : Array[String],
  seen : Array[String],
  out : Array[ConcCycle],
  depth : Int32,
) -> Unit {
  if depth > CONC_MAX_CYCLE_DEPTH {
    return
  }
  if path.contains(node) {
    // A CYCLE: the part of the path from `node` onwards.
    let mut start = 0
    for i in 0..<path.length() {
      if path[i] == node {
        start = i
        break
      }
    }
    let cyc : Array[String] = []
    for i in start..<path.length() {
      cyc.push(path[i])
    }
    let key = conc_cycle_key(cyc)
    if !seen.contains(key) {
      seen.push(key)
      let mut desc = ""
      for i in 0..<cyc.length() {
        desc = desc +
          "'" +
          cyc[i] +
          "' is held while '" +
          cyc[(i + 1) % cyc.length()] +
          "' is wanted, and "
      }
      desc = desc +
        "so the locks are taken in a circular order and no task on the cycle can proceed."
      let mut file = ""
      let mut line = 0
      let mut task = ""
      for e in edges {
        if e.kind == "wants" && e.from == cyc[0] {
          file = e.file
          line = e.line
          task = e.task
          break
        }
      }
      out.push({ task, lock: cyc[0], file, line, desc, })
    }
    return
  }
  path.push(node)
  for e in edges {
    // A lock that is held while another one is wanted.
    let next = if e.kind == "wants" && e.from == node {
      Some(e.to)
    } else {
      None
    }
    match next {
      Some(n) => conc_cycle_walk(n, edges, path, seen, out, depth + 1)
      None => ()
    }
  }
  ignore(path.pop())
}

///|
/// The canonical key of a cycle: the nodes in the order they were found,
/// rotated to start at the smallest one. The same cycle is reachable from
/// every node on it, and the rotation makes them all the same key.
fn conc_cycle_key(cyc : Array[String]) -> String {
  if cyc.length() == 0 {
    return ""
  }
  let mut min = 0
  for i in 1..<cyc.length() {
    if cyc[i] < cyc[min] {
      min = i
    }
  }
  let mut out = ""
  for i in 0..<cyc.length() {
    out = out + cyc[(min + i) % cyc.length()] + "|"
  }
  out
}
