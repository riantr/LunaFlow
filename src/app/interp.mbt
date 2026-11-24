///|
pub(all) struct RunOptions {
  trials : Int32
  max_steps : Int32
  max_depth : Int32
  /// The COUNT cap on the functions that are entered. It is OFF by default
  /// (0): a count of functions is not a bound on WORK, and the bound that IS
  /// on is the module-wide STEP BUDGET (`DEFAULT_MAX_TOTAL_STEPS`).
  max_functions : Int32
  entry_filter : String
}

///|
pub fn RunOptions::default() -> RunOptions {
  {
    trials: 8,
    max_steps: 2000,
    max_depth: 6,
    max_functions: 0,
    entry_filter: "",
  }
}

///|
/// The MODULE-WIDE STEP BUDGET of the dynamic layer, in interpreted steps.
///
/// This is the default bound of the default scan, and it REPLACED a count of
/// functions. The count was the wrong shape for a bound: the same 150
/// functions cost 3,011 steps on this tree and 47,835 on
/// `riantr/moonbit_doubleML@0.164.64` -- a 16x difference -- so the count
/// bounded the WORK sixteen times over depending on which functions came
/// first in file order. And the count was taken in file order, so it took
/// whole DIRECTORIES and left whole directories uninterpreted: on this tree
/// the 150-function cap interpreted 8 of 64 files, all of them in `src/app/`.
///
/// The budget is the shape the ABSTRACT LAYER already uses (`run_abstract`):
/// a bound on the work, not on the number of things.
///
/// ITS SIZE IS MEASURED, IN BOTH DIRECTIONS:
///
///   * it has to COVER a module. This tree's 850 functions cost 24,297
///     steps, so the default covers every one of them with 4x headroom. A
///     module of about 3,500 functions costs about 100,000 steps at the same
///     density -- which is the size of the module that asked for this.
///   * it has to FIT the artefact budget. The events a step produces are
///     stable across corpora (4.5 to 5.6 events per step) and an event is
///     about 158 bytes, so 100,000 steps is about 77 MB of trace at the
///     documented `--trials 4` recipe, and about 139 MB at the default
///     `--trials 8`. The trace ceiling (A12) follows the coverage.
///
/// The budget is checked BEFORE each function is entered, so the scan
/// overshoots it by at most one function's own budget (2,000 steps).
pub const DEFAULT_MAX_TOTAL_STEPS : Int32 = 100000

///|
pub(all) enum Signal {
  Normal
  Returned(Val)
  BreakLoop
  ContinueLoop
}

///|
struct Interp {
  funcs : Map[String, Func]
  /// The FOREIGN declarations: the calls that cross the C boundary.
  ffi : Map[String, FfiDecl]
  events : Array[TraceEvent]
  findings : Array[Finding]
  ranges : Ranges
  mut trial : Int32
  mut steps : Int32
  max_steps : Int32
  max_depth : Int32
  mut depth : Int32
  mut budget : Bool
  /// The RECURSION DEPTH budget was exhausted: the call chain was not
  /// followed any deeper.  Like the step budget, it is reported ONCE, and
  /// like the step budget it is a claim the analyser could NOT DECIDE.
  mut depth_budget : Bool
  reads : Array[String]
  mut func_name : String
  mut file : String
  /// The module's GLOBAL REGION: the values of the top-level bindings.
  mut global_values : Map[String, Val]
  /// The value of each expression statement, by statement id.
  expr_values : Map[Int32, Val]
}

///|
fn Interp::new(
  funcs : Map[String, Func],
  opts : RunOptions,
  trial : Int32,
  ffi : Map[String, FfiDecl],
) -> Interp {
  {
    funcs,
    ffi,
    events: [],
    findings: [],
    ranges: Ranges::new(),
    trial,
    steps: 0,
    max_steps: opts.max_steps,
    max_depth: opts.max_depth,
    depth: 0,
    budget: false,
    depth_budget: false,
    reads: [],
    func_name: "",
    file: "",
    global_values: Map([]),
    expr_values: Map([]),
  }
}

///|
/// Evaluate the module's GLOBAL REGION: the top-level bindings, in DEPENDENCY
/// order.
///
/// MoonBit resolves top-level bindings by dependency, not by file order, so a
/// global may read a global declared later in the file. The globals are
/// computed ONCE, outside the trials: they are constants of the module, so
/// their value does not depend on the input the analyzer happened to sample.
///
/// A global that is MUTATED somewhere in the module is left unknown: its
/// value at the point of use is not the value of its initializer, and
/// guessing would be a lie the report could not defend.
pub fn eval_globals(
  funcs : Map[String, Func],
  opts : RunOptions,
  ast : ModuleAst,
) -> (Map[String, Val], Array[TraceEvent]) {
  let table = globals_of(ast)
  let (order, _unresolved) = global_order(table)
  let mutated = globals_mutated(ast)
  let values : Map[String, Val] = Map([])
  let events : Array[TraceEvent] = []
  let p = Interp::new(funcs, opts, 0, ffi_map(ast))
  p.func_name = "<global>"
  for name in order {
    match table.get(name) {
      Some(g) => {
        let env : Map[String, Val] = Map([])
        for other in order {
          if other != name {
            match values.get(other) {
              Some(v) => env[other] = v
              None => ()
            }
          }
        }
        let v = if mutated.contains(name) {
          clean(VUnknown)
        } else {
          eval(p, env, g.init)
        }
        values[name] = v
        events.push(
          TraceEvent::new(
            EvDef,
            "<global>",
            g.file,
            g.line,
            0,
            name,
            v.v.repr(),
            false,
            0,
            "global",
          ),
        )
      }
      None => ()
    }
  }
  for e in p.events {
    events.push(e)
  }
  (values, events)
}

///|
pub struct RunResult {
  events : Array[TraceEvent]
  findings : Array[Finding]
  ranges : Ranges
  steps : Int32
  trials : Int32
  functions_run : Int32
  functions_skipped : Array[String]
  /// The MODULE-WIDE STEP BUDGET that was in force (0 = no budget), and
  /// WHETHER it is what stopped the scan. A reader who sees a truncated
  /// scan has to be able to tell a budget from a count from a filter.
  max_total_steps : Int32
  stopped_by_budget : Bool
  stopped_by_count : Bool
}

///|
fn unique_reads(p : Interp) -> String {
  let out : Array[String] = []
  for r in p.reads {
    if !out.contains(r) {
      out.push(r)
    }
  }
  out.join(",")
}

