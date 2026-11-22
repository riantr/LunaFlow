///|
pub struct Span {
  file : String
  start_line : Int32
  start_col : Int32
  end_line : Int32
  end_col : Int32
}

///|
pub fn Span::new(
  file : String,
  start_line : Int32,
  start_col : Int32,
  end_line : Int32,
  end_col : Int32,
) -> Span {
  { file, start_line, start_col, end_line, end_col, }
}

///|
pub fn Span::empty(file : String) -> Span {
  Span::new(file, 0, 0, 0, 0)
}

///|
pub fn Span::to_string(self : Span) -> String {
  if self.start_line == self.end_line {
    "\{self.file}:\{self.start_line}:\{self.start_col}"
  } else {
    "\{self.file}:\{self.start_line}:\{self.start_col}-\{self.end_line}:\{self.end_col}"
  }
}

///|
pub fn Span::merge(self : Span, other : Span) -> Span {
  let end_line = if other.end_line > self.end_line {
    other.end_line
  } else {
    self.end_line
  }
  let end_col = if other.end_line > self.end_line {
    other.end_col
  } else if other.end_line == self.end_line && other.end_col > self.end_col {
    other.end_col
  } else {
    self.end_col
  }
  {
    file: self.file,
    start_line: self.start_line,
    start_col: self.start_col,
    end_line,
    end_col,
  }
}

///|
#derive(Eq)
pub(all) enum BinOp {
  OpAdd
  OpSub
  OpMul
  OpDiv
  OpMod
  OpEq
  OpNe
  OpLt
  OpLe
  OpGt
  OpGe
  OpAnd
  OpOr
  OpBitAnd
  OpBitOr
  OpBitXor
  OpShl
  OpShr
}

///|
pub extend BinOp with Eq::{not_equal, equal}

///|
pub fn BinOp::symbol(self : BinOp) -> String {
  match self {
    OpAdd => "+"
    OpSub => "-"
    OpMul => "*"
    OpDiv => "/"
    OpMod => "%"
    OpEq => "=="
    OpNe => "!="
    OpLt => "<"
    OpLe => "<="
    OpGt => ">"
    OpGe => ">="
    OpAnd => "&&"
    OpOr => "||"
    OpBitAnd => "&"
    OpBitOr => "|"
    OpBitXor => "^"
    OpShl => "<<"
    OpShr => ">>"
  }
}

///|
#derive(Eq)
pub(all) enum UnOp {
  UnNeg
  UnNot
}

///|
pub extend UnOp with Eq::{not_equal, equal}

///|
pub(all) enum ExprKind {
  EInt(Int32)
  EDouble(Double)
  EBool(Bool)
  EString(String)
  /// A BYTE literal: `b"abc"`. It is not a string: it is the way MoonBit
  /// writes a `Bytes`, and the byte length of its content is what the C
  /// side is told when a buffer crosses the boundary.
  EBytes(String)
  EName(String)
  EBin(BinOp, Expr, Expr)
  EUn(UnOp, Expr)
  ECall(String, Array[Expr])
  EMethod(Expr, String, Array[Expr])
  EField(Expr, String)
  EIndex(Expr, Expr)
  ESlice(Expr, Expr?, Expr?)
  EArray(Array[Expr])
  ETuple(Array[Expr])
  /// A RANGE: `a..<b` (exclusive) or `a..<=b` (inclusive). The flag says
  /// whether the END is included.
  ///
  /// A range is not a value in MoonBit -- the toolchain says "Range operators
  /// are currently only supported in `for .. in` loops" -- so this node only
  /// ever appears as the ITERATOR of a `for .. in` loop.
  ERange(Expr, Expr, Bool)
  /// A FUNCTION LITERAL: its synthetic name and whether it is `async`. The
  /// body lives in `SourceFile.closures`, keyed by that name, so the
  /// expression domain does not have to carry statements.
  EFn(String, Bool)
  EUnknown(String)
}

///|
pub struct Expr {
  span : Span
  kind : ExprKind
}

///|
pub fn Expr::new(span : Span, kind : ExprKind) -> Expr {
  { span, kind, }
}

///|
pub fn Expr::unknown(span : Span, text : String) -> Expr {
  { span, kind: EUnknown(text), }
}

