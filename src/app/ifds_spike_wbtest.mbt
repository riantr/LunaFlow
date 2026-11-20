///|
/// THE IFDS SPIKE -- a MEASUREMENT, not a product feature.
///
/// It answers ONE question, with numbers: does a flow-sensitive, kill-exact,
/// labelled may-taint fixpoint over the module's OWN CFG drop the taint the
/// L2's blanket loop rule invents, without losing a taint the L2 really has?
///
/// It is NOT wired into the analyzer. It is not reachable from the CLI, and it
/// adds no flag. Every item in this file is PRIVATE, so
/// `src/app/pkg.generated.mbti` -- the published API surface -- does not
/// change by a byte, and the only way to run this is the white-box test
/// that drives it (`src/app/ifds_spike_wbtest.mbt`).
///
/// THE MODEL
///
/// A FACT is a pair (variable, source). The source says where the taint came
/// from: "param:<name>" for a parameter, "rule:loop" for the L2's blanket
/// rule. Facts are joined by UNION, so a variable's fact set is the set of
/// every source that may have reached it -- which is what makes the engine
/// LABELLED: the measurement can say WHICH source put the taint there.
///
/// A STATE maps a variable name to its facts. Two states are joined by
/// joining their fact sets, variable by variable. The join is a UNION, and
/// it is the SAME union the L2 performs: since IFDS Phase 1 the L2's taint
/// is a set of sources as well, and `abs_join_state` unions the two source
/// sets (`srcs_union`) exactly as the spike unions its fact sets.
///
/// THE TRANSFER FUNCTIONS
///
/// The spike walks the CFG with a worklist and joins the INCOMING state of
/// every node. The L2 walks the statements in order and joins the branch
/// states. The two agree on the transfer functions:
///
///  - `let` and `=`: the variable is KILLED and re-bound with the taint of
///    the right-hand side;
///  - `+=` and the other compound assignments: the variable KEEPS its facts
///    and gains the right-hand side's;
///  - a branch: the two sides are joined at the merge;
///  - a loop: the head is joined with the back edge, so the facts that the
///    body produces come back around;
///  - `for x in xs`: the binder is re-bound at every iteration, so what the
///    body does to it does not carry over;
///  - an expression statement, a return, a block, a try: the facts pass
///    through unchanged.
///
/// The ONE difference the spike makes is the MODE. `SpikePlain` has no
/// blanket rule. `SpikeWithRule` has the L2's blanket rule -- the rule that
/// taints every NUMBER the loop condition reads when the condition itself is
/// tainted -- applied at a `while` head, on the edge into the body only,
/// exactly where the L2 applies it (`abs.mbt`, `implicit_abs_taint`).
///
/// THE SINK RULES
///
/// The spike reports a taint sink when the sink's ARGUMENT is tainted. It
/// does NOT apply the L2's two filters: the container must be known to be an
/// array, and the index must not be provably inside it. Those filters live
/// in the L2's VALUE domain -- they need the container's abstract type and
/// the index's interval -- and a taint-only engine cannot reproduce them
/// without becoming the L2. The consequence for the measurement is spelled
/// out in `docs/qa/IFDS_SPIKE.md`: the comparison is between the L2's
/// findings and the spike's findings, and every difference is decomposed by
/// cause rather than waved at.
///
/// The spike still tracks whether a variable holds a NUMBER and whether it
/// holds an ARRAY, because the blanket rule needs the first and the report
/// needs the second.

///|
/// The MODE of the spike.
priv enum SpikeMode {
  /// The plain fixpoint: no blanket rule. This is the engine that is
  /// supposed to drop the taint the blanket rule invents.
  SpikePlain
  /// The fixpoint WITH the L2's blanket loop rule. This is the engine that
  /// is supposed to behave like the L2, so that the difference between the
  /// two modes is the blanket rule and nothing else.
  SpikeWithRule
}

///|
/// A VARIABLE's facts at one program point.
priv struct SpikeVar {
  /// The SOURCES of the taint. Empty means the variable is clean.
  sources : Array[String]
  /// Whether the variable holds a NUMBER. The L2's blanket rule applies
  /// only to numbers, so the spike has to know which those are -- and it
  /// has to know it the way the L2 knows it, which is by the VALUE the
  /// abstract interpreter gives the variable, not by the type the author
  /// wrote next to it.
  numeric : Bool
  /// What the variable holds, as far as the L2 can tell: `array` (the L2
  /// sees an array), `made` (the variable holds the result of an
  /// allocation, which the L2 does NOT see as an array -- see
  /// `SPIKE_ALLOC_ARRAY`), or `unknown`. The spike's own sink rule does
  /// not use this; it is here so that the measurement can say why the L2
  /// did or did not report a site.
  array : String
}

///|
/// The FACTS at one program point.
type SpikeState = Map[String, SpikeVar]

///|
/// What one function's analysis produced.
priv struct SpikeFnResult {
  findings : Array[Finding]
  /// The CFG nodes the fixpoint visited.
  nodes : Int32
  /// The worklist steps the fixpoint took.
  steps : Int32
  /// The facts the fixpoint held at the end.
  facts : Int32
}

///|
/// What a whole module's analysis produced.
priv struct SpikeResult {
  findings : Array[Finding]
  functions : Int32
  nodes : Int32
  steps : Int32
  facts : Int32
  /// The statements the spike could not model. They are counted, not
  /// hidden: a statement the parser did not model may carry a taint the
  /// spike does not follow.
  gaps : Int32
  /// The statements the spike modelled, by kind.
  kinds : Map[String, Int32]
}

///|
/// The SOURCE of a parameter's taint.
fn spike_param_source(name : String) -> String {
  "param:" + name
}

///|
/// The SOURCE of the taint the L2's blanket rule invents.
const SPIKE_RULE_SOURCE : String = "rule:loop"

///|
/// The name the PARSER gives a call to `Array::make`.
///
/// It is `Array.make` and not `Array::make`, and the difference is not
/// cosmetic: the parser renders a qualified path with a DOT
/// (`Expr::render` on an `EField`), so a call whose name is built from a
/// qualified path carries the dotted form.
///
/// MEASURED: the L2 matches `f == "Array::make"`, which the parser never
/// produces, so the L2's allocation-size sink is DEAD -- it cannot fire on
/// any input. The spike matches what the parser actually produces, and
/// the measurement reports the difference as a finding about the L2.
const SPIKE_ALLOC_ARRAY : String = "Array.make"

