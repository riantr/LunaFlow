///|
pub(all) enum AbsVal {
  ABottom
  AInt(Int32, Int32)
  ADouble(Double, Double)
  ABool(Bool, Bool)
  AStr(Array[String])
  AArr(Int32, Int32)
  ATuple(Array[AbsVal])
  ATop
}

///|
#derive(Eq)
pub(all) enum TaintMode {
  TClean
  TMaybe
  TTainted
}

///|
pub extend TaintMode with Eq::{not_equal, equal}

///|
pub fn AbsVal::code(self : AbsVal) -> String {
  match self {
    ABottom => "bottom"
    AInt(l, h) => "[" + l.to_string() + "," + h.to_string() + "]"
    ADouble(l, h) => "[" + format_double(l) + "," + format_double(h) + "]"
    ABool(t, f) =>
      if t && f {
        "{false,true}"
      } else if t {
        "{true}"
      } else if f {
        "{false}"
      } else {
        "{}"
      }
    AStr(xs) => "{" + truncate(xs.join(", "), 30) + "}"
    AArr(l, h) => "len[" + l.to_string() + "," + h.to_string() + "]"
    ATuple(xs) => "(" + xs.length().to_string() + " tuple)"
    ATop => "top"
  }
}

///|
pub fn TaintMode::join(a : TaintMode, b : TaintMode) -> TaintMode {
  match (a, b) {
    (TTainted, _) | (_, TTainted) => TTainted
    (TMaybe, _) | (_, TMaybe) => TMaybe
    _ => TClean
  }
}

///|
pub fn TaintMode::code(self : TaintMode) -> String {
  match self {
    TClean => "clean"
    TMaybe => "maybe"
    TTainted => "tainted"
  }
}

///|
pub struct AbsCell {
  v : AbsVal
  t : TaintMode
}

///|
pub fn AbsCell::new(v : AbsVal, t : TaintMode) -> AbsCell {
  { v, t, }
}

///|
pub struct AbsState {
  env : Map[String, AbsCell]
}

///|
pub fn AbsState::new() -> AbsState {
  { env: Map::new(), }
}

///|
fn abs_join_val(a : AbsVal, b : AbsVal) -> AbsVal {
  match (a, b) {
    (ABottom, x) | (x, ABottom) => x
    (AInt(al, ah), AInt(bl, bh)) =>
      AInt(if al < bl { al } else { bl }, if ah > bh { ah } else { bh })
    (ADouble(al, ah), ADouble(bl, bh)) =>
      ADouble(if al < bl { al } else { bl }, if ah > bh { ah } else { bh })
    (ABool(at, af), ABool(bt, bf)) => ABool(at || bt, af || bf)
    (AStr(xs), AStr(ys)) => {
      let out : Array[String] = []
      for x in xs {
        if !out.contains(x) && out.length() < 12 {
          out.push(x)
        }
      }
      for y in ys {
        if !out.contains(y) && out.length() < 12 {
          out.push(y)
        }
      }
      AStr(out)
    }
    (AArr(al, ah), AArr(bl, bh)) =>
      AArr(if al < bl { al } else { bl }, if ah > bh { ah } else { bh })
    _ => ATop
  }
}

///|
fn abs_join_state(a : AbsState, b : AbsState) -> AbsState {
  let out = AbsState::new()
  for pair in a.env.to_array() {
    let name = pair.0
    let ca = pair.1
    match b.env.get(name) {
      Some(cb) =>
        out.env[name] = AbsCell::new(abs_join_val(ca.v, cb.v), ca.t.join(cb.t))
      None => out.env[name] = ca
    }
  }
  for pair in b.env.to_array() {
    if !out.env.contains(pair.0) {
      out.env[pair.0] = pair.1
    }
  }
  out
}

///|
fn abs_val_equal(a : AbsVal, b : AbsVal) -> Bool {
  match (a, b) {
    (ABottom, ABottom) | (ATop, ATop) => true
    (AInt(al, ah), AInt(bl, bh)) => al == bl && ah == bh
    (ADouble(al, ah), ADouble(bl, bh)) => al == bl && ah == bh
    (ABool(at, af), ABool(bt, bf)) => at == bt && af == bf
    (AArr(al, ah), AArr(bl, bh)) => al == bl && ah == bh
    (AStr(xs), AStr(ys)) => xs.length() == ys.length() && xs == ys
    _ => false
  }
}