///|
pub fn Expr::render(self : Expr) -> String {
  match self.kind {
    EInt(n) => n.to_string()
    EDouble(d) => format_double(d)
    EBool(b) => if b { "true" } else { "false" }
    EString(s) => "\"" + s + "\""
    EBytes(s) => "b\"" + s + "\""
    EName(n) => n
    EBin(op, l, r) =>
      "(" + l.render() + " " + op.symbol() + " " + r.render() + ")"
    EUn(UnNeg, e) => "-" + e.render()
    EUn(UnNot, e) => "!" + e.render()
    ECall(f, args) => f + "(" + render_args(args) + ")"
    EMethod(e, m, args) => e.render() + "." + m + "(" + render_args(args) + ")"
    EField(e, f) => e.render() + "." + f
    EIndex(e, i) => e.render() + "[" + i.render() + "]"
    ESlice(e, s, en) => {
      let lo = match s {
        Some(x) => x.render()
        None => ""
      }
      let hi = match en {
        Some(x) => x.render()
        None => ""
      }
      e.render() + "[" + lo + ":" + hi + "]"
    }
    EArray(xs) => "[" + render_args(xs) + "]"
    ETuple(xs) => "(" + render_args(xs) + ")"
    ERange(a, b, inclusive) =>
      a.render() + (if inclusive { "..<=" } else { "..<" }) + b.render()
    EFn(id, _) => "fn-literal"
    EUnknown(t) => t
  }
}

///|
pub fn render_args(xs : Array[Expr]) -> String {
  let parts : Array[String] = []
  for x in xs {
    parts.push(x.render())
  }
  parts.join(", ")
}

///|
pub struct Param {
  name : String
  ty : String
  default : Expr?
}

///|
pub fn Param::new(name : String, ty : String, default : Expr?) -> Param {
  { name, ty, default, }
}

///|
pub(all) enum StmtKind {
  SLet(String, String, Expr)
  SAssign(Expr, Expr)
  SAssignOp(BinOp, Expr, Expr)
  SIf(Expr, Array[Stmt], Array[Stmt])
  SWhile(Expr, Array[Stmt])
  SFor(String, Expr, Expr, Expr, Array[Stmt])
  // The binder is a list because a `for` may destructure: `for k, v in
  // entries` binds two names. One name for a plain binder.
  SForIn(Array[String], Expr, Array[Stmt])
  SReturn(Expr?)
  SBreak
  SContinue
  SExpr(Expr)
  SBlock(Array[Stmt])
  STry(Array[Stmt])
  SUnsupported(String)
}

///|
pub struct Stmt {
  id : Int32
  span : Span
  kind : StmtKind
  text : String
}

///|
pub fn Stmt::new(
  id : Int32,
  span : Span,
  kind : StmtKind,
  text : String,
) -> Stmt {
  { id, span, kind, text, }
}

///|
pub struct Func {
  name : String
  params : Array[Param]
  ret_ty : String
  body : Array[Stmt]
  span : Span
  file : String
  is_test : Bool
  /// Whether the function is `async`. A call to an async function is an
  /// AWAIT POINT -- the only place a MoonBit task yields, and so the only
  /// place another task may run.
  mut is_async : Bool
  start_line : Int32
  end_line : Int32
  mut contract : Contract
}

///|
pub struct ParseIssue {
  file : String
  line : Int32
  message : String
}

///|
pub struct SourceFile {
  path : String
  lines : Array[String]
  funcs : Array[Func]
  issues : Array[ParseIssue]
  /// The module's GLOBAL REGION: the top-level bindings, which live for the
  /// whole module rather than in a frame.
  globals : Array[Global]
  /// The FOREIGN declarations: the C functions and the module imports the
  /// module depends on. See `ffi.mbt`.
  ffi_decls : Array[FfiDecl]
  /// The `#external` types: opaque types whose payload the C side owns.
  external_types : Array[ExternalType]
  /// The module's own type declarations, so the analyzer can tell a type
  /// with a heap representation from a value type.
  types : Array[TypeDecl]
  /// The FUNCTION LITERALS in this file. A closure handed to a spawn call is
  /// a task body, so the concurrency model needs its statements.
  closures : Array[Func]
  mut parsed_stmts : Int32
  mut unsupported_stmts : Int32
}