///|
fn seed_reads(p : Interp, csv : String) -> Unit {
  p.reads.clear()
  for r in csv.split(",") {
    let t = r.trim().to_owned()
    if t != "" {
      p.reads.push(t)
    }
  }
}

///|

///|
fn apply_implicit_loop_taint(p : Interp, env : Map[String, Val]) -> Unit {
  for name in p.reads.copy() {
    match env.get(name) {
      Some(v) => if v.v.numeric() != None { env[name] = Val::new(v.v, true) }
      None => ()
    }
  }
}

///|
fn numeric_of(v : Val) -> Double? {
  v.v.numeric()
}

///|
/// The integer a value holds, when it holds one.
///
/// A range's end is an integer in the source. When the value computed for it
/// is not an integer -- it is unknown, or the expression failed -- there is
/// no trip count to run, and the loop does not run.
fn int_of_value(v : Value) -> Int32 {
  match v {
    VInt(n) => n
    VDouble(d) => d.to_int()
    _ => 0
  }
}

///|
/// Bind the binders of a `for` loop. A plain binder takes the element; a
/// destructuring binder takes the parts of a tuple element, one name per
/// part. An element that is not a tuple leaves every name unknown rather
/// than guessing.
fn bind_for_binders(
  p : Interp,
  env : Map[String, Val],
  names : Array[String],
  item : Value,
  tainted : Bool,
  span : Span,
  stmt : Int32,
) -> Unit {
  if names.length() == 1 {
    let v = Val::new(item, tainted)
    env[names[0]] = v
    observe_def(p, names[0], v, span, stmt)
    return
  }
  let parts = match item {
    VTuple(xs) => xs
    _ => []
  }
  let mut i = 0
  for n in names {
    let v = if i < parts.length() {
      Val::new(parts[i], tainted)
    } else {
      Val::new(VUnknown, tainted)
    }
    env[n] = v
    observe_def(p, n, v, span, stmt)
    i = i + 1
  }
}

///|
fn observe_def(
  p : Interp,
  name : String,
  val : Val,
  span : Span,
  stmt : Int32,
) -> Unit {
  let site = span.to_string()
  p.events.push(
    TraceEvent::new(
      EvDef,
      p.func_name,
      p.file,
      span.start_line,
      stmt,
      name,
      val.v.repr(),
      val.tainted,
      p.trial,
      unique_reads(p),
    ),
  )
  match numeric_of(val) {
    Some(d) => p.ranges.observe(p.func_name, name, d, val.v.repr(), site)
    None => ()
  }
}

///|
fn arith(op : BinOp, a : Val, b : Val) -> Val {
  let t = a.tainted || b.tainted
  let na = a.v.numeric()
  let nb = b.v.numeric()
  match (na, nb) {
    (Some(x), Some(y)) =>
      match op {
        OpAdd =>
          if a.v is VStr(_) || b.v is VStr(_) {
            let sv = match a.v {
              VStr(s) => s
              _ => a.v.repr()
            }
            let tv = match b.v {
              VStr(s) => s
              _ => b.v.repr()
            }
            Val::new(VStr(sv + tv), t)
          } else if a.v is VInt(_) && b.v is VInt(_) {
            Val::new(VInt(x.to_int() + y.to_int()), t)
          } else {
            Val::new(VDouble(x + y), t)
          }
        OpSub => Val::new(numeric_result(x - y, a, b), t)
        OpMul => Val::new(numeric_result(x * y, a, b), t)
        OpDiv =>
          if y == 0.0 {
            Val::new(VUnknown, t)
          } else {
            Val::new(numeric_result(x / y, a, b), t)
          }
        OpMod =>
          if y == 0.0 {
            Val::new(VUnknown, t)
          } else {
            Val::new(VInt(x.to_int() % y.to_int()), t)
          }
        OpEq => Val::new(VBool(x == y), t)
        OpNe => Val::new(VBool(x != y), t)
        OpLt => Val::new(VBool(x < y), t)
        OpLe => Val::new(VBool(x <= y), t)
        OpGt => Val::new(VBool(x > y), t)
        OpGe => Val::new(VBool(x >= y), t)
        OpBitAnd => Val::new(VInt(x.to_int() & y.to_int()), t)
        OpBitOr => Val::new(VInt(x.to_int() | y.to_int()), t)
        OpBitXor => Val::new(VInt(x.to_int() ^ y.to_int()), t)
        OpShl => Val::new(VInt(x.to_int() << y.to_int()), t)
        OpShr => Val::new(VInt(x.to_int() >> y.to_int()), t)
        OpAnd | OpOr => Val::new(VBool(x != 0.0), t)
      }
    _ =>
      if op == OpAdd && (a.v is VStr(_) || b.v is VStr(_)) {
        Val::new(VStr(a.v.repr() + b.v.repr()), t)
      } else {
        Val::new(VUnknown, t)
      }
  }
}

///|
fn numeric_result(d : Double, a : Val, b : Val) -> Value {
  if a.v is VInt(_) && b.v is VInt(_) {
    VInt(d.to_int())
  } else {
    VDouble(d)
  }
}

