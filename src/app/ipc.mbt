/// THE IPC AND BUFFER SAFETY MODEL.
///
/// MoonBit's own IPC -- sockets, pipes and process stdio -- goes through the
/// core's `BinaryReader` and `BinaryWriter` traits. Those traits have a
/// contract, and the contract is where the defects are. Everything below was
/// MEASURED against the toolchain and the core's own source, which is the
/// authority here -- not the documentation, and not a reading of the API's
/// shape:
///
///   - `read_into(dst, offset?, max_len?)` returns the NUMBER OF BYTES IT
///     READ. Measured: a 16-byte buffer pre-filled with `0xFF`, a pipe with 3
///     bytes in it, one `read_into` -> returned 3, and the buffer afterwards
///     was `61 62 63 FF FF FF ... FF`. The bytes past the count were never
///     written: they still held what the buffer held before. So a read can
///     leave a STALE TAIL, and the count is the only thing that says so.
///   - `read_into(buf, offset=8)` returned 3 and wrote at `buf[8..11]`. The
///     caller has to advance the offset by the count itself.
///   - At EOF `read_into` returns 0 and `read()` returns `None`. So 0 is
///     both "no progress" and "the stream ended", and a loop that discards
///     the count cannot tell them apart.
///   - `peek` returns a VIEW into the reader's own buffer, and the core says
///     so: "The returned chunk ... is a copy-free slice of the reader's
///     internal buffer, and its content will be overwritten by subsequent
///     reader operations. So caller of `peek` MUST NOT use the returned slice
///     after any other `BinaryReader` operation is invoked on the same
///     reader." Measured: peeked `61 62 63`; after two `read()` calls the
///     SAME view read `78 79 7A`. The reader keeps ONE buffer and reuses it.
///   - `write` is EXHAUSTIVE: it loops until every byte has been handed over.
///     Measured: 5 bytes written, read 2 at a time -> 5 bytes in 3 reads. So
///     there is NO partial-write defect at the `write` level, and this model
///     does not claim one.
///   - A pending write is NOT A SNAPSHOT. Measured: a 4-byte buffer of 'A',
///     handed to `write`, then overwritten with 'B' while the write was
///     still pending -> the reader received `42 42 42 42` ('B'), not the 'A's
///     that were in the buffer when the write was issued. So a buffer that is
///     reused while a write of it is pending delivers the NEW bytes.
///
/// The families are the defect classes those measurements make checkable.
/// What the model does NOT cover is in the report.

///|
/// A call the module makes on a reader or a writer.
pub struct IpcCall {
  /// The API name: `read_into`, `peek`, `write`, ...
  op : String
  /// The receiver: the variable the reader or the writer is bound to. Empty
  /// when the call is not a method call.
  receiver : String
  /// True when the value the call returns is DISCARDED.
  discarded : Bool
  /// The variable the value is bound to, when it is bound to one.
  bound : String
  file : String
  line : Int32
  fn_name : String
}

///|
/// A view into a reader's buffer: the result of a `peek`.
pub struct IpcView {
  /// The variable the view is bound to.
  name : String
  /// The reader the view points into.
  receiver : String
  /// The line of the `peek` that produced it.
  peek_line : Int32
  /// The line of the operation that broke it.
  broken_line : Int32
  /// The operation that broke it.
  broken_op : String
  file : String
  fn_name : String
}

///|
/// A buffer that a task body and the function that started it both write.
pub struct IpcShared {
  /// The buffer.
  name : String
  /// The task body that writes it.
  task : String
  /// The function that started the task.
  parent : String
  /// The line of the write in the task body.
  task_line : Int32
  /// The line of the use in the parent.
  parent_line : Int32
  file : String
  fn_name : String
}

///|
/// The whole IPC surface of a module.
pub struct IpcModel {
  /// The calls the module makes on its readers and writers.
  calls : Array[IpcCall]
  /// The views that were used after the reader had reused their buffer.
  views : Array[IpcView]
  /// The buffers that a task body and its parent both write.
  shared : Array[IpcShared]
  /// The findings.
  findings : Array[Finding]
}

///|
/// The working state of one function's scan.
priv struct IpcState {
  /// The reads whose count was DISCARDED and whose buffer has not been used
  /// since: the buffer may hold bytes the read never wrote.
  mut pending : Array[IpcPending]
  /// The views into a reader's buffer, and whether they have been broken.
  views : Array[IpcViewRec]
}

