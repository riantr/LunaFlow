///|
/// THE FOREIGN ADDRESS SPACE.
///
/// MoonBit has no pointer type, no address arithmetic and no address space:
/// there is nothing in the language that IS an address. The C boundary is
/// where an address appears, and it appears on the OTHER side of it.
///
/// Everything below was MEASURED against the toolchain, which is the
/// authority here -- not the documentation, and not a reading of the
/// compiler's source:
///
///   - `extern "C" fn name(args) -> Ret = "c_symbol"` is the only C form, and
///     the `= "c_symbol"` part is REQUIRED (without it the compiler reports
///     E4140 and E3002).
///   - The wasm backend REJECTS `extern "C"` (E4156: "extern "C" is
///     unsupported in wasm backend"), so a C extern is a native-only
///     declaration. The mirror holds: a MODULE IMPORT -- `fn f() = "pkg"
///     "path"` -- is rejected on native (E4156: "import is unsupported in
///     native backend").
///   - `#external type T` is an OPAQUE type. Natively it is a GC-managed
///     external object -- the toolchain's `moonbit.h` builds one with
///     `moonbit_make_external_object(finalize, payload_size)` -- so the
///     PAYLOAD belongs to the C side.
///   - A `String` crosses as `uint16_t *` and a `Bytes` as `uint8_t *`
///     (`moonbit_string_t` / `moonbit_bytes_t`): the C side receives an
///     ADDRESS of a MoonBit heap object. Measured by value: the pointer that
///     arrives in C is a heap address, not a copy.
///   - The scalars cross by value. Measured by value: `Int` arrives as a
///     32-bit signed value, `Int64` as a 64-bit one, `Double` as a C
///     `double` in a FLOATING-POINT register (read through an `int64_t`
///     prototype it arrives as garbage -- which is exactly what a wrong C
///     prototype does to a value), `Bool` as 0 or 1, `Char` as its 32-bit
///     code point.
///   - The toolchain REFUSES a pointer-typed parameter without an ownership
///     annotation (E0055) and says the current default -- `#owned` -- "will
///     be changed in the future".
///   - The toolchain does NOT enforce the annotation: using an `#owned`
///     argument AFTER the call compiles clean.
///   - The toolchain does NOT notice two declarations claiming the same C
///     symbol with different signatures.
///
/// So there are TWO address spaces here, and the analysis is about the
/// boundary between them: the MOONBIT space (the reference-counted heap, the
/// global region, the frame) and the FOREIGN space (whatever the C code
/// owns, plus the payloads of external objects). A C call is where a value
/// crosses from one to the other.
#derive(Eq)
pub(all) enum FfiSpace {
  /// The analyzer cannot classify the declared type.
  SUnclassified
  /// COPIED BY VALUE: the C side receives the bits, not an address.
  SScalar
  /// A POINTER INTO THE MOONBIT HEAP: the C side receives the ADDRESS of a
  /// MoonBit object. This is the case that needs an ownership annotation.
  SHeapPointer
  /// An `#external` type: an opaque address whose payload the C side owns.
  SExternal
  /// A value C produced: its provenance is unknown to the analyzer.
  SForeign
}

///|
pub extend FfiSpace with Eq::{not_equal, equal}

///|
/// The space, in the words the report uses.
pub fn FfiSpace::label(self : FfiSpace) -> String {
  match self {
    SUnclassified => "unknown"
    SScalar => "value"
    SHeapPointer => "heap pointer"
    SExternal => "foreign address"
    SForeign => "foreign value"
  }
}

///|
/// The ownership, in the words the report uses.
pub fn FfiOwnership::label(self : FfiOwnership) -> String {
  match self {
    OUnannotated => "default"
    OBorrow => "borrow"
    OOwned => "owned"
  }
}

///|
/// Who owns the MoonBit object a pointer parameter refers to.
#derive(Eq)
pub(all) enum FfiOwnership {
  /// No annotation. The toolchain's current default is `#owned`, and it says
  /// that default will change.
  OUnannotated
  /// `#borrow(x)`: the C side may use the object for the duration of the
  /// call.
  OBorrow
  /// `#owned(x)`: the object moves to the C side at the call.
  OOwned
}

///|
pub extend FfiOwnership with Eq::{not_equal, equal}

///|
/// One parameter of a foreign declaration.
pub struct FfiParam {
  name : String
  ty : String
  space : FfiSpace
  ownership : FfiOwnership
  /// True when the parameter is declared with `~` (an optional parameter).
  optional : Bool
}

///|
/// A foreign declaration: a C function the module depends on, or a module
/// import it depends on.
pub struct FfiDecl {
  /// The MoonBit name of the declaration.
  name : String
  /// The C symbol it binds. Empty for a module import.
  symbol : String
  /// True for `extern "C"`, false for a module import.
  is_c : Bool
  params : Array[FfiParam]
  ret_ty : String
  ret_space : FfiSpace
  file : String
  line : Int32
  /// The `#cfg(...)` text of the declaration, when it has one.
  cfg : String
}

///|
/// An `#external type`: an opaque type whose payload the C side owns.
pub struct ExternalType {
  name : String
  file : String
  line : Int32
}

///|
/// A type the module declares. The analyzer needs to know whether a user
/// type has a heap representation, because that decides whether it is a
/// POINTER at the C boundary.
pub struct TypeDecl {
  name : String
  /// True when the type has a heap representation: a `struct` always does,
  /// and an `enum` does when one of its constructors carries a field.
  is_pointer : Bool
  file : String
  line : Int32
}

///|
/// An ATTRIBUTE on a declaration: `#external`, `#borrow(x)`, `#owned(x)`,
/// `#cfg(...)`.
pub struct Attr {
  name : String
  /// The parameter an ownership annotation names.
  arg : String
  /// The raw text of the attribute's argument list.
  text : String
  line : Int32
}

///|
/// One argument at a call site of a foreign function.
pub struct FfiArg {
  /// The source text of the argument.
  text : String
  /// The constant value of the argument, when it is an integer literal.
  const_value : Int64?
  /// True when the parameter's declared type is an integer type: a candidate
  /// address.
  is_int_slot : Bool
  /// True when the parameter's declared type is an `#external` type: an
  /// address by construction.
  is_external_slot : Bool
  /// The REGION the address belongs to, when the analyzer can name it: the
  /// C symbol that produced the value. Empty when it cannot.
  region : String
}

///|
/// A call site of a foreign function.
pub struct FfiCall {
  decl_name : String
  symbol : String
  file : String
  line : Int32
  fn_name : String
  args : Array[FfiArg]
}

///|
/// A NAMED ADDRESS: a constant that the module hands to C.
///
/// The analyzer does not claim that a constant IS an address -- an integer
/// argument to a C function may be an address, a length or a plain value.
/// What it can say is that the SAME constant is handed to C more than once,
/// and then the value the C side reads from that address is not a constant of
/// the program.
pub struct FfiRegister {
  /// The constant.
  address : Int64
  /// The constant in hex.
  text : String
  /// The C symbols the constant was handed to.
  symbols : Array[String]
  /// The call sites, as `symbol@file:line`.
  sites : Array[String]
  /// The file of the first site.
  file : String
  /// The line of the first site.
  line : Int32
  /// The function of the first site.
  fn_name : String
  /// The OTHER constant arguments seen at those sites: the values written
  /// through the address.
  values : Array[Int64]
}

///|
/// The whole foreign boundary of a module.
pub struct FfiModel {
  /// The foreign declarations.
  decls : Array[FfiDecl]
  /// The `#external` types.
  external_types : Array[ExternalType]
  /// The module's own type declarations.
  types : Array[TypeDecl]
  /// The call sites of the foreign functions.
  calls : Array[FfiCall]
  /// The named addresses.
  registers : Array[FfiRegister]
  /// The findings.
  findings : Array[Finding]
}

///|
/// The base name of a declared type: `Array[Int]` is `Array`, `Point?` is
/// `Point`, and a tuple has no base name.
fn base_type_name(ty : String) -> String {
  let t = ty.trim()
  if t.has_prefix("(") {
    return ""
  }
  let mut i = 0
  while i < t.length() {
    let c = t.get_char(i).unwrap_or(' ')
    if c == '[' || c == '?' {
      break
    }
    i = i + 1
  }
  t[:i].to_owned()
}

///|
/// True when the declared type is an INTEGER type: a value that may be an
/// address.
pub fn is_integer_type(ty : String) -> Bool {
  let b = base_type_name(ty)
  b == "Int" ||
  b == "Int16" ||
  b == "Int32" ||
  b == "Int64" ||
  b == "UInt" ||
  b == "UInt16" ||
  b == "UInt32" ||
  b == "UInt64"
}