///|
pub fn SourceFile::new(path : String, text : String) -> SourceFile {
  {
    path,
    lines: split_lines(text),
    funcs: [],
    issues: [],
    globals: [],
    ffi_decls: [],
    external_types: [],
    types: [],
    closures: [],
    parsed_stmts: 0,
    unsupported_stmts: 0,
  }
}

///|
pub(all) struct ModuleAst {
  coord : String
  version : String
  root : String
  files : Array[SourceFile]
  manifest_deps : Array[String]
  manifest_target : String
}

///|
pub fn ModuleAst::all_funcs(self : ModuleAst) -> Array[Func] {
  let out : Array[Func] = []
  for f in self.files {
    for fn_name in f.funcs {
      if !fn_name.is_test {
        out.push(fn_name)
      }
    }
  }
  out
}

///|
pub fn ModuleAst::all_funcs_including_tests(self : ModuleAst) -> Array[Func] {
  let out : Array[Func] = []
  for f in self.files {
    for fn_name in f.funcs {
      out.push(fn_name)
    }
  }
  out
}

///|
#derive(Eq)
pub(all) enum NodeKind {
  NEntry
  NExit
  NStmt
  NBranch
  NLoop
  NMerge
  NDead
}

///|
pub extend NodeKind with Eq::{not_equal, equal}

///|
#derive(Eq)
pub(all) enum EdgeKind {
  ESeq
  ETrue
  EFalse
  EBack
}

///|
pub extend EdgeKind with Eq::{not_equal, equal}

///|
pub struct CfgNode {
  id : Int32
  kind : NodeKind
  label : String
  fn_name : String
  file : String
  line : Int32
  stmt : Int32
}

///|
pub struct CfgEdge {
  from : Int32
  to : Int32
  kind : EdgeKind
}

///|
pub struct Cfg {
  fn_name : String
  file : String
  nodes : Array[CfgNode]
  edges : Array[CfgEdge]
  entry : Int32
  exit : Int32
  cyclomatic : Int32
}

///|
pub fn Cfg::node(self : Cfg, id : Int32) -> CfgNode? {
  for n in self.nodes {
    if n.id == id {
      return Some(n)
    }
  }
  None
}

///|
#derive(Eq)
pub(all) enum FindingKind {
  FDead
  FUnreachable
  FInfinite
  FTaintIndex
  FTaintIndexRange
  FTaintAlloc
  FRangeViolation
  FParseGap
  FBudget
  FUnsupported
  // The EVOLVED VALUE ANALYSIS families. See `eva.mbt` for the engine and
  // `family.mbt` for each family's contract.
  FIntOverflow
  FDivZero
  FIndexOob
  FNoneDeref
  FUninitRead
  FInvalidCast
  // The MEMORY family's one finding: a collection that only ever grows.
  FUnboundedGrowth
  // The RESERVED families: the defect classes MoonBit's type system makes
  // impossible in safe code. They are in the roster so that `--explain` can
  // answer for them, and their contracts say why they never fire.
  FUseAfterFree
  FPointerArithmetic
  FMemoryLeak
  FFormatString
  // The FOREIGN ADDRESS SPACE families. See `ffi.mbt` for the model and the
  // measurements every one of them rests on.
  FFfiSignatureConflict
  FFfiUnannotatedOwnership
  FFfiUseAfterMove
  FFfiTargetMismatch
  FFfiAddressUnknown
  FFfiAddressConflict
  FFfiDoubleFree
  FFfiUseAfterFree
  FFfiLengthMismatch
  // The classes that safe MoonBit cannot express, and that the C boundary
  // CAN. See `ffi.mbt` for the model and the measurements it rests on.
  FFfiAllocationNotReleased
  FFfiFormatString
  FFfiAddressOob
  // The CONCURRENCY families. See `conc.mbt` for the model and the
  // measurements every one of them rests on.
  FFconcLostUpdate
  FFconcStaleRead
  FFconcDeadlockCycle
  FFconcResourceUnreleased
  // The IPC AND BUFFER families. See `ipc.mbt` for the model and the
  // measurements every one of them rests on.
  FIpcPartialRead
  FIpcReadEof
  FIpcViewStale
  FIpcBufferShared
}

///|
pub extend FindingKind with Eq::{not_equal, equal}