///|
fn abs_state_equal(a : AbsState, b : AbsState) -> Bool {
  if a.env.length() != b.env.length() {
    return false
  }
  for pair in a.env.to_array() {
    match b.env.get(pair.0) {
      Some(cb) =>
        if !abs_val_equal(pair.1.v, cb.v) || pair.1.t != cb.t {
          return false
        }
      None => return false
    }
  }
  true
}

///|
fn abs_widen(old : AbsState, next : AbsState) -> AbsState {
  let out = AbsState::new()
  for pair in next.env.to_array() {
    let name = pair.0
    let cn = pair.1
    match old.env.get(name) {
      Some(co) =>
        match (co.v, cn.v) {
          (AInt(ol, oh), AInt(nl, nh)) =>
            if nl < ol || nh > oh {
              out.env[name] = AbsCell::new(
                AInt(-1000000, 1000000),
                cn.t.join(co.t),
              )
            } else {
              out.env[name] = cn
            }
          (ADouble(ol, oh), ADouble(nl, nh)) =>
            if nl < ol || nh > oh {
              out.env[name] = AbsCell::new(
                ADouble(-1000000.0, 1000000.0),
                cn.t.join(co.t),
              )
            } else {
              out.env[name] = cn
            }
          _ =>
            out.env[name] = AbsCell::new(
              abs_join_val(co.v, cn.v),
              cn.t.join(co.t),
            )
        }
      None => out.env[name] = cn
    }
  }
  out
}

///|
pub struct AbsRange {
  mut lo : Double
  mut hi : Double
  mut seen : Int32
}

///|
pub struct AbsContext {
  fn_name : String
  file : String
  findings : Array[Finding]
  ranges : Map[String, AbsRange]
  mut steps : Int32
  max_steps : Int32
}

///|
fn add_finding(
  ctx : AbsContext,
  kind : FindingKind,
  line : Int32,
  message : String,
  confidence : Double,
  evidence : String,
) -> Unit {
  for f in ctx.findings {
    if f.kind == kind && f.line == line && f.message == message {
      return
    }
  }
  ctx.findings.push(
    Finding::new(
      kind,
      ctx.file,
      line,
      ctx.fn_name,
      message,
      "L2-abstract",
      confidence,
      evidence,
    ),
  )
}

///|
fn record_range(
  ctx : AbsContext,
  name : String,
  lo : Double,
  hi : Double,
) -> Unit {
  let key = ctx.fn_name + "::" + name
  match ctx.ranges.get(key) {
    Some(r) => {
      if lo < r.lo {
        r.lo = lo
      }
      if hi > r.hi {
        r.hi = hi
      }
      r.seen = r.seen + 1
    }
    None => ctx.ranges[key] = { lo, hi, seen: 1, }
  }
}

///|
fn bool_of_abs(v : AbsVal) -> (Bool, Bool) {
  match v {
    ABool(t, f) => (t, f)
    AInt(l, h) => (h != 0, l <= 0)
    ABottom => (false, false)
    _ => (true, true)
  }
}

///|
fn abs_cmp(
  op : BinOp,
  al : Double,
  ah : Double,
  bl : Double,
  bh : Double,
) -> (Bool, Bool) {
  match op {
    OpLt => (ah < bl, al >= bh)
    OpLe => (ah <= bl, al > bh)
    OpGt => (al > bh, ah <= bl)
    OpGe => (al >= bh, ah < bl)
    OpEq => (al == ah && bl == bh && al == bl, ah < bl || bh < al)
    OpNe => (ah < bl || bh < al, al == ah && bl == bh && al == bl)
    _ => (true, true)
  }
}