///|
/// A read whose count was discarded.
priv struct IpcPending {
  /// The buffer the read fills.
  name : String
  /// The line of the read.
  line : Int32
  /// The reader the read is on.
  receiver : String
}

///|
/// A view into a reader's buffer.
priv struct IpcViewRec {
  name : String
  receiver : String
  peek_line : Int32
  /// The line of the operation that broke the view, or 0 while it is good.
  mut broken_line : Int32
  mut broken_op : String
  /// False once the name has been bound again: the name then holds a
  /// DIFFERENT view, and the old one is not what the name shows.
  mut live : Bool
  /// True once the stale view has been reported, so one defect is one
  /// finding and not one per use.
  mut reported : Bool
}

///|
/// A call on a reader or a writer, as the scan sees it.
priv struct IpcCallRec {
  op : String
  receiver : String
  args : Array[Expr]
  discarded : Bool
  bound : String
}

///|
/// The reader API of the core. The analyzer matches the METHOD NAME: it does
/// not infer types, and the core's readers are a trait every reader
/// implements, so the name is the one thing they share.
fn ipc_reader_ops() -> Array[String] {
  [
    "read_into", "read", "read_at_least", "read_exactly", "read_all", "read_until",
    "peek", "peek_at_least", "peek_exactly", "drop_exactly", "drop_all",
  ]
}

///|
/// The writer API of the core.
fn ipc_writer_ops() -> Array[String] {
  ["write", "write_reader"]
}

///|
/// The calls that return a VIEW into the reader's own buffer.
fn ipc_peek_ops() -> Array[String] {
  ["peek", "peek_at_least", "peek_exactly"]
}

///|
/// True when the operation is one of the core's reader calls.
fn ipc_is_reader_op(op : String) -> Bool {
  ipc_reader_ops().contains(op)
}

///|
/// True when the operation returns a view into the reader's buffer.
fn ipc_is_peek_op(op : String) -> Bool {
  ipc_peek_ops().contains(op)
}

///|
/// The last part of a qualified name: `write` for `@io.write`.
fn ipc_last_part(name : String) -> String {
  let mut i = name.length() - 1
  while i >= 0 {
    if name[i] == '.' {
      return name[i + 1:].to_owned()
    }
    i = i - 1
  }
  name
}

///|
/// The root name of an expression: the variable it is, or "" when it is not
/// a plain variable.
fn ipc_root(e : Expr) -> String {
  match e.kind {
    EName(n) => n
    _ => ""
  }
}

///|
/// The name of the BUFFER an expression stands for.
///
/// A buffer is often not passed as the variable itself but as something
/// derived from it: `buf.unsafe_reinterpret_as_bytes()` is the buffer
/// `buf`, and `buf[0]` is the buffer `buf`. So the base of the expression is
/// what names it.
fn ipc_base_name(e : Expr) -> String {
  match e.kind {
    EName(n) => n
    EMethod(x, _, _) => ipc_base_name(x)
    EIndex(x, _) => ipc_base_name(x)
    EField(x, _) => ipc_base_name(x)
    _ => ""
  }
}

///|
/// The reader a bound expression takes its view from, when the expression
/// takes one at all.
///
/// The view is often bound through an `unwrap` -- `r.peek().unwrap()` -- so
/// the peek is looked for ANYWHERE in the expression rather than only at its
/// top.
fn ipc_find_peek(e : Expr) -> String? {
  match e.kind {
    EMethod(recv, m, _) =>
      if ipc_is_peek_op(m) {
        Some(ipc_root(recv))
      } else {
        ipc_find_peek(recv)
      }
    ECall(_, args) => ipc_find_peek_in(args)
    EBin(_, l, r) =>
      match ipc_find_peek(l) {
        Some(x) => Some(x)
        None => ipc_find_peek(r)
      }
    EUn(_, x) => ipc_find_peek(x)
    EField(x, _) => ipc_find_peek(x)
    EIndex(x, i) =>
      match ipc_find_peek(x) {
        Some(v) => Some(v)
        None => ipc_find_peek(i)
      }
    _ => None
  }
}

///|
fn ipc_find_peek_in(args : Array[Expr]) -> String? {
  for a in args {
    match ipc_find_peek(a) {
      Some(r) => return Some(r)
      None => ()
    }
  }
  None
}