///|
fn eval(p : Interp, env : Map[String, Val], e : Expr) -> Val {
  match e.kind {
    EInt(n) => clean(VInt(n))
    EDouble(d) => clean(VDouble(d))
    EBool(b) => clean(VBool(b))
    EString(s) => clean(VStr(s))
    EBytes(s) => clean(VStr(s))
    EName(n) => {
      p.reads.push(n)
      match env.get(n) {
        Some(v) => v
        None =>
          // A name that is not local may be a GLOBAL: the module's global
          // region, whose value was computed once in dependency order.
          match p.global_values.get(n) {
            Some(g) => g
            None => clean(VUnknown)
          }
      }
    }
    EBin(OpAnd, l, r) => {
      let lv = eval(p, env, l)
      match lv.v.bool_of() {
        Some(false) => clean(VBool(false))
        _ => {
          let rv = eval(p, env, r)
          Val::new(
            VBool(rv.v.bool_of().unwrap_or(true)),
            lv.tainted || rv.tainted,
          )
        }
      }
    }
    EBin(OpOr, l, r) => {
      let lv = eval(p, env, l)
      match lv.v.bool_of() {
        Some(true) => clean(VBool(true))
        _ => {
          let rv = eval(p, env, r)
          Val::new(
            VBool(rv.v.bool_of().unwrap_or(false)),
            lv.tainted || rv.tainted,
          )
        }
      }
    }
    EBin(op, l, r) => {
      let lv = eval(p, env, l)
      let rv = eval(p, env, r)
      arith(op, lv, rv)
    }
    EUn(UnNeg, x) => {
      let v = eval(p, env, x)
      match v.v.numeric() {
        Some(d) => Val::new(numeric_result(-d, v, v), v.tainted)
        None => Val::new(VUnknown, v.tainted)
      }
    }
    EUn(UnNot, x) => {
      let v = eval(p, env, x)
      match v.v.bool_of() {
        Some(b) => Val::new(VBool(!b), v.tainted)
        None => Val::new(VUnknown, v.tainted)
      }
    }
    EIndex(base, idx) => {
      let bv = eval(p, env, base)
      let iv = eval(p, env, idx)
      p.events.push(
        TraceEvent::new(
          EvIndex,
          p.func_name,
          p.file,
          e.span.start_line,
          0,
          base.render(),
          iv.v.repr(),
          iv.tainted,
          p.trial,
          unique_reads(p),
        ),
      )
      if iv.tainted {
        // The alarm is about the OUT-OF-BOUNDS risk. When the observed index
        // was inside the observed array, that risk was not witnessed, and the
        // honest finding is the weaker claim -- untrusted input selects the
        // element -- not an error that it may go out of bounds.
        let len = bv.v.len_of()
        let witnessed_in_range = match (len, iv.v.numeric()) {
          (Some(n), Some(d)) => {
            let i = d.to_int()
            i >= 0 && i < n
          }
          _ => false
        }
        let evidence = base.render() +
          "[" +
          iv.v.repr() +
          "]" +
          (match len {
            Some(n) => " of length " + n.to_string()
            None => ""
          })
        if witnessed_in_range {
          p.findings.push(
            Finding::new(
              FTaintIndexRange,
              p.file,
              e.span.start_line,
              p.func_name,
              "untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed",
              "dynamic+symbolic",
              0.5,
              evidence,
            ),
          )
        } else {
          p.findings.push(
            Finding::new(
              FTaintIndex,
              p.file,
              e.span.start_line,
              p.func_name,
              "tainted value reaches an array index / buffer offset",
              "dynamic+symbolic",
              0.8,
              evidence,
            ),
          )
        }
      }
      match (bv.v, iv.v.numeric()) {
        (VArr(xs), Some(d)) => {
          let i = d.to_int()
          if i < 0 || i >= xs.length() {
            p.findings.push(
              Finding::new(
                FRangeViolation,
                p.file,
                e.span.start_line,
                p.func_name,
                "index out of bounds in an observed execution",
                "dynamic",
                1.0,
                "index " +
                i.to_string() +
                " vs length " +
                xs.length().to_string(),
              ),
            )
            Val::new(VUnknown, bv.tainted || iv.tainted)
          } else {
            let elem = xs[i]
            Val::new(
              elem,
              bv.tainted || iv.tainted || elem_is_tainted(elem, bv),
            )
          }
        }
        _ => Val::new(VUnknown, bv.tainted || iv.tainted)
      }
    }
    ESlice(base, start, end) => {
      let bv = eval(p, env, base)
      let sv = match start {
        Some(x) => eval(p, env, x)
        None => clean(VInt(0))
      }
      let ev = match end {
        Some(x) => Some(eval(p, env, x))
        None => None
      }
      let tainted = bv.tainted ||
        sv.tainted ||
        (match ev {
          Some(v) => v.tainted
          None => false
        })
      // The bounds are used to build the value, not to raise a range
      // violation: a slice out of range is clamped by the runtime, so it
      // never reads out of bounds the way an index does.
      match
        (
          bv.v,
          sv.v.numeric(),
          match ev {
            Some(v) => v.v.numeric()
            None => None
          },
        ) {
        (VArr(xs), Some(sd), Some(ed)) => {
          let lo = if sd.to_int() < 0 { 0 } else { sd.to_int() }
          let hi = if ed.to_int() > xs.length() {
            xs.length()
          } else {
            ed.to_int()
          }
          let sub : Array[Value] = []
          let mut i = lo
          while i < hi {
            sub.push(xs[i])
            i = i + 1
          }
          Val::new(VArr(sub), tainted)
        }
        (VArr(xs), Some(sd), None) => {
          let lo = if sd.to_int() < 0 { 0 } else { sd.to_int() }
          let sub : Array[Value] = []
          let mut i = lo
          while i < xs.length() {
            sub.push(xs[i])
            i = i + 1
          }
          Val::new(VArr(sub), tainted)
        }
        _ => Val::new(VUnknown, tainted)
      }
    }
    ECall(name, args) => eval_call(p, env, name, args, e.span)
    EMethod(recv, m, args) => eval_method(p, env, recv, m, args, e.span)
    EField(base, _) => {
      let v = eval(p, env, base)
      Val::new(VUnknown, v.tainted)
    }
    EArray(xs) => {
      let out : Array[Value] = []
      let mut t = false
      for x in xs {
        let v = eval(p, env, x)
        out.push(v.v)
        t = t || v.tainted
      }
      Val::new(VArr(out), t)
    }
    ETuple(xs) => {
      let out : Array[Value] = []
      let mut t = false
      for x in xs {
        let v = eval(p, env, x)
        out.push(v.v)
        t = t || v.tainted
      }
      Val::new(VTuple(out), t)
    }
    ERange(_, _, _) =>
      // A RANGE is not a value: the toolchain says "Range operators are
      // currently only supported in `for .. in` loops". It is read by the
      // `for` loop itself, so evaluating one here means the range was used
      // somewhere it cannot be used.
      clean(VUnknown)
    EFn(_, _) => clean(VUnknown)
    EUnknown(_) => clean(VUnknown)
  }
}

///|
fn elem_is_tainted(elem : Value, container : Val) -> Bool {
  ignore(elem)
  ignore(container)
  false
}