///|
fn abs_binop(op : BinOp, a : AbsCell, b : AbsCell) -> AbsCell {
  let t = a.t.join(b.t)
  match (a.v, b.v) {
    (AInt(al, ah), AInt(bl, bh)) =>
      match op {
        OpAdd => AbsCell::new(AInt(al + bl, ah + bh), t)
        OpSub => AbsCell::new(AInt(al - bh, ah - bl), t)
        OpMul =>
          AbsCell::new(
            AInt(
              min4(
                al.to_double() * bl.to_double(),
                al.to_double() * bh.to_double(),
                ah.to_double() * bl.to_double(),
                ah.to_double() * bh.to_double(),
              ).to_int(),
              max4(
                al.to_double() * bl.to_double(),
                al.to_double() * bh.to_double(),
                ah.to_double() * bl.to_double(),
                ah.to_double() * bh.to_double(),
              ).to_int(),
            ),
            t,
          )
        OpDiv =>
          if bl <= 0 && bh >= 0 {
            AbsCell::new(ATop, t)
          } else {
            AbsCell::new(AInt(al / bl, ah / bh), t)
          }
        OpMod =>
          AbsCell::new(
            AInt(
              0,
              if ah.abs() > bh.abs() {
                ah.abs() - 1
              } else {
                bh.abs() - 1
              },
            ),
            t,
          )
        OpEq => {
          let (ct, cf) = abs_cmp(
            OpEq,
            al.to_double(),
            ah.to_double(),
            bl.to_double(),
            bh.to_double(),
          )
          AbsCell::new(ABool(ct, cf), t)
        }
        OpNe => {
          let (ct, cf) = abs_cmp(
            OpNe,
            al.to_double(),
            ah.to_double(),
            bl.to_double(),
            bh.to_double(),
          )
          AbsCell::new(ABool(ct, cf), t)
        }
        OpLt | OpLe | OpGt | OpGe => {
          let (ct, cf) = abs_cmp(
            op,
            al.to_double(),
            ah.to_double(),
            bl.to_double(),
            bh.to_double(),
          )
          AbsCell::new(ABool(ct, cf), t)
        }
        OpAnd | OpOr => AbsCell::new(ABool(true, true), t)
        _ => AbsCell::new(ATop, t)
      }
    (ADouble(al, ah), ADouble(bl, bh)) =>
      match op {
        OpAdd => AbsCell::new(ADouble(al + bl, ah + bh), t)
        OpSub => AbsCell::new(ADouble(al - bh, ah - bl), t)
        OpMul =>
          AbsCell::new(
            ADouble(
              min4(al * bl, al * bh, ah * bl, ah * bh),
              max4(al * bl, al * bh, ah * bl, ah * bh),
            ),
            t,
          )
        OpDiv =>
          if bl <= 0.0 && bh >= 0.0 {
            AbsCell::new(ATop, t)
          } else {
            AbsCell::new(
              ADouble(
                min4(al / bl, al / bh, ah / bl, ah / bh),
                max4(al / bl, al / bh, ah / bl, ah / bh),
              ),
              t,
            )
          }
        OpLt | OpLe | OpGt | OpGe | OpEq | OpNe => {
          let (ct, cf) = abs_cmp(op, al, ah, bl, bh)
          AbsCell::new(ABool(ct, cf), t)
        }
        _ => AbsCell::new(ATop, t)
      }
    (AStr(xs), AStr(ys)) =>
      if op == OpAdd {
        let out : Array[String] = []
        for x in xs {
          for y in ys {
            if out.length() < 12 {
              out.push(x + y)
            }
          }
        }
        AbsCell::new(AStr(out), t)
      } else {
        AbsCell::new(ATop, t)
      }
    _ => AbsCell::new(ATop, t)
  }
}

///|
fn refine_cond(st : AbsState, cond : Expr, truth : Bool) -> AbsState {
  let out = AbsState::new()
  for pair in st.env.to_array() {
    out.env[pair.0] = pair.1
  }
  refine_into(out, cond, truth)
  out
}

///|
fn refine_into(st : AbsState, cond : Expr, truth : Bool) -> Unit {
  match cond.kind {
    EBin(OpAnd, a, b) =>
      if truth {
        refine_into(st, a, true)
        refine_into(st, b, true)
      }
    EBin(OpOr, a, b) =>
      if !truth {
        refine_into(st, a, false)
        refine_into(st, b, false)
      }
    EUn(UnNot, a) => refine_into(st, a, !truth)
    EBin(op, a, b) =>
      match (a.kind, b.kind) {
        (EName(n), EInt(c)) =>
          match st.env.get(n) {
            Some(cell) =>
              match cell.v {
                AInt(l, h) => {
                  let mut nl = l
                  let mut nh = h
                  let eff = if truth { op } else { negate_op(op) }
                  match eff {
                    OpGe => if c > nl { nl = c }
                    OpGt => if c + 1 > nl { nl = c + 1 }
                    OpLe => if c < nh { nh = c }
                    OpLt => if c - 1 < nh { nh = c - 1 }
                    OpEq => {
                      if c > nl {
                        nl = c
                      }
                      if c < nh {
                        nh = c
                      }
                    }
                    _ => ()
                  }
                  if nl <= nh {
                    st.env[n] = AbsCell::new(AInt(nl, nh), cell.t)
                  } else {
                    st.env[n] = AbsCell::new(ABottom, cell.t)
                  }
                }
                _ => ()
              }
            None => ()
          }
        (EInt(_), EName(_)) =>
          refine_into(st, Expr::new(cond.span, EBin(flip_op(op), b, a)), truth)
        _ => ()
      }
    _ => ()
  }
}