///|
pub fn FindingKind::code(self : FindingKind) -> String {
  match self {
    FDead => "DEAD-CODE"
    FUnreachable => "UNREACHABLE"
    FInfinite => "INFINITE-LOOP"
    FTaintIndex => "TAINT-INDEX"
    FTaintIndexRange => "TAINT-INDEX-RANGE"
    FTaintAlloc => "TAINT-ALLOC"
    FRangeViolation => "RANGE-VIOLATION"
    FParseGap => "PARSE-GAP"
    FBudget => "BUDGET-EXCEEDED"
    FUnsupported => "UNSUPPORTED"
    FIntOverflow => "INTEGER-OVERFLOW"
    FDivZero => "DIVISION-BY-ZERO"
    FIndexOob => "INDEX-OOB"
    FNoneDeref => "NONE-DEREF"
    FUninitRead => "UNINITIALIZED-READ"
    FInvalidCast => "INVALID-CAST"
    FUnboundedGrowth => "UNBOUNDED-GROWTH"
    FUseAfterFree => "USE-AFTER-FREE"
    FPointerArithmetic => "POINTER-ARITHMETIC"
    FMemoryLeak => "MEMORY-LEAK"
    FFormatString => "FORMAT-STRING"
    FFfiSignatureConflict => "FFI-SIGNATURE-CONFLICT"
    FFfiUnannotatedOwnership => "FFI-UNANNOTATED-OWNERSHIP"
    FFfiUseAfterMove => "FFI-USE-AFTER-MOVE"
    FFfiTargetMismatch => "FFI-TARGET-MISMATCH"
    FFfiAddressUnknown => "FFI-ADDRESS-UNKNOWN"
    FFfiAddressConflict => "FFI-ADDRESS-CONFLICT"
    FFfiDoubleFree => "FFI-DOUBLE-FREE"
    FFfiUseAfterFree => "FFI-USE-AFTER-FREE"
    FFfiLengthMismatch => "FFI-LENGTH-MISMATCH"
    FFfiAllocationNotReleased => "FFI-ALLOCATION-NOT-RELEASED"
    FFfiFormatString => "FFI-FORMAT-STRING"
    FFfiAddressOob => "FFI-ADDRESS-OOB"
    FFconcLostUpdate => "CONC-RACE-LOST-UPDATE"
    FFconcStaleRead => "CONC-RACE-STALE-READ"
    FFconcDeadlockCycle => "CONC-DEADLOCK-CYCLE"
    FFconcResourceUnreleased => "CONC-RESOURCE-UNRELEASED"
    FIpcPartialRead => "IPC-PARTIAL-READ"
    FIpcReadEof => "IPC-READ-EOF"
    FIpcViewStale => "IPC-VIEW-STALE"
    FIpcBufferShared => "IPC-BUFFER-SHARED"
  }
}