///|
/// The name the parser gives a call to `FixedArray::make`.
const SPIKE_ALLOC_FIXED_ARRAY : String = "FixedArray.make"

///|
/// An empty variable.
fn spike_var_empty() -> SpikeVar {
  { sources: [], numeric: false, array: "", }
}

///|
/// The UNION of two source lists.
fn spike_union(a : Array[String], b : Array[String]) -> Array[String] {
  let out = a.copy()
  for s in b {
    if !out.contains(s) {
      out.push(s)
    }
  }
  out
}

///|
/// The facts of a variable in a state, or an empty variable.
fn spike_get(st : SpikeState, name : String) -> SpikeVar {
  match st.get(name) {
    Some(v) => v
    None => spike_var_empty()
  }
}

///|
/// The SOURCES of a variable's taint.
fn spike_sources_of(st : SpikeState, name : String) -> Array[String] {
  spike_get(st, name).sources
}

///|
/// Whether two states carry the same facts.
///
/// The comparison is on the SOURCES, not on the flags: the flags say what
/// the variable holds, and the sources say what may have reached it. A
/// state that changed only in a flag does not need the worklist to run
/// again -- the flags are read by the transfer functions, which run on
/// every visit.
fn spike_same_facts(a : SpikeState, b : SpikeState) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for pair in a.to_array() {
    match b.get(pair.0) {
      None => return false
      Some(other) => {
        if pair.1.sources.length() != other.sources.length() {
          return false
        }
        for s in pair.1.sources {
          if !other.sources.contains(s) {
            return false
          }
        }
      }
    }
  }
  true
}

///|
/// A COPY of a state.
///
/// The transfer functions must not write into the state they are given: the
/// worklist keeps one state per CFG node, and a transfer that edited it in
/// place would corrupt the node it is working on.
fn spike_copy_state(st : SpikeState) -> SpikeState {
  let out : SpikeState = Map([])
  for pair in st.to_array() {
    out[pair.0] = pair.1
  }
  out
}

///|
/// The JOIN of two states: the union of the facts, variable by variable.
///
/// A variable that is in one state and not the other keeps the one that is
/// there -- the same rule the L2's `abs_join_state` uses. The flags are
/// joined the way the L2 joins the abstract VALUES: a variable is an array
/// only if it is an array on BOTH sides, because the L2's join of an array
/// with anything else is `ATop`.
fn spike_join(a : SpikeState, b : SpikeState) -> SpikeState {
  let out : SpikeState = Map([])
  for pair in a.to_array() {
    let name = pair.0
    let va = pair.1
    match b.get(name) {
      Some(vb) =>
        out[name] = {
          sources: spike_union(va.sources, vb.sources),
          numeric: va.numeric && vb.numeric,
          array: spike_join_array(va.array, vb.array),
        }
      None => out[name] = va
    }
  }
  for pair in b.to_array() {
    if !out.contains(pair.0) {
      out[pair.0] = pair.1
    }
  }
  out
}

///|
/// The taint of an EXPRESSION: the union of the facts of every name it
/// reads.
///
/// This mirrors the L2's `abs_eval`, which gives an expression the taint of
/// its parts: a binary operation joins its operands, a call joins its
/// arguments, a field takes its base's taint, and a literal is clean.
fn spike_taint_of(st : SpikeState, e : Expr) -> Array[String] {
  match e.kind {
    EInt(_) | EDouble(_) | EBool(_) | EString(_) | EBytes(_) => []
    EName(n) => spike_sources_of(st, n)
    EBin(_, a, b) => spike_union(spike_taint_of(st, a), spike_taint_of(st, b))
    EUn(_, a) => spike_taint_of(st, a)
    ECall(_, args) => {
      let mut out : Array[String] = []
      for a in args {
        out = spike_union(out, spike_taint_of(st, a))
      }
      out
    }
    EMethod(recv, _, args) => {
      let mut out = spike_taint_of(st, recv)
      for a in args {
        out = spike_union(out, spike_taint_of(st, a))
      }
      out
    }
    EField(base, _) => spike_taint_of(st, base)
    EIndex(base, idx) =>
      spike_union(spike_taint_of(st, base), spike_taint_of(st, idx))
    ESlice(base, s, en) => {
      let mut out = spike_taint_of(st, base)
      match s {
        Some(x) => out = spike_union(out, spike_taint_of(st, x))
        None => ()
      }
      match en {
        Some(x) => out = spike_union(out, spike_taint_of(st, x))
        None => ()
      }
      out
    }
    EArray(xs) | ETuple(xs) => {
      let mut out : Array[String] = []
      for x in xs {
        out = spike_union(out, spike_taint_of(st, x))
      }
      out
    }
    // A RANGE is not a value: the toolchain says range operators are only
    // supported in `for .. in` loops. The L2 gives it no taint, and so does
    // the spike. The `for .. in` loop reads its range's two ends itself,
    // and the spike does that too.
    ERange(_, _, _) => []
    EFn(_, _) => []
    EUnknown(_) => []
  }
}

///|
/// Whether an EXPRESSION holds a NUMBER.
///
/// This is the L2's question, not a syntactic one: the L2's blanket rule
/// applies to a variable whose abstract VALUE is an integer or a double.
/// An array literal is not a number even though its elements are, and a
/// field of a struct is not a number even when the struct's type says so,
/// because the L2 gives a field `ATop`.
fn spike_is_numeric(st : SpikeState, e : Expr) -> Bool {
  match e.kind {
    EInt(_) | EDouble(_) => true
    EName(n) => spike_get(st, n).numeric
    EUn(UnNeg, a) => spike_is_numeric(st, a)
    EBin(op, a, b) =>
      match op {
        OpEq | OpNe | OpLt | OpLe | OpGt | OpGe | OpAnd | OpOr => false
        _ => spike_is_numeric(st, a) && spike_is_numeric(st, b)
      }
    // `x.length()` is a number.
    EMethod(_, m, _) => m == "length"
    _ => false
  }
}

///|
/// The JOIN of two container kinds.
///
/// The L2 joins the abstract VALUES, and the join of an array with
/// anything that is not an array is `ATop` -- which is not an array. So
/// the kinds join the same way: `array` only if BOTH sides are `array`.
fn spike_join_array(a : String, b : String) -> String {
  if a == "array" && b == "array" {
    "array"
  } else if a == "made" || b == "made" {
    "made"
  } else {
    "unknown"
  }
}