///|
fn negate_op(op : BinOp) -> BinOp {
  match op {
    OpLt => OpGe
    OpLe => OpGt
    OpGt => OpLe
    OpGe => OpLt
    OpEq => OpNe
    OpNe => OpEq
    x => x
  }
}

///|
fn flip_op(op : BinOp) -> BinOp {
  match op {
    OpLt => OpGt
    OpLe => OpGe
    OpGt => OpLt
    OpGe => OpLe
    OpEq => OpEq
    OpNe => OpNe
    x => x
  }
}

///|
fn abs_eval(ctx : AbsContext, st : AbsState, e : Expr) -> AbsCell {
  ctx.steps = ctx.steps + 1
  match e.kind {
    EInt(n) => AbsCell::new(AInt(n, n), TClean)
    EDouble(d) => AbsCell::new(ADouble(d, d), TClean)
    EBool(b) => AbsCell::new(ABool(b, b), TClean)
    EString(s) => AbsCell::new(AStr([s]), TClean)
    EName(n) =>
      match st.env.get(n) {
        Some(c) => c
        None => AbsCell::new(ATop, TClean)
      }
    EBin(OpAnd, a, b) => {
      let ca = abs_eval(ctx, st, a)
      let cb = abs_eval(ctx, st, b)
      let (at, af) = bool_of_abs(ca.v)
      let (bt, bf) = bool_of_abs(cb.v)
      AbsCell::new(ABool(at && bt, af || bf), ca.t.join(cb.t))
    }
    EBin(OpOr, a, b) => {
      let ca = abs_eval(ctx, st, a)
      let cb = abs_eval(ctx, st, b)
      let (at, af) = bool_of_abs(ca.v)
      let (bt, bf) = bool_of_abs(cb.v)
      AbsCell::new(ABool(at || bt, af && bf), ca.t.join(cb.t))
    }
    EBin(op, a, b) => {
      let ca = abs_eval(ctx, st, a)
      let cb = abs_eval(ctx, st, b)
      abs_binop(op, ca, cb)
    }
    EUn(UnNeg, a) => {
      let ca = abs_eval(ctx, st, a)
      match ca.v {
        AInt(l, h) => AbsCell::new(AInt(-h, -l), ca.t)
        ADouble(l, h) => AbsCell::new(ADouble(-h, -l), ca.t)
        _ => AbsCell::new(ATop, ca.t)
      }
    }
    EUn(UnNot, a) => {
      let ca = abs_eval(ctx, st, a)
      let (t, f) = bool_of_abs(ca.v)
      AbsCell::new(ABool(f, t), ca.t)
    }
    EIndex(base, idx) => {
      let cb = abs_eval(ctx, st, base)
      let ci = abs_eval(ctx, st, idx)
      if ci.t != TClean {
        add_finding(
          ctx,
          FTaintIndex,
          e.span.start_line,
          "tainted value may reach an array index / buffer offset",
          0.6,
          base.render() + "[" + ci.v.code() + "]",
        )
      }
      match (cb.v, ci.v) {
        (AArr(lo_len, hi_len), AInt(il, ih)) =>
          if il < 0 || ih >= lo_len {
            let definite = ih < 0 || il >= hi_len
            add_finding(
              ctx,
              FRangeViolation,
              e.span.start_line,
              if definite {
                "abstract interval proves the index is out of bounds"
              } else {
                "index may be out of bounds on some inputs"
              },
              if definite {
                0.95
              } else {
                0.6
              },
              "index [" +
              il.to_string() +
              "," +
              ih.to_string() +
              "] vs length [" +
              lo_len.to_string() +
              "," +
              hi_len.to_string() +
              "]",
            )
          }
        _ => ()
      }
      AbsCell::new(ATop, cb.t.join(ci.t))
    }
    ECall(f, args) => {
      let cells : Array[AbsCell] = []
      let mut t = TClean
      for a in args {
        let c = abs_eval(ctx, st, a)
        cells.push(c)
        t = t.join(c.t)
      }
      if f == "Array::make" || f == "FixedArray::make" {
        if cells.length() > 0 {
          let size = cells[0]
          if size.t != TClean {
            add_finding(
              ctx,
              FTaintAlloc,
              e.span.start_line,
              "tainted value may control an allocation size",
              0.6,
              f + "(" + size.v.code() + ")",
            )
          }
          match size.v {
            AInt(l, h) => {
              if l < 0 {
                add_finding(
                  ctx,
                  FRangeViolation,
                  e.span.start_line,
                  "allocation size may be negative",
                  0.9,
                  "size [" + l.to_string() + "," + h.to_string() + "]",
                )
              }
              AbsCell::new(
                AArr(if l < 0 { 0 } else { l }, if h < 0 { 0 } else { h }),
                t,
              )
            }
            _ => AbsCell::new(AArr(0, 64), t)
          }
        } else {
          AbsCell::new(AArr(0, 0), t)
        }
      } else if f == "abort" || f == "panic" || f == "fail" {
        if t != TClean {
          add_finding(
            ctx,
            FUnsupported,
            e.span.start_line,
            "tainted value may reach abort/panic",
            0.5,
            f,
          )
        }
        AbsCell::new(ATop, t)
      } else if f == "require" || f == "assert_true" {
        if cells.length() > 0 {
          let (ct, cf) = bool_of_abs(cells[0].v)
          if cf {
            add_finding(
              ctx,
              FRangeViolation,
              e.span.start_line,
              "assertion may fail on some inputs",
              0.6,
              "assert may be false",
            )
          }
          ignore(ct)
        }
        AbsCell::new(ATop, t)
      } else {
        AbsCell::new(ATop, t)
      }
    }
    EMethod(recv, m, args) => {
      let cr = abs_eval(ctx, st, recv)
      let mut t = cr.t
      for a in args {
        let c = abs_eval(ctx, st, a)
        t = t.join(c.t)
      }
      if m == "length" {
        match cr.v {
          AArr(l, h) => AbsCell::new(AInt(l, h), t)
          AStr(xs) => {
            let mut lo = 999
            let mut hi = 0
            for x in xs {
              if x.length() < lo {
                lo = x.length()
              }
              if x.length() > hi {
                hi = x.length()
              }
            }
            AbsCell::new(AInt(lo, hi), t)
          }
          _ => AbsCell::new(ATop, t)
        }
      } else if m == "push" {
        match recv.kind {
          EName(n) =>
            match st.env.get(n) {
              Some(cell) =>
                match cell.v {
                  AArr(l, h) =>
                    st.env[n] = AbsCell::new(AArr(l + 1, h + 1), cell.t)
                  _ => ()
                }
              None => ()
            }
          _ => ()
        }
        AbsCell::new(ATop, t)
      } else if m == "to_string" {
        AbsCell::new(AStr(["<string>"]), t)
      } else {
        AbsCell::new(ATop, t)
      }
    }
    EField(base, _) => {
      let cb = abs_eval(ctx, st, base)
      AbsCell::new(ATop, cb.t)
    }
    EArray(xs) => {
      let mut t = TClean
      for x in xs {
        t = t.join(abs_eval(ctx, st, x).t)
      }
      AbsCell::new(AArr(xs.length(), xs.length()), t)
    }
    ETuple(xs) => {
      let vals : Array[AbsVal] = []
      let mut t = TClean
      for x in xs {
        let c = abs_eval(ctx, st, x)
        vals.push(c.v)
        t = t.join(c.t)
      }
      AbsCell::new(ATuple(vals), t)
    }
    EUnknown(_) => AbsCell::new(ATop, TClean)
  }
}