///|
fn eval_method(
  p : Interp,
  env : Map[String, Val],
  recv : Expr,
  m : String,
  args : Array[Expr],
  span : Span,
) -> Val {
  // A MODULE's function written as a method call: `Array.make(n, 0)`. The
  // parser reads a qualified path `Array::make` as a field access and then
  // a call, so the two spellings of the SAME call reach the analyzer by
  // different routes -- and the allocation rule has to answer to both, or
  // the same call is analysed two ways.
  let owner = match recv.kind {
    EName(n) => n
    _ => ""
  }
  if (m == "make" || m == "new") && (owner == "Array" || owner == "FixedArray") {
    return eval_call(p, env, owner + "." + m, args, span)
  }
  let rv = eval(p, env, recv)
  if m == "length" {
    match rv.v.len_of() {
      Some(n) => Val::new(VInt(n), rv.tainted)
      None => Val::new(VUnknown, rv.tainted)
    }
  } else if m == "to_string" {
    Val::new(VStr(rv.v.repr()), rv.tainted)
  } else if m == "to_array" {
    // `String::to_array` is modelled with the REAL characters. Without it the
    // result was an unknown value, and an unknown value has no LENGTH -- so
    // every index into a string was an index of unknown bounds, and the
    // taint alarm on it could never be resolved either way.
    match rv.v {
      VStr(s) => {
        let xs : Array[Value] = []
        for ch in s.to_array() {
          xs.push(VStr(ch.to_string()))
        }
        Val::new(VArr(xs), rv.tainted)
      }
      _ => Val::new(VUnknown, rv.tainted)
    }
  } else if m == "copy" {
    match rv.v {
      VArr(xs) => Val::new(VArr(xs.copy()), rv.tainted)
      _ => Val::new(VUnknown, rv.tainted)
    }
  } else if m == "push" {
    let arg = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VUnknown)
    }
    match rv.v {
      VArr(xs) => xs.push(arg.v)
      _ => ()
    }
    clean(VUnit)
  } else if m == "get" {
    let idx = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VUnknown)
    }
    match (rv.v, idx.v.numeric()) {
      (VArr(xs), Some(d)) =>
        if d.to_int() >= 0 && d.to_int() < xs.length() {
          Val::new(xs[d.to_int()], rv.tainted || idx.tainted)
        } else {
          Val::new(VUnknown, rv.tainted || idx.tainted)
        }
      _ => Val::new(VUnknown, rv.tainted || idx.tainted)
    }
  } else if m == "sort" || m == "stable_sort" {
    match rv.v {
      VArr(xs) => sort_values(xs)
      _ => ()
    }
    clean(VUnit)
  } else {
    let mut t = rv.tainted
    for a in args {
      let av = eval(p, env, a)
      t = t || av.tainted
    }
    p.events.push(
      TraceEvent::new(
        EvCall,
        p.func_name,
        p.file,
        recv.span.start_line,
        0,
        "." + m,
        "?",
        t,
        p.trial,
        unique_reads(p),
      ),
    )
    Val::new(VUnknown, t)
  }
}

///|
fn sort_values(xs : Array[Value]) -> Unit {
  let mut i = 0
  while i < xs.length() {
    let mut j = 0
    while j + 1 < xs.length() - i {
      let a = xs[j].numeric().unwrap_or(0.0)
      let b = xs[j + 1].numeric().unwrap_or(0.0)
      if a > b {
        let tmp = xs[j]
        xs[j] = xs[j + 1]
        xs[j + 1] = tmp
      }
      j = j + 1
    }
    i = i + 1
  }
}

///|
fn eval_call(
  p : Interp,
  env : Map[String, Val],
  name : String,
  args : Array[Expr],
  span : Span,
) -> Val {
  // The parser renders a qualified path with a DOT -- `Array::make(n)`
  // becomes the call name `Array.make` -- so the `::` spelling never
  // arrives here, and a rule that matches only that spelling is DEAD.
  // Both are accepted, because a caller may build the expression itself.
  if name == "Array.make" ||
    name == "Array::make" ||
    name == "FixedArray.make" ||
    name == "FixedArray::make" ||
    name == "Array.new" ||
    name == "Array::new" {
    let size = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VInt(0))
    }
    let init = if args.length() > 1 {
      eval(p, env, args[1])
    } else {
      clean(VUnknown)
    }
    if size.tainted {
      p.findings.push(
        Finding::new(
          FTaintAlloc,
          p.file,
          span.start_line,
          p.func_name,
          "tainted value controls an allocation size",
          "dynamic+symbolic",
          0.8,
          name + "(" + size.v.repr() + ", ...)",
        ),
      )
      p.events.push(
        TraceEvent::new(
          EvAlloc,
          p.func_name,
          p.file,
          span.start_line,
          0,
          name,
          size.v.repr(),
          true,
          p.trial,
          unique_reads(p),
        ),
      )
    }
    match size.v.numeric() {
      Some(d) =>
        if d.to_int() >= 0 && d.to_int() <= 64 {
          let xs : Array[Value] = []
          let mut i = 0
          while i < d.to_int() {
            xs.push(init.v)
            i = i + 1
          }
          Val::new(VArr(xs), size.tainted || init.tainted)
        } else {
          Val::new(VUnknown, size.tainted)
        }
      None => Val::new(VUnknown, size.tainted)
    }
  } else if name == "abort" || name == "panic" || name == "fail" {
    let mut t = false
    for a in args {
      let av = eval(p, env, a)
      t = t || av.tainted
    }
    p.events.push(
      TraceEvent::new(
        EvAbort,
        p.func_name,
        p.file,
        span.start_line,
        0,
        name,
        "",
        t,
        p.trial,
        unique_reads(p),
      ),
    )
    clean(VUnit)
  } else if name == "require" || name == "assert_true" || name == "assert_eq" {
    let _ = if args.length() > 0 { eval(p, env, args[0]) } else { clean(VUnit) }
    clean(VUnit)
  } else if name == "println" || name == "print" || name == "inspect" {
    for a in args {
      let _ = eval(p, env, a)
    }
    clean(VUnit)
  } else if name.has_prefix("@env.args") || name == "@process" {
    p.events.push(
      TraceEvent::new(
        EvSource,
        p.func_name,
        p.file,
        span.start_line,
        0,
        name,
        "argv",
        true,
        p.trial,
        "",
      ),
    )
    Val::new(VStr("tainted-argv"), true)
  } else if name == "Int.to_string" ||
    name == "Int::to_string" ||
    name == "Double.to_string" ||
    name == "Double::to_string" {
    let v = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VUnknown)
    }
    Val::new(VStr(v.v.repr()), v.tainted)
  } else if name == "Int.from_string" ||
    name == "Int::from_string" ||
    name == "Double.from_string" ||
    name == "Double::from_string" {
    let v = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VUnknown)
    }
    Val::new(VInt(0), v.tainted)
  } else {
    let arg_vals : Array[Val] = []
    let mut t = false
    for a in args {
      let av = eval(p, env, a)
      arg_vals.push(av)
      t = t || av.tainted
    }
    p.events.push(
      TraceEvent::new(
        EvCall,
        p.func_name,
        p.file,
        span.start_line,
        0,
        name,
        arg_vals.length().to_string(),
        t,
        p.trial,
        unique_reads(p),
      ),
    )
    match p.funcs.get(name) {
      Some(target) =>
        if p.depth < p.max_depth {
          call_user(p, target, arg_vals, span)
        } else {
          // The RECURSION DEPTH budget was exhausted, so the call chain was
          // NOT followed any deeper.  The value the call would have returned
          // is unknown, and everything computed from it is unknown too, so
          // nothing about the rest of the chain was decided.
          //
          // That is a claim the analyser could NOT DECIDE -- not a claim about
          // the module -- and it is reported as such, with the same family and
          // the same verdict as the step budget above.
          //
          // BEFORE THIS, THE TRUNCATION WAS SILENT.  A recursive module and a
          // clean one produced the same report: the value that could not be
          // computed was simply absent, and an absent claim is
          // indistinguishable from a decided and clean one.
          if !p.depth_budget {
            p.depth_budget = true
            p.findings.push(
              Finding::undecided(
                FBudget,
                p.file,
                span.start_line,
                p.func_name,
                "the recursion depth budget was exhausted: the call chain was not followed past this depth, so no claim about the rest of it was decided",
                "dynamic",
                0.6,
                "max_depth=" +
                p.max_depth.to_string() +
                " depth=" +
                p.depth.to_string() +
                " call=" +
                name,
              ),
            )
            p.events.push(
              TraceEvent::new(
                EvBudget,
                p.func_name,
                p.file,
                span.start_line,
                0,
                name,
                "",
                false,
                p.trial,
                "depth budget",
              ),
            )
          }
          Val::new(VUnknown, t)
        }
      None =>
        // A call that crosses the C boundary. The value it returns is a
        // FOREIGN value: it lives in the other address space, and the
        // analyzer knows only which symbol produced it.
        match ffi_lookup(p.ffi, name) {
          Some(d) => Val::new(VForeign(d.symbol), t)
          None => Val::new(VUnknown, t)
        }
    }
  }
}