///|
pub fn FindingKind::severity(self : FindingKind) -> String {
  match self {
    FDead | FUnreachable | FParseGap => "info"
    FInfinite | FRangeViolation | FBudget => "warning"
    FTaintIndex | FTaintAlloc => "error"
    FTaintIndexRange => "warning"
    FUnsupported => "info"
    // A runtime panic in the analysed program is an error, whether the
    // analyzer can PROVE it happens or only that it MAY happen.
    FIntOverflow | FDivZero | FIndexOob | FNoneDeref | FUninitRead => "error"
    // A silent wrong value, not a crash: the program keeps running with a
    // value the author did not intend.
    FInvalidCast => "warning"
    // A collection that only ever grows: the module holds every item it is
    // given, for as long as it lives.
    FUnboundedGrowth => "warning"
    // Reserved: never produced.
    FUseAfterFree | FPointerArithmetic | FMemoryLeak | FFormatString =>
      "warning"
    // The FOREIGN ADDRESS SPACE families.
    //
    // Two C declarations that cannot both be true, an object the C side owns
    // and the MoonBit side still uses, a declaration the published target
    // cannot build: these are errors.
    FFfiSignatureConflict | FFfiUseAfterMove | FFfiTargetMismatch => "error"
    // A C function that frees the same object twice, and an object that is
    // used after the C side freed it: both are errors.
    FFfiDoubleFree | FFfiUseAfterFree => "error"
    // A contract the toolchain leaves to the default, and an address whose
    // owner is ambiguous.
    FFfiUnannotatedOwnership | FFfiAddressConflict => "warning"
    // A length the C side is told that is not the length of the object it is
    // given: the C side may read or write outside the object.
    FFfiLengthMismatch => "warning"
    // An address the analyzer cannot name: a limit of the analysis, not a
    // defect.
    FFfiAddressUnknown => "info"
    // The classes safe MoonBit cannot express, and the C boundary can.
    //
    // A format string the untrusted input chooses, and an address that points
    // outside the region it was carved from: both are errors.
    FFfiFormatString | FFfiAddressOob => "error"
    // An allocation the module never releases: the C side holds it for as
    // long as the process lives. The C source is not visible, so this is a
    // may-claim.
    FFfiAllocationNotReleased => "warning"
    // The CONCURRENCY families.
    //
    // An update that is lost, and a deadlock in which no task can proceed:
    // these are errors.
    FFconcLostUpdate | FFconcDeadlockCycle => "error"
    // A read that may already be out of date, and a lock that is never given
    // back: both are warnings.
    FFconcStaleRead | FFconcResourceUnreleased => "warning"
    // The IPC AND BUFFER families.
    //
    // A buffer whose tail was never written, a loop that can never see EOF,
    // and a buffer that two tasks write at once: these are errors.
    FIpcPartialRead | FIpcReadEof | FIpcBufferShared => "error"
    // A view that shows bytes the reader has already overwritten: a warning,
    // because the program keeps running with data it did not intend to read.
    FIpcViewStale => "warning"
  }
}

///|
/// The VERDICT of a finding: was the claim DECIDED, or could it not be
/// decided at all?
///
/// The L3 has had this third state for a while -- `VCStatus::VCUnknown`,
/// "insufficient facts for a decision" -- and the abstract layer has its own
/// (`EUnknown`). What was MISSING is the same state on the FINDING itself.
/// Without it, a claim the analyser could not decide is simply ABSENT, and
/// "absent" and "decided absent" are the same thing to a reader: the report
/// can say "there was nothing here", but not "we could not decide".
///
/// The verdict is what makes the difference visible. It is carried in the
/// findings sidecar, it is a column of the findings table, and the policy in
/// `policy.mbt` decides what an undecided claim MEANS for its family.
#derive(Eq)
pub(all) enum FindingVerdict {
  VerdictCertain
  VerdictUnknown
}

///|
pub extend FindingVerdict with Eq::{not_equal, equal}

///|
pub fn FindingVerdict::code(self : FindingVerdict) -> String {
  match self {
    VerdictCertain => "certain"
    VerdictUnknown => "unknown"
  }
}

///|
#derive(Eq)
pub struct Finding {
  kind : FindingKind
  file : String
  line : Int32
  fn_name : String
  message : String
  mode : String
  confidence : Double
  evidence : String
  verdict : FindingVerdict
}

///|
pub extend Finding with Eq::{not_equal, equal}

///|
pub fn Finding::new(
  kind : FindingKind,
  file : String,
  line : Int32,
  fn_name : String,
  message : String,
  mode : String,
  confidence : Double,
  evidence : String,
) -> Finding {
  {
    kind,
    file,
    line,
    fn_name,
    message,
    mode,
    confidence,
    evidence,
    verdict: VerdictCertain,
  }
}

///|
/// A finding that records a claim the analyser COULD NOT DECIDE.
///
/// The only difference from `Finding::new` is the verdict, and the verdict is
/// the whole point: a claim that was NOT decided must not look like a claim
/// that was decided and found clean.  The severity of an undecided claim
/// comes from the POLICY in `policy.mbt`, not from the family alone -- an
/// undecided safety claim is an error, because the module's safety is then
/// not established.
pub fn Finding::undecided(
  kind : FindingKind,
  file : String,
  line : Int32,
  fn_name : String,
  message : String,
  mode : String,
  confidence : Double,
  evidence : String,
) -> Finding {
  {
    kind,
    file,
    line,
    fn_name,
    message,
    mode,
    confidence,
    evidence,
    verdict: VerdictUnknown,
  }
}

///|
#derive(Eq)
pub(all) enum EventKind {
  EvEnter
  EvDef
  EvRead
  EvCond
  EvCall
  EvIndex
  EvAlloc
  EvLoop
  EvReturn
  EvSource
  EvSink
  EvAbort
  EvBudget
  EvUnsupported
}