///|
/// The whole IPC surface of a module.
pub fn analyze_ipc(ast : ModuleAst) -> IpcModel {
  let calls : Array[IpcCall] = []
  let views : Array[IpcView] = []
  let shared : Array[IpcShared] = []
  let findings : Array[Finding] = []
  let sigs = ipc_signatures(ast)
  for f in ast.all_funcs() {
    ipc_scan_function(f, calls, views, findings, sigs)
  }
  ipc_check_shared(ast, shared, findings)
  { calls, views, shared, findings, }
}

///|
/// The signatures of the module's own functions: the parameter types and the
/// return type.
///
/// This is the EVIDENCE that tells a VIEW from something else. A `peek` is a
/// common name — a parser has one, and it returns a token — so the name
/// alone cannot decide. What decides it is that the value is USED AS A VIEW:
/// passed to a parameter declared `BytesView`, handed to the core's writer,
/// or copied with a method only a view has.
fn ipc_signatures(ast : ModuleAst) -> Map[String, (Array[String], String)] {
  let out = Map([])
  for f in ast.all_funcs() {
    let params : Array[String] = []
    for p in f.params {
      params.push(p.ty)
    }
    out.set(f.name, (params, f.ret_ty))
  }
  out
}

///|
/// The methods only a `BytesView` has. A call on one of them proves the
/// receiver is a view.
fn ipc_view_only_methods() -> Array[String] {
  [
    "to_owned", "exact_view", "get_view", "clamped_view", "start_offset", "unsafe_get",
    "equal_to_bytes",
  ]
}

///|
/// True when the name is USED AS A VIEW in the body.
///
/// The evidence, all of it a fact about the source:
///
///   - the binding is annotated `BytesView`;
///   - the name is an argument to the core's WRITER — `write` and
///     `write_reader` take a `BytesView`;
///   - the name is an argument to one of the module's own functions, at a
///     position whose parameter is declared `BytesView`;
///   - the name is the receiver of a method only a view has;
///   - the name is returned from a function whose return type is `BytesView`.
fn ipc_used_as_view(
  stmts : Array[Stmt],
  name : String,
  fn_name : String,
  sigs : Map[String, (Array[String], String)],
) -> Bool {
  for s in stmts {
    match s.kind {
      SLet(bound, ty, _) =>
        if bound == name && ty.contains("BytesView") {
          return true
        }
      _ => ()
    }
    for e in ipc_exprs_of(s) {
      if ipc_expr_used_as_view(e, name, sigs) {
        return true
      }
    }
    for sub in ipc_sub_stmts(s) {
      if ipc_used_as_view(sub, name, fn_name, sigs) {
        return true
      }
    }
  }
  // The function RETURNS the view.
  match sigs.get(fn_name) {
    Some((_, ret)) =>
      if ret.contains("BytesView") {
        for s in stmts {
          match s.kind {
            SReturn(Some(e)) => if ipc_root(e) == name { return true }
            _ => ()
          }
        }
      }
    None => ()
  }
  false
}