///|
fn call_user(p : Interp, target : Func, args : Array[Val], span : Span) -> Val {
  let saved_func = p.func_name
  let saved_file = p.file
  let saved_reads = p.reads.copy()
  p.depth = p.depth + 1
  p.func_name = target.name
  p.file = target.file
  p.reads.clear()
  let env : Map[String, Val] = Map([])
  let mut i = 0
  while i < target.params.length() && i < args.length() {
    env[target.params[i].name] = args[i]
    i = i + 1
  }
  p.events.push(
    TraceEvent::new(
      EvEnter,
      target.name,
      target.file,
      target.span.start_line,
      0,
      target.name,
      args.length().to_string(),
      false,
      p.trial,
      "",
    ),
  )
  let sig = exec_block(p, env, target.body, target.name)
  let result = match sig {
    Returned(v) => v
    _ => clean(VUnit)
  }
  p.depth = p.depth - 1
  p.func_name = saved_func
  p.file = saved_file
  for r in saved_reads {
    p.reads.push(r)
  }
  ignore(span)
  result
}

///|
fn is_literal_true(e : Expr) -> Bool {
  match e.kind {
    EBool(true) => true
    EName(n) => n == "true"
    _ => false
  }
}

///|
fn exec_block(
  p : Interp,
  env : Map[String, Val],
  stmts : Array[Stmt],
  fn_name : String,
) -> Signal {
  for s in stmts {
    if p.steps >= p.max_steps {
      if !p.budget {
        p.budget = true
        // The execution budget ran out, so the rest of this function was NOT
        // executed.  Nothing about it was decided -- that is the difference
        // between this finding and a claim about the module, and the verdict
        // is what says so.
        p.findings.push(
          Finding::undecided(
            FBudget,
            p.file,
            s.span.start_line,
            fn_name,
            "the execution budget was exhausted: the rest of this function was not executed, so no claim about it was decided",
            "dynamic",
            0.6,
            "max_steps=" + p.max_steps.to_string(),
          ),
        )
        p.events.push(
          TraceEvent::new(
            EvBudget,
            fn_name,
            p.file,
            s.span.start_line,
            s.id,
            "",
            "",
            false,
            p.trial,
            "",
          ),
        )
      }
      return Normal
    }
    p.reads.clear()
    let sig = exec_stmt(p, env, s, fn_name)
    match sig {
      Normal => ()
      _ => return sig
    }
  }
  Normal
}