///|
/// The container kind of an EXPRESSION.
///
/// `array` -- an array literal, or a variable that holds an array.
/// `made` -- the result of an allocation, which the L2 does not see as an
/// array. `unknown` -- anything else.
fn spike_is_array(st : SpikeState, e : Expr) -> String {
  match e.kind {
    EName(n) => spike_get(st, n).array
    EArray(_) => "array"
    ECall(f, _) =>
      if f == SPIKE_ALLOC_ARRAY || f == SPIKE_ALLOC_FIXED_ARRAY {
        "made"
      } else {
        "unknown"
      }
    _ => "unknown"
  }
}

///|
/// Whether a PARAMETER's declared type says it holds a number.
fn spike_type_is_numeric(ty : String) -> Bool {
  ty.contains("Int") ||
  ty.contains("UInt") ||
  ty.contains("Byte") ||
  ty.contains("Double") ||
  ty.contains("Float")
}

///|
/// Whether a PARAMETER's declared type says it holds an array.
fn spike_type_is_array(ty : String) -> Bool {
  ty.contains("Array") || ty.contains("FixedArray")
}

///|
/// The state a function STARTS in: every parameter tainted, because every
/// parameter may come from outside the module.
///
/// This is the L2's source set (`initial_cell` gives every parameter
/// `TTainted`). The L1's other sources -- `@env.args` and `@process` -- are
/// NOT modelled here, because the L2 does not model them either, and the
/// whole point of the measurement is a like-for-like comparison. Modelling
/// them is a Phase 1 item, not a Phase 0 one.
fn spike_initial_state(func : Func) -> SpikeState {
  let st : SpikeState = Map([])
  for p in func.params {
    st[p.name] = {
      sources: [spike_param_source(p.name)],
      numeric: spike_type_is_numeric(p.ty),
      array: if spike_type_is_array(p.ty) {
        "array"
      } else {
        ""
      },
    }
  }
  st
}

///|
/// The index of every statement of a function, by its id.
///
/// The CFG names a statement by its id and carries no statement of its
/// own, so the spike looks the statement up here to know what the node
/// means.
fn spike_index_stmts(stmts : Array[Stmt], out : Map[Int32, Stmt]) -> Unit {
  for s in stmts {
    out[s.id] = s
    match s.kind {
      SIf(_, a, b) => {
        spike_index_stmts(a, out)
        spike_index_stmts(b, out)
      }
      SWhile(_, body) => spike_index_stmts(body, out)
      SFor(_, _, _, _, body) => spike_index_stmts(body, out)
      SForIn(_, _, body) => spike_index_stmts(body, out)
      SBlock(inner) | STry(inner) => spike_index_stmts(inner, out)
      _ => ()
    }
  }
}

///|
/// The NAMES an expression reads.
///
/// The spike's own implementation: the spike is the engine the L2 is
/// MEASURED against, and an engine that borrows the other one's name
/// collector is not independent of it. (It used to borrow the L2's
/// `collect_names`, which the L2's blanket rule needed and the spike's
/// `rule:loop` mode still models.)
fn spike_names_of(e : Expr) -> Array[String] {
  let names : Array[String] = []
  spike_collect_names(e, names)
  names
}

///|
fn spike_collect_names(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    EName(n) => if !out.contains(n) { out.push(n) }
    EBin(_, a, b) => {
      spike_collect_names(a, out)
      spike_collect_names(b, out)
    }
    EUn(_, a) => spike_collect_names(a, out)
    EIndex(a, b) => {
      spike_collect_names(a, out)
      spike_collect_names(b, out)
    }
    ESlice(a, s, en) => {
      spike_collect_names(a, out)
      match s {
        Some(x) => spike_collect_names(x, out)
        None => ()
      }
      match en {
        Some(x) => spike_collect_names(x, out)
        None => ()
      }
    }
    EMethod(a, _, args) => {
      spike_collect_names(a, out)
      for x in args {
        spike_collect_names(x, out)
      }
    }
    ECall(_, args) =>
      for x in args {
        spike_collect_names(x, out)
      }
    EField(a, _) => spike_collect_names(a, out)
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        spike_collect_names(x, out)
      }
    _ => ()
  }
}

///|
/// A SINK the spike found, and the sources of the taint that reached it.
///
/// The worklist visits a node once per iteration of the fixpoint, so the
/// same sink is found again and again. The sinks are therefore collected
/// in a MAP, one per site, and the sources of every visit are merged into
/// it -- which is also what makes the measurement able to say WHY a site is
/// in the set.
priv struct SpikeSink {
  kind : FindingKind
  file : String
  line : Int32
  fn_name : String
  message : String
  mode : String
  /// The evidence WITHOUT the sources. The sources are appended when the
  /// finding is built, because they are only final at the end.
  evidence : String
  mut sources : Array[String]
}

///|
/// The key a sink is filed under.
fn spike_sink_key(kind : FindingKind, file : String, line : Int32) -> String {
  kind.code() + "|" + file + "|" + line.to_string()
}

///|
/// The CONTAINER KIND of an index expression, as the spike sees it.
///
/// The L2's sink filter asks whether the container is KNOWN to be an
/// array, and it answers from its own value domain. The spike has no value
/// domain, so it answers from what it can see: the declared type of a
/// parameter or a local, an array literal, or the result of an allocation.
///
/// The three answers matter because they have three different causes:
///
///  - `array`: the container is an array by type. The L2 agrees, so
///    whatever stopped the L2 at such a site is its TAINT or its BOUNDS.
///  - `made`: the container is the result of an allocation. The L2 does
///    NOT see it as an array, because the L2's allocation rule matches a
///    name the parser never produces (see `SPIKE_ALLOC_ARRAY`).
///  - `unknown`: the container's type is not known. The L2's filter stops
///    the site here.
fn spike_container_kind(st : SpikeState, e : Expr) -> String {
  let k = spike_is_array(st, e)
  if k == "" {
    "unknown"
  } else {
    k
  }
}

