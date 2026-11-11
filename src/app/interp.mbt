///|
pub(all) struct RunOptions {
  trials : Int32
  max_steps : Int32
  max_depth : Int32
  max_functions : Int32
  entry_filter : String
}

///|
pub fn RunOptions::default() -> RunOptions {
  {
    trials: 8,
    max_steps: 2000,
    max_depth: 6,
    max_functions: 120,
    entry_filter: "",
  }
}

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
  events : Array[TraceEvent]
  findings : Array[Finding]
  ranges : Ranges
  mut trial : Int32
  mut steps : Int32
  max_steps : Int32
  max_depth : Int32
  mut depth : Int32
  mut budget : Bool
  reads : Array[String]
  mut func_name : String
  mut file : String
}

///|
fn Interp::new(
  funcs : Map[String, Func],
  opts : RunOptions,
  trial : Int32,
) -> Interp {
  {
    funcs,
    events: [],
    findings: [],
    ranges: Ranges::new(),
    trial,
    steps: 0,
    max_steps: opts.max_steps,
    max_depth: opts.max_depth,
    depth: 0,
    budget: false,
    reads: [],
    func_name: "",
    file: "",
  }
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
    EName(n) => {
      p.reads.push(n)
      match env.get(n) {
        Some(v) => v
        None => clean(VUnknown)
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
    ECall(name, args) => eval_call(p, env, name, args, e.span)
    EMethod(recv, m, args) => eval_method(p, env, recv, m, args)
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
) -> Val {
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
  if name == "Array::make" || name == "FixedArray::make" || name == "Array::new" {
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
  } else if name == "Int::to_string" || name == "Double::to_string" {
    let v = if args.length() > 0 {
      eval(p, env, args[0])
    } else {
      clean(VUnknown)
    }
    Val::new(VStr(v.v.repr()), v.tainted)
  } else if name == "Int::from_string" || name == "Double::from_string" {
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
          Val::new(VUnknown, t)
        }
      None => Val::new(VUnknown, t)
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
  let env : Map[String, Val] = Map::new()
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
        p.findings.push(
          Finding::new(
            FBudget,
            p.file,
            s.span.start_line,
            fn_name,
            "execution budget exhausted; loop may be non-terminating or inputs too large",
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
            if is_literal_true(cond) && iterations >= 64 {
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
      let src = eval(p, env, iter)
      let src_names = unique_reads(p)
      match src.v {
        VArr(xs) => {
          let mut i = 0
          while i < xs.length() && p.steps < p.max_steps {
            seed_reads(p, src_names)
            bind_for_binders(p, env, names, xs[i], src.tainted, s.span, s.id)
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
      let _ = eval(p, env, e)
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
pub fn run_function(
  fn_name : Func,
  funcs : Map[String, Func],
  opts : RunOptions,
  trial : Int32,
) -> RunResult {
  let p = Interp::new(funcs, opts, trial)
  p.func_name = fn_name.name
  p.file = fn_name.file
  let env : Map[String, Val] = Map::new()
  let trials = synthesize(fn_name, opts.trials)
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
      _ => clean(VUnit)
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
  }
}

///|
pub fn run_function_by_name(
  ast : ModuleAst,
  name : String,
  opts : RunOptions,
) -> RunResult {
  let funcs : Map[String, Func] = Map::new()
  for f in ast.all_funcs_including_tests() {
    if !funcs.contains(f.name) {
      funcs[f.name] = f
    }
  }
  match funcs.get(name) {
    Some(f) => run_function(f, funcs, opts, 0)
    None =>
      {
        events: [],
        findings: [],
        ranges: Ranges::new(),
        steps: 0,
        trials: 0,
        functions_run: 0,
        functions_skipped: [name],
      }
  }
}

///|
pub fn run_module(ast : ModuleAst, opts : RunOptions) -> RunResult {
  let funcs : Map[String, Func] = Map::new()
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
  for f in ast.all_funcs() {
    if opts.entry_filter != "" && f.name != opts.entry_filter {
      continue
    }
    if count >= opts.max_functions {
      skipped.push(f.name)
      continue
    }
    if f.body.length() == 0 {
      skipped.push(f.name)
      continue
    }
    let r = run_function(f, funcs, opts, count)
    count = count + 1
    total_steps = total_steps + r.steps
    for e in r.events {
      all_events.push(e)
    }
    for finding in r.findings {
      all_findings.push(finding)
    }
    ranges.merge_from(r.ranges)
  }
  {
    events: all_events,
    findings: all_findings,
    ranges,
    steps: total_steps,
    trials: count,
    functions_run: count,
    functions_skipped: skipped,
  }
}
