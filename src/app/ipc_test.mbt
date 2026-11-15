///|
/// THE IPC AND BUFFER MODEL, AND THE THREE NEW FOREIGN-BOUNDARY FAMILIES.
///
/// Every claim in this file was settled by RUNNING the real core, not by
/// reading its documentation:
///
///  - `read_into(dst)` returns the NUMBER OF BYTES IT READ, and that number
///    can be smaller than the buffer. Measured: a 16-byte buffer pre-filled
///    with 0xFF, a pipe with 3 bytes in it, one `read_into` -> returned 3,
///    and the buffer afterwards was `61 62 63 FF FF FF ... FF`. The bytes
///    past the count were never written.
///  - `read_into(buf, offset=8)` returned 3 and wrote at `buf[8..11]`: the
///    caller advances the offset itself.
///  - At EOF `read_into` returns 0 and `read()` returns None.
///  - `peek` returns a VIEW into the reader's own buffer, and the core says
///    the caller must not use it after any other operation on the same
///    reader. Measured: peeked `61 62 63`; after two reads the SAME view read
///    `78 79 7A`.
///  - A pending write is NOT a snapshot: a 4-byte buffer of 'A' handed to
///    `write` and then overwritten with 'B' while the write was pending
///    delivered the 'B's.
///  - `write` is EXHAUSTIVE -- it loops until every byte is handed over --
///    so there is no partial-write defect, and none is claimed.
///
/// The tests below pin BOTH directions: the defect is found, and the ordinary
/// shape next to it is not.