///|
/// Record a taint sink: an index whose index is tainted.
///
/// The EVIDENCE carries the SOURCES of the taint after an `@`, which is
/// what lets the measurement say WHY a site is in the set: a source of
/// `rule:loop` means the L2's blanket rule put the taint there, and any
/// other source means a real flow put it there. The evidence also carries
/// the CONTAINER KIND before a `;`, which is what lets the measurement say
/// why the L2 did not report the site.
fn spike_report_index(
  sinks : Map[String, SpikeSink],
  file : String,
  line : Int32,
  fn_name : String,
  base : Expr,
  idx : Expr,
  mode : String,
  sources : Array[String],
  container : String,
) -> Unit {
  let key = spike_sink_key(FTaintIndex, file, line)
  match sinks.get(key) {
    Some(s) => s.sources = spike_union(s.sources, sources)
    None =>
      sinks[key] = {
        kind: FTaintIndex,
        file,
        line,
        fn_name,
        message: "tainted value may reach an array index / buffer offset",
        mode,
        evidence: container + ";" + base.render() + "[" + idx.render() + "]",
        sources: sources.copy(),
      }
  }
}

///|
/// Record a taint sink: an allocation whose size is tainted.
fn spike_report_alloc(
  sinks : Map[String, SpikeSink],
  file : String,
  line : Int32,
  fn_name : String,
  callee : String,
  mode : String,
  sources : Array[String],
) -> Unit {
  let key = spike_sink_key(FTaintAlloc, file, line)
  match sinks.get(key) {
    Some(s) => s.sources = spike_union(s.sources, sources)
    None =>
      sinks[key] = {
        kind: FTaintAlloc,
        file,
        line,
        fn_name,
        message: "tainted value may control an allocation size",
        mode,
        evidence: "size;" + callee,
        sources: sources.copy(),
      }
  }
}

///|
/// The findings of a set of sinks.
fn spike_sink_findings(sinks : Map[String, SpikeSink]) -> Array[Finding] {
  let out : Array[Finding] = []
  for pair in sinks.to_array() {
    let s = pair.1
    out.push(
      Finding::new(
        s.kind,
        s.file,
        s.line,
        s.fn_name,
        s.message,
        s.mode,
        0.6,
        s.evidence + " @" + s.sources.join("|"),
      ),
    )
  }
  out
}

///|
/// Scan an EXPRESSION for the taint sinks it contains.
///
/// The L2 files a sink while it evaluates the expression, with the facts it
/// has at that point. The spike does the same: the scan runs with the
/// state of the node that holds the expression.
fn spike_scan_expr(
  st : SpikeState,
  e : Expr,
  file : String,
  fn_name : String,
  sinks : Map[String, SpikeSink],
  mode : String,
) -> Unit {
  match e.kind {
    EIndex(base, idx) => {
      spike_scan_expr(st, base, file, fn_name, sinks, mode)
      spike_scan_expr(st, idx, file, fn_name, sinks, mode)
      let sources = spike_taint_of(st, idx)
      if sources.length() > 0 {
        spike_report_index(
          sinks,
          file,
          e.span.start_line,
          fn_name,
          base,
          idx,
          mode,
          sources,
          spike_container_kind(st, base),
        )
      }
    }
    ECall(f, args) => {
      for a in args {
        spike_scan_expr(st, a, file, fn_name, sinks, mode)
      }
      if f == SPIKE_ALLOC_ARRAY || f == SPIKE_ALLOC_FIXED_ARRAY {
        if args.length() > 0 {
          let sources = spike_taint_of(st, args[0])
          if sources.length() > 0 {
            spike_report_alloc(
              sinks,
              file,
              e.span.start_line,
              fn_name,
              f,
              mode,
              sources,
            )
          }
        }
      }
    }
    EBin(_, a, b) => {
      spike_scan_expr(st, a, file, fn_name, sinks, mode)
      spike_scan_expr(st, b, file, fn_name, sinks, mode)
    }
    EUn(_, a) => spike_scan_expr(st, a, file, fn_name, sinks, mode)
    EMethod(recv, _, args) => {
      spike_scan_expr(st, recv, file, fn_name, sinks, mode)
      for a in args {
        spike_scan_expr(st, a, file, fn_name, sinks, mode)
      }
    }
    EField(base, _) => spike_scan_expr(st, base, file, fn_name, sinks, mode)
    ESlice(base, s, en) => {
      spike_scan_expr(st, base, file, fn_name, sinks, mode)
      match s {
        Some(x) => spike_scan_expr(st, x, file, fn_name, sinks, mode)
        None => ()
      }
      match en {
        Some(x) => spike_scan_expr(st, x, file, fn_name, sinks, mode)
        None => ()
      }
    }
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        spike_scan_expr(st, x, file, fn_name, sinks, mode)
      }
    ERange(a, b, _) => {
      spike_scan_expr(st, a, file, fn_name, sinks, mode)
      spike_scan_expr(st, b, file, fn_name, sinks, mode)
    }
    _ => ()
  }
}

///|
/// Apply the L2's BLANKET RULE to a loop head.
///
/// The rule: when the loop's condition is tainted, every NUMBER the
/// condition reads is tainted too. The L2 applies it to the state that goes
/// INTO the body (`implicit_abs_taint(body_in, cond)`), so the spike
/// applies it on the edge into the body and not on the edge out of the
/// loop.
///
/// The source of the taint is `rule:loop`, and it is ADDED to the facts the
/// variable already has. The L2 REPLACES the variable's mode with `TMaybe`,
/// which is a downgrade when the variable was definitely tainted -- but the
/// two are the same for every sink the L2 has, because a sink asks
/// "tainted or not", and `TMaybe` and `TTainted` are both tainted.
fn spike_apply_rule(st : SpikeState, cond : Expr) -> SpikeState {
  let out = spike_copy_state(st)
  for n in spike_names_of(cond) {
    let v = spike_get(out, n)
    if v.numeric {
      out[n] = {
        sources: spike_union(v.sources, [SPIKE_RULE_SOURCE]),
        numeric: v.numeric,
        array: v.array,
      }
    }
  }
  out
}

///|
/// KILL a variable and re-bind it.
fn spike_bind(st : SpikeState, name : String, e : Expr) -> SpikeState {
  let out = spike_copy_state(st)
  let sources = spike_taint_of(st, e)
  out[name] = {
    sources,
    numeric: spike_is_numeric(st, e),
    array: spike_is_array(st, e),
  }
  out
}

///|
/// JOIN a variable's facts with another expression's taint. This is what a
/// compound assignment does: the variable keeps what it had and gains the
/// right-hand side.
fn spike_bind_op(st : SpikeState, name : String, e : Expr) -> SpikeState {
  let out = spike_copy_state(st)
  let v = spike_get(st, name)
  let sources = spike_union(v.sources, spike_taint_of(st, e))
  out[name] = {
    sources,
    numeric: v.numeric || spike_is_numeric(st, e),
    array: spike_join_array(v.array, spike_is_array(st, e)),
  }
  out
}