///|
fn abs_block(ctx : AbsContext, st : AbsState, stmts : Array[Stmt]) -> AbsState {
  let mut cur = st
  for s in stmts {
    if ctx.steps > ctx.max_steps {
      add_finding(
        ctx,
        FBudget,
        s.span.start_line,
        "abstract interpretation step budget exhausted",
        0.5,
        "L2 budget",
      )
      return cur
    }
    cur = abs_stmt(ctx, cur, s)
  }
  cur
}

///|
fn abs_stmt(ctx : AbsContext, st : AbsState, s : Stmt) -> AbsState {
  ctx.steps = ctx.steps + 1
  match s.kind {
    SLet(n, _, e) => {
      let c = abs_eval(ctx, st, e)
      let out = copy_state(st)
      out.env[n] = c
      record_abs_range(ctx, n, c)
      out
    }
    SAssign(lhs, e) => {
      let c = abs_eval(ctx, st, e)
      match lhs.kind {
        EName(n) => {
          let out = copy_state(st)
          out.env[n] = c
          record_abs_range(ctx, n, c)
          out
        }
        _ => st
      }
    }
    SAssignOp(op, lhs, e) =>
      match lhs.kind {
        EName(n) => {
          let cur = match st.env.get(n) {
            Some(c) => c
            None => AbsCell::new(ATop, TClean)
          }
          let c = abs_binop(op, cur, abs_eval(ctx, st, e))
          let out = copy_state(st)
          out.env[n] = c
          record_abs_range(ctx, n, c)
          out
        }
        _ => st
      }
    SIf(cond, a, b) => {
      let cc = abs_eval(ctx, st, cond)
      let (may_true, may_false) = bool_of_abs(cc.v)
      let sa = refine_cond(st, cond, true)
      let sb = refine_cond(st, cond, false)
      let ra = if may_true {
        abs_block(ctx, sa, a)
      } else {
        add_finding(
          ctx,
          FUnreachable,
          s.span.start_line,
          "then-branch is unreachable for the abstract input set",
          0.8,
          cond.render(),
        )
        AbsState::new()
      }
      let rb = if may_false {
        abs_block(ctx, sb, b)
      } else {
        add_finding(
          ctx,
          FUnreachable,
          s.span.start_line,
          "else-branch is unreachable for the abstract input set",
          0.8,
          cond.render(),
        )
        AbsState::new()
      }
      if may_true && may_false {
        abs_join_state(ra, rb)
      } else if may_true {
        ra
      } else {
        rb
      }
    }
    SWhile(cond, body) => {
      let mut cur = st
      let mut iter = 0
      let mut last_cond = AbsCell::new(ABool(true, true), TClean)
      while iter < 6 {
        last_cond = abs_eval(ctx, cur, cond)
        let (may_true, _) = bool_of_abs(last_cond.v)
        if !may_true {
          break
        }
        let body_in = refine_cond(cur, cond, true)
        if last_cond.t != TClean {
          implicit_abs_taint(body_in, cond)
        }
        let after = abs_block(ctx, body_in, body)
        let next = abs_join_state(cur, after)
        let widened = if iter >= 3 { abs_widen(cur, next) } else { next }
        if abs_state_equal(widened, cur) {
          cur = widened
          break
        }
        cur = widened
        iter = iter + 1
      }
      let (may_true, may_false) = bool_of_abs(last_cond.v)
      if may_true && !may_false && !has_break_or_return(body) {
        add_finding(
          ctx,
          FInfinite,
          s.span.start_line,
          "loop condition is true for the whole abstract input set and has no break",
          0.7,
          cond.render(),
        )
      }
      refine_cond(cur, cond, false)
    }
    SFor(n, init, cond, step, body) => {
      let c = abs_eval(ctx, st, init)
      let mut cur = copy_state(st)
      cur.env[n] = c
      let mut iter = 0
      while iter < 6 {
        let cc = abs_eval(ctx, cur, cond)
        let (may_true, _) = bool_of_abs(cc.v)
        if !may_true {
          break
        }
        let body_in = refine_cond(cur, cond, true)
        let after = abs_block(ctx, body_in, body)
        let stepped = copy_state(after)
        ignore(abs_eval(ctx, stepped, step))
        let next = abs_join_state(cur, stepped)
        let widened = if iter >= 3 { abs_widen(cur, next) } else { next }
        if abs_state_equal(widened, cur) {
          break
        }
        cur = widened
        iter = iter + 1
      }
      refine_cond(cur, cond, false)
    }
    SForIn(names, iter, body) => {
      let ci = abs_eval(ctx, st, iter)
      let cur = copy_state(st)
      for n in names {
        cur.env[n] = AbsCell::new(ATop, ci.t)
      }
      let after = abs_block(ctx, cur, body)
      abs_join_state(cur, after)
    }
    SReturn(e) => {
      match e {
        Some(x) => ignore(abs_eval(ctx, st, x))
        None => ()
      }
      st
    }
    SExpr(e) => {
      ignore(abs_eval(ctx, st, e))
      st
    }
    SBlock(inner) | STry(inner) => abs_block(ctx, st, inner)
    SUnsupported(_) => st
    _ => st
  }
}