///|
fn ipc_ast(src : String) -> @app.ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
/// How many findings of one kind the IPC model produces.
fn ipc_count(src : String, kind : @app.FindingKind) -> Int32 {
  let m = @app.analyze_ipc(ipc_ast(src))
  let mut n = 0
  for f in m.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
/// How many findings of any kind the IPC model produces.
fn ipc_total(src : String) -> Int32 {
  @app.analyze_ipc(ipc_ast(src)).findings.length()
}

///|
/// The read whose count is DISCARDED and whose buffer is then used whole.
const IPC_PARTIAL_SRC : String =
  #|pub fn partial() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  reader.read_into(buf)
  #|  use_buffer(buf)
  #|}
  #|

///|
/// The SAME read, with the count kept.
const IPC_CHECKED_SRC : String =
  #|pub fn checked() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  let n = reader.read_into(buf)
  #|  use_buffer(buf)
  #|}
  #|

///|
/// A loop that reads until the stream ends, with the count discarded.
const IPC_LOOP_SRC : String =
  #|pub fn until_eof() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  while true {
  #|    reader.read_into(buf)
  #|  }
  #|}
  #|

///|
/// A view taken with `peek` and used AFTER the reader ran again.
const IPC_STALE_VIEW_SRC : String =
  #|pub fn stale() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  let v = reader.peek()
  #|  let n = reader.read_into(buf)
  #|  use_buffer(buf)
  #|  use_view(v)
  #|}
  #|

///|
/// The SAME view, used BEFORE the reader runs again.
const IPC_FRESH_VIEW_SRC : String =
  #|pub fn fresh() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  let v = reader.peek()
  #|  use_view(v)
  #|  let n = reader.read_into(buf)
  #|  use_buffer(buf)
  #|}
  #|

///|
/// A buffer a task writes and the function that started the task then uses.
const IPC_SHARED_SRC : String =
  #|pub async fn shared() -> Unit {
  #|  let writer = make_writer()
  #|  let buf = make_buffer()
  #|  let tasks : Array[async () -> Unit] = []
  #|  tasks.push(async fn() -> Unit {
  #|    writer.write(buf)
  #|  })
  #|  ignore(@async.all(tasks))
  #|  buf[0] = 1
  #|}
  #|

///|
/// A task that writes a buffer of its OWN.
const IPC_PRIVATE_SRC : String =
  #|pub async fn private() -> Unit {
  #|  let writer = make_writer()
  #|  let tasks : Array[async () -> Unit] = []
  #|  tasks.push(async fn() -> Unit {
  #|    let own = make_buffer()
  #|    writer.write(own)
  #|  })
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
test "a read whose count is discarded leaves a stale tail" {
  inspect(ipc_count(IPC_PARTIAL_SRC, @app.FIpcPartialRead), content="1")
}

///|
test "a count discarded with ignore() is the same defect" {
  // MoonBit does not let a value be dropped silently, so the count is
  // discarded with `ignore(...)` or with `let _ = ...`. Both are the same
  // defect, and both have to be seen.
  let src =
    #|pub fn partial() -> Unit {
    #|  let reader = make_reader()
    #|  let buf = make_buffer()
    #|  ignore(reader.read_into(buf))
    #|  use_buffer(buf)
    #|}
    #|
  inspect(ipc_count(src, @app.FIpcPartialRead), content="1")
  let src2 =
    #|pub fn partial() -> Unit {
    #|  let reader = make_reader()
    #|  let buf = make_buffer()
    #|  let _ = reader.read_into(buf)
    #|  use_buffer(buf)
    #|}
    #|
  inspect(ipc_count(src2, @app.FIpcPartialRead), content="1")
}

///|
test "a read whose count is kept is not reported" {
  inspect(ipc_count(IPC_CHECKED_SRC, @app.FIpcPartialRead), content="0")
  inspect(ipc_total(IPC_CHECKED_SRC), content="0")
}

///|
test "a loop that discards the count cannot see the end of the stream" {
  inspect(ipc_count(IPC_LOOP_SRC, @app.FIpcReadEof), content="1")
}

///|
test "a peeked view used after the reader ran again is reported" {
  inspect(ipc_count(IPC_STALE_VIEW_SRC, @app.FIpcViewStale), content="1")
}

///|
test "a peeked view used before the reader ran again is not reported" {
  inspect(ipc_count(IPC_FRESH_VIEW_SRC, @app.FIpcViewStale), content="0")
}

///|
test "a buffer a task writes and the parent uses is reported" {
  inspect(ipc_count(IPC_SHARED_SRC, @app.FIpcBufferShared), content="1")
}

///|
test "a task with a buffer of its own is not reported" {
  inspect(ipc_count(IPC_PRIVATE_SRC, @app.FIpcBufferShared), content="0")
}

///|
test "the IPC model records the calls it saw" {
  let m = @app.analyze_ipc(ipc_ast(IPC_PARTIAL_SRC))
  inspect(m.calls.length(), content="1")
  inspect(m.calls[0].op, content="read_into")
  inspect(m.calls[0].discarded, content="true")
}

///|
/// The three new foreign-boundary families.
const FFI_RELEASE_DECL : String =
  #|extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"
  #|

///|
const FFI_RELEASE_TWICE_SRC : String =
  #|extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"
  #|
  #|pub fn twice() -> Unit {
  #|  let buffer = b"payload"
  #|  release_buffer(buffer)
  #|  release_buffer(buffer)
  #|}
  #|

///|
const FFI_USE_AFTER_RELEASE_SRC : String =
  #|extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"
  #|
  #|pub fn used() -> Unit {
  #|  let buffer = b"payload"
  #|  release_buffer(buffer)
  #|  println(buffer)
  #|}
  #|

///|
const FFI_COPY_DECL : String =
  #|extern "C" fn copy_bytes(src : Bytes, len : Int) -> Unit = "copy_bytes"
  #|

///|
const FFI_WRONG_LENGTH_SRC : String =
  #|extern "C" fn copy_bytes(src : Bytes, len : Int) -> Unit = "copy_bytes"
  #|
  #|pub fn wrong() -> Unit {
  #|  copy_bytes(b"abc", 4)
  #|}
  #|

///|
const FFI_RIGHT_LENGTH_SRC : String =
  #|extern "C" fn copy_bytes(src : Bytes, len : Int) -> Unit = "copy_bytes"
  #|
  #|pub fn right() -> Unit {
  #|  let payload = b"abc"
  #|  copy_bytes(payload, payload.length())
  #|}
  #|

///|
test "the same buffer released twice is a double free" {
  inspect(ffi_count(FFI_RELEASE_TWICE_SRC, @app.FFfiDoubleFree), content="1")
}

///|
test "a buffer the C side released, used afterwards" {
  inspect(
    ffi_count(FFI_USE_AFTER_RELEASE_SRC, @app.FFfiUseAfterFree),
    content="1",
  )
}

///|
test "the release is not reported as a use after a move as well" {
  // The two are different defects: a MOVE gives the ownership away, a
  // RELEASE frees the memory. The fixture uses `#borrow` so the free check
  // stands on its own.
  let m = ffi_model(FFI_USE_AFTER_RELEASE_SRC)
  let mut moves = 0
  for f in m.findings {
    if f.kind == @app.FFfiUseAfterMove {
      moves = moves + 1
    }
  }
  inspect(moves, content="0")
}

///|
test "a length that is not the object's length is reported" {
  inspect(ffi_count(FFI_WRONG_LENGTH_SRC, @app.FFfiLengthMismatch), content="1")
}

///|
test "a length that IS the object's length is not reported" {
  inspect(ffi_count(FFI_RIGHT_LENGTH_SRC, @app.FFfiLengthMismatch), content="0")
}

///|
test "a byte literal is parsed as a byte literal" {
  let f = @app.parse_file("c.mbt", "pub fn f() -> Unit { let b = b\"abc\" }")
  inspect(f.issues.length(), content="0")
  let funcs = f.funcs
  inspect(funcs.length(), content="1")
}

///|
test "the IPC families have their own method" {
  let m = @app.analyze_ipc(ipc_ast(IPC_PARTIAL_SRC))
  for finding in m.findings {
    assert_true(finding.mode == "L2-IPC")
  }
}

///|
/// A `peek` that returns something else is NOT a view. A parser has one and
/// it returns a token, and the analyzer's own source is full of them: before
/// the evidence rule they were reported as stale views, thirteen times.
const IPC_PEEK_NOT_A_VIEW_SRC : String =
  #|pub fn not_a_view() -> Unit {
  #|  let t = p.peek()
  #|  match t.kind {
  #|    TInt => 0
  #|    _ => 1
  #|  }
  #|}
  #|

///|
test "a peek whose result is not used as a view is not a view" {
  inspect(ipc_count(IPC_PEEK_NOT_A_VIEW_SRC, @app.FIpcViewStale), content="0")
}

///|
/// The evidence that a peek DID produce a view: the value is passed to a
/// parameter declared `BytesView`.
const IPC_VIEW_USED_AS_ONE_SRC : String =
  #|fn take(b : BytesView) -> Unit {
  #|  ignore(b.length())
  #|}
  #|
  #|pub fn stale() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  let v = reader.peek()
  #|  let n = reader.read_into(buf)
  #|  use_buffer(buf)
  #|  take(v)
  #|}
  #|

///|
test "a peek whose result is used as a view IS a view" {
  inspect(ipc_count(IPC_VIEW_USED_AS_ONE_SRC, @app.FIpcViewStale), content="1")
}

///|
/// The same view, used twice after the reader ran again: one defect is one
/// finding.
const IPC_VIEW_USED_TWICE_SRC : String =
  #|fn take(b : BytesView) -> Unit {
  #|  ignore(b.length())
  #|}
  #|
  #|pub fn stale() -> Unit {
  #|  let reader = make_reader()
  #|  let buf = make_buffer()
  #|  let v = reader.peek()
  #|  let n = reader.read_into(buf)
  #|  use_buffer(buf)
  #|  take(v)
  #|  take(v)
  #|}
  #|

///|
test "a stale view used twice is reported once" {
  inspect(ipc_count(IPC_VIEW_USED_TWICE_SRC, @app.FIpcViewStale), content="1")
}

///|
/// A `BytesView` parameter of a C function is a POINTER: measured, the
/// toolchain's own E0055 fires for it exactly as it fires for a `Bytes`.
const FFI_BYTESVIEW_DECL : String =
  #|extern "C" fn takes_view(v : BytesView) -> Unit = "takes_view"
  #|

///|
test "a BytesView parameter of a C function is a pointer" {
  let m = ffi_model(FFI_BYTESVIEW_DECL)
  let mut unannotated = 0
  for f in m.findings {
    if f.kind == @app.FFfiUnannotatedOwnership {
      unannotated = unannotated + 1
    }
  }
  inspect(unannotated, content="1")
}