///|
/// The RESULT of the transfer function of one CFG node: the state that
/// leaves the node, and the sinks the node's expressions hold.
priv struct SpikeTransfer {
  state : SpikeState
}

///|
/// The transfer function of a node.
///
/// The node's statement says what the node does. The node's KIND says
/// which part of a compound statement it stands for: a `for` has an
/// initialisation node and a loop-head node, and the loop head is the one
/// that reads the condition.
fn spike_transfer(
  node : CfgNode,
  stmt : Stmt?,
  st : SpikeState,
  fn_name : String,
  file : String,
  mode : SpikeMode,
  sinks : Map[String, SpikeSink],
) -> SpikeTransfer {
  let mut out = st
  let mode_name = match mode {
    SpikePlain => "spike-plain"
    SpikeWithRule => "spike-with-rule"
  }
  match stmt {
    None => ()
    Some(s) =>
      match s.kind {
        SLet(n, _, e) => {
          spike_scan_expr(st, e, file, fn_name, sinks, mode_name)
          out = spike_bind(st, n, e)
        }
        SAssign(lhs, e) => {
          spike_scan_expr(st, e, file, fn_name, sinks, mode_name)
          match lhs.kind {
            EName(n) => out = spike_bind(st, n, e)
            // A write into an array or a field is not modelled: the L2 does
            // not model it either, and the heap taint both of them would
            // need is a different problem.
            _ => out = st
          }
        }
        SAssignOp(_, lhs, e) => {
          spike_scan_expr(st, e, file, fn_name, sinks, mode_name)
          match lhs.kind {
            EName(n) => out = spike_bind_op(st, n, e)
            _ => out = st
          }
        }
        SExpr(e) => {
          spike_scan_expr(st, e, file, fn_name, sinks, mode_name)
          out = st
        }
        SReturn(e) => {
          match e {
            Some(x) => spike_scan_expr(st, x, file, fn_name, sinks, mode_name)
            None => ()
          }
          out = st
        }
        SBlock(_) | STry(_) | SBreak | SContinue => out = st
        // A statement the parser did not model. The spike does not guess
        // what it does: it lets the facts THROUGH, because a may-analysis
        // that drops facts loses sinks, and it COUNTS the gap so the
        // measurement can say how many there are. The L2 lets them through
        // too, so the two agree here.
        SUnsupported(_) => out = st
        SIf(cond, _, _) => {
          spike_scan_expr(st, cond, file, fn_name, sinks, mode_name)
          out = st
        }
        SWhile(cond, _) => {
          spike_scan_expr(st, cond, file, fn_name, sinks, mode_name)
          out = st
        }
        SFor(n, init, cond, step, _) =>
          if node.kind == NStmt {
            // The initialisation node: the loop's variable is bound here,
            // and only here. The CFG gives the step no node of its own, so
            // the step's effect on the variable is invisible to the
            // fixpoint -- the same way it is invisible to the CFG. The
            // L2 binds the variable in the same place.
            spike_scan_expr(st, init, file, fn_name, sinks, mode_name)
            out = spike_bind(st, n, init)
          } else {
            // The loop head: the condition, and the step that the CFG does
            // not give a node of its own.
            spike_scan_expr(st, cond, file, fn_name, sinks, mode_name)
            spike_scan_expr(st, step, file, fn_name, sinks, mode_name)
            out = st
          }
        SForIn(names, iter, _) => {
          // The binder is bound at the loop head, on the edge into the
          // body. The L2 re-binds it in every iteration, so what the body
          // does to it does not carry over.
          spike_scan_expr(st, iter, file, fn_name, sinks, mode_name)
          let binder = match iter.kind {
            ERange(a, b, _) =>
              spike_union(spike_taint_of(st, a), spike_taint_of(st, b))
            _ => spike_taint_of(st, iter)
          }
          out = spike_copy_state(st)
          for n in names {
            out[n] = { sources: binder.copy(), numeric: true, array: "", }
          }
        }
      }
  }
  { state: out, }
}

///|
/// The adjustment a state gets on the way along an EDGE.
///
/// The blanket rule is the only edge-sensitive rule: it applies to the
/// edge INTO the body of a `while`, and to nothing else.
fn spike_edge_adjust(
  stmt : Stmt?,
  edge : EdgeKind,
  st : SpikeState,
  mode : SpikeMode,
) -> SpikeState {
  let with_rule = match mode {
    SpikePlain => false
    SpikeWithRule => true
  }
  if !with_rule || edge != ETrue {
    return st
  }
  match stmt {
    Some(s) =>
      match s.kind {
        SWhile(cond, _) =>
          if spike_taint_of(st, cond).length() > 0 {
            spike_apply_rule(st, cond)
          } else {
            st
          }
        _ => st
      }
    None => st
  }
}

///|
/// Analyse one function with the spike.
fn spike_analyze_fn(func : Func, mode : SpikeMode) -> SpikeFnResult {
  let sinks : Map[String, SpikeSink] = Map([])
  let cfg = build_cfg(func)
  let stmts : Map[Int32, Stmt] = Map([])
  spike_index_stmts(func.body, stmts)
  let facts_at : Map[Int32, SpikeState] = Map([])
  let queued : Map[Int32, Bool] = Map([])
  let queue : Array[Int32] = []
  let init = spike_initial_state(func)
  facts_at[cfg.entry] = init
  queue.push(cfg.entry)
  queued[cfg.entry] = true
  let mut head = 0
  let mut steps = 0
  while head < queue.length() {
    let id = queue[head]
    head = head + 1
    queued[id] = false
    steps = steps + 1
    let node = match cfg.node(id) {
      Some(n) => n
      None => continue
    }
    let in_state = match facts_at.get(id) {
      Some(s) => s
      None => continue
    }
    let stmt = match node.stmt {
      -1 => None
      s =>
        match stmts.get(s) {
          Some(x) => Some(x)
          None => None
        }
    }
    let tr = spike_transfer(
      node,
      stmt,
      in_state,
      func.name,
      func.file,
      mode,
      sinks,
    )
    for edge in cfg.edges {
      if edge.from != id {
        continue
      }
      let edge_state = spike_edge_adjust(stmt, edge.kind, tr.state, mode)
      let old = facts_at.get(edge.to)
      let merged = match old {
        Some(o) => spike_join(o, edge_state)
        None => edge_state
      }
      let changed = match old {
        Some(o) => !spike_same_facts(o, merged)
        None => true
      }
      if changed {
        facts_at[edge.to] = merged
        if !queued.get_or_default(edge.to, false) {
          queue.push(edge.to)
          queued[edge.to] = true
        }
      }
    }
  }
  let mut facts = 0
  for pair in facts_at.to_array() {
    for v in pair.1.to_array() {
      facts = facts + v.1.sources.length()
    }
  }
  {
    findings: spike_sink_findings(sinks),
    nodes: cfg.nodes.length(),
    steps,
    facts,
  }
}