///|
fn ipc_expr_used_as_view(
  e : Expr,
  name : String,
  sigs : Map[String, (Array[String], String)],
) -> Bool {
  match e.kind {
    ECall(f, args) => {
      // The core's WRITER takes a `BytesView`.
      if ipc_writer_ops().contains(ipc_last_part(f)) {
        for a in args {
          if ipc_root(a) == name {
            return true
          }
        }
        return false
      }
      // One of the module's own functions, at a `BytesView` parameter.
      match sigs.get(f) {
        Some((params, _)) => {
          let mut i = 0
          while i < args.length() {
            if i < params.length() &&
              params[i].contains("BytesView") &&
              ipc_root(args[i]) == name {
              return true
            }
            i = i + 1
          }
          false
        }
        // A callee the analyzer cannot see: a function of ANOTHER module.
        // Its parameter types are not visible, so the argument MAY be a
        // view -- and the argument is not the name being matched on, which
        // is what a token is used for.
        None => {
          let mut found = false
          for a in args {
            if ipc_root(a) == name {
              found = true
            }
          }
          found
        }
      }
    }
    EMethod(recv, m, args) => {
      // A method only a view has, on the name itself.
      if ipc_root(recv) == name && ipc_view_only_methods().contains(m) {
        return true
      }
      // The name handed to the core's writer.
      if ipc_writer_ops().contains(m) {
        for a in args {
          if ipc_root(a) == name {
            return true
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Scan one function.
fn ipc_scan_function(
  f : Func,
  calls : Array[IpcCall],
  views : Array[IpcView],
  findings : Array[Finding],
  sigs : Map[String, (Array[String], String)],
) -> Unit {
  let state = IpcState::{ pending: [], views: [], }
  // Which of the peeks produced a VIEW. This is worked out over the whole
  // body first, because a view may be used long after the peek that made it
  // -- and because a `peek` that returns something else is not a view at
  // all.
  let view_names = ipc_view_names(f.body, f.body, f.name, sigs)
  ipc_scan_stmts(f.body, f, false, state, calls, views, findings, view_names)
}

///|
/// The names in the body that a `peek` bound AND that are used as a view.
fn ipc_view_names(
  top : Array[Stmt],
  stmts : Array[Stmt],
  fn_name : String,
  sigs : Map[String, (Array[String], String)],
) -> Array[String] {
  let out : Array[String] = []
  for s in stmts {
    match s.kind {
      SLet(name, _, e) =>
        match ipc_find_peek(e) {
          Some(recv) =>
            if recv != "" &&
              !out.contains(name) &&
              ipc_used_as_view(top, name, fn_name, sigs) {
              out.push(name)
            }
          None => ()
        }
      _ => ()
    }
    for sub in ipc_sub_stmts(s) {
      for n in ipc_view_names(top, sub, fn_name, sigs) {
        if !out.contains(n) {
          out.push(n)
        }
      }
    }
  }
  out
}

///|
/// Scan a list of statements, in order.
///
/// The three statement-level rules share one walk, because they share one
/// question: what does this statement do to the reader's state, and to the
/// buffers the module reads into?
fn ipc_scan_stmts(
  stmts : Array[Stmt],
  f : Func,
  in_loop : Bool,
  state : IpcState,
  calls : Array[IpcCall],
  views : Array[IpcView],
  findings : Array[Finding],
  view_names : Array[String],
) -> Unit {
  for s in stmts {
    let call = ipc_call_of(s)
    // (1) A buffer whose count was discarded, used before it is written
    // again. The bytes past the count were never written.
    if state.pending.length() > 0 {
      let kept : Array[IpcPending] = []
      for p in state.pending {
        if ipc_stmt_mentions(s, p.name) {
          findings.push(
            Finding::new(
              FIpcPartialRead,
              f.file,
              s.span.start_line,
              f.name,
              "the count that '" +
              p.receiver +
              ".read_into' returns is discarded, so nothing says how much of '" +
              p.name +
              "' the read actually filled. Measured: a read can return fewer bytes than the buffer holds, and the bytes past the count keep whatever the buffer held before -- here the read is at line " +
              p.line.to_string() +
              ".",
              "L2-IPC",
              0.9,
              p.name + " @ " + f.file + ":" + p.line.to_string(),
            ),
          )
        } else {
          kept.push(p)
        }
      }
      state.pending = kept
    }
    // (2) The call the statement makes.
    match call {
      Some(c) => {
        if ipc_is_reader_op(c.op) || ipc_writer_ops().contains(c.op) {
          calls.push({
            op: c.op,
            receiver: c.receiver,
            discarded: c.discarded,
            bound: c.bound,
            file: f.file,
            line: s.span.start_line,
            fn_name: f.name,
          })
        }
        // (3) A read whose count is DISCARDED. In a loop the count is also
        // the only way to see the end of the stream.
        if c.op == "read_into" && c.discarded && c.args.length() > 0 {
          let buf = ipc_base_name(c.args[0])
          if buf != "" {
            if in_loop {
              findings.push(
                Finding::new(
                  FIpcReadEof,
                  f.file,
                  s.span.start_line,
                  f.name,
                  "this loop reads until the stream ends, but the count that '" +
                  c.receiver +
                  ".read_into' returns is discarded, so the loop cannot see the end: at EOF the read returns 0 and '" +
                  buf +
                  "' keeps the bytes of the previous iteration. Measured: at EOF the read returns 0.",
                  "L2-IPC",
                  0.9,
                  buf + " @ " + f.file + ":" + s.span.start_line.to_string(),
                ),
              )
            } else {
              state.pending.push({
                name: buf,
                line: s.span.start_line,
                receiver: c.receiver,
              })
            }
          }
        }
        // (4) A reader operation breaks the views into that reader's buffer.
        if ipc_is_reader_op(c.op) && c.receiver != "" {
          for v in state.views {
            if v.live && v.receiver == c.receiver && v.broken_line == 0 {
              v.broken_line = s.span.start_line
              v.broken_op = c.op
            }
          }
        }
      }
      None => ()
    }
    // (5) A view that was broken, used anyway. It is reported ONCE: one
    // defect is one finding, and not one per use of the name.
    for v in state.views {
      if v.live &&
        !v.reported &&
        v.broken_line != 0 &&
        ipc_stmt_mentions(s, v.name) {
        v.reported = true
        views.push({
          name: v.name,
          receiver: v.receiver,
          peek_line: v.peek_line,
          broken_line: v.broken_line,
          broken_op: v.broken_op,
          file: f.file,
          fn_name: f.name,
        })
        findings.push(
          Finding::new(
            FIpcViewStale,
            f.file,
            s.span.start_line,
            f.name,
            "'" +
            v.name +
            "' is a view into '" +
            v.receiver +
            "'s own buffer, taken by 'peek' at line " +
            v.peek_line.to_string() +
            ". The core's contract says the caller of 'peek' must not use the returned slice after any other operation on the same reader, and '" +
            v.broken_op +
            "' at line " +
            v.broken_line.to_string() +
            " is one. The reader keeps one buffer and reuses it, so the bytes '" +
            v.name +
            "' shows may already be the bytes of a later read.",
            "L2-IPC",
            0.7,
            v.name + " @ " + f.file + ":" + v.peek_line.to_string(),
          ),
        )
      }
    }
    // (6) The statement may BIND a view. Only a peek whose result is USED AS
    // A VIEW is one: a `peek` that returns a token is not a view, and the
    // name holds ONE view -- a new binding of it replaces the old one.
    match s.kind {
      SLet(name, _, e) =>
        match ipc_find_peek(e) {
          Some(recv) =>
            if recv != "" && view_names.contains(name) {
              for v in state.views {
                if v.name == name {
                  v.live = false
                }
              }
              state.views.push({
                name,
                receiver: recv,
                peek_line: s.span.start_line,
                broken_line: 0,
                broken_op: "",
                live: true,
                reported: false,
              })
            }
          None => ()
        }
      _ => ()
    }
    // (7) The nested statements, in order. A `while` body is a loop; a `for`
    // body is not, because the `for` has a count of its own.
    for sub in ipc_sub_stmts(s) {
      let nested_loop = in_loop || ipc_is_while(s)
      ipc_scan_stmts(
        sub, f, nested_loop, state, calls, views, findings, view_names,
      )
    }
  }
}

///|
/// True when the statement is a `while` loop.
fn ipc_is_while(s : Stmt) -> Bool {
  match s.kind {
    SWhile(_, _) => true
    _ => false
  }
}

///|
/// The call a statement makes on a reader or a writer, and whether the value
/// it returns is discarded.
///
/// The call is not always the WHOLE statement: MoonBit does not let a value
/// be dropped silently, so the count a read returns is discarded with
/// `ignore(reader.read_into(buf))` or with `let _ = reader.read_into(buf)`.
/// Both are the same defect, and both have to be seen.
fn ipc_call_of(s : Stmt) -> IpcCallRec? {
  match s.kind {
    SExpr(e) => ipc_find_io_call(e, 1)
    SLet(name, _, e) =>
      match ipc_find_io_call(e, if name == "_" { 1 } else { 0 }) {
        Some(c) =>
          Some({
            op: c.op,
            receiver: c.receiver,
            args: c.args,
            discarded: c.discarded,
            bound: name,
          })
        None => None
      }
    _ => None
  }
}

///|
/// The context a call was found in.
///
///   0 = BOUND: the call is the whole right-hand side of a `let`, so its
///       value is kept.
///   1 = DISCARDED: the call's value is thrown away -- the statement is a
///       bare expression, the binding is `_`, or the call sits inside an
///       `ignore(...)`.
///   2 = USED: the call's value flows into an expression, so it is read.
fn ipc_find_io_call(e : Expr, ctx : Int32) -> IpcCallRec? {
  match e.kind {
    EMethod(recv, m, args) =>
      if ipc_is_reader_op(m) || ipc_writer_ops().contains(m) {
        Some({
          op: m,
          receiver: ipc_root(recv),
          args,
          discarded: ctx == 1,
          bound: "",
        })
      } else {
        ipc_find_io_in(args, 2)
      }
    ECall(f, args) =>
      if f == "ignore" {
        ipc_find_io_in(args, 1)
      } else {
        ipc_find_io_in(args, 2)
      }
    EBin(_, l, r) =>
      match ipc_find_io_call(l, 2) {
        Some(c) => Some(c)
        None => ipc_find_io_call(r, 2)
      }
    EUn(_, x) => ipc_find_io_call(x, 2)
    EField(x, _) => ipc_find_io_call(x, 2)
    EIndex(x, i) =>
      match ipc_find_io_call(x, 2) {
        Some(c) => Some(c)
        None => ipc_find_io_call(i, 2)
      }
    ESlice(x, _, _) => ipc_find_io_call(x, 2)
    EArray(xs) => ipc_find_io_in(xs, 2)
    ETuple(xs) => ipc_find_io_in(xs, 2)
    _ => None
  }
}

///|
fn ipc_find_io_in(xs : Array[Expr], ctx : Int32) -> IpcCallRec? {
  for x in xs {
    match ipc_find_io_call(x, ctx) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  None
}

///|
/// The nested statement lists of a statement.
fn ipc_sub_stmts(s : Stmt) -> Array[Array[Stmt]] {
  let out : Array[Array[Stmt]] = []
  match s.kind {
    SIf(_, t, e) => {
      out.push(t)
      out.push(e)
    }
    SWhile(_, body) => out.push(body)
    SFor(_, _, _, _, body) => out.push(body)
    SForIn(_, _, body) => out.push(body)
    SBlock(body) => out.push(body)
    STry(body) => out.push(body)
    _ => ()
  }
  out
}

///|
/// The expressions a statement contains, the nested ones included.
fn ipc_exprs_of(s : Stmt) -> Array[Expr] {
  let out : Array[Expr] = []
  ipc_exprs_in_stmt(s, out)
  out
}

///|
fn ipc_exprs_in_stmt(s : Stmt, out : Array[Expr]) -> Unit {
  match s.kind {
    SLet(_, _, e) => ipc_exprs_in(e, out)
    SAssign(a, b) => {
      ipc_exprs_in(a, out)
      ipc_exprs_in(b, out)
    }
    SAssignOp(_, a, b) => {
      ipc_exprs_in(a, out)
      ipc_exprs_in(b, out)
    }
    SIf(c, t, e) => {
      ipc_exprs_in(c, out)
      for x in t {
        ipc_exprs_in_stmt(x, out)
      }
      for x in e {
        ipc_exprs_in_stmt(x, out)
      }
    }
    SWhile(c, body) => {
      ipc_exprs_in(c, out)
      for x in body {
        ipc_exprs_in_stmt(x, out)
      }
    }
    SFor(_, a, b, c2, body) => {
      ipc_exprs_in(a, out)
      ipc_exprs_in(b, out)
      ipc_exprs_in(c2, out)
      for x in body {
        ipc_exprs_in_stmt(x, out)
      }
    }
    SForIn(_, it, body) => {
      ipc_exprs_in(it, out)
      for x in body {
        ipc_exprs_in_stmt(x, out)
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => ipc_exprs_in(x, out)
        None => ()
      }
    SExpr(e) => ipc_exprs_in(e, out)
    SBlock(body) =>
      for x in body {
        ipc_exprs_in_stmt(x, out)
      }
    STry(body) =>
      for x in body {
        ipc_exprs_in_stmt(x, out)
      }
    _ => ()
  }
}

///|
fn ipc_exprs_in(e : Expr, out : Array[Expr]) -> Unit {
  out.push(e)
  match e.kind {
    EBin(_, l, r) => {
      ipc_exprs_in(l, out)
      ipc_exprs_in(r, out)
    }
    EUn(_, x) => ipc_exprs_in(x, out)
    ECall(_, args) =>
      for a in args {
        ipc_exprs_in(a, out)
      }
    EMethod(x, _, args) => {
      ipc_exprs_in(x, out)
      for a in args {
        ipc_exprs_in(a, out)
      }
    }
    EField(x, _) => ipc_exprs_in(x, out)
    EIndex(x, i) => {
      ipc_exprs_in(x, out)
      ipc_exprs_in(i, out)
    }
    ESlice(x, s, en) => {
      ipc_exprs_in(x, out)
      match s {
        Some(v) => ipc_exprs_in(v, out)
        None => ()
      }
      match en {
        Some(v) => ipc_exprs_in(v, out)
        None => ()
      }
    }
    EArray(xs) =>
      for x in xs {
        ipc_exprs_in(x, out)
      }
    ETuple(xs) =>
      for x in xs {
        ipc_exprs_in(x, out)
      }
    _ => ()
  }
}

///|
/// True when the statement mentions the name.
fn ipc_stmt_mentions(s : Stmt, name : String) -> Bool {
  match s.kind {
    SLet(_, _, init) => ipc_expr_mentions(init, name)
    SAssign(a, b) => ipc_expr_mentions(a, name) || ipc_expr_mentions(b, name)
    SAssignOp(_, a, b) =>
      ipc_expr_mentions(a, name) || ipc_expr_mentions(b, name)
    SIf(c, t, e) =>
      ipc_expr_mentions(c, name) ||
      ipc_stmts_mention(t, name) ||
      ipc_stmts_mention(e, name)
    SWhile(c, body) =>
      ipc_expr_mentions(c, name) || ipc_stmts_mention(body, name)
    SFor(_, a, b, c2, body) =>
      ipc_expr_mentions(a, name) ||
      ipc_expr_mentions(b, name) ||
      ipc_expr_mentions(c2, name) ||
      ipc_stmts_mention(body, name)
    SForIn(_, it, body) =>
      ipc_expr_mentions(it, name) || ipc_stmts_mention(body, name)
    SReturn(e) =>
      match e {
        Some(x) => ipc_expr_mentions(x, name)
        None => false
      }
    SExpr(e) => ipc_expr_mentions(e, name)
    SBlock(body) => ipc_stmts_mention(body, name)
    STry(body) => ipc_stmts_mention(body, name)
    _ => false
  }
}

///|
fn ipc_stmts_mention(stmts : Array[Stmt], name : String) -> Bool {
  for s in stmts {
    if ipc_stmt_mentions(s, name) {
      return true
    }
  }
  false
}

///|
fn ipc_expr_mentions(e : Expr, name : String) -> Bool {
  match e.kind {
    EName(n) => n == name
    EBin(_, l, r) => ipc_expr_mentions(l, name) || ipc_expr_mentions(r, name)
    EUn(_, x) => ipc_expr_mentions(x, name)
    ECall(_, args) => ipc_args_mention(args, name)
    EMethod(x, _, args) =>
      ipc_expr_mentions(x, name) || ipc_args_mention(args, name)
    EField(x, _) => ipc_expr_mentions(x, name)
    EIndex(x, i) => ipc_expr_mentions(x, name) || ipc_expr_mentions(i, name)
    ESlice(x, s, en) => {
      if ipc_expr_mentions(x, name) {
        return true
      }
      if ipc_opt_mentions(s, name) {
        return true
      }
      ipc_opt_mentions(en, name)
    }
    EArray(xs) => ipc_exprs_mention(xs, name)
    ETuple(xs) => ipc_exprs_mention(xs, name)
    _ => false
  }
}

///|
fn ipc_args_mention(args : Array[Expr], name : String) -> Bool {
  for a in args {
    if ipc_expr_mentions(a, name) {
      return true
    }
  }
  false
}

///|
fn ipc_exprs_mention(xs : Array[Expr], name : String) -> Bool {
  for x in xs {
    if ipc_expr_mentions(x, name) {
      return true
    }
  }
  false
}

///|
fn ipc_opt_mentions(e : Expr?, name : String) -> Bool {
  match e {
    Some(x) => ipc_expr_mentions(x, name)
    None => false
  }
}

///|
/// The names a body binds: the variables that are private to it.
fn ipc_bound_names(stmts : Array[Stmt]) -> Array[String] {
  let out : Array[String] = []
  for s in stmts {
    match s.kind {
      SLet(bound, _, _) => out.push(bound)
      SFor(v, _, _, _, _) => out.push(v)
      SForIn(vs, _, _) =>
        for v in vs {
          out.push(v)
        }
      _ => ()
    }
    for sub in ipc_sub_stmts(s) {
      for n in ipc_bound_names(sub) {
        out.push(n)
      }
    }
  }
  out
}

///|
/// The buffers a body reads into or writes from.
fn ipc_io_buffers(stmts : Array[Stmt]) -> Array[(String, Int32)] {
  let out : Array[(String, Int32)] = []
  for s in stmts {
    for e in ipc_exprs_of(s) {
      match e.kind {
        EMethod(_, m, args) =>
          if (m == "read_into" || m == "write") && args.length() > 0 {
            let n = ipc_base_name(args[0])
            if n != "" {
              out.push((n, s.span.start_line))
            }
          }
        _ => ()
      }
    }
    for sub in ipc_sub_stmts(s) {
      for b in ipc_io_buffers(sub) {
        out.push(b)
      }
    }
  }
  out
}

///|
/// The closure literals a statement contains.
fn ipc_fns_in_stmt(s : Stmt, out : Array[String]) -> Unit {
  for e in ipc_exprs_of(s) {
    match e.kind {
      EFn(id, _) => out.push(id)
      _ => ()
    }
  }
}

///|
/// A buffer that a task body and the function that started it both write.
///
/// The measurement this rests on: a pending write is not a snapshot. A
/// 4-byte buffer of 'A' handed to `write` and then overwritten with 'B' while
/// the write was pending delivered the 'B's to the reader. So a buffer the
/// parent keeps using after the task started is a buffer whose bytes the two
/// sides can both decide.
fn ipc_check_shared(
  ast : ModuleAst,
  shared : Array[IpcShared],
  findings : Array[Finding],
) -> Unit {
  let closures = ipc_closure_map(ast)
  for f in ast.all_funcs() {
    ipc_scan_shared_body(f.body, f.name, f.file, closures, shared, findings)
  }
  for file in ast.files {
    for c in file.closures {
      ipc_scan_shared_body(
        c.body,
        c.name,
        file.path,
        closures,
        shared,
        findings,
      )
    }
  }
}

///|
/// Every closure in the module, by its synthetic name.
fn ipc_closure_map(ast : ModuleAst) -> Map[String, Func] {
  let out = Map([])
  for file in ast.files {
    for c in file.closures {
      out.set(c.name, c)
    }
  }
  out
}

///|
fn ipc_scan_shared_body(
  stmts : Array[Stmt],
  owner : String,
  owner_file : String,
  closures : Map[String, Func],
  shared : Array[IpcShared],
  findings : Array[Finding],
) -> Unit {
  let mut i = 0
  while i < stmts.length() {
    let s = stmts[i]
    let ids : Array[String] = []
    ipc_fns_in_stmt(s, ids)
    for id in ids {
      let c = match closures.get(id) {
        Some(x) => x
        None => continue
      }
      let bound = ipc_bound_names(c.body)
      for (buf, task_line) in ipc_io_buffers(c.body) {
        if bound.contains(buf) {
          continue
        }
        // Is the buffer used AFTER the task was started?
        let mut j = i + 1
        while j < stmts.length() {
          if ipc_stmt_mentions(stmts[j], buf) {
            shared.push({
              name: buf,
              task: c.name,
              parent: owner,
              task_line,
              parent_line: stmts[j].span.start_line,
              file: owner_file,
              fn_name: owner,
            })
            findings.push(
              Finding::new(
                FIpcBufferShared,
                owner_file,
                stmts[j].span.start_line,
                owner,
                "the buffer '" +
                buf +
                "' is written by the task '" +
                c.name +
                "' (at line " +
                task_line.to_string() +
                ") and used here, after the task was started. Measured: a pending write is not a snapshot -- the bytes are taken from the buffer when the write is handed over, so the two sides can both decide what the buffer holds.",
                "L2-IPC",
                0.85,
                buf +
                " @ " +
                owner_file +
                ":" +
                stmts[j].span.start_line.to_string(),
              ),
            )
            break
          }
          j = j + 1
        }
      }
    }
    for sub in ipc_sub_stmts(s) {
      ipc_scan_shared_body(sub, owner, owner_file, closures, shared, findings)
    }
    i = i + 1
  }
}