///|
/// True when the declared type is a SCALAR: copied by value at the
/// boundary.
pub fn is_scalar_type(ty : String) -> Bool {
  let b = base_type_name(ty)
  b == "Int" ||
  b == "Int16" ||
  b == "Int32" ||
  b == "Int64" ||
  b == "UInt" ||
  b == "UInt16" ||
  b == "UInt32" ||
  b == "UInt64" ||
  b == "Double" ||
  b == "Float" ||
  b == "Bool" ||
  b == "Char" ||
  b == "Unit"
}

///|
/// The BUILT-IN types the toolchain treats as pointer types. Measured: the
/// toolchain's own E0055 fires for exactly these, and for none of the
/// scalars, and not for a tuple.
///
/// `String`, `StringView`, `Bytes`, `BytesView`, `Array`, `FixedArray`,
/// `Option`, `Result` and `Map` all have a heap representation, so the C side
/// gets an address of a MoonBit object. `BytesView` was MEASURED too: an
/// `extern "C" fn takes_view(v : BytesView)` trips E0055 exactly like a
/// `Bytes` parameter does.
fn is_builtin_pointer_type(ty : String) -> Bool {
  let b = base_type_name(ty)
  b == "String" ||
  b == "StringView" ||
  b == "Bytes" ||
  b == "BytesView" ||
  b == "Array" ||
  b == "FixedArray" ||
  b == "Option" ||
  b == "Result" ||
  b == "Map"
}

///|
/// The space a declared type lives in, at the C boundary.
pub fn space_of_type(
  ty : String,
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
) -> FfiSpace {
  let b = base_type_name(ty)
  if b == "" {
    return SUnclassified
  }
  for e in external_types {
    if e.name == b {
      return SExternal
    }
  }
  if is_builtin_pointer_type(ty) {
    return SHeapPointer
  }
  if is_scalar_type(ty) {
    return SScalar
  }
  for t in types {
    if t.name == b {
      return if t.is_pointer { SHeapPointer } else { SScalar }
    }
  }
  SUnclassified
}

///|
/// True when the declared type is a POINTER at the boundary: the C side
/// receives an address of a MoonBit object, and the ownership annotation
/// decides how long that address may be used.
///
/// Measured against the toolchain's E0055: the built-in pointer types, a
/// user's `struct`, a user's `enum` that carries a field, and a plain
/// opaque `type` are pointer types. An `#external` type is NOT: its payload
/// belongs to the C side. A tuple and the scalars are not.
pub fn is_pointer_type(
  ty : String,
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
) -> Bool {
  let b = base_type_name(ty)
  if b == "" {
    return false
  }
  for e in external_types {
    if e.name == b {
      return false
    }
  }
  if is_builtin_pointer_type(ty) {
    return true
  }
  if is_scalar_type(ty) {
    return false
  }
  for t in types {
    if t.name == b {
      return t.is_pointer
    }
  }
  false
}

///|
/// The signature of a declaration, as the C symbol sees it. Two
/// declarations of the same symbol must agree on it: the C function has ONE
/// prototype.
pub fn ffi_signature(decl : FfiDecl) -> String {
  let parts : Array[String] = []
  for p in decl.params {
    parts.push(p.ty + (if p.optional { "?" } else { "" }))
  }
  "(" + parts.join(", ") + ") -> " + decl.ret_ty
}

///|
/// The constant value of an integer literal expression, when it is one.
pub fn const_of_expr(e : Expr) -> Int64? {
  match e.kind {
    EInt(n) => Some(n.to_int64())
    EUn(UnNeg, inner) =>
      match const_of_expr(inner) {
        Some(v) => Some(-v)
        None => None
      }
    EBin(OpAdd, l, r) =>
      match (const_of_expr(l), const_of_expr(r)) {
        (Some(a), Some(b)) => Some(a + b)
        _ => None
      }
    EBin(OpSub, l, r) =>
      match (const_of_expr(l), const_of_expr(r)) {
        (Some(a), Some(b)) => Some(a - b)
        _ => None
      }
    EBin(OpMul, l, r) =>
      match (const_of_expr(l), const_of_expr(r)) {
        (Some(a), Some(b)) => Some(a * b)
        _ => None
      }
    _ => None
  }
}

///|
/// The hex form of a constant.
pub fn hex_of(n : Int64) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  out.write_string("0x")
  let mut v = if n < 0 { -n } else { n }
  if v == 0 {
    out.write_string("0")
    return out.to_string()
  }
  let buf : Array[String] = []
  while v > 0 {
    let d = (v % 16).to_int()
    buf.push(digits.get_char(d).unwrap_or('0').to_string())
    v = v / 16
  }
  let mut i = buf.length() - 1
  while i >= 0 {
    out.write_string(buf[i])
    i = i - 1
  }
  if n < 0 {
    out.write_string(" (negative)")
  }
  out.to_string()
}

///|
/// The name a C symbol is called by, normalised: the parser spells a
/// qualified call `A::b` and a qualified path `A.b`, and the two have to
/// meet.
fn norm_name(s : String) -> String {
  s.replace(old="::", new=".")
}

///|
/// Find the foreign declaration a call names, if any.
fn find_decl(decls : Array[FfiDecl], name : String) -> FfiDecl? {
  let n = norm_name(name)
  for d in decls {
    if norm_name(d.name) == n {
      return Some(d)
    }
  }
  None
}

///|
/// The name a bound variable mentions, when the expression IS that variable
/// or a method on it.
fn root_name(e : Expr) -> String {
  match e.kind {
    EName(n) => n
    EMethod(recv, _, _) => root_name(recv)
    EField(base, _) => root_name(base)
    _ => ""
  }
}