///|
fn exec_stmt(
  p : Interp,
  env : Map[String, Val],
  s : Stmt,
  fn_name : String,
) -> Signal {
  p.steps = p.steps + 1
  match s.kind {
    SLet(name, _, e) => {
      let v = eval(p, env, e)
      env[name] = v
      observe_def(p, name, v, s.span, s.id)
      Normal
    }
    SAssign(lhs, rhs) => {
      let v = eval(p, env, rhs)
      match lhs.kind {
        EName(n) => {
          env[n] = v
          observe_def(p, n, v, s.span, s.id)
        }
        EIndex(base, idx) => {
          let iv = eval(p, env, idx)
          match base.kind {
            EName(n) =>
              match env.get(n) {
                Some(bv) =>
                  match bv.v {
                    VArr(xs) => {
                      match iv.v.numeric() {
                        Some(d) =>
                          if d.to_int() >= 0 && d.to_int() < xs.length() {
                            xs[d.to_int()] = v.v
                          } else {
                            p.findings.push(
                              Finding::new(
                                FRangeViolation,
                                p.file,
                                s.span.start_line,
                                fn_name,
                                "store index out of bounds in an observed execution",
                                "dynamic",
                                1.0,
                                n + "[" + d.to_int().to_string() + "]",
                              ),
                            )
                          }
                        None => ()
                      }
                      observe_def(p, n, Val::new(bv.v, v.tainted), s.span, s.id)
                    }
                    _ => ()
                  }
                None => ()
              }
            _ => ()
          }
        }
        _ => ()
      }
      Normal
    }
    SAssignOp(op, lhs, rhs) => {
      let rhs_v = eval(p, env, rhs)
      match lhs.kind {
        EName(n) => {
          let cur = env.get(n).unwrap_or(clean(VInt(0)))
          let v = arith(op, cur, rhs_v)
          env[n] = v
          observe_def(p, n, v, s.span, s.id)
        }
        _ => ()
      }
      Normal
    }
    SIf(cond, then_b, else_b) => {
      let cv = eval(p, env, cond)
      p.events.push(
        TraceEvent::new(
          EvCond,
          fn_name,
          p.file,
          s.span.start_line,
          s.id,
          "if",
          cv.v.repr(),
          cv.tainted,
          p.trial,
          unique_reads(p),
        ),
      )
      match cv.v.bool_of() {
        Some(true) => exec_block(p, env, then_b, fn_name)
        Some(false) => exec_block(p, env, else_b, fn_name)
        None => {
          let sig = exec_block(p, env, then_b, fn_name)
          match sig {
            Normal => exec_block(p, env, else_b, fn_name)
            _ => sig
          }
        }
      }
    }
    SWhile(cond, body) => {
      let mut iterations = 0
      let mut result = Normal
      while iterations < 64 && p.steps < p.max_steps {
        let cv = eval(p, env, cond)
        p.events.push(
          TraceEvent::new(
            EvCond,
            fn_name,
            p.file,
            s.span.start_line,
            s.id,
            "while",
            cv.v.repr(),
            cv.tainted,
            p.trial,
            unique_reads(p),
          ),
        )
        if cv.tainted {
          apply_implicit_loop_taint(p, env)
        }
        match cv.v.bool_of() {
          Some(false) => {
            result = Normal
            break
          }
          _ => {
            let sig = exec_block(p, env, body, fn_name)
            p.events.push(
              TraceEvent::new(
                EvLoop,
                fn_name,
                p.file,
                s.span.start_line,
                s.id,
                "iter",
                iterations.to_string(),
                cv.tainted,
                p.trial,
                "",
              ),
            )
            iterations = iterations + 1
            match sig {
              BreakLoop => {
                result = Normal
                break
              }
              ContinueLoop => continue
              Normal => ()
              Returned(v) => return Returned(v)
            }
            if is_literal_true(cond) && iterations >= 64 && !has_gap(body) {
              // The cap was reached, but only a body the model fully
              // understands proves the loop is infinite. A body with an
              // unmodelled construct in it may break out of the loop, and
              // then the cap says nothing about the program.
              p.findings.push(
                Finding::new(
                  FInfinite,
                  p.file,
                  s.span.start_line,
                  fn_name,
                  "loop did not terminate within the iteration cap (possible infinite loop)",
                  "dynamic",
                  0.7,
                  "iterations=64",
                ),
              )
            }
          }
        }
      }
      result
    }
    SFor(name, init, cond, step, body) => {
      let iv = eval(p, env, init)
      env[name] = iv
      let mut iterations = 0
      while iterations < 64 && p.steps < p.max_steps {
        let cv = eval(p, env, cond)
        if cv.tainted {
          apply_implicit_loop_taint(p, env)
        }
        match cv.v.bool_of() {
          Some(false) => break
          _ => {
            let sig = exec_block(p, env, body, fn_name)
            match sig {
              BreakLoop => break
              Returned(v) => return Returned(v)
              _ => ()
            }
            let _ = eval(p, env, step)
            iterations = iterations + 1
          }
        }
      }
      Normal
    }
    SForIn(names, iter, body) => {
      match iter.kind {
        ERange(start_e, end_e, inclusive) => {
          // A RANGE loop: `for i in a..<b`.
          //
          // The end is evaluated ONCE, before the loop. MEASURED against the
          // toolchain: `for i in 0..<next(0)` yields ONE value, not one per
          // call -- a bound that the body changes does not change the trip
          // count.
          let sv = eval(p, env, start_e)
          let ev = eval(p, env, end_e)
          let range_reads = unique_reads(p)
          let lo = int_of_value(sv.v)
          let hi = int_of_value(ev.v)
          let tainted = sv.tainted || ev.tainted
          let mut i = lo
          while (if inclusive { i <= hi } else { i < hi }) &&
                p.steps < p.max_steps {
            seed_reads(p, range_reads)
            bind_for_binders(p, env, names, VInt(i), tainted, s.span, s.id)
            let sig = exec_block(p, env, body, fn_name)
            match sig {
              BreakLoop => break
              Returned(v) => return Returned(v)
              _ => ()
            }
            i = i + 1
          }
        }
        _ => {
          let src = eval(p, env, iter)
          let src_names = unique_reads(p)
          match src.v {
            VArr(xs) => {
              let mut i = 0
              while i < xs.length() && p.steps < p.max_steps {
                seed_reads(p, src_names)
                bind_for_binders(
                  p,
                  env,
                  names,
                  xs[i],
                  src.tainted,
                  s.span,
                  s.id,
                )
                let sig = exec_block(p, env, body, fn_name)
                match sig {
                  BreakLoop => break
                  Returned(v) => return Returned(v)
                  _ => ()
                }
                i = i + 1
              }
            }
            _ => ()
          }
        }
      }
      Normal
    }
    SReturn(e) => {
      let v = match e {
        Some(x) => eval(p, env, x)
        None => clean(VUnit)
      }
      p.events.push(
        TraceEvent::new(
          EvReturn,
          fn_name,
          p.file,
          s.span.start_line,
          s.id,
          "return",
          v.v.repr(),
          v.tainted,
          p.trial,
          unique_reads(p),
        ),
      )
      Returned(v)
    }
    SBreak => BreakLoop
    SContinue => ContinueLoop
    SExpr(e) => {
      let v = eval(p, env, e)
      // The value of an expression statement is remembered by its statement
      // id, so a function body that ENDS with an expression can return it --
      // which is what MoonBit does: `fn f() -> Int { 42 }` returns 42.
      p.expr_values[s.id] = v
      Normal
    }
    SBlock(inner) => exec_block(p, env, inner, fn_name)
    STry(inner) => exec_block(p, env, inner, fn_name)
    SUnsupported(what) => {
      p.events.push(
        TraceEvent::new(
          EvUnsupported,
          fn_name,
          p.file,
          s.span.start_line,
          s.id,
          what,
          "",
          false,
          p.trial,
          s.text,
        ),
      )
      Normal
    }
  }
}

///|
/// The value of a function body that ENDS with an expression.
///
/// MoonBit gives a block the value of its last expression, so `fn f() -> Int
/// { 42 }` returns 42 and not Unit. The value was already computed while the
/// statement ran, so it is looked up by the statement's id rather than
/// evaluated a second time -- evaluating it twice would run its side effects
/// twice.
fn tail_value(p : Interp, body : Array[Stmt]) -> Val? {
  if body.length() == 0 {
    return None
  }
  let last = body[body.length() - 1]
  match last.kind {
    SExpr(_) =>
      match p.expr_values.get(last.id) {
        Some(v) => Some(v)
        None => None
      }
    _ => None
  }
}