///|
fn record_abs_range(ctx : AbsContext, n : String, c : AbsCell) -> Unit {
  match c.v {
    AInt(l, h) => record_range(ctx, n, l.to_double(), h.to_double())
    ADouble(l, h) => record_range(ctx, n, l, h)
    _ => ()
  }
}

///|
fn copy_state(st : AbsState) -> AbsState {
  let out = AbsState::new()
  for pair in st.env.to_array() {
    out.env[pair.0] = pair.1
  }
  out
}

///|
fn implicit_abs_taint(st : AbsState, cond : Expr) -> Unit {
  let names : Array[String] = []
  collect_names(cond, names)
  for n in names {
    match st.env.get(n) {
      Some(c) =>
        match c.v {
          AInt(_, _) | ADouble(_, _) => st.env[n] = AbsCell::new(c.v, TMaybe)
          _ => ()
        }
      None => ()
    }
  }
}

///|
fn collect_names(e : Expr, out : Array[String]) -> Unit {
  match e.kind {
    EName(n) => if !out.contains(n) { out.push(n) }
    EBin(_, a, b) => {
      collect_names(a, out)
      collect_names(b, out)
    }
    EUn(_, a) => collect_names(a, out)
    EIndex(a, b) => {
      collect_names(a, out)
      collect_names(b, out)
    }
    EMethod(a, _, args) => {
      collect_names(a, out)
      for x in args {
        collect_names(x, out)
      }
    }
    ECall(_, args) =>
      for x in args {
        collect_names(x, out)
      }
    EField(a, _) => collect_names(a, out)
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        collect_names(x, out)
      }
    _ => ()
  }
}