///|
/// Analyse a whole module with the spike.
///
/// The L2 analyses every function of the module and reports what it finds.
/// The spike does the same, and counts the statements it could not model.
fn spike_analyze_module(ast : ModuleAst, mode : SpikeMode) -> SpikeResult {
  let findings : Array[Finding] = []
  let kinds : Map[String, Int32] = Map([])
  let mut functions = 0
  let mut nodes = 0
  let mut steps = 0
  let mut facts = 0
  let mut gaps = 0
  for f in ast.all_funcs() {
    spike_count_kinds(f.body, kinds)
    gaps = gaps + spike_count_gaps(f.body)
    if f.body.length() == 0 {
      continue
    }
    let r = spike_analyze_fn(f, mode)
    functions = functions + 1
    nodes = nodes + r.nodes
    steps = steps + r.steps
    facts = facts + r.facts
    for x in r.findings {
      findings.push(x)
    }
  }
  { findings, functions, nodes, steps, facts, gaps, kinds, }
}

///|
/// Count the statements of a function by kind.
fn spike_count_kinds(stmts : Array[Stmt], kinds : Map[String, Int32]) -> Unit {
  for s in stmts {
    let k = match s.kind {
      SLet(_, _, _) => "let"
      SAssign(_, _) => "assign"
      SAssignOp(_, _, _) => "assign_op"
      SIf(_, _, _) => "if"
      SWhile(_, _) => "while"
      SFor(_, _, _, _, _) => "for"
      SForIn(_, _, _) => "for_in"
      SReturn(_) => "return"
      SBreak => "break"
      SContinue => "continue"
      SExpr(_) => "expr"
      SBlock(_) => "block"
      STry(_) => "try"
      SUnsupported(_) => "unsupported"
    }
    kinds[k] = kinds.get_or_default(k, 0) + 1
    match s.kind {
      SIf(_, a, b) => {
        spike_count_kinds(a, kinds)
        spike_count_kinds(b, kinds)
      }
      SWhile(_, body) => spike_count_kinds(body, kinds)
      SFor(_, _, _, _, body) => spike_count_kinds(body, kinds)
      SForIn(_, _, body) => spike_count_kinds(body, kinds)
      SBlock(inner) | STry(inner) => spike_count_kinds(inner, kinds)
      _ => ()
    }
  }
}

///|
/// Count the statements of a function the spike could not model.
fn spike_count_gaps(stmts : Array[Stmt]) -> Int32 {
  let mut n = 0
  for s in stmts {
    match s.kind {
      SUnsupported(_) => n = n + 1
      SIf(_, a, b) => n = n + spike_count_gaps(a) + spike_count_gaps(b)
      SWhile(_, body) => n = n + spike_count_gaps(body)
      SFor(_, _, _, _, body) => n = n + spike_count_gaps(body)
      SForIn(_, _, body) => n = n + spike_count_gaps(body)
      SBlock(inner) | STry(inner) => n = n + spike_count_gaps(inner)
      _ => ()
    }
  }
  n
}

///|
/// THE IFDS SPIKE'S WHITE-BOX DRIVER.
///
/// This file is compiled as part of the PACKAGE, not as a test-only unit,
/// so it can call the spike's private items. Its name ends in `_wbtest`
/// for exactly that reason: a plain `_test.mbt` file sees only the
/// package's `pub` items, and the spike's items are private on purpose --
/// the published API must not grow by a line. `src/app/pkg.generated.mbti`
/// does not change, and nothing here is reachable from the CLI.
///
/// The file has two jobs.
///
/// The FIRST is the falsifiable part: a handful of hand-written modules
/// whose taint behaviour is asserted exactly. They are the ground truth
/// the measurement is read against, and they are written to fail when the
/// engine's semantics move.
///
/// The SECOND is the measurement: it reads a module tree, runs the L2 and
/// the spike over it in both modes, and prints the sites each of them
/// found. The harness (`scripts/qa/ifds_spike.mjs`) reads those lines and
/// turns them into the four numbers of `docs/qa/IFDS_SPIKE.md`.
///
/// The corpus is named by the environment variable
/// `LUNAFLOW_IFDS_SPIKE_MODULE`, which holds a DIRECTORY. With no
/// variable the measurement test says so and passes; the assertions above
/// do not depend on a corpus and always run.

///|
/// A MODULE built from parsed files.
fn spike_ast_of(files : Array[SourceFile]) -> ModuleAst {
  {
    coord: "spike/local",
    version: "0.0.0",
    root: ".",
    files,
    manifest_deps: [],
    manifest_target: "",
  }
}

///|
/// The SINK SITES a module has under one mode of the spike.
///
/// A site is the kind of the finding and the line it was filed on. The
/// file is not part of the key because the modules the measurement reads
/// hold one file each; the file is printed with the site anyway.
fn spike_sites(ast : ModuleAst, mode : SpikeMode) -> Array[String] {
  let r = spike_analyze_module(ast, mode)
  let out : Array[String] = []
  for f in r.findings {
    out.push(f.kind.code() + "@" + f.line.to_string())
  }
  out
}

///|
/// The SOURCES a spike finding carries, which its evidence holds after
/// an `@`.
fn spike_evidence_sources(evidence : String) -> Array[String] {
  let at = evidence.find("@")
  match at {
    None => []
    Some(i) => {
      let rest = evidence[i + 1:]
      let out : Array[String] = []
      for s in rest.split("|") {
        if s != "" {
          out.push(s.to_owned())
        }
      }
      out
    }
  }
}