///|
/// `inputs` is the INPUT SET to run, and it is optional: with no `inputs` the
/// function is run on the synthesized trials, exactly as before. With one, the
/// function is run on THAT input and on no other.
///
/// This is the seam the counterexample minimiser needs: a single input has to
/// be executable on its own, and the trial list cannot say which trial
/// produced a finding -- the finding carries no trial number, because the
/// finding's IDENTITY is its family, its place and its function, and the
/// evidence (which carries the observed value) changes with the input.
///
/// The published signature of this function is unchanged for a caller that
/// does not use it: the argument is optional.
pub fn run_function(
  fn_name : Func,
  funcs : Map[String, Func],
  opts : RunOptions,
  trial : Int32,
  global_values~ : Map[String, Val] = Map([]),
  ffi~ : Map[String, FfiDecl] = Map([]),
  inputs~ : Array[InputSet] = [],
) -> RunResult {
  let p = Interp::new(funcs, opts, trial, ffi)
  p.func_name = fn_name.name
  p.file = fn_name.file
  p.global_values = global_values
  let env : Map[String, Val] = Map([])
  let trials = if inputs.length() > 0 {
    inputs
  } else {
    synthesize(fn_name, opts.trials)
  }
  let mut i = 0
  let mut run = 0
  while i < trials.length() {
    let input = trials[i]
    p.trial = i
    p.steps = 0
    let n = if input.args.length() < fn_name.params.length() {
      input.args.length()
    } else {
      fn_name.params.length()
    }
    let mut j = 0
    while j < n {
      env[fn_name.params[j].name] = input.args[j]
      p.events.push(
        TraceEvent::new(
          EvSource,
          fn_name.name,
          fn_name.file,
          fn_name.span.start_line,
          0,
          fn_name.params[j].name,
          input.args[j].v.repr(),
          true,
          i,
          "parameter",
        ),
      )
      j = j + 1
    }
    p.events.push(
      TraceEvent::new(
        EvEnter,
        fn_name.name,
        fn_name.file,
        fn_name.span.start_line,
        0,
        fn_name.name,
        input.args.length().to_string(),
        true,
        i,
        "",
      ),
    )
    let sig = exec_block(p, env, fn_name.body, fn_name.name)
    let rv = match sig {
      Returned(v) => v
      _ =>
        // MoonBit: the value of a function body is the value of its LAST
        // EXPRESSION, so a body that ends in an expression returns it rather
        // than Unit.
        match tail_value(p, fn_name.body) {
          Some(v) => v
          None => clean(VUnit)
        }
    }
    observe_def(p, "<ret>", rv, fn_name.span, -1)
    run = run + 1
    i = i + 1
  }
  let skipped : Array[String] = []
  {
    events: p.events,
    findings: p.findings,
    ranges: p.ranges,
    steps: p.steps,
    trials: run,
    functions_run: if run > 0 {
      1
    } else {
      0
    },
    functions_skipped: skipped,
    max_total_steps: 0,
    stopped_by_budget: false,
    stopped_by_count: false,
  }
}

///|
pub fn run_function_by_name(
  ast : ModuleAst,
  name : String,
  opts : RunOptions,
) -> RunResult {
  let funcs : Map[String, Func] = Map([])
  for f in ast.all_funcs_including_tests() {
    if !funcs.contains(f.name) {
      funcs[f.name] = f
    }
  }
  match funcs.get(name) {
    Some(f) => {
      let (global_values, _) = eval_globals(funcs, opts, ast)
      run_function(f, funcs, opts, 0, global_values~, ffi=ffi_map(ast))
    }
    None =>
      {
        events: [],
        findings: [],
        ranges: Ranges::new(),
        steps: 0,
        trials: 0,
        functions_run: 0,
        functions_skipped: [name],
        max_total_steps: 0,
        stopped_by_budget: false,
        stopped_by_count: false,
      }
  }
}

///|
/// Run the module, entering each function as an entry point.
///
/// THE DEFAULT SCAN ENTERS EVERY FUNCTION. The bound that stops it is a
/// WORK budget -- `max_total_steps`, the module-wide number of interpreted
/// steps -- and not a count of functions. The count was the wrong shape: it
/// bounded the work sixteen times over depending on which functions came
/// first in file order, and because it was taken in file order it took whole
/// DIRECTORIES and left whole directories uninterpreted.
///
/// `max_functions` is still honoured when it is set (it is 0 by default, and
/// 0 means "no count cap"), so an explicit `--max-functions` keeps working.
///
/// `per_function` lifts BOTH bounds: every function in the module is entered,
/// with no budget at all. It is an optional argument, so the published
/// signature of this function is unchanged for a caller that does not use it.
///
/// `max_total_steps` is an optional argument too, and it defaults to
/// `DEFAULT_MAX_TOTAL_STEPS`; 0 means "no budget".
///
/// THIS IS THE MODULE-WIDE RUNNER, and it stays that one.  The budget here is
/// the MODULE's: one budget for the whole module, spent on the first packages
/// in file order.  The per-package mode -- one budget per package -- is
/// `run_module_packages`, and it is what the command-line tool uses by
/// default.  The two are kept apart on purpose: `max_total_steps` means "the
/// module's budget" in THIS function, and a caller that already passes it
/// must keep getting what it asked for.  A budget that silently became a
/// per-package one would change what the number MEANS, and no signature check
/// would catch that.
///
/// THE COST IS REAL and it was measured: on `riantr/moonbit_doubleML@0.164.64`
/// (2,529 functions) the capped run took 11.4 s and 47,835 steps, and the
/// uncapped one 123.2 s and 465,001 steps, with 2,103,552 trace events
/// instead of 243,472. The budget is what keeps a large module cheap -- and
/// unlike the count it bounds the TRACE too, because the events a step
/// produces are stable across corpora (4.5 to 5.6 events per step).
pub fn run_module(
  ast : ModuleAst,
  opts : RunOptions,
  per_function~ : Bool = false,
  max_total_steps~ : Int32 = DEFAULT_MAX_TOTAL_STEPS,
) -> RunResult {
  let (result, _packages) = run_module_packages(
    ast,
    opts,
    per_function~,
    max_total_steps~,
    // The MODULE-WIDE runner, whatever the per-package runner's own default
    // is.  `max_total_steps` is documented here as the MODULE's budget, and a
    // budget that silently became a per-package one would change what the
    // number MEANS for every caller that already uses it -- a change no
    // signature check would catch.  The per-package runner is
    // `run_module_packages`, whose default is the per-package mode.
    per_package=false,
  )
  result
}