///|
pub struct AbsResult {
  findings : Array[Finding]
  ranges : Map[String, AbsRange]
  functions : Int32
  steps : Int32
  iterations : Int32
}

///|
fn initial_cell(ty : String) -> AbsCell {
  if ty.contains("Array") || ty.contains("FixedArray") {
    AbsCell::new(AArr(0, 64), TTainted)
  } else if ty.contains("Bool") {
    AbsCell::new(ABool(true, true), TTainted)
  } else if ty.contains("Double") {
    AbsCell::new(ADouble(-1000000.0, 1000000.0), TTainted)
  } else if ty.contains("String") || ty.contains("Char") {
    AbsCell::new(AStr(["", "abc", "../../etc/passwd"]), TTainted)
  } else if ty.contains("Int") || ty.contains("UInt") || ty.contains("Byte") {
    AbsCell::new(AInt(-1000000, 1000000), TTainted)
  } else {
    AbsCell::new(ATop, TTainted)
  }
}

///|
pub fn run_abstract(
  ast : ModuleAst,
  max_functions : Int32,
  max_steps : Int32,
) -> AbsResult {
  let findings : Array[Finding] = []
  let ranges : Map[String, AbsRange] = Map::new()
  let mut steps = 0
  let mut count = 0
  for f in ast.all_funcs() {
    if count >= max_functions {
      break
    }
    if f.body.length() == 0 {
      continue
    }
    let ctx : AbsContext = {
      fn_name: f.name,
      file: f.file,
      findings,
      ranges,
      steps: 0,
      max_steps,
    }
    let st = AbsState::new()
    for p in f.params {
      st.env[p.name] = initial_cell(p.ty)
      record_abs_range(ctx, p.name, st.env[p.name])
    }
    ignore(abs_block(ctx, st, f.body))
    steps = steps + ctx.steps
    count = count + 1
  }
  { findings, ranges, functions: count, steps, iterations: 6, }
}