///|
/// The CONTAINER KIND a spike finding carries, which its evidence holds
/// before a `;`.
///
/// `array` -- the container is an array by type. `made` -- the container is
/// the result of an allocation, which the L2 does not see as an array
/// because its allocation rule matches a name the parser never produces.
/// `unknown` -- the container's type is not known. `size` -- an allocation
/// size, which has no container.
fn spike_evidence_container(evidence : String) -> String {
  let at = evidence.find(";")
  match at {
    None => "unknown"
    Some(i) => evidence[:i].to_owned()
  }
}

///|
/// The taint SITES of a set of findings, with the sources of each.
///
/// Only the two taint families are kept: `TAINT-INDEX` and `TAINT-ALLOC`.
/// The L1's `TAINT-INDEX-RANGE` is not produced by the L2 at all, and the
/// L2's `UNSUPPORTED` finding is a mixed family that also carries claims
/// which are not taint claims.
fn spike_site_map(findings : Array[Finding]) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = Map([])
  for f in findings {
    if f.kind != FTaintIndex && f.kind != FTaintAlloc {
      continue
    }
    let key = spike_sink_key(f.kind, f.file, f.line)
    let srcs = spike_evidence_sources(f.evidence)
    match out.get(key) {
      Some(old) => out[key] = spike_union(old, srcs)
      None => out[key] = srcs
    }
  }
  out
}

///|
/// The CONTAINER KIND of every site, by site key.
fn spike_container_map(findings : Array[Finding]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for f in findings {
    if f.kind != FTaintIndex && f.kind != FTaintAlloc {
      continue
    }
    let key = spike_sink_key(f.kind, f.file, f.line)
    if !out.contains(key) {
      out[key] = spike_evidence_container(f.evidence)
    }
  }
  out
}

///|
/// The corpus the measurement reads.
fn spike_corpus_root() -> String {
  match @env.get_env_var("LUNAFLOW_IFDS_SPIKE_MODULE") {
    Some(v) => v
    None => ""
  }
}

///|
/// GROUND TRUTH 1 -- the blanket rule is what taints a loop counter.
///
/// The counter `i` is not derived from anything untrusted: it starts at
/// zero and is incremented. What makes the L2's loop condition tainted is
/// `xs.length()`, and the L2's blanket rule then taints EVERY number the
/// condition reads -- including the counter, which is a claim about the
/// counter that is not true.
///
/// The flow-sensitive fixpoint does not make that claim, because it does
/// not have a rule that taints names; it follows the assignments. So the
/// plain spike finds NO sink here, and the spike with the rule finds the
/// same one the L2 finds.
///
/// This is the whole point of the measurement, asserted.
test "ifds_spike: a loop counter is tainted by the blanket rule and by nothing else" {
  let src =
    #|pub fn f(xs : Array[Int], ys : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < xs.length() {
    #|    total = total + ys[i]
    #|    i = i + 1
    #|  }
    #|  total
    #|}
    #|
  let ast = spike_ast_of([parse_file("a.mbt", src)])
  assert_eq(spike_sites(ast, SpikePlain).length(), 0)
  assert_eq(spike_sites(ast, SpikeWithRule).length(), 1)
}

///|
/// GROUND TRUTH 2 -- a real sink survives.
///
/// The length of a tainted string IS derived from the taint, so the index
/// it reaches is tainted, and every mode finds it. The flow-sensitive
/// fixpoint does not need a blanket rule to keep this one: the facts
/// follow the assignment.
test "ifds_spike: a tainted value that reaches an index is found in every mode" {
  let src =
    #|pub fn g(user : String, ys : Array[Int]) -> Int {
    #|  let n = user.length()
    #|  let x = ys[n]
    #|  x
    #|}
    #|
  let ast = spike_ast_of([parse_file("a.mbt", src)])
  assert_eq(spike_sites(ast, SpikePlain).length(), 1)
  assert_eq(spike_sites(ast, SpikeWithRule).length(), 1)
}

///|
/// GROUND TRUTH 3 -- a tainted allocation size is found in every mode.
test "ifds_spike: a tainted allocation size is found in every mode" {
  let src =
    #|pub fn k(user : String) -> Int {
    #|  let n = user.length()
    #|  let a = Array::make(n, 0)
    #|  a.length()
    #|}
    #|
  let ast = spike_ast_of([parse_file("a.mbt", src)])
  assert_eq(spike_sites(ast, SpikePlain).length(), 1)
  assert_eq(spike_sites(ast, SpikeWithRule).length(), 1)
}

///|
/// GROUND TRUTH 4 -- the fixpoint is KILL-EXACT.
///
/// A tainted value that is overwritten before it reaches the sink leaves no
/// taint behind, so no mode reports the sink. A boolean taint that cannot
/// be killed would report it, and the measurement would be measuring
/// nothing.
test "ifds_spike: a tainted value that is overwritten leaves no taint behind" {
  let src =
    #|pub fn h(user : String, ys : Array[Int]) -> Int {
    #|  let n = user.length()
    #|  let m = 0
    #|  let x = ys[m]
    #|  x
    #|}
    #|
  let ast = spike_ast_of([parse_file("a.mbt", src)])
  assert_eq(spike_sites(ast, SpikePlain).length(), 0)
  assert_eq(spike_sites(ast, SpikeWithRule).length(), 0)
}

///|
/// GROUND TRUTH 5 -- the L2 and the flow-sensitive fixpoint agree on the
/// loop counter, and the honest claim survives.
///
/// This assertion CHANGED with Phase 1. It used to say "the L2 finds the
/// same sink the spike WITH the blanket rule finds" -- because the L2
/// carried the blanket rule too. Phase 1 deleted the rule from the L2, so
/// the L2 now agrees with the spike WITHOUT it: neither claims that the
/// counter is tainted, because it is not -- the BOUND is, and the counter's
/// value is bounded by it.
///
/// What survives is the honest claim: the index may be out of bounds. That
/// is the VALUE domain's relation between the counter and the bound, and
/// it is asserted here so that deleting the rule cannot silently lose the
/// signal the rule was a proxy for.
test "ifds_spike: the L2 and the flow-sensitive fixpoint agree on the loop counter" {
  let src =
    #|pub fn f(xs : Array[Int], ys : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < xs.length() {
    #|    total = total + ys[i]
    #|    i = i + 1
    #|  }
    #|  total
    #|}
    #|
  let ast = spike_ast_of([parse_file("a.mbt", src)])
  let l2 = run_abstract(ast, 10, 1000)
  let mut taint = 0
  let mut oob = 0
  for f in l2.findings {
    if f.kind == FTaintIndex {
      taint = taint + 1
    }
    if f.kind == FIndexOob {
      oob = oob + 1
    }
  }
  // The counter is NOT tainted, so no tainted index is claimed.
  assert_eq(taint, 0)
  // The index may still be out of bounds, and that claim is made.
  assert_eq(oob, 1)
  // The spike without the rule agrees: no sink either.
  assert_eq(spike_sites(ast, SpikePlain).length(), 0)
  // The spike WITH the rule still claims one -- the rule's claim is what
  // Phase 1 removed from the L2.
  assert_eq(spike_sites(ast, SpikeWithRule).length(), 1)
}