///|
/// Run the module PACKAGE BY PACKAGE, and say what each package cost.
///
/// THE MODE, AND WHY IT EXISTS.  The step budget is a bound on the WORK, and
/// the work of a module is the work of its PACKAGES.  A module-wide budget is
/// therefore a bound on the FIRST packages in file order: it is spent on the
/// first directory, and the rest of the tree is never interpreted.  MEASURED
/// on `riantr/moonbit_static_analysis@0.5.4` (17 packages): the module-wide
/// budget entered 711 of 1,437 functions and stopped inside `src/flow`,
/// while this mode entered 1,212 and reached every other package whole.
///
/// Per package, each package gets its own budget, so a module of N packages
/// has a budget of N times the one.  What is left over in one package does
/// NOT carry over to the next: each package's budget is spent on that
/// package, and that is the point -- a package's work is its own.
///
/// THE COUNT CAP STAYS MODULE-WIDE.  `--max-functions` bounds how many
/// functions are entered, and it is OFF by default; a per-package count
/// would multiply it the same way the budget is multiplied, and a reader who
/// asked for "150 functions" did not ask for "150 functions per package".
/// So the count is module-wide and the budget is per package.
///
/// THE ENTRY ORDINAL IS THE PACKAGE-MAJOR ONE.  The scan enters the
/// functions package by package, so the n-th entry of this run is not the
/// n-th function in file order.  The ordinal labels the events; the INPUTS
/// of a function are synthesized from the function itself and not from the
/// ordinal, so the FINDINGS of the two modes are the same.
///
/// The returned breakdown is EMPTY when `per_package` is false: there was no
/// per-package run, so there is no per-package result to report.
///
/// `per_package` DEFAULTS TO TRUE: the per-package mode is the default scan.
/// It became the default because the measurement says it is the better
/// default -- a module-wide budget is a bound on the FIRST packages in file
/// order, so the rest of the tree is never interpreted, and the per-package
/// budget reaches the whole module.  MEASURED on
/// `riantr/moonbit_static_analysis@0.5.4` (17 packages): the module-wide
/// budget entered 711 of 1,437 functions, and this mode entered 1,212 and
/// reached every other package whole.
///
/// `run_module` is the module-wide runner and says so: it passes
/// `per_package=false` explicitly, because its `max_total_steps` is the
/// MODULE's budget.
///
pub fn run_module_packages(
  ast : ModuleAst,
  opts : RunOptions,
  per_function~ : Bool = false,
  max_total_steps~ : Int32 = DEFAULT_MAX_TOTAL_STEPS,
  per_package~ : Bool = true,
) -> (RunResult, Array[PackageRun]) {
  let funcs : Map[String, Func] = Map([])
  for f in ast.all_funcs_including_tests() {
    if !funcs.contains(f.name) {
      funcs[f.name] = f
    }
  }
  let all_events : Array[TraceEvent] = []
  let all_findings : Array[Finding] = []
  let ranges = Ranges::new()
  let mut total_steps = 0
  let skipped : Array[String] = []
  let mut count = 0
  let mut stopped_by_budget = false
  let mut stopped_by_count = false
  // The GROUPS: one per package in the per-package mode, and ONE group that
  // holds the whole module otherwise.  The loop below is the same either
  // way -- the difference is that the budget is read from the GROUP's
  // counter, and a group is a package.
  let names : Array[String] = if per_package {
    module_packages(ast)
  } else {
    [""]
  }
  let groups : Map[String, Array[Func]] = if per_package {
    functions_by_package(ast)
  } else {
    let one : Map[String, Array[Func]] = Map([])
    one[""] = ast.all_funcs()
    one
  }
  // The GLOBAL REGION is computed once, before any function runs: the
  // top-level bindings are constants of the module.  Its events belong to
  // the package that DECLARES them, and they are counted before the run so
  // that a package's own count includes them.
  let (global_values, global_events) = eval_globals(funcs, opts, ast)
  for e in global_events {
    all_events.push(e)
  }
  let global_counts = count_events_by_package(ast, global_events)
  // The per-package rows, one per package, in the order the packages were
  // met.
  let packages : Array[PackageRun] = []
  for pkg_name in names {
    let pkg_funcs : Array[Func] = match groups.get(pkg_name) {
      Some(g) => g
      None => []
    }
    // The budget of THIS group.  In the module-wide mode there is one group,
    // so this is the module's budget, read from the same counter as before.
    let mut pkg_steps = 0
    let mut pkg_run = 0
    let mut pkg_skipped = 0
    let mut pkg_findings = 0
    let mut pkg_events = match global_counts.get(pkg_name) {
      Some(n) => n
      None => 0
    }
    let mut pkg_stopped = false
    for f in pkg_funcs {
      if opts.entry_filter != "" && f.name != opts.entry_filter {
        continue
      }
      // The COUNT cap: an explicit bound on how many functions are entered.
      // It is OFF by default, and what stops the default scan is the budget
      // below.
      if !per_function && opts.max_functions > 0 && count >= opts.max_functions {
        skipped.push(f.name)
        stopped_by_count = true
        pkg_skipped = pkg_skipped + 1
        continue
      }
      // The STEP BUDGET: the bound on WORK.  It is checked before a function
      // is entered, so the scan overshoots it by at most one function's own
      // budget.  In the per-package mode it is the GROUP's steps that are
      // compared, so the budget is spent per package.
      if !per_function && max_total_steps > 0 && pkg_steps >= max_total_steps {
        skipped.push(f.name)
        stopped_by_budget = true
        pkg_stopped = true
        pkg_skipped = pkg_skipped + 1
        continue
      }
      if f.body.length() == 0 {
        skipped.push(f.name)
        pkg_skipped = pkg_skipped + 1
        continue
      }
      let r = run_function(
        f,
        funcs,
        opts,
        count,
        global_values~,
        ffi=ffi_map(ast),
      )
      count = count + 1
      pkg_run = pkg_run + 1
      total_steps = total_steps + r.steps
      pkg_steps = pkg_steps + r.steps
      pkg_events = pkg_events + r.events.length()
      for e in r.events {
        all_events.push(e)
      }
      for finding in r.findings {
        all_findings.push(finding)
        pkg_findings = pkg_findings + 1
      }
      ranges.merge_from(r.ranges)
    }
    if per_package {
      packages.push({
        name: pkg_name,
        functions_run: pkg_run,
        functions_skipped: pkg_skipped,
        steps: pkg_steps,
        events: pkg_events,
        findings: pkg_findings,
        stopped_by_budget: pkg_stopped,
      })
    }
  }
  (
    {
      events: all_events,
      findings: all_findings,
      ranges,
      steps: total_steps,
      trials: count,
      functions_run: count,
      functions_skipped: skipped,
      max_total_steps: if per_function {
        0
      } else {
        max_total_steps
      },
      stopped_by_budget,
      stopped_by_count,
    },
    packages,
  )
}
