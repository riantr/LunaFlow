///|
/// THE FOREIGN ADDRESS SPACE MODEL.
///
/// Every claim in this file was settled by RUNNING the real toolchain:
///
///  - `extern "C" fn name(args) -> Ret = "c_symbol"` is the only C form, and
///    the `= "c_symbol"` part is REQUIRED;
///  - the wasm backend REJECTS `extern "C"` (E4156) and native REJECTS a
///    module import, so the two forms are not interchangeable;
///  - `#external type T` is an OPAQUE type whose payload the C side owns;
///  - a pointer-typed parameter needs `#borrow(x)` or `#owned(x)`, and the
///    toolchain's E0055 fires for exactly the types with a heap
///    representation;
///  - the annotation is NOT enforced by the compiler, and two declarations
///    claiming the same C symbol with different signatures are NOT noticed
///    by it either. Those two are this analyzer's own checks.
///
/// The tests below pin BOTH directions: the defect is found, and the
/// ordinary shape next to it is not.

///|
fn ffi_ast(src : String) -> @app.ModuleAst {
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
fn ffi_model(src : String) -> @app.FfiModel {
  @app.analyze_ffi(ffi_ast(src))
}

///|
fn ffi_count(src : String, kind : @app.FindingKind) -> Int32 {
  let m = ffi_model(src)
  let mut n = 0
  for f in m.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
test "a C extern is parsed as a foreign declaration" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
    #|
    #|pub fn f() -> UInt32 {
    #|  read_reg(1)
    #|}
  let m = ffi_model(src)
  inspect(m.decls.length(), content="1")
  inspect(m.decls[0].symbol, content="read_reg")
  inspect(m.decls[0].is_c, content="true")
}

///|
test "the foreign declaration is not a parse issue any more" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
  let f = @app.parse_file("c.mbt", src)
  inspect(f.issues.length(), content="0")
  inspect(f.ffi_decls.length(), content="1")
}

///|
test "an #external type is parsed as a foreign type" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn read_reg(name : Reg) -> UInt32 = "read_reg"
  let m = ffi_model(src)
  inspect(m.external_types.length(), content="1")
  inspect(m.external_types[0].name, content="Reg")
}

///|
test "a module import is not a C call" {
  let src =
    #|fn from_module() -> Int = "moonbitlang/async" "fs/dir_entry_length"
  let m = ffi_model(src)
  inspect(m.decls.length(), content="1")
  inspect(m.decls[0].is_c, content="false")
}

///|
test "the ownership annotation belongs to the parameter it names" {
  let src =
    #|#owned(buffer)
    #|extern "C" fn write_reg(name : Int32, buffer : Bytes) -> Unit = "write_reg"
  let m = ffi_model(src)
  inspect(m.decls[0].params[0].ownership == @app.OUnannotated, content="true")
  inspect(m.decls[0].params[1].ownership == @app.OOwned, content="true")
}

///|
test "one C symbol with two signatures is a conflict" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
    #|
    #|extern "C" fn read_reg_wide(name : Int64) -> UInt64 = "read_reg"
  inspect(ffi_count(src, @app.FFfiSignatureConflict), content="2")
}

///|
test "two declarations of the same symbol with the SAME signature are not a conflict" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
    #|
    #|extern "C" fn read_reg_alias(name : Int32) -> UInt32 = "read_reg"
  inspect(ffi_count(src, @app.FFfiSignatureConflict), content="0")
}

///|
test "an #owned argument used after the call is a use after move" {
  let src =
    #|#owned(buffer)
    #|extern "C" fn write_reg(name : Int32, buffer : Bytes) -> Unit = "write_reg"
    #|
    #|pub fn f() -> Unit {
    #|  let buffer = b"payload"
    #|  write_reg(1, buffer)
    #|  println(buffer)
    #|}
  inspect(ffi_count(src, @app.FFfiUseAfterMove), content="1")
}

///|
test "an #owned argument NOT used after the call is not a use after move" {
  let src =
    #|#owned(buffer)
    #|extern "C" fn write_reg(name : Int32, buffer : Bytes) -> Unit = "write_reg"
    #|
    #|pub fn f() -> Unit {
    #|  let buffer = b"payload"
    #|  write_reg(1, buffer)
    #|}
  inspect(ffi_count(src, @app.FFfiUseAfterMove), content="0")
}

///|
test "a pointer parameter without an annotation relies on the default" {
  let src =
    #|extern "C" fn write_reg(name : Int32, buffer : Bytes) -> Unit = "write_reg"
  inspect(ffi_count(src, @app.FFfiUnannotatedOwnership), content="1")
}

///|
test "a scalar parameter is not a pointer" {
  let src =
    #|extern "C" fn write_reg(name : Int32, value : Int32) -> Unit = "write_reg"
  inspect(ffi_count(src, @app.FFfiUnannotatedOwnership), content="0")
}

///|
test "an #external parameter is not a pointer: the C side owns the payload" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn read_reg(name : Reg) -> UInt32 = "read_reg"
  inspect(ffi_count(src, @app.FFfiUnannotatedOwnership), content="0")
}

///|
test "a user struct is a pointer at the boundary" {
  let src =
    #|pub struct Point {
    #|  x : Int
    #|}
    #|
    #|extern "C" fn send(p : Point) -> Unit = "send"
  inspect(ffi_count(src, @app.FFfiUnannotatedOwnership), content="1")
}