///|
pub extend EventKind with Eq::{not_equal, equal}

///|
pub fn EventKind::tag(self : EventKind) -> String {
  match self {
    EvEnter => "enter"
    EvDef => "def"
    EvRead => "read"
    EvCond => "cond"
    EvCall => "call"
    EvIndex => "index"
    EvAlloc => "alloc"
    EvLoop => "loop"
    EvReturn => "return"
    EvSource => "source"
    EvSink => "sink"
    EvAbort => "abort"
    EvBudget => "budget"
    EvUnsupported => "unsupported"
  }
}

///|
pub fn parse_event_tag(tag : String) -> EventKind? {
  match tag {
    "enter" => Some(EvEnter)
    "def" => Some(EvDef)
    "read" => Some(EvRead)
    "cond" => Some(EvCond)
    "call" => Some(EvCall)
    "index" => Some(EvIndex)
    "alloc" => Some(EvAlloc)
    "loop" => Some(EvLoop)
    "return" => Some(EvReturn)
    "source" => Some(EvSource)
    "sink" => Some(EvSink)
    "abort" => Some(EvAbort)
    "budget" => Some(EvBudget)
    "unsupported" => Some(EvUnsupported)
    _ => None
  }
}

///|
pub struct TraceEvent {
  kind : EventKind
  fn_name : String
  file : String
  line : Int32
  stmt : Int32
  name : String
  value : String
  tainted : Bool
  trial : Int32
  detail : String
}

///|
pub fn TraceEvent::new(
  kind : EventKind,
  fn_name : String,
  file : String,
  line : Int32,
  stmt : Int32,
  name : String,
  value : String,
  tainted : Bool,
  trial : Int32,
  detail : String,
) -> TraceEvent {
  { kind, fn_name, file, line, stmt, name, value, tainted, trial, detail, }
}

///|
pub struct RangeStat {
  mut min : Double
  mut max : Double
  mut count : Int32
  values : Array[String]
}

///|
pub fn RangeStat::new() -> RangeStat {
  { min: 0.0, max: 0.0, count: 0, values: [], }
}

///|
pub fn RangeStat::observe(self : RangeStat, v : Double, raw : String) -> Unit {
  if self.count == 0 {
    self.min = v
    self.max = v
  } else {
    if v < self.min {
      self.min = v
    }
    if v > self.max {
      self.max = v
    }
  }
  self.count = self.count + 1
  if !self.values.contains(raw) && self.values.length() < 12 {
    self.values.push(raw)
  }
}

///|
pub struct Ranges {
  stats : Map[String, RangeStat]
  sites : Map[String, String]
}

///|
pub fn Ranges::new() -> Ranges {
  { stats: {}, sites: {}, }
}

///|
pub fn Ranges::key(fn_name : String, name : String) -> String {
  fn_name + "::" + name
}

///|
pub fn Ranges::observe(
  self : Ranges,
  fn_name : String,
  name : String,
  value : Double,
  raw : String,
  site : String,
) -> Unit {
  let key = Ranges::key(fn_name, name)
  match self.stats.get(key) {
    Some(stat) => stat.observe(value, raw)
    None => {
      let stat = RangeStat::new()
      stat.observe(value, raw)
      self.stats[key] = stat
      self.sites[key] = site
    }
  }
}

///|
pub fn Ranges::get(
  self : Ranges,
  fn_name : String,
  name : String,
) -> RangeStat? {
  self.stats.get(Ranges::key(fn_name, name))
}

///|
pub fn Ranges::site(self : Ranges, fn_name : String, name : String) -> String {
  self.sites.get(Ranges::key(fn_name, name)).unwrap_or("")
}

///|
pub fn Ranges::merge_from(self : Ranges, other : Ranges) -> Unit {
  for pair in other.stats.to_array() {
    let key = pair.0
    let src = pair.1
    match self.stats.get(key) {
      Some(dst) => {
        if src.count > 0 {
          if dst.count == 0 || src.min < dst.min {
            dst.min = src.min
          }
          if dst.count == 0 || src.max > dst.max {
            dst.max = src.max
          }
          dst.count = dst.count + src.count
        }
        for v in src.values {
          if !dst.values.contains(v) && dst.values.length() < 12 {
            dst.values.push(v)
          }
        }
      }
      None => {
        let copy = RangeStat::new()
        copy.min = src.min
        copy.max = src.max
        copy.count = src.count
        for v in src.values {
          copy.values.push(v)
        }
        self.stats[key] = copy
        match other.sites.get(key) {
          Some(s) => self.sites[key] = s
          None => ()
        }
      }
    }
  }
}