///|
/// The measurement: the L2 and the spike over a module tree.
///
/// The output is one line per fact, so the harness can read it without a
/// JSON parser and without a dependency.
fn spike_measure(ast : ModuleAst, stats : ScanStats, root : String) -> String {
  // The same per-function step budget the CLI uses, and no cap on the
  // number of functions: a truncated comparison would be a comparison of
  // two different modules.
  let t0 = @env.now()
  let l2 = run_abstract(ast, 1000000, 200000)
  let t1 = @env.now()
  let plain = spike_analyze_module(ast, SpikePlain)
  let t2 = @env.now()
  let withrule = spike_analyze_module(ast, SpikeWithRule)
  let t3 = @env.now()
  let l2_map = spike_site_map(l2.findings)
  let plain_map = spike_site_map(plain.findings)
  let wr_map = spike_site_map(withrule.findings)
  let containers = spike_container_map(withrule.findings)
  let plain_containers = spike_container_map(plain.findings)
  let keys : Array[String] = []
  for k in l2_map.to_array() {
    if !keys.contains(k.0) {
      keys.push(k.0)
    }
  }
  for k in plain_map.to_array() {
    if !keys.contains(k.0) {
      keys.push(k.0)
    }
  }
  for k in wr_map.to_array() {
    if !keys.contains(k.0) {
      keys.push(k.0)
    }
  }
  keys.sort()
  let mut budget = 0
  for f in l2.findings {
    if f.kind == FBudget {
      budget = budget + 1
    }
  }
  let lines : Array[String] = []
  lines.push(
    "IFDS_SPIKE_CORPUS root=" +
    root +
    " files=" +
    stats.files.to_string() +
    " funcs=" +
    stats.funcs.to_string() +
    " stmts=" +
    stats.stmts.to_string() +
    " unsupported=" +
    stats.unsupported.to_string() +
    " issues=" +
    stats.issues.to_string(),
  )
  lines.push(
    "IFDS_SPIKE_L2 findings=" +
    l2.findings.length().to_string() +
    " functions=" +
    l2.functions.to_string() +
    " steps=" +
    l2.steps.to_string() +
    " budget=" +
    budget.to_string(),
  )
  for f in l2.findings {
    lines.push(
      "IFDS_SPIKE_L2FINDING kind=" +
      f.kind.code() +
      " file=" +
      f.file +
      " line=" +
      f.line.to_string() +
      " fn=" +
      f.fn_name,
    )
  }
  lines.push(spike_engine_line("plain", plain))
  lines.push(spike_engine_line("with-rule", withrule))
  lines.push("IFDS_SPIKE_TIME engine=l2 ms=" + spike_ms(t0, t1))
  lines.push("IFDS_SPIKE_TIME engine=spike-plain ms=" + spike_ms(t1, t2))
  lines.push("IFDS_SPIKE_TIME engine=spike-with-rule ms=" + spike_ms(t2, t3))
  for pair in plain.kinds.to_array() {
    lines.push(
      "IFDS_SPIKE_KIND kind=" + pair.0 + " count=" + pair.1.to_string(),
    )
  }
  for key in keys {
    let parts = key.split("|").to_array()
    let kind = parts[0].to_owned()
    let file = parts[1].to_owned()
    let line = parts[2].to_owned()
    let in_l2 = l2_map.contains(key)
    let in_plain = plain_map.contains(key)
    let in_wr = wr_map.contains(key)
    let mut sources : Array[String] = []
    match plain_map.get(key) {
      Some(s) => sources = spike_union(sources, s)
      None => ()
    }
    match wr_map.get(key) {
      Some(s) => sources = spike_union(sources, s)
      None => ()
    }
    let container = match containers.get(key) {
      Some(c) => c
      None =>
        match plain_containers.get(key) {
          Some(c) => c
          None => "unknown"
        }
    }
    lines.push(
      "IFDS_SPIKE_SITE kind=" +
      kind +
      " file=" +
      file +
      " line=" +
      line +
      " l2=" +
      spike_bit(in_l2) +
      " plain=" +
      spike_bit(in_plain) +
      " withrule=" +
      spike_bit(in_wr) +
      " container=" +
      container +
      " sources=" +
      sources.join(","),
    )
  }
  lines.join("\n")
}

///|
/// One engine's summary line.
fn spike_engine_line(label : String, r : SpikeResult) -> String {
  "IFDS_SPIKE_ENGINE mode=" +
  label +
  " findings=" +
  r.findings.length().to_string() +
  " functions=" +
  r.functions.to_string() +
  " nodes=" +
  r.nodes.to_string() +
  " steps=" +
  r.steps.to_string() +
  " facts=" +
  r.facts.to_string() +
  " gaps=" +
  r.gaps.to_string()
}

///|
/// The milliseconds between two readings of the clock.
fn spike_ms(t0 : UInt64, t1 : UInt64) -> String {
  (t1 - t0).to_string()
}

///|
/// A boolean as a digit.
fn spike_bit(b : Bool) -> String {
  if b {
    "1"
  } else {
    "0"
  }
}

///|
/// THE MEASUREMENT.
///
/// The corpus is a directory named by `LUNAFLOW_IFDS_SPIKE_MODULE`. With no
/// corpus the test says so and passes: the assertions above do not depend
/// on one, and the harness always sets the variable.
test "ifds_spike_measure" {
  let root = spike_corpus_root()
  if root == "" {
    println("IFDS_SPIKE_SKIP corpus=<none>")
    return
  }
  let mut report = ""
  @async.run_async_main(async fn() -> Unit {
    let (ast, stats) = load_module(root, "spike/local", "0.0.0", 20000)
    report = spike_measure(ast, stats, root)
  })
  println(report)
}
