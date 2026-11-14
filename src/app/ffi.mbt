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
/// `String`, `StringView`, `Bytes`, `Array`, `FixedArray`, `Option`,
/// `Result` and `Map` all have a heap representation, so the C side gets an
/// address of a MoonBit object.
fn is_builtin_pointer_type(ty : String) -> Bool {
  let b = base_type_name(ty)
  b == "String" ||
  b == "StringView" ||
  b == "Bytes" ||
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
/// The foreign calls a statement makes.
fn stmt_ffi_calls(
  s : Stmt,
  decls : Array[FfiDecl],
  out : Array[(FfiDecl, Array[Expr])],
) -> Unit {
  match s.kind {
    SLet(_, _, init) => expr_ffi_calls(init, decls, out)
    SAssign(_, rhs) => expr_ffi_calls(rhs, decls, out)
    SAssignOp(_, _, rhs) => expr_ffi_calls(rhs, decls, out)
    SIf(cond, then_body, else_body) => {
      expr_ffi_calls(cond, decls, out)
      for x in then_body {
        stmt_ffi_calls(x, decls, out)
      }
      for x in else_body {
        stmt_ffi_calls(x, decls, out)
      }
    }
    SWhile(cond, body) => {
      expr_ffi_calls(cond, decls, out)
      for x in body {
        stmt_ffi_calls(x, decls, out)
      }
    }
    SFor(_, from, to, step, body) => {
      expr_ffi_calls(from, decls, out)
      expr_ffi_calls(to, decls, out)
      expr_ffi_calls(step, decls, out)
      for x in body {
        stmt_ffi_calls(x, decls, out)
      }
    }
    SForIn(_, iter, body) => {
      expr_ffi_calls(iter, decls, out)
      for x in body {
        stmt_ffi_calls(x, decls, out)
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => expr_ffi_calls(x, decls, out)
        None => ()
      }
    SExpr(e) => expr_ffi_calls(e, decls, out)
    SBlock(body) =>
      for x in body {
        stmt_ffi_calls(x, decls, out)
      }
    STry(body) =>
      for x in body {
        stmt_ffi_calls(x, decls, out)
      }
    SUnsupported(_) => ()
    SBreak => ()
    SContinue => ()
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
  { decls, external_types, types, calls, registers, findings, }
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
    // The C symbol that produced each local value: the PROVENANCE of a
    // foreign address.
    let producers : Map[String, String] = Map([])
    for s in f.body {
      ffi_visit_stmt(
        f, s, decls, external_types, types, calls, findings, moved, producers,
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
  producers : Map[String, String],
) -> Unit {
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
  let found : Array[(FfiDecl, Array[Expr])] = []
  stmt_ffi_calls(s, decls, found)
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
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
      for x in else_body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
    }
    SWhile(_, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
    SFor(_, _, _, _, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
    SForIn(_, _, body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
    SBlock(body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
        )
      }
    STry(body) =>
      for x in body {
        ffi_visit_stmt(
          f, x, decls, external_types, types, calls, findings, moved, producers,
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