///|
#derive(Eq)
pub(all) enum TaintNodeKind {
  TSource
  TStep
  TSink
}

///|
pub extend TaintNodeKind with Eq::{not_equal, equal}

///|
pub fn TaintNodeKind::code(self : TaintNodeKind) -> String {
  match self {
    TSource => "src"
    TStep => "step"
    TSink => "sink"
  }
}

///|
pub struct TaintNode {
  id : Int32
  kind : TaintNodeKind
  label : String
  fn_name : String
  file : String
  line : Int32
}

///|
pub struct TaintEdge {
  from : Int32
  to : Int32
  label : String
}

///|
pub struct TaintGraph {
  nodes : Array[TaintNode]
  edges : Array[TaintEdge]
  sinks : Array[Finding]
}

///|
pub fn TaintGraph::new() -> TaintGraph {
  { nodes: [], edges: [], sinks: [], }
}

///|
pub fn TaintGraph::add_node(
  self : TaintGraph,
  kind : TaintNodeKind,
  label : String,
  fn_name : String,
  file : String,
  line : Int32,
) -> Int32 {
  let id = self.nodes.length()
  self.nodes.push({ id, kind, label, fn_name, file, line, })
  id
}

///|
pub fn TaintGraph::add_edge(
  self : TaintGraph,
  from : Int32,
  to : Int32,
  label : String,
) -> Unit {
  self.edges.push({ from, to, label, })
}

///|
#derive(Eq)
pub(all) enum SliceDirection {
  SliceBackward
  SliceForward
}

///|
pub extend SliceDirection with Eq::{not_equal, equal}

///|
pub fn SliceDirection::code(self : SliceDirection) -> String {
  match self {
    SliceBackward => "backward"
    SliceForward => "forward"
  }
}

///|
pub struct LineHit {
  file : String
  line : Int32
  hits : Int32
}

///|
pub struct Coverage {
  hits : Map[String, Map[Int32, Int32]]
  mut covered : Int32
  mut total : Int32
  source : String
}

///|
pub fn Coverage::new(source : String) -> Coverage {
  { hits: Map([]), covered: 0, total: 0, source, }
}

///|
pub fn Coverage::add(
  self : Coverage,
  file : String,
  line : Int32,
  count : Int32,
) -> Unit {
  match self.hits.get(file) {
    Some(m) => m[line] = count
    None => {
      let m : Map[Int32, Int32] = Map([])
      m[line] = count
      self.hits[file] = m
    }
  }
  self.total = self.total + 1
  if count > 0 {
    self.covered = self.covered + 1
  }
}

///|
pub fn Coverage::hits_at(
  self : Coverage,
  file : String,
  line : Int32,
) -> Int32? {
  match self.hits.get(file) {
    Some(m) => m.get(line)
    None => None
  }
}

///|
pub fn Coverage::ratio(self : Coverage) -> String {
  pct(self.covered, self.total)
}

///|
pub struct SliceNode {
  key : String
  fn_name : String
  file : String
  line : Int32
  text : String
  kind : String
  depth : Int32
}

///|
pub struct SliceEdge {
  from : String
  to : String
  label : String
}

///|
pub struct SliceResult {
  criterion : String
  direction : SliceDirection
  nodes : Array[SliceNode]
  edges : Array[SliceEdge]
}

///|
pub fn SliceResult::new(
  criterion : String,
  direction : SliceDirection,
) -> SliceResult {
  { criterion, direction, nodes: [], edges: [], }
}

///|
pub fn SliceResult::has(self : SliceResult, key : String) -> Bool {
  for n in self.nodes {
    if n.key == key {
      return true
    }
  }
  false
}

///|
pub fn SliceResult::add(self : SliceResult, node : SliceNode) -> Unit {
  if !self.has(node.key) {
    self.nodes.push(node)
  }
}