///|
test "a fieldless enum is not a pointer" {
  let src =
    #|pub enum Colour {
    #|  Red
    #|  Green
    #|}
    #|
    #|extern "C" fn paint(c : Colour) -> Unit = "paint"
  inspect(ffi_count(src, @app.FFfiUnannotatedOwnership), content="0")
}

///|
test "the same constant handed to two C symbols is a conflict" {
  let src =
    #|extern "C" fn poke(base : UInt64) -> Unit = "poke"
    #|
    #|extern "C" fn peek(base : UInt64) -> Unit = "peek"
    #|
    #|pub fn f() -> Unit {
    #|  poke(1073741824)
    #|  peek(1073741824)
    #|}
  inspect(ffi_count(src, @app.FFfiAddressConflict), content="1")
}

///|
test "a slot that is constant elsewhere and computed here cannot be named" {
  let src =
    #|extern "C" fn poke(base : UInt64, value : UInt32) -> Unit = "poke"
    #|
    #|pub fn f(base : UInt64) -> Unit {
    #|  poke(1073741824, 7)
    #|  poke(base, 7)
    #|}
  inspect(ffi_count(src, @app.FFfiAddressUnknown), content="1")
}

///|
test "a slot that is computed at every call site is not claimed" {
  let src =
    #|extern "C" fn poke(base : UInt64, value : UInt32) -> Unit = "poke"
    #|
    #|pub fn f(base : UInt64) -> Unit {
    #|  poke(base, 7)
    #|}
  inspect(ffi_count(src, @app.FFfiAddressUnknown), content="0")
}

///|
test "a C extern in a module published for wasm is a target mismatch" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "wasm",
  }
  let m = @app.analyze_ffi(ast)
  let mut n = 0
  for f in m.findings {
    if f.kind == @app.FFfiTargetMismatch {
      n = n + 1
    }
  }
  inspect(n, content="1")
}

///|
test "a module import in a native module is a target mismatch" {
  let src =
    #|fn from_module() -> Int = "moonbitlang/async" "fs/dir_entry_length"
  inspect(ffi_count(src, @app.FFfiTargetMismatch), content="1")
}

///|
test "a #cfg target guard keeps a declaration out of the other build" {
  let src =
    #|#cfg(target="native")
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
  let m = ffi_model(src)
  // The guard is read, and it says the declaration is native-only.
  inspect(@app.cfg_allows(m.decls[0].cfg, "native"), content="true")
  inspect(@app.cfg_allows(m.decls[0].cfg, "wasm"), content="false")
  // So a module that publishes for wasm is NOT in conflict with it.
  let ast : @app.ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "wasm",
  }
  let m2 = @app.analyze_ffi(ast)
  let mut n = 0
  for f in m2.findings {
    if f.kind == @app.FFfiTargetMismatch {
      n = n + 1
    }
  }
  inspect(n, content="0")
}

///|
test "the declared type says which space a value lands in" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|pub struct Point {
    #|  x : Int
    #|}
    #|
    #|extern "C" fn f(
    #|  a : String,
    #|  b : Int32,
    #|  c : Reg,
    #|  d : Point,
    #|) -> Unit = "f"
  let m = ffi_model(src)
  inspect(m.decls[0].params[0].space == @app.SHeapPointer, content="true")
  inspect(m.decls[0].params[1].space == @app.SScalar, content="true")
  inspect(m.decls[0].params[2].space == @app.SExternal, content="true")
  inspect(m.decls[0].params[3].space == @app.SHeapPointer, content="true")
}

///|
test "a C call returns a FOREIGN value, not an unknown one" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
    #|
    #|pub fn f() -> UInt32 {
    #|  read_reg(1)
    #|}
  let ast = ffi_ast(src)
  let opts : @app.RunOptions = @app.RunOptions::default()
  let r = @app.run_module(ast, opts)
  let mut ret = "?"
  for e in r.events {
    if e.name == "<ret>" {
      ret = e.value
    }
  }
  inspect(ret, content="foreign(read_reg)")
}

///|
test "the named addresses are the constants the module hands to C" {
  let src =
    #|extern "C" fn poke(base : UInt64, value : UInt32) -> Unit = "poke"
    #|
    #|pub fn f() -> Unit {
    #|  poke(1073741824, 7)
    #|}
  let m = ffi_model(src)
  inspect(m.registers.length(), content="2")
  inspect(m.registers[0].text, content="0x40000000")
}

///|
test "the report has the foreign address space section" {
  let src =
    #|extern "C" fn read_reg(name : Int32) -> UInt32 = "read_reg"
    #|
    #|pub fn f() -> UInt32 {
    #|  read_reg(1)
    #|}
  let ast = ffi_ast(src)
  let opts : @app.RunOptions = @app.RunOptions::default()
  let run = @app.run_module(ast, opts)
  let input : @app.ReportInput = {
    coord: "demo/x",
    version: "1.0.0",
    pinning: "none",
    root: ".",
    target: "native",
    deps: [],
    files: 1,
    funcs: 1,
    stmts: 1,
    unsupported: 0,
    issues: 0,
    cfgs: [],
    cfg_findings: [],
    run,
    taint: @app.TaintGraph::new(),
    slices: [],
    coverage: None,
    opts: @app.ReportOptions::default(),
    elapsed_ms: 0,
    level: 1,
    funnel: None,
    abstract: None,
    proof: None,
  }
  let md = @app.render_report(input, ffi=Some(ffi_model(src)))
  inspect(md.contains("### 5.7 The foreign address space"), content="true")
  inspect(md.contains("read_reg"), content="true")
}