///|
/// True when the expression mentions the name -- a read of it.
fn expr_mentions(e : Expr, name : String) -> Bool {
  match e.kind {
    EName(n) => n == name
    EBin(_, l, r) => expr_mentions(l, name) || expr_mentions(r, name)
    EUn(_, x) => expr_mentions(x, name)
    ECall(f, args) => {
      if f == name {
        return true
      }
      for a in args {
        if expr_mentions(a, name) {
          return true
        }
      }
      false
    }
    EMethod(recv, _, args) => {
      if expr_mentions(recv, name) {
        return true
      }
      for a in args {
        if expr_mentions(a, name) {
          return true
        }
      }
      false
    }
    EField(base, _) => expr_mentions(base, name)
    EIndex(a, b) => expr_mentions(a, name) || expr_mentions(b, name)
    ESlice(a, b, c) => {
      let mut hit = expr_mentions(a, name)
      match b {
        Some(x) => if expr_mentions(x, name) { hit = true }
        None => ()
      }
      match c {
        Some(x) => if expr_mentions(x, name) { hit = true }
        None => ()
      }
      hit
    }
    EArray(xs) | ETuple(xs) => {
      for x in xs {
        if expr_mentions(x, name) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// True when the statement READS the name. An assignment to it is a write,
/// not a read, so it is not a use.
fn stmt_reads(s : Stmt, name : String) -> Bool {
  match s.kind {
    SLet(bound, _, init) => {
      if bound == name {
        return false
      }
      expr_mentions(init, name)
    }
    SAssign(lhs, rhs) => {
      if expr_mentions(lhs, name) {
        return false
      }
      expr_mentions(rhs, name)
    }
    SAssignOp(_, lhs, rhs) => {
      if expr_mentions(lhs, name) {
        return false
      }
      expr_mentions(rhs, name)
    }
    SIf(cond, then_body, else_body) => {
      if expr_mentions(cond, name) {
        return true
      }
      for x in then_body {
        if stmt_reads(x, name) {
          return true
        }
      }
      for x in else_body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    SWhile(cond, body) => {
      if expr_mentions(cond, name) {
        return true
      }
      for x in body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    SFor(_, _, _, _, body) => {
      for x in body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    SForIn(_, iter, body) => {
      if expr_mentions(iter, name) {
        return true
      }
      for x in body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    SReturn(e) =>
      match e {
        Some(x) => expr_mentions(x, name)
        None => false
      }
    SExpr(e) => expr_mentions(e, name)
    SBlock(body) => {
      for x in body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    STry(body) => {
      for x in body {
        if stmt_reads(x, name) {
          return true
        }
      }
      false
    }
    SUnsupported(_) => false
    SBreak => false
    SContinue => false
  }
}

///|
fn expr_ffi_calls(
  e : Expr,
  decls : Array[FfiDecl],
  out : Array[(FfiDecl, Array[Expr])],
) -> Unit {
  match e.kind {
    ECall(name, args) => {
      match find_decl(decls, name) {
        Some(d) => out.push((d, args))
        None => ()
      }
      for a in args {
        expr_ffi_calls(a, decls, out)
      }
    }
    EMethod(recv, _, args) => {
      expr_ffi_calls(recv, decls, out)
      for a in args {
        expr_ffi_calls(a, decls, out)
      }
    }
    EBin(_, l, r) => {
      expr_ffi_calls(l, decls, out)
      expr_ffi_calls(r, decls, out)
    }
    EUn(_, x) => expr_ffi_calls(x, decls, out)
    EField(base, _) => expr_ffi_calls(base, decls, out)
    EIndex(a, b) => {
      expr_ffi_calls(a, decls, out)
      expr_ffi_calls(b, decls, out)
    }
    ESlice(a, b, c) => {
      expr_ffi_calls(a, decls, out)
      match b {
        Some(x) => expr_ffi_calls(x, decls, out)
        None => ()
      }
      match c {
        Some(x) => expr_ffi_calls(x, decls, out)
        None => ()
      }
    }
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        expr_ffi_calls(x, decls, out)
      }
    _ => ()
  }
}

///|
/// The foreign declarations of a module.
pub fn ffi_decls_of(ast : ModuleAst) -> Array[FfiDecl] {
  let out : Array[FfiDecl] = []
  for f in ast.files {
    for d in f.ffi_decls {
      out.push(d)
    }
  }
  out
}

///|
/// The `#external` types of a module.
pub fn external_types_of(ast : ModuleAst) -> Array[ExternalType] {
  let out : Array[ExternalType] = []
  for f in ast.files {
    for t in f.external_types {
      out.push(t)
    }
  }
  out
}

///|
/// The type declarations of a module.
pub fn type_decls_of(ast : ModuleAst) -> Array[TypeDecl] {
  let out : Array[TypeDecl] = []
  for f in ast.files {
    for t in f.types {
      out.push(t)
    }
  }
  out
}

///|
/// The foreign declarations, indexed by the name they are called by.
pub fn ffi_map(ast : ModuleAst) -> Map[String, FfiDecl] {
  let out : Map[String, FfiDecl] = Map([])
  for d in ffi_decls_of(ast) {
    out[norm_name(d.name)] = d
  }
  out
}

///|
/// The foreign declaration a call names.
///
/// A MODULE IMPORT is not one: it lives in the same value space as the
/// MoonBit code, so nothing crosses a boundary at that call.
pub fn ffi_lookup(m : Map[String, FfiDecl], name : String) -> FfiDecl? {
  let n = norm_name(name)
  match m.get(n) {
    Some(d) => if d.is_c { Some(d) } else { None }
    None => None
  }
}

///|
/// The foreign declarations, with every parameter and every return value
/// put into the space it lives in.
///
/// The space is a property of the DECLARED TYPE, so it is the same for
/// every call of the declaration -- it does not depend on the call site.
fn classify_decls(
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
) -> Array[FfiDecl] {
  let out : Array[FfiDecl] = []
  for d in decls {
    let params : Array[FfiParam] = []
    for p in d.params {
      params.push({
        name: p.name,
        ty: p.ty,
        space: space_of_type(p.ty, external_types, types),
        ownership: p.ownership,
        optional: p.optional,
      })
    }
    out.push({
      name: d.name,
      symbol: d.symbol,
      is_c: d.is_c,
      params,
      ret_ty: d.ret_ty,
      ret_space: space_of_type(d.ret_ty, external_types, types),
      file: d.file,
      line: d.line,
      cfg: d.cfg,
    })
  }
  out
}

///|
/// Analyse the C boundary of a module.
///
/// The analysis is STATIC -- it is computed over the AST -- so it does not
/// depend on which inputs a run happened to sample.
pub fn analyze_ffi(ast : ModuleAst) -> FfiModel {
  let external_types = external_types_of(ast)
  let types = type_decls_of(ast)
  let decls = classify_decls(ffi_decls_of(ast), external_types, types)
  let findings : Array[Finding] = []
  let calls : Array[FfiCall] = []
  let registers : Array[FfiRegister] = []
  // The signature conflict: ONE C symbol, TWO MoonBit signatures. The
  // toolchain does not notice this (measured), and the C function has one
  // prototype, so one of the two claims is wrong.
  ffi_check_signature_conflicts(decls, findings)
  // The ownership contract: a pointer parameter with no annotation relies on
  // a default the toolchain says will change.
  ffi_check_ownership(decls, external_types, types, findings)
  // The target: a C extern in a module whose preferred target is wasm, or a
  // module import in a module whose preferred target is native.
  ffi_check_target(ast, decls, findings)
  // The call sites.
  ffi_collect_calls(ast, decls, external_types, types, calls, findings)
  // The named addresses.
  ffi_collect_addresses(calls, registers, findings)
  ffi_check_address_conflicts(registers, findings)
  // The classes safe MoonBit cannot express, and the C boundary can: the
  // allocation the module never releases, and the address it computes out of
  // a region it carved.
  //
  // The scan is only worth its three walks of the AST when the module HAS a
  // C boundary: a module that declares no foreign function has no allocation
  // to leak and no region to leave.
  if ffi_has_c_decls(decls) {
    ffi_scan_module(ast, decls, external_types, types, findings)
  }
  { decls, external_types, types, calls, registers, findings, }
}

///|
/// True when the module declares at least one C function.
fn ffi_has_c_decls(decls : Array[FfiDecl]) -> Bool {
  for d in decls {
    if d.is_c && d.symbol != "" {
      return true
    }
  }
  false
}

///|
/// Two declarations of the same C symbol with different signatures.
fn ffi_check_signature_conflicts(
  decls : Array[FfiDecl],
  findings : Array[Finding],
) -> Unit {
  let mut i = 0
  while i < decls.length() {
    let d = decls[i]
    if d.is_c && d.symbol != "" {
      let sig = ffi_signature(d)
      let mut j = i + 1
      while j < decls.length() {
        let other = decls[j]
        if other.is_c && other.symbol == d.symbol && ffi_signature(other) != sig {
          findings.push(
            Finding::new(
              FFfiSignatureConflict,
              d.file,
              d.line,
              "",
              "the C symbol '" +
              d.symbol +
              "' is declared with two different signatures: " +
              sig +
              " here and " +
              ffi_signature(other) +
              " at " +
              other.file +
              ":" +
              other.line.to_string() +
              ". The C function has ONE prototype, so one of the two claims is wrong.",
              "L2-FFI",
              0.9,
              d.name + " / " + other.name + " -> " + d.symbol,
            ),
          )
          findings.push(
            Finding::new(
              FFfiSignatureConflict,
              other.file,
              other.line,
              "",
              "the C symbol '" +
              other.symbol +
              "' is declared with two different signatures: " +
              ffi_signature(other) +
              " here and " +
              sig +
              " at " +
              d.file +
              ":" +
              d.line.to_string() +
              ". The C function has ONE prototype, so one of the two claims is wrong.",
              "L2-FFI",
              0.9,
              other.name + " / " + d.name + " -> " + other.symbol,
            ),
          )
        }
        j = j + 1
      }
    }
    i = i + 1
  }
}

///|
/// A pointer parameter with no ownership annotation.
fn ffi_check_ownership(
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  findings : Array[Finding],
) -> Unit {
  for d in decls {
    if !d.is_c {
      continue
    }
    for p in d.params {
      if p.ownership == OUnannotated &&
        is_pointer_type(p.ty, external_types, types) {
        findings.push(
          Finding::new(
            FFfiUnannotatedOwnership,
            d.file,
            d.line,
            "",
            "the pointer parameter '" +
            p.name +
            "' of '" +
            d.name +
            "' has no #borrow/#owned annotation. The toolchain requires one and says the current default (#owned) will change, so this declaration's calling convention is not pinned down.",
            "L2-FFI",
            0.85,
            d.name + "(" + p.name + " : " + p.ty + ")",
          ),
        )
      }
    }
  }
}

///|
/// True when a declaration is part of the build for `target`.
///
/// A `#cfg(target = "native")` guard keeps a declaration OUT of the wasm
/// build -- which is exactly how a module that declares a C extern and
/// publishes for wasm is written. So a target mismatch is only a defect
/// when the declaration is in the build for the published target.
pub fn cfg_allows(cfg : String, target : String) -> Bool {
  if cfg == "" {
    return true
  }
  // The target clauses in the guard: `target = "native"`, with or without
  // spaces around the `=`.
  let mut found = false
  let mut i = 0
  while i < cfg.length() {
    match cfg[i:].find("target") {
      Some(at) => {
        let mut j = i + at + 6
        while j < cfg.length() && is_space(cfg.get_char(j).unwrap_or(' ')) {
          j = j + 1
        }
        if j < cfg.length() && cfg.get_char(j) == Some('=') {
          j = j + 1
          while j < cfg.length() && is_space(cfg.get_char(j).unwrap_or(' ')) {
            j = j + 1
          }
          let start = j
          if j < cfg.length() && cfg.get_char(j) == Some('"') {
            // The quoted form: `target = "native"`.
            j = j + 1
            let qstart = j
            while j < cfg.length() && cfg.get_char(j) != Some('"') {
              j = j + 1
            }
            found = true
            if cfg[qstart:j] == target {
              return true
            }
          } else {
            // The rendered form: the attribute's tokens carry the string's
            // CONTENT, not its quotes, so the value runs to the separator.
            while j < cfg.length() {
              let c = cfg.get_char(j).unwrap_or(' ')
              if c == ',' || c == ')' || is_space(c) {
                break
              }
              j = j + 1
            }
            found = true
            if cfg[start:j] == target {
              return true
            }
          }
        }
        i = j + 1
      }
      None => break
    }
  }
  // A guard with no target clause applies to every target.
  !found
}

///|
/// The target the module publishes, against the kind of declaration it has.
fn ffi_check_target(
  ast : ModuleAst,
  decls : Array[FfiDecl],
  findings : Array[Finding],
) -> Unit {
  let target = ast.manifest_target
  if target == "" {
    return
  }
  for d in decls {
    if !cfg_allows(d.cfg, target) {
      // The declaration is not part of the build for the published target.
      continue
    }
    if d.is_c {
      if target == "wasm" {
        findings.push(
          Finding::new(
            FFfiTargetMismatch,
            d.file,
            d.line,
            "",
            "'" +
            d.name +
            "' is a C extern, and the module's preferred target is wasm, where the toolchain rejects extern \"C\" (E4156). The published artifact cannot be built for this target.",
            "L2-FFI",
            0.9,
            d.name + " -> " + d.symbol,
          ),
        )
      }
    } else if target == "native" {
      findings.push(
        Finding::new(
          FFfiTargetMismatch,
          d.file,
          d.line,
          "",
          "'" +
          d.name +
          "' is a module import, and the module's preferred target is native, where the toolchain rejects module imports (E4156: use extern \"C\" instead).",
          "L2-FFI",
          0.9,
          d.name,
        ),
      )
    }
  }
}

///|
/// The call sites of the foreign functions, and what happens at them.

///|
/// An object the C side has been told to FREE.
priv struct FfiFreed {
  /// The name of the object.
  name : String
  /// The line of the call that freed it.
  line : Int32
  /// The C symbol that freed it.
  symbol : String
  /// False once the name has been given a NEW value: it then holds a
  /// different object, and the object that was freed is not this one.
  mut live : Bool
}

///|
/// True when the C symbol is a RELEASE: a function that frees what it is
/// given.
///
/// The analyzer cannot see the C source, so the NAME is all it has. The
/// words below are the ones the C world uses for a release, and a C function
/// that frees under a name outside this set is not recognised -- the family
/// contract says so, so the limit is stated rather than implied.
fn ffi_is_release_symbol(symbol : String) -> Bool {
  let s = symbol.to_lower()
  for
    word in [
      "free", "release", "destroy", "dispose", "dealloc", "finalize", "close",
    ] {
    if s.contains(word) {
      return true
    }
  }
  false
}

///|
/// True when the parameter's NAME says it is a LENGTH.
///
/// The C source is not visible, so the name is the only signal there is.
fn ffi_is_length_name(name : String) -> Bool {
  let n = name.to_lower()
  n.contains("len") || n.contains("size") || n.contains("count") || n == "n"
}

///|
/// True when the type is a byte buffer: a `Bytes`, or an array of bytes.
///
/// A `String` is NOT one of these: it crosses as `uint16_t *`, so its length
/// in bytes is not its length in MoonBit.
fn ffi_is_bytes_type(ty : String) -> Bool {
  let t = ty.trim()
  t == "Bytes" || t == "FixedArray[Byte]" || t == "Array[Byte]"
}

///|
/// The byte length of a byte literal, when the analyzer can tell it.
///
/// The length is exact only when every byte is a printable ASCII one: an
/// escape has already been resolved by the lexer, so the text would be
/// longer than the bytes it stands for, and those are not measured.
fn ffi_bytes_literal_len(e : Expr) -> Int32? {
  match e.kind {
    EBytes(s) => {
      for i in 0..<s.length() {
        let b = s[i]
        if b < 32 || b > 126 {
          return None
        }
      }
      Some(s.length())
    }
    _ => None
  }
}

///|
/// The root name of an expression: the variable it is.
fn ffi_root_name(e : Expr) -> String {
  match e.kind {
    EName(n) => n
    _ => ""
  }
}

///|
/// True when the statement REBINDS the name, rather than reading what it
/// holds.
fn ffi_assigns_to(s : Stmt, name : String) -> Bool {
  match s.kind {
    SAssign(lhs, _) =>
      match lhs.kind {
        EName(n) => n == name
        _ => false
      }
    _ => false
  }
}

///|
/// The length the C side is told, and the object it is told it for.
///
/// Two shapes are a disagreement, and both are facts rather than guesses:
///
///   - the length is the length of something this call is NOT given: the C
///     side is told how many bytes to move, and the number describes a
///     different object;
///   - the length is a literal and the object is a literal of another
///     length: the C side is told to move four bytes of a three-byte object.
///
/// A length that is a VARIABLE is not judged: the analyzer cannot prove what
/// the variable holds, and the family contract says so.
fn ffi_check_length_mismatch(
  d : FfiDecl,
  args : Array[Expr],
  f : Func,
  s : Stmt,
  findings : Array[Finding],
) -> Unit {
  let mut len_idx = -1
  let obj_idx : Array[Int32] = []
  for i in 0..<d.params.length() {
    let p = d.params[i]
    if is_integer_type(p.ty) && ffi_is_length_name(p.name) {
      if len_idx < 0 {
        len_idx = i
      }
    } else if ffi_is_bytes_type(p.ty) {
      obj_idx.push(i)
    }
  }
  if len_idx < 0 || obj_idx.length() == 0 {
    return
  }
  if len_idx >= args.length() {
    return
  }
  // The names of the objects this call is given.
  let obj_names : Array[String] = []
  for i in obj_idx {
    if i < args.length() {
      let n = ffi_root_name(args[i])
      if n != "" {
        obj_names.push(n)
      }
    }
  }
  let len_text = args[len_idx].render()
  // (1) The length is the length of something this call is NOT given.
  let suffix = ".length()"
  if len_text.has_suffix(suffix) {
    let other = len_text[0:len_text.length() - suffix.length()].to_owned()
    if !obj_names.contains(other) {
      findings.push(
        Finding::new(
          FFfiLengthMismatch,
          f.file,
          s.span.start_line,
          f.name,
          "'" +
          d.name +
          "' is given the length of '" +
          other +
          "', which is not one of the objects it is given (" +
          ffi_join(obj_names) +
          "). The C side is told how many bytes to move, and the number describes a different object, so it may read or write outside the one the C side was handed.",
          "L2-FFI",
          0.7,
          d.name + " @ " + f.file + ":" + s.span.start_line.to_string(),
        ),
      )
    }
    return
  }
  // (2) The length is a literal and the ONE object is a literal of another
  // length.
  if obj_idx.length() != 1 {
    return
  }
  let oi = obj_idx[0]
  if oi >= args.length() {
    return
  }
  match const_of_expr(args[len_idx]) {
    Some(n) =>
      match ffi_bytes_literal_len(args[oi]) {
        Some(actual) =>
          if actual.to_int64() != n {
            findings.push(
              Finding::new(
                FFfiLengthMismatch,
                f.file,
                s.span.start_line,
                f.name,
                "'" +
                d.name +
                "' is given the length " +
                n.to_string() +
                " and an object of " +
                actual.to_string() +
                " bytes. The C side is told to move more bytes than the object holds, so it may read or write outside it.",
                "L2-FFI",
                0.7,
                d.name + " @ " + f.file + ":" + s.span.start_line.to_string(),
              ),
            )
          }
        None => ()
      }
    None => ()
  }
}

///|
fn ffi_join(names : Array[String]) -> String {
  if names.length() == 0 {
    return "none"
  }
  let mut out = ""
  let mut i = 0
  while i < names.length() {
    if i > 0 {
      out = out + ", "
    }
    out = out + "'" + names[i] + "'"
    i = i + 1
  }
  out
}

///|
fn ffi_collect_calls(
  ast : ModuleAst,
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  calls : Array[FfiCall],
  findings : Array[Finding],
) -> Unit {
  for f in ast.all_funcs() {
    let moved : Array[(String, Int32, String)] = []
    let freed : Array[FfiFreed] = []
    // The C symbol that produced each local value: the PROVENANCE of a
    // foreign address.
    let producers : Map[String, String] = Map([])
    for s in f.body {
      ffi_visit_stmt(
        f, s, decls, external_types, types, calls, findings, moved, freed, producers,
      )
    }
  }
}

///|
/// One statement of a function, in order: the foreign calls it makes, the
/// objects it gives away, and what it touches afterwards.
fn ffi_visit_stmt(
  f : Func,
  s : Stmt,
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  calls : Array[FfiCall],
  findings : Array[Finding],
  moved : Array[(String, Int32, String)],
  freed : Array[FfiFreed],
  producers : Map[String, String],
) -> Unit {
  // The name is given a NEW value: it is a different object now, so the
  // object the C side freed is not the one the name holds.
  match s.kind {
    SAssign(lhs, _) =>
      match lhs.kind {
        EName(n) => {
          let mut k = 0
          while k < freed.length() {
            if freed[k].name == n {
              freed[k].live = false
            }
            k = k + 1
          }
        }
        _ => ()
      }
    _ => ()
  }
  // The calls this statement makes, and the objects it releases. The release
  // is worked out BEFORE the use checks, because a call that FREES an object
  // is not itself a USE of the freed memory -- it IS the free.
  //
  // The collector is the one that does NOT descend: this walk descends
  // itself, and a collector that descended as well would visit every nested
  // statement twice -- one defect, reported once per visit.
  let found : Array[(FfiDecl, Array[Expr])] = []
  ffi_stmt_calls(s, decls, found)
  let freed_here : Array[String] = []
  for (d, args) in found {
    if d.is_c && d.symbol != "" && ffi_is_release_symbol(d.symbol) {
      for i in 0..<d.params.length() {
        if !is_pointer_type(d.params[i].ty, external_types, types) {
          continue
        }
        if i >= args.length() {
          continue
        }
        let name = root_name(args[i])
        if name != "" && !freed_here.contains(name) {
          freed_here.push(name)
        }
      }
    }
  }
  // A USE of an object the C side has already freed.
  for fr in freed {
    if fr.live &&
      !freed_here.contains(fr.name) &&
      !ffi_assigns_to(s, fr.name) &&
      stmt_reads(s, fr.name) {
      findings.push(
        Finding::new(
          FFfiUseAfterFree,
          f.file,
          s.span.start_line,
          f.name,
          "'" +
          fr.name +
          "' was given to the C function '" +
          fr.symbol +
          "' at line " +
          fr.line.to_string() +
          ", and it is used here. That function frees what it is given, so this use reads memory the allocator may already have handed to someone else.",
          "L2-FFI",
          0.9,
          fr.name + " -> " + fr.symbol,
        ),
      )
    }
  }
  // A USE of an object that was already given away.
  for (name, line, symbol) in moved {
    if stmt_reads(s, name) {
      findings.push(
        Finding::new(
          FFfiUseAfterMove,
          f.file,
          s.span.start_line,
          f.name,
          "'" +
          name +
          "' was given to the C function '" +
          symbol +
          "' as #owned at line " +
          line.to_string() +
          ", and it is used here. The C side owns it now; this use reads memory the MoonBit side no longer owns.",
          "L2-FFI",
          0.9,
          name + " -> " + symbol,
        ),
      )
    }
  }
  for (d, args) in found {
    let call_args : Array[FfiArg] = []
    for i in 0..<args.length() {
      let a = args[i]
      let mut ty = ""
      if i < d.params.length() {
        ty = d.params[i].ty
      }
      let external_slot = space_of_type(ty, external_types, types) == SExternal
      // The REGION of an address: the C symbol that produced the value,
      // when the analyzer can trace it.
      let mut region = ""
      if external_slot {
        match a.kind {
          EName(n) =>
            match producers.get(n) {
              Some(sym) => region = sym
              None => region = ""
            }
          ECall(callee, _) =>
            match find_decl(decls, callee) {
              Some(d) => region = d.symbol
              None => region = ""
            }
          _ => region = ""
        }
      }
      call_args.push({
        text: a.render(),
        const_value: const_of_expr(a),
        is_int_slot: is_integer_type(ty),
        is_external_slot: external_slot,
        region,
      })
    }
    calls.push({
      decl_name: d.name,
      symbol: d.symbol,
      file: f.file,
      line: s.span.start_line,
      fn_name: f.name,
      args: call_args,
    })
    // The object this call gives away.
    for i in 0..<d.params.length() {
      if d.params[i].ownership != OOwned {
        continue
      }
      if i >= args.length() {
        continue
      }
      let name = root_name(args[i])
      if name == "" {
        continue
      }
      moved.push((name, s.span.start_line, d.symbol))
    }
    // The object this call FREES. A release-shaped C symbol frees what it is
    // given, whatever the ownership annotation says.
    if d.is_c && d.symbol != "" && ffi_is_release_symbol(d.symbol) {
      for i in 0..<d.params.length() {
        if !is_pointer_type(d.params[i].ty, external_types, types) {
          continue
        }
        if i >= args.length() {
          continue
        }
        let name = root_name(args[i])
        if name == "" {
          continue
        }
        let mut already = false
        for fr in freed {
          if fr.live && fr.name == name {
            already = true
            break
          }
        }
        if already {
          findings.push(
            Finding::new(
              FFfiDoubleFree,
              f.file,
              s.span.start_line,
              f.name,
              "'" +
              name +
              "' was already given to a C function that frees it, and it is given to one again here. The C side frees the same object twice, so the second free hands the allocator memory it has already taken back.",
              "L2-FFI",
              0.9,
              name + " -> " + d.symbol,
            ),
          )
        } else {
          freed.push({
            name,
            line: s.span.start_line,
            symbol: d.symbol,
            live: true,
          })
        }
      }
    }
    // The length the C side is told, and the object it is told it for.
    ffi_check_length_mismatch(d, args, f, s, findings)
    // The FORMAT slot, handed a string the module did not write out.
    ffi_check_format_string(d, args, f, s, findings)
    // The PROVENANCE of the value this call returns: the name it is bound
    // to now belongs to the C symbol that produced it.
    match s.kind {
      SLet(bound, _, init) =>
        match init.kind {
          ECall(callee, _) =>
            if norm_name(callee) == norm_name(d.name) {
              producers[bound] = d.symbol
            }
          _ => ()
        }
      _ => ()
    }
  }
  // Recurse into the nested statements, in order.
  match s.kind {
    SIf(_, then_body, else_body) => {
      for x in then_body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
      for x in else_body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    }
    SWhile(_, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    SFor(_, _, _, _, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    SForIn(_, _, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    SBlock(body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    STry(body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, freed, producers,
        )
      }
    _ => ()
  }
}

///|
/// The constant addresses the module hands to C, and the slots whose value
/// the analyzer cannot name.
///
/// The analyzer does NOT claim that an integer argument is an address: an
/// integer handed to a C function may be an address, a length or a plain
/// value, and nothing in the MoonBit source says which. What it can say is
/// this:
///
///   - a slot that the module fills with a CONSTANT at one call site and
///     with a COMPUTED value at another is a slot the module treats as
///     sometimes-fixed. If it carries an address, the region the call
///     touches cannot be named at the computed site.
///   - the constants themselves are collected into a table, so a reader can
///     see every fixed number the module hands to C.
fn ffi_collect_addresses(
  calls : Array[FfiCall],
  registers : Array[FfiRegister],
  findings : Array[Finding],
) -> Unit {
  // The slots each symbol fills with a constant.
  let const_slots : Map[String, Array[Int32]] = Map([])
  for c in calls {
    if c.symbol == "" {
      continue
    }
    let mut slots : Array[Int32] = []
    match const_slots.get(c.symbol) {
      Some(s) => slots = s.copy()
      None => ()
    }
    for i in 0..<c.args.length() {
      let a = c.args[i]
      if a.is_int_slot && a.const_value is Some(_) && !slots.contains(i) {
        slots.push(i)
      }
    }
    const_slots[c.symbol] = slots
  }
  for c in calls {
    if c.symbol == "" {
      continue
    }
    let slots : Array[Int32] = match const_slots.get(c.symbol) {
      Some(s) => s
      None => []
    }
    for i in 0..<c.args.length() {
      let a = c.args[i]
      if !a.is_int_slot {
        continue
      }
      match a.const_value {
        None =>
          // The slot is a constant at another call site of the same symbol
          // and computed here: the analyzer cannot name what it is.
          if slots.contains(i) {
            findings.push(
              Finding::new(
                FFfiAddressUnknown,
                c.file,
                c.line,
                c.fn_name,
                "the argument in slot " +
                i.to_string() +
                " of '" +
                c.symbol +
                "' is computed here, while the module passes a constant in the same slot elsewhere. If that slot carries an address, the region this call touches cannot be named.",
                "L2-FFI",
                0.5,
                c.decl_name + "(" + a.text + ")",
              ),
            )
          }
        Some(v) => {
          let site = c.symbol + "@" + c.file + ":" + c.line.to_string()
          // The OTHER constants at this site: the values written with the
          // address.
          let others : Array[Int64] = []
          for j in 0..<c.args.length() {
            if j == i {
              continue
            }
            match c.args[j].const_value {
              Some(w) => if !others.contains(w) { others.push(w) }
              None => ()
            }
          }
          let mut found = false
          for r in registers {
            if r.address == v {
              found = true
              if !r.symbols.contains(c.symbol) {
                r.symbols.push(c.symbol)
              }
              if !r.sites.contains(site) {
                r.sites.push(site)
              }
              for w in others {
                if !r.values.contains(w) {
                  r.values.push(w)
                }
              }
            }
          }
          if !found {
            registers.push({
              address: v,
              text: hex_of(v),
              symbols: [c.symbol],
              sites: [site],
              file: c.file,
              line: c.line,
              fn_name: c.fn_name,
              values: others,
            })
          }
        }
      }
    }
  }
}

///|
/// The same constant handed to two different C symbols.
///
/// The analyzer does not claim the constant is an address -- it may be a
/// value -- so the finding is stated as what it can prove: the same fixed
/// number reaches two different C functions.
fn ffi_check_address_conflicts(
  registers : Array[FfiRegister],
  findings : Array[Finding],
) -> Unit {
  for r in registers {
    if r.symbols.length() > 1 {
      findings.push(
        Finding::new(
          FFfiAddressConflict,
          r.file,
          r.line,
          r.fn_name,
          "the constant " +
          r.text +
          " is handed to " +
          r.symbols.length().to_string() +
          " different C symbols (" +
          r.symbols.join(", ") +
          "). If it is an address, at most one of them can own it, so what the C side does with it depends on which call ran last.",
          "L2-FFI",
          0.5,
          r.text + " -> " + r.symbols.join(", "),
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// The classes that safe MoonBit cannot express, and that the C boundary CAN.
//
// MoonBit has no raw pointer, no free, no format string and no pointer
// arithmetic, so the EVA layer can never produce USE-AFTER-FREE,
// MEMORY-LEAK, POINTER-ARITHMETIC or FORMAT-STRING -- their contracts say
// why. The C boundary is where all four are real, and the C source is not
// visible, so each one is recognised by what the MOONBIT side does:
//
//   - FFI-ALLOCATION-NOT-RELEASED: an allocation the C side handed back, and
//     nothing in the module ever releases;
//   - FFI-FORMAT-STRING: a format slot handed a string the module did not
//     write out;
//   - FFI-ADDRESS-OOB: an address computed out of a region the module carved,
//     past the end of that region.
//
// Every check here is a MAY-claim unless it says otherwise, and each
// family's contract in `family.mbt` states what the analyzer cannot see.
// ---------------------------------------------------------------------------

///|
/// The foreign calls ONE statement makes, without descending into the
/// statements nested in it.
///
/// The descent is the caller's job, so that every statement is seen with the
/// context it was written in -- a binding inside an `if` is the binding of
/// that `if`, and not of the function. A collector that descends as well
/// would visit every nested statement twice, and one defect would then be
/// reported once per visit.
fn ffi_stmt_calls(
  s : Stmt,
  decls : Array[FfiDecl],
  out : Array[(FfiDecl, Array[Expr])],
) -> Unit {
  match s.kind {
    SLet(_, _, init) => expr_ffi_calls(init, decls, out)
    SAssign(_, rhs) => expr_ffi_calls(rhs, decls, out)
    SAssignOp(_, _, rhs) => expr_ffi_calls(rhs, decls, out)
    SIf(cond, _, _) => expr_ffi_calls(cond, decls, out)
    SWhile(cond, _) => expr_ffi_calls(cond, decls, out)
    SFor(_, from, to, step, _) => {
      expr_ffi_calls(from, decls, out)
      expr_ffi_calls(to, decls, out)
      expr_ffi_calls(step, decls, out)
    }
    SForIn(_, iter, _) => expr_ffi_calls(iter, decls, out)
    SReturn(e) =>
      match e {
        Some(x) => expr_ffi_calls(x, decls, out)
        None => ()
      }
    SExpr(e) => expr_ffi_calls(e, decls, out)
    _ => ()
  }
}

///|
/// True when the symbol's name is the WORD: the name is the word, or the
/// word followed by the separator that ends it.
///
/// The name is read the way the C world spells one -- in lower case, with
/// `_` between the words -- because that is the only shape the analyzer can
/// rely on. "create_region" carries "create"; "created_at" does not, because
/// the word there is "created".
fn ffi_name_is_word(symbol : String, word : String) -> Bool {
  let s = symbol.to_lower()
  s == word || s.has_prefix(word + "_")
}

///|
/// True when the symbol's name STARTS with the stem, whatever follows it.
///
/// Only the stems that legitimately extend are matched this way: "alloc"
/// covers "alloc", "allocate", "allocation" and "allocator".
fn ffi_name_starts_with(symbol : String, stem : String) -> Bool {
  symbol.to_lower().has_prefix(stem)
}

///|
/// True when the C symbol ALLOCATES: it hands back something the C side owns.
///
/// The analyzer cannot see the C source, so the NAME is all it has -- the
/// same bargain the release list makes. Three things keep the set honest:
///
///   - the symbol must not be a release;
///   - it must RETURN an address: a foreign type, which is one by
///     construction, or an integer, which may be one. This is what keeps
///     "unmap_page" out of the set even though it contains "map", and it is
///     the difference between an allocation and a free;
///   - an INTEGER return is weaker evidence than a foreign address, so then
///     the name has to be one of the allocator names proper. A function
///     called "created_at" that returns an Int32 is not an allocation.
fn ffi_is_allocator_symbol(
  symbol : String,
  ret_ty : String,
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
) -> Bool {
  if symbol == "" || ffi_is_release_symbol(symbol) {
    return false
  }
  let foreign = space_of_type(ret_ty, external_types, types) == SExternal
  let integer = is_integer_type(ret_ty)
  if !foreign && !integer {
    return false
  }
  if integer && !foreign {
    return ffi_name_is_allocator_proper(symbol)
  }
  ffi_name_starts_with(symbol, "alloc") ||
  ffi_name_is_word(symbol, "mmap") ||
  ffi_name_is_word(symbol, "create") ||
  ffi_name_is_word(symbol, "reserve") ||
  ffi_name_is_word(symbol, "open") ||
  ffi_name_is_word(symbol, "obtain") ||
  ffi_name_is_word(symbol, "acquire") ||
  ffi_name_is_word(symbol, "new") ||
  ffi_name_is_word(symbol, "dup")
}

///|
/// The allocator names proper: the ones that mean an allocation on their own,
/// with no need for the type to say it too.
fn ffi_name_is_allocator_proper(symbol : String) -> Bool {
  ffi_name_starts_with(symbol, "alloc") ||
  ffi_name_starts_with(symbol, "mmap") ||
  ffi_name_starts_with(symbol, "malloc") ||
  ffi_name_starts_with(symbol, "calloc") ||
  ffi_name_starts_with(symbol, "realloc")
}

///|
/// True when the parameter's NAME says it is a FORMAT.
///
/// The C source is not visible, so the name is the only signal there is --
/// the same bargain the length slot makes. A format parameter is the one the
/// C side INTERPRETS: a string with '%' in it is read as a format, so an
/// untrusted string in that slot is read as a format too.
fn ffi_is_format_name(name : String) -> Bool {
  let n = name.to_lower()
  n == "fmt" ||
  n == "format" ||
  n == "template" ||
  n == "spec" ||
  n == "pattern"
}

///|
/// True when the type is a STRING the C side can read characters from.
fn ffi_is_string_type(ty : String) -> Bool {
  let t = ty.trim()
  t == "String" || t == "Bytes"
}

///|
/// True when the expression is a string the module WROTE OUT.
fn ffi_is_string_literal(e : Expr) -> Bool {
  match e.kind {
    EString(_) => true
    _ => false
  }
}

///|
/// True when the value comes from OUTSIDE the function: it is one of the
/// function's parameters, or it is derived from one.
///
/// The FFI model is a static pass over the AST and it has no taint of its
/// own, so "untrusted" here means "not computed inside the function". The
/// family's contract says so, so the limit is stated rather than implied.
fn ffi_comes_from_outside(f : Func, e : Expr) -> Bool {
  for p in f.params {
    if expr_mentions(e, p.name) {
      return true
    }
  }
  false
}

///|
/// One allocation the C side handed back.
priv struct FfiAllocation {
  name : String
  symbol : String
  ty : String
  file : String
  line : Int32
  fn_name : String
  escapes : Bool
}

///|
/// One name handed to something that frees.
priv struct FfiReleased {
  name : String
  ty : String
  is_ptr : Bool
}

///|
/// One address the module COMPUTED at a call site: a base and an offset.
priv struct FfiComputed {
  base : Int64
  offset : Int64
  symbol : String
  param : String
  file : String
  line : Int32
  fn_name : String
}

///|
/// What the FFI model collects for the WHOLE MODULE while it walks it.
///
/// The arrays are the mutable part: the model hands this struct down the
/// recursion and pushes into the arrays, so the module-wide facts survive
/// the walk.
priv struct FfiModuleScan {
  /// The allocations the C side handed back, and the name each was bound to.
  allocated : Array[FfiAllocation]
  /// Every name handed to something that frees.
  released : Array[FfiReleased]
  /// The regions the module carved out: the base address and the size.
  regions : Array[(Int64, Int64)]
  /// The addresses the module computed at a call site.
  computed : Array[FfiComputed]
}

///|
/// The module-wide facts the FFI model needs.
fn ffi_new_scan() -> FfiModuleScan {
  { allocated: [], released: [], regions: [], computed: [], }
}

///|
/// Walk the module and collect what the two module-wide checks need.
///
/// The scan is PER FUNCTION. The analyzer follows one function at a time --
/// the release families say so in their contracts -- and a module-wide name
/// table would mix two functions' bindings together: a function that releases
/// a name would cancel an unrelated allocation of the SAME name in another
/// function, and the finding would vanish.
fn ffi_scan_module(
  ast : ModuleAst,
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  findings : Array[Finding],
) -> Unit {
  for f in ast.all_funcs() {
    let escaped = ffi_escaped_names(f)
    let scan = ffi_new_scan()
    for s in f.body {
      ffi_scan_stmt(f, s, decls, external_types, types, scan, escaped)
    }
    ffi_check_allocations(scan, findings)
    ffi_check_address_bounds(scan, findings)
  }
}

///|
/// One statement: the foreign calls it makes, what it releases, what it binds
/// to an allocation, and the addresses it computes.
fn ffi_scan_stmt(
  f : Func,
  s : Stmt,
  decls : Array[FfiDecl],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  scan : FfiModuleScan,
  escaped : Array[String],
) -> Unit {
  let found : Array[(FfiDecl, Array[Expr])] = []
  ffi_stmt_calls(s, decls, found)
  for (d, args) in found {
    if !d.is_c || d.symbol == "" {
      continue
    }
    // What this call RELEASES.
    if ffi_is_release_symbol(d.symbol) {
      ffi_scan_release(d, args, external_types, types, scan)
      continue
    }
    // What this call ALLOCATES: the region it carved out, and the name the
    // allocation was bound to.
    if ffi_is_allocator_symbol(d.symbol, d.ret_ty, external_types, types) {
      ffi_scan_allocation(f, s, d, args, scan, escaped)
    }
    // The addresses the module computes at this call site.
    ffi_scan_computed(f, s, d, args, scan)
  }
  // Descend, in order.
  match s.kind {
    SIf(_, then_body, else_body) => {
      for x in then_body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
      for x in else_body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    }
    SWhile(_, body) =>
      for x in body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    SFor(_, _, _, _, body) =>
      for x in body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    SForIn(_, _, body) =>
      for x in body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    SBlock(body) =>
      for x in body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    STry(body) =>
      for x in body {
        ffi_scan_stmt(f, x, decls, external_types, types, scan, escaped)
      }
    _ => ()
  }
}

///|
/// What a release-shaped C call gives back: the name it is given, and the
/// type of the slot it was given in.
///
/// The release is recognised by the SYMBOL's NAME, and the slot has to be
/// one the C side can own: a POINTER, or a value of the foreign type the
/// allocator handed back.
fn ffi_scan_release(
  d : FfiDecl,
  args : Array[Expr],
  external_types : Array[ExternalType],
  types : Array[TypeDecl],
  scan : FfiModuleScan,
) -> Unit {
  // The loop runs over the ARGUMENTS, not over the parameters: the arguments
  // are what the call actually passed, and their length is a number the
  // analyzer can see, while a parameter list is a field of a struct and its
  // length is opaque. Iterating the arguments is also what makes the index
  // provably inside them.
  for i in 0..<args.length() {
    if i >= d.params.length() {
      continue
    }
    let name = root_name(args[i])
    if name == "" {
      continue
    }
    let is_ptr = is_pointer_type(d.params[i].ty, external_types, types)
    let is_foreign = space_of_type(d.params[i].ty, external_types, types) ==
      SExternal
    if !is_ptr && !is_foreign {
      continue
    }
    let ty = base_type_name(d.params[i].ty)
    let mut known = false
    for r in scan.released {
      if r.name == name && r.ty == ty {
        known = true
        break
      }
    }
    if !known {
      scan.released.push({ name, ty, is_ptr, })
    }
  }
}

///|
/// The allocation a call hands back: the region it carved out, and the name
/// the result was bound to.
fn ffi_scan_allocation(
  f : Func,
  s : Stmt,
  d : FfiDecl,
  args : Array[Expr],
  scan : FfiModuleScan,
  escaped : Array[String],
) -> Unit {
  // The REGION: the base address and the size the module asked for. The
  // size is the argument whose parameter name says it is a length, and both
  // have to be constants for the region to be nameable.
  let base = ffi_region_base(d, args)
  let size = ffi_region_size(d, args)
  match (base, size) {
    (Some(b), Some(sz)) => {
      let mut known = false
      for r in scan.regions {
        if r.0 == b && r.1 == sz {
          known = true
          break
        }
      }
      if !known {
        scan.regions.push((b, sz))
      }
    }
    _ => ()
  }
  // The NAME the allocation was bound to.
  let bound = ffi_bound_name(s, d.name)
  if bound != "" {
    let ty = base_type_name(d.ret_ty)
    scan.allocated.push({
      name: bound,
      symbol: d.symbol,
      ty,
      file: f.file,
      line: s.span.start_line,
      fn_name: f.name,
      escapes: ffi_name_escapes(f, bound, ty, escaped),
    })
  }
}

///|
/// The BASE of the region a call carved out: the argument in the slot whose
/// name says it is an address, or the first argument when there is no such
/// slot.
fn ffi_region_base(d : FfiDecl, args : Array[Expr]) -> Int64? {
  for i in 0..<args.length() {
    if i >= d.params.length() {
      continue
    }
    if !ffi_is_base_name(d.params[i].name) {
      continue
    }
    match const_of_expr(args[i]) {
      Some(v) => return Some(v)
      None => return None
    }
  }
  if args.length() == 0 {
    return None
  }
  const_of_expr(args[0])
}

///|
/// The SIZE of the region a call carved out: the argument in the slot whose
/// name says it is a length, when it is a constant.
fn ffi_region_size(d : FfiDecl, args : Array[Expr]) -> Int64? {
  for i in 0..<args.length() {
    if i >= d.params.length() {
      continue
    }
    if !ffi_is_length_name(d.params[i].name) {
      continue
    }
    match const_of_expr(args[i]) {
      Some(v) => return Some(v)
      None => return None
    }
  }
  None
}

///|
/// True when the parameter's NAME says it is the BASE of a region.
fn ffi_is_base_name(name : String) -> Bool {
  let n = name.to_lower()
  n.contains("base") ||
  n.contains("addr") ||
  n.contains("start") ||
  n.contains("origin") ||
  n == "p"
}

///|
/// The name a call's result is bound to, when the statement binds it.
fn ffi_bound_name(s : Stmt, callee : String) -> String {
  match s.kind {
    SLet(n, _, init) =>
      match init.kind {
        ECall(c, _) => if norm_name(c) == norm_name(callee) { n } else { "" }
        _ => ""
      }
    SAssign(lhs, rhs) =>
      match (lhs.kind, rhs.kind) {
        (EName(n), ECall(c, _)) =>
          if norm_name(c) == norm_name(callee) {
            n
          } else {
            ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
/// The address the module COMPUTES at a call site: a constant base and a
/// constant offset, added together.
///
/// The address is only nameable when both halves are constants: a computed
/// offset is a number the analyzer cannot compare against the region's size,
/// and the family's contract says so.
fn ffi_scan_computed(
  f : Func,
  s : Stmt,
  d : FfiDecl,
  args : Array[Expr],
  scan : FfiModuleScan,
) -> Unit {
  for i in 0..<args.length() {
    if i >= d.params.length() {
      continue
    }
    if !is_integer_type(d.params[i].ty) {
      continue
    }
    match args[i].kind {
      EBin(OpAdd, l, r) =>
        match (const_of_expr(l), const_of_expr(r)) {
          (Some(a), Some(b)) =>
            scan.computed.push({
              base: a,
              offset: b,
              symbol: d.symbol,
              param: d.params[i].name,
              file: f.file,
              line: s.span.start_line,
              fn_name: f.name,
            })
          _ => ()
        }
      _ => ()
    }
  }
}

///|
/// Whether the function HANDS the allocation ON.
///
/// Whoever holds it now is responsible for it, so it is not a leak. Two
/// shapes hand it on: the function RETURNS it, and it is STORED into another
/// object. A function whose OWN return type is the allocation's type is the
/// common shape, `fn make() -> Reg`, and it is the caller of that function
/// that holds it.
///
/// Passing it to a C call is NOT one of them: the C side may only read it,
/// and the analyzer cannot see whether the C function takes it over.
fn ffi_name_escapes(
  f : Func,
  name : String,
  ty : String,
  escaped : Array[String],
) -> Bool {
  if ty != "" && base_type_name(f.ret_ty) == ty {
    return true
  }
  escaped.contains(name)
}

///|
/// The names the function HANDS ON: the ones it returns, and the ones it
/// stores into another object.
///
/// The set is computed ONCE per function. Asking the question per allocation
/// would walk the function's body once per allocation, and a function with
/// many allocations would cost its body length times over.
fn ffi_escaped_names(f : Func) -> Array[String] {
  let out : Array[String] = []
  for s in f.body {
    ffi_collect_escaped_stmt(s, out)
  }
  // The TAIL: a function body ends with its last expression, and that
  // expression is the function's value.
  if f.body.length() > 0 {
    let last = f.body[f.body.length() - 1]
    match last.kind {
      SExpr(e) =>
        match e.kind {
          EName(n) => if !out.contains(n) { out.push(n) }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// The names one statement hands on.
///
/// Only a BARE NAME counts. A method call on the allocation -- `r.push(x)` --
/// mutates it in place and hands it to nobody, and the receiver of a method
/// call is the same thing the receiver of any other call is.
fn ffi_collect_escaped_stmt(s : Stmt, out : Array[String]) -> Unit {
  match s.kind {
    SReturn(e) =>
      match e {
        Some(x) =>
          match x.kind {
            EName(n) => if !out.contains(n) { out.push(n) }
            _ => ()
          }
        None => ()
      }
    SAssign(lhs, rhs) =>
      match (lhs.kind, rhs.kind) {
        (EField(_, _) | EIndex(_, _), EName(n)) =>
          if !out.contains(n) {
            out.push(n)
          }
        _ => ()
      }
    SIf(_, then_body, else_body) => {
      for x in then_body {
        ffi_collect_escaped_stmt(x, out)
      }
      for x in else_body {
        ffi_collect_escaped_stmt(x, out)
      }
    }
    SWhile(_, body) =>
      for x in body {
        ffi_collect_escaped_stmt(x, out)
      }
    SFor(_, _, _, _, body) =>
      for x in body {
        ffi_collect_escaped_stmt(x, out)
      }
    SForIn(_, _, body) =>
      for x in body {
        ffi_collect_escaped_stmt(x, out)
      }
    SBlock(body) =>
      for x in body {
        ffi_collect_escaped_stmt(x, out)
      }
    STry(body) =>
      for x in body {
        ffi_collect_escaped_stmt(x, out)
      }
    _ => ()
  }
}

///|
/// An allocation the module never releases.
///
/// The C side owns what it allocated, and the C source is not visible: the
/// analyzer can say that the module received an allocation and never handed
/// it to anything that frees, so the allocation is still held when the
/// module ends. It cannot say that the C side did not free it by itself, so
/// the claim is a may-claim and the family is a warning.
///
/// The RELEASE is recognised the way the release list recognises it -- by the
/// symbol's NAME -- and the ALLOCATION the way the allocator list recognises
/// it: by the symbol's name AND by the fact that it returns an address.
fn ffi_check_allocations(
  scan : FfiModuleScan,
  findings : Array[Finding],
) -> Unit {
  for a in scan.allocated {
    if a.escapes {
      continue
    }
    if ffi_allocation_released(scan, a) {
      continue
    }
    findings.push(
      Finding::new(
        FFfiAllocationNotReleased,
        a.file,
        a.line,
        a.fn_name,
        "the C function '" +
        a.symbol +
        "' handed back an allocation, bound to '" +
        a.name +
        "', and nothing in the module ever releases it. The C side owns it, so it is still held when the module ends.",
        "L2-FFI",
        0.6,
        a.name + " -> " + a.symbol,
      ),
    )
  }
}

///|
/// Whether something in the module released the allocation.
fn ffi_allocation_released(scan : FfiModuleScan, a : FfiAllocation) -> Bool {
  for r in scan.released {
    if r.name != a.name {
      continue
    }
    // The slot has to be one the C side can own: a POINTER, or a value of
    // the foreign type the allocator handed back.
    if r.is_ptr || r.ty == a.ty {
      return true
    }
  }
  false
}

///|
/// An address that points outside the region it was carved from.
///
/// The module allocates a region -- a base address and a size -- and then
/// hands the C side an address that is the base plus an offset. When the
/// offset is not smaller than the size, the address is past the end of the
/// region, and the C side reads or writes outside it.
fn ffi_check_address_bounds(
  scan : FfiModuleScan,
  findings : Array[Finding],
) -> Unit {
  for c in scan.computed {
    // The region the base belongs to. The base may be either half of the
    // sum, so both are tried.
    for r in scan.regions {
      let mut offset : Int64 = 0
      let mut matched = false
      if r.0 == c.base {
        offset = c.offset
        matched = true
      } else if r.0 == c.offset {
        offset = c.base
        matched = true
      }
      if !matched {
        continue
      }
      if offset < r.1 {
        continue
      }
      findings.push(
        Finding::new(
          FFfiAddressOob,
          c.file,
          c.line,
          c.fn_name,
          "the C function '" +
          c.symbol +
          "' is given the address " +
          (c.base + c.offset).to_string() +
          ", which is " +
          offset.to_string() +
          " bytes into a region of " +
          r.1.to_string() +
          " bytes. The address points past the end of the region, so the C side reads or writes outside it.",
          "L2-FFI",
          0.8,
          c.symbol + "(" + c.param + ")",
        ),
      )
      break
    }
  }
}

///|
/// A FORMAT slot handed a string the module did not write out.
///
/// The C function's parameter NAME says the C side interprets it, and the
/// value is not a literal, so the C side reads whatever the module's caller
/// put there as a format -- and a '%' in it is a directive the C side
/// follows.
///
/// The rule is the one GCC's -Wformat-security uses: a format slot with no
/// OTHER argument after it. A C function that takes more arguments is
/// almost certainly using its format properly, so the analyzer does not
/// claim it. And the value has to come from OUTSIDE the function that makes
/// the call: a string the module built itself is the module's own.
fn ffi_check_format_string(
  d : FfiDecl,
  args : Array[Expr],
  f : Func,
  s : Stmt,
  findings : Array[Finding],
) -> Unit {
  if d.params.length() != 1 {
    return
  }
  let p = d.params[0]
  if !ffi_is_format_name(p.name) {
    return
  }
  if !ffi_is_string_type(p.ty) {
    return
  }
  if args.length() == 0 {
    return
  }
  let a = args[0]
  if ffi_is_string_literal(a) {
    return
  }
  if !ffi_comes_from_outside(f, a) {
    return
  }
  findings.push(
    Finding::new(
      FFfiFormatString,
      f.file,
      s.span.start_line,
      f.name,
      "the C function '" +
      d.symbol +
      "' takes its format in the slot named '" +
      p.name +
      "', and it is given '" +
      a.render() +
      "', which comes from outside this function. The C side reads that string as a format, so a '%' in it is a directive the C side follows.",
      "L2-FFI",
      0.7,
      d.symbol + "(" + p.name + ")",
    ),
  )
}
