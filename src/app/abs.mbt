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
  // A length bound is a RELATION between two names, and a relation survives
  // a join only when it holds on both sides.
  prune_length_bounds(out, a, b)
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
              // The WIDENING: the bound that moved goes to the top, and the
              // bound that did not stays where it was.
              //
              // Widening BOTH ends threw away what the loop had already
              // proved: a counter that starts at zero and only goes up lost
              // its lower bound, so an index that cannot be negative became
              // one that might be -- and the relation that says the index is
              // below the array's length could not be used.
              let lo = if nl < ol { -1000000 } else { ol }
              let hi = if nh > oh { 1000000 } else { oh }
              out.env[name] = AbsCell::new(AInt(lo, hi), cn.t.join(co.t))
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
  /// The module's GLOBAL REGION: the abstract value of each top-level
  /// binding. A name that is not local may still be a global.
  globals : Map[String, AbsCell]
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
    // A comparison of two intervals: it may hold, and it may not, and the
    // question is whether there is a VALUE of each interval for which it
    // does.
    //
    // `a < b` can hold when the smallest `a` is below the largest `b`, and
    // it can fail when the largest `a` reaches the smallest `b`. This used
    // to ask for the intervals to be SEPARATED -- all of `a` below all of
    // `b` for the comparison to hold, and all of `a` above all of `b` for
    // it to fail -- and two intervals that OVERLAP were then neither: the
    // comparison was impossible, both branches were reported as
    // unreachable, and the code after them was analysed as dead.
    //
    // `x < 0` with `x` in `[-1000000, 1000000]` is the shape that paid for
    // it: the intervals overlap, so the comparison can hold and can fail,
    // and the analyzer has to say so.
    OpLt => (al < bh, ah >= bl)
    OpLe => (al <= bh, ah > bl)
    OpGt => (ah > bl, al <= bh)
    OpGe => (ah >= bl, al < bh)
    // The two intervals OVERLAP when there is a value in both, and they can
    // DIFFER unless they are the same single point.
    //
    // This used to read "equal" as "both are the same single point" and
    // "different" as "the intervals do not overlap at all". Two intervals
    // that overlap but are not single points -- `x == 0` with `x` in
    // `[0, 64]` -- were then neither equal nor different, so the condition
    // was ABOTTOM: BOTH branches were reported as unreachable, and the code
    // after them was analysed as dead. `x.length() == 0` is that shape, and
    // it is how an empty array is tested.
    OpEq => (al <= bh && bl <= ah, al != ah || bl != bh || al != bl)
    OpNe => (al != ah || bl != bh || al != bl, al <= bh && bl <= ah)
    _ => (true, true)
  }
}

///|
fn abs_binop(
  ctx : AbsContext,
  eva : EvaState,
  op : BinOp,
  a_expr : Expr,
  b_expr : Expr,
  a : AbsCell,
  b : AbsCell,
) -> AbsCell {
  let t = a.t.join(b.t)
  match (a.v, b.v) {
    (AInt(al, ah), AInt(bl, bh)) =>
      match op {
        OpAdd => {
          eva_check_overflow(ctx, eva, op, a_expr, b_expr, al, ah, bl, bh)
          let (lo, hi) = eva_clamp32(
            al.to_int64() + bl.to_int64(),
            ah.to_int64() + bh.to_int64(),
          )
          AbsCell::new(AInt(lo, hi), t)
        }
        OpSub => {
          eva_check_overflow(ctx, eva, op, a_expr, b_expr, al, ah, bl, bh)
          let (lo, hi) = eva_clamp32(
            al.to_int64() - bh.to_int64(),
            ah.to_int64() - bl.to_int64(),
          )
          AbsCell::new(AInt(lo, hi), t)
        }
        OpMul => {
          eva_check_overflow(ctx, eva, op, a_expr, b_expr, al, ah, bl, bh)
          let p1 = al.to_int64() * bl.to_int64()
          let p2 = al.to_int64() * bh.to_int64()
          let p3 = ah.to_int64() * bl.to_int64()
          let p4 = ah.to_int64() * bh.to_int64()
          let (lo, hi) = eva_clamp32(
            min4i(p1, p2, p3, p4),
            max4i(p1, p2, p3, p4),
          )
          AbsCell::new(AInt(lo, hi), t)
        }
        OpDiv => {
          eva_check_divzero(ctx, al, ah, bl, bh, a_expr.span.start_line)
          if bl <= 0 && bh >= 0 {
            AbsCell::new(ATop, t)
          } else {
            AbsCell::new(AInt(al / bl, ah / bh), t)
          }
        }
        OpMod => {
          eva_check_divzero(ctx, al, ah, bl, bh, a_expr.span.start_line)
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
        }
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
    EBin(op, a, b) => {
      let eff = if truth { op } else { negate_op(op) }
      match (a.kind, b.kind) {
        (EName(n), EInt(c)) =>
          match st.env.get(n) {
            Some(cell) =>
              match cell.v {
                AInt(l, h) => {
                  let mut nl = l
                  let mut nh = h
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
        (EMethod(recv, m, _), EInt(c)) =>
          // A COMPARISON WITH A LENGTH: `x.length() == 1`. The number is a
          // bound on the array's length, so the array's length is narrowed.
          if m == "length" {
            match recv.kind {
              EName(arr) => refine_array_length(st, arr, eff, c)
              _ => ()
            }
          }
        (EInt(c), EMethod(recv, m, _)) =>
          if m == "length" {
            match recv.kind {
              EName(arr) => refine_array_length(st, arr, flip_op(eff), c)
              _ => ()
            }
          }
        (EName(n), EMethod(recv, m, _)) =>
          // A COMPARISON WITH A LENGTH, the other way round: `i < xs.length()`.
          // The index is below that array's length, and that is a relation
          // the intervals cannot hold -- so it is kept as its own fact.
          //
          // `eff` is `OpLt` for the comparison itself and for the FALSE side
          // of its opposite: `if i >= xs.length() { return }` leaves
          // `i < xs.length()` behind. `OpLe` is not enough -- an index AT
          // the length is out of bounds.
          if m == "length" && eff == OpLt {
            record_length_bound(st, n, recv.render())
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// The array whose length this expression is BELOW, and by how much.
///
/// `xs.length() - 1` is one below the length of `xs`, so a value that holds
/// it is inside the array -- as long as the array is not empty and the
/// constant is at least one. A constant below one would put the value AT
/// the length, which is out of bounds.
fn length_bound_source(e : Expr) -> (String, Int32)? {
  match e.kind {
    EBin(OpSub, lhs, rhs) =>
      match rhs.kind {
        EInt(c) =>
          if c >= 1 {
            match lhs.kind {
              EMethod(recv, m, _) =>
                if m == "length" {
                  Some((recv.render(), c))
                } else {
                  None
                }
              _ => None
            }
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Does this assignment keep the length bound of the name it assigns?
///
/// `i = i - 1` cannot push the index past the end of the array it is below,
/// so the relation that says the index is below that length still holds.
/// Any other assignment may give the index a new value, and the relation
/// is dropped.
fn assignment_keeps_bound(e : Expr, name : String) -> Bool {
  match e.kind {
    EBin(OpSub, lhs, rhs) =>
      match rhs.kind {
        EInt(k) =>
          if k >= 0 {
            match lhs.kind {
              EName(n) => n == name
              _ => false
            }
          } else {
            false
          }
        _ => false
      }
    _ => false
  }
}

///|
/// Is this index DERIVED FROM the length of the array it indexes?
///
/// `xs[xs.length() - 1]` is the last element, and it is in bounds whenever
/// the array is not empty. The two intervals -- the index's and the array's
/// length's -- are independent of one another, so the comparison of them
/// cannot see that: the index's upper bound is the length's upper bound
/// less one, and the length's lower bound may be zero, so the two look like
/// they may not match.
///
/// The relation is the reason, so it is read from the EXPRESSION: the index
/// is the array's own length less a constant. The constant must be at least
/// one -- less than one would put the index AT the length, which is out of
/// bounds -- and the array must be known to hold at least that many
/// elements, so the index is at least zero.
fn index_is_length_relative(base : Expr, idx : Expr, lo_len : Int32) -> Bool {
  match length_bound_source(idx) {
    Some((src, c)) => src == base.render() && lo_len >= c
    None => false
  }
}

///|
/// Narrow an ARRAY's LENGTH from a comparison of its length with a number.
///
/// `x.length() == 1` says the array has exactly one element, and
/// `x.length() != 1` says it has any number but one. The interval domain
/// cannot hold a hole, so the second one only narrows the interval at its
/// ends -- and it is the `==` that carries the weight: `if x.length() != 1
/// { return }` leaves the code after it with an array of exactly one
/// element, and an index into that array is in bounds.
fn refine_array_length(
  st : AbsState,
  arr : String,
  op : BinOp,
  c : Int32,
) -> Unit {
  match st.env.get(arr) {
    Some(cell) =>
      match cell.v {
        AArr(l, h) => {
          let mut nl = l
          let mut nh = h
          match op {
            OpEq => {
              nl = c
              nh = c
            }
            OpNe => {
              if c == l {
                nl = l + 1
              }
              if c == h {
                nh = h - 1
              }
            }
            OpLt => if c - 1 < nh { nh = c - 1 }
            OpLe => if c < nh { nh = c }
            OpGt => if c + 1 > nl { nl = c + 1 }
            OpGe => if c > nl { nl = c }
            _ => ()
          }
          if nl <= nh {
            st.env[arr] = AbsCell::new(AArr(nl, nh), cell.t)
          } else {
            st.env[arr] = AbsCell::new(ABottom, cell.t)
          }
        }
        _ => ()
      }
    None => ()
  }
}

///|
/// Does this branch END by returning?
///
/// The shape that matters is `if cond { return }`: the code after the `if`
/// is reached only when the condition is false, so the state there is the
/// FALSE branch's state -- refined by the condition -- and not a join with a
/// branch that left the function.
///
/// A branch that returns in the MIDDLE is not enough: the code after that
/// return is unreachable, but the code after the `if` is still reached from
/// the other branch, and the join is the right answer there.
fn branch_returns(stmts : Array[Stmt]) -> Bool {
  if stmts.length() == 0 {
    return false
  }
  let last = stmts[stmts.length() - 1]
  match last.kind {
    SReturn(_) => true
    SBlock(inner) => branch_returns(inner)
    SIf(_, a, b) => branch_returns(a) && branch_returns(b)
    _ => false
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
fn abs_eval(
  ctx : AbsContext,
  st : AbsState,
  eva : EvaState,
  e : Expr,
) -> AbsCell {
  ctx.steps = ctx.steps + 1
  match e.kind {
    EInt(n) => AbsCell::new(AInt(n, n), TClean)
    EDouble(d) => AbsCell::new(ADouble(d, d), TClean)
    EBool(b) => AbsCell::new(ABool(b, b), TClean)
    EString(s) => AbsCell::new(AStr([s]), TClean)
    EBytes(s) => AbsCell::new(AStr([s]), TClean)
    EName(n) =>
      match st.env.get(n) {
        Some(c) => c
        None =>
          // Not a local: it may be a GLOBAL, whose abstract value was
          // computed once for the whole module.
          match ctx.globals.get(n) {
            Some(c) => c
            None => AbsCell::new(ATop, TClean)
          }
      }
    EBin(OpAnd, a, b) => {
      let ca = abs_eval(ctx, st, eva, a)
      let cb = abs_eval(ctx, st, eva, b)
      let (at, af) = bool_of_abs(ca.v)
      let (bt, bf) = bool_of_abs(cb.v)
      AbsCell::new(ABool(at && bt, af || bf), ca.t.join(cb.t))
    }
    EBin(OpOr, a, b) => {
      let ca = abs_eval(ctx, st, eva, a)
      let cb = abs_eval(ctx, st, eva, b)
      let (at, af) = bool_of_abs(ca.v)
      let (bt, bf) = bool_of_abs(cb.v)
      AbsCell::new(ABool(at || bt, af && bf), ca.t.join(cb.t))
    }
    EBin(op, a, b) => {
      let ca = abs_eval(ctx, st, eva, a)
      let cb = abs_eval(ctx, st, eva, b)
      abs_binop(ctx, eva, op, a, b, ca, cb)
    }
    EUn(UnNeg, a) => {
      let ca = abs_eval(ctx, st, eva, a)
      match ca.v {
        AInt(l, h) => AbsCell::new(AInt(-h, -l), ca.t)
        ADouble(l, h) => AbsCell::new(ADouble(-h, -l), ca.t)
        _ => AbsCell::new(ATop, ca.t)
      }
    }
    EUn(UnNot, a) => {
      let ca = abs_eval(ctx, st, eva, a)
      let (t, f) = bool_of_abs(ca.v)
      AbsCell::new(ABool(f, t), ca.t)
    }
    EIndex(base, idx) => {
      let cb = abs_eval(ctx, st, eva, base)
      let ci = abs_eval(ctx, st, eva, idx)
      // The container must be KNOWN to be an array. The finding claims an
      // ARRAY index or a BUFFER offset, and a container whose type the
      // analyzer cannot see may well be a MAP -- where the index is a KEY:
      // a key cannot be out of bounds, and it is not an offset that
      // untrusted input chose.
      //
      // The analyzer reads a container's type from its DECLARED type (a
      // parameter or a local) or from the literal it was built from. A FIELD
      // of a struct is opaque to it -- the frontend does not carry a struct's
      // field types -- so a claim about a field's container would be a claim
      // about something the analyzer cannot see. The dynamic layer sees the
      // container's RUNTIME type, and it is the layer that files the
      // witnessed claim.
      let is_array = match cb.v {
        AArr(_, _) => true
        _ => false
      }
      // An index that is PROVABLY inside the array it indexes is not a
      // risk: not an out-of-bounds access, and not an offset that untrusted
      // input chose.
      let arr_lo = match cb.v {
        AArr(l, _) => l
        _ => 0
      }
      let bounded = match ci.v {
        AInt(il, _) =>
          index_is_bounded_by(st, base, idx, il) ||
          index_is_length_relative(base, idx, arr_lo)
        _ => false
      }
      if ci.t != TClean && is_array && !bounded {
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
          if !bounded && !index_is_length_relative(base, idx, lo_len) {
            eva_check_index_oob(ctx, il, ih, lo_len, hi_len, e.span.start_line)
          }
        _ => ()
      }
      // An element of an UNINITIALIZED array is a different defect from an
      // out-of-bounds one: the index is in range and the value is still
      // indeterminate. MoonBit does not panic on it.
      match (cb.v, ci.v) {
        (_, AInt(il, ih)) =>
          eva_check_uninit_read(ctx, eva, base, idx, il, ih, e.span.start_line)
        _ => ()
      }
      AbsCell::new(ATop, cb.t.join(ci.t))
    }
    ESlice(base, start, end) => {
      let cb = abs_eval(ctx, st, eva, base)
      let cs = match start {
        Some(x) => abs_eval(ctx, st, eva, x)
        None => AbsCell::new(AInt(0, 0), TClean)
      }
      let ce = match end {
        Some(x) => abs_eval(ctx, st, eva, x)
        None => AbsCell::new(AInt(0, 0), TClean)
      }
      // A slice is clamped by the runtime, so there is no out-of-bounds claim
      // here the way there is for an index. The slice carries the taint of
      // its parts, and that is all that is claimed.
      AbsCell::new(ATop, cb.t.join(cs.t).join(ce.t))
    }
    ECall(f, args) => {
      let cells : Array[AbsCell] = []
      let mut t = TClean
      for a in args {
        let c = abs_eval(ctx, st, eva, a)
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
      let cr = abs_eval(ctx, st, eva, recv)
      let mut t = cr.t
      let arg_cells : Array[AbsCell] = []
      for a in args {
        let c = abs_eval(ctx, st, eva, a)
        arg_cells.push(c)
        t = t.join(c.t)
      }
      // The EVOLVED VALUE ANALYSIS checks: what the RECEIVER IS USED FOR.
      // Each one is a question about the use of a value, not about its range.
      if m == "unwrap" {
        // `None.unwrap()` is MoonBit's null dereference: it panics.
        eva_check_none_deref(ctx, eva, recv, e.span.start_line)
      } else if m == "to_int" || m == "to_int64" {
        // `Double::to_int` SATURATES: a value outside the target's range
        // silently becomes the bound, and a NaN becomes 0.
        match cr.v {
          ADouble(lo, hi) =>
            eva_check_invalid_cast(ctx, m, lo, hi, e.span.start_line)
          _ => ()
        }
      } else if m == "set" && arg_cells.length() > 0 {
        // A write into an uninitialized array.
        match arg_cells[0].v {
          AInt(k, k2) => if k == k2 { eva_note_uninit_set(eva, recv, k) }
          _ => ()
        }
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
      let cb = abs_eval(ctx, st, eva, base)
      AbsCell::new(ATop, cb.t)
    }
    EArray(xs) => {
      let mut t = TClean
      for x in xs {
        t = t.join(abs_eval(ctx, st, eva, x).t)
      }
      AbsCell::new(AArr(xs.length(), xs.length()), t)
    }
    ETuple(xs) => {
      let vals : Array[AbsVal] = []
      let mut t = TClean
      for x in xs {
        let c = abs_eval(ctx, st, eva, x)
        vals.push(c.v)
        t = t.join(c.t)
      }
      AbsCell::new(ATuple(vals), t)
    }
    EFn(_, _) => AbsCell::new(ATop, TClean)
    ERange(_, _, _) =>
      // A RANGE is not a value: the toolchain says "Range operators are
      // currently only supported in `for .. in` loops". The `for` loop reads
      // its own range, so a range that reaches here was used somewhere it
      // cannot be used.
      AbsCell::new(ATop, TClean)
    EUnknown(_) => AbsCell::new(ATop, TClean)
  }
}

///|
fn abs_block(
  ctx : AbsContext,
  st : AbsState,
  eva : EvaState,
  stmts : Array[Stmt],
) -> AbsState {
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
    cur = abs_stmt(ctx, cur, eva, s)
  }
  cur
}

///|
fn abs_stmt(
  ctx : AbsContext,
  st : AbsState,
  eva : EvaState,
  s : Stmt,
) -> AbsState {
  ctx.steps = ctx.steps + 1
  match s.kind {
    SLet(n, ty, e) => {
      let c = abs_eval(ctx, st, eva, e)
      let out = copy_state(st)
      out.env[n] = c
      drop_length_bounds(out, n)
      // A value that is BELOW a length is inside that array.
      match length_bound_source(e) {
        Some((src, _)) => record_length_bound(out, n, src)
        None => ()
      }
      record_abs_range(ctx, n, c)
      // The EVA facts for a binding. The declared type wins over the
      // expression's own type, because the annotation is what the author
      // wrote and the inference is the analyzer's guess.
      eva_bind(eva, n, ty, e)
      out
    }
    SAssign(lhs, e) => {
      let c = abs_eval(ctx, st, eva, e)
      match lhs.kind {
        EName(n) => {
          let out = copy_state(st)
          out.env[n] = c
          // An index that only goes DOWN keeps the relation that says it is
          // below the array's length; any other assignment drops it.
          if !assignment_keeps_bound(e, n) {
            drop_length_bounds(out, n)
          }
          // A value that is BELOW a length is inside that array.
          match length_bound_source(e) {
            Some((src, _)) => record_length_bound(out, n, src)
            None => ()
          }
          record_abs_range(ctx, n, c)
          eva_bind(eva, n, "", e)
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
          let c = abs_binop(
            ctx,
            eva,
            op,
            lhs,
            e,
            cur,
            abs_eval(ctx, st, eva, e),
          )
          let out = copy_state(st)
          out.env[n] = c
          record_abs_range(ctx, n, c)
          out
        }
        _ => st
      }
    SIf(cond, a, b) => {
      let cc = abs_eval(ctx, st, eva, cond)
      let (may_true, may_false) = bool_of_abs(cc.v)
      let sa = refine_cond(st, cond, true)
      let sb = refine_cond(st, cond, false)
      // The EVA facts are FLOW-SENSITIVE, so the two branches are analysed
      // from the same starting facts and the facts that come out of them are
      // JOINED. Without the join a name that is None on one branch would
      // stay None after the `if`, and the idiomatic
      //
      //     let mut x = None
      //     if c { x = Some(v) } else { x = Some(w) }
      //     x.unwrap()
      //
      // would be reported as a None dereference when it is not one.
      let snap = eva_copy(eva)
      // The UNREACHABLE finding says that a branch is not taken for the
      // abstract input set. Inside a LOOP that is a claim about one
      // iteration: the loop's state changes between iterations, so a branch
      // that is unreachable in the first one may be reached in the second.
      //
      //   let mut i = 0
      //   while i < xs.length() {
      //     if i > 0 { ... }   // unreachable in the first iteration only
      //     i = i + 1
      //   }
      //
      // So the finding is filed outside a loop body, and inside one the
      // CFG's own unreachable-statement finding is what the reader gets.
      let in_loop = eva.loop_depth > 0
      let ra = if may_true {
        abs_block(ctx, sa, eva, a)
      } else {
        if !in_loop {
          add_finding(
            ctx,
            FUnreachable,
            s.span.start_line,
            "then-branch is unreachable for the abstract input set",
            0.8,
            cond.render(),
          )
        }
        AbsState::new()
      }
      let after_a = eva_copy(eva)
      eva_assign(eva, snap)
      let rb = if may_false {
        abs_block(ctx, sb, eva, b)
      } else {
        if !in_loop {
          add_finding(
            ctx,
            FUnreachable,
            s.span.start_line,
            "else-branch is unreachable for the abstract input set",
            0.8,
            cond.render(),
          )
        }
        AbsState::new()
      }
      let after_b = eva_copy(eva)
      // The join is of the two BRANCHES, not of the branches and the state
      // before them: a fact that was true before the `if` and is false on
      // both branches is false after it.
      eva_assign(eva, eva_join(after_a, after_b))
      if branch_returns(a) {
        // The then-branch RETURNS: the code after the `if` is reached only
        // from the else branch.
        //
        // `if cond { return }` is the shape that matters: the code after it
        // is reached only when the condition is false, so the state there
        // is the FALSE branch's state -- refined by the condition -- and
        // not a join with a branch that left the function. Joining them
        // lost the refinement, and with it the narrowing the guard was
        // written to give: `if len_idx < 0 { return }` says the index is
        // not negative, and the join threw that away.
        //
        // When the else branch is unreachable too -- the condition is always
        // true -- the code after the `if` is unreachable as well, and the
        // state there is empty. The CFG reports that code as unreachable;
        // the abstract layer does not report defects inside it.
        rb
      } else if branch_returns(b) {
        // The else-branch RETURNS: the code after the `if` is reached only
        // from the then branch, so the state there is the TRUE branch's
        // state -- refined by the condition -- and not a join with a branch
        // that left the function.
        //
        // This is the mirror of the rule above, and it is what makes a
        // `guard` usable. MEASURED (2026-11-18): MoonBit's
        //
        //     guard total > 0 else { "0%" }
        //
        // never falls through when the condition is false -- the else
        // block's value is the function's RETURN value (measured on the
        // toolchain: `f(0)` returned "0%"), so the guard's else path leaves
        // the function. The parser desugars the guard into exactly this
        // shape, and without this rule the join threw the refinement away:
        // the analyzer reported a division by zero on a divisor that
        // `guard total > 0` had already excluded.
        ra
      } else if may_true && may_false {
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
      // A write inside a loop makes an uninitialized array's written set
      // unbounded, so the loop depth is tracked while the body is analysed.
      let outer_depth = eva.loop_depth
      eva.loop_depth = outer_depth + 1
      let snap = eva_copy(eva)
      while iter < 6 {
        last_cond = abs_eval(ctx, cur, eva, cond)
        let (may_true, _) = bool_of_abs(last_cond.v)
        if !may_true {
          break
        }
        let body_in = refine_cond(cur, cond, true)
        if last_cond.t != TClean {
          implicit_abs_taint(body_in, cond)
        }
        let after = abs_block(ctx, body_in, eva, body)
        let next = abs_join_state(cur, after)
        let widened = if iter >= 3 { abs_widen(cur, next) } else { next }
        if abs_state_equal(widened, cur) {
          cur = widened
          break
        }
        cur = widened
        iter = iter + 1
      }
      eva.loop_depth = outer_depth
      // The loop may run zero times, so the facts that come out of it are
      // JOINED with the facts that went in.
      let after_loop = eva_copy(eva)
      eva_assign(eva, eva_join(snap, after_loop))
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
      let c = abs_eval(ctx, st, eva, init)
      let mut cur = copy_state(st)
      cur.env[n] = c
      let mut iter = 0
      let outer_depth = eva.loop_depth
      eva.loop_depth = outer_depth + 1
      let snap = eva_copy(eva)
      while iter < 6 {
        let cc = abs_eval(ctx, cur, eva, cond)
        let (may_true, _) = bool_of_abs(cc.v)
        if !may_true {
          break
        }
        let body_in = refine_cond(cur, cond, true)
        let after = abs_block(ctx, body_in, eva, body)
        let stepped = copy_state(after)
        ignore(abs_eval(ctx, stepped, eva, step))
        let next = abs_join_state(cur, stepped)
        let widened = if iter >= 3 { abs_widen(cur, next) } else { next }
        if abs_state_equal(widened, cur) {
          break
        }
        cur = widened
        iter = iter + 1
      }
      eva.loop_depth = outer_depth
      let after_loop = eva_copy(eva)
      eva_assign(eva, eva_join(snap, after_loop))
      refine_cond(cur, cond, false)
    }
    SForIn(names, iter, body) => {
      // The body of a loop is analysed with the loop depth raised: the
      // unreachable-branch finding is not filed inside a loop, because a
      // claim about one iteration is not a claim about the loop.
      let outer_depth = eva.loop_depth
      eva.loop_depth = outer_depth + 1
      let result = match iter.kind {
        ERange(start_e, end_e, inclusive) => {
          // A RANGE loop: `for i in a..<b`.
          //
          // The binder's value is the range's start, up to its end -- one
          // less when the end is EXCLUSIVE. That is only known when the end
          // is a number the analysis could compute; when it is not, the
          // binder's value is unknown, the same way the binder of an ARRAY
          // loop is unknown: the loop's trip count is not known, so the
          // value the binder holds is not known either.
          let cs = abs_eval(ctx, st, eva, start_e)
          let ce = abs_eval(ctx, st, eva, end_e)
          let t = cs.t.join(ce.t)
          // The binder's value is the range's start, up to its end -- one
          // less when the end is EXCLUSIVE.
          //
          // When the END is not a number the analysis could compute, the
          // trip count is not known -- but the START still is, and the
          // binder is never below it. So the binder keeps the start and
          // loses only the end.
          let binder = match (cs.v, ce.v) {
            (AInt(sl, _), AInt(_, eh)) =>
              AbsCell::new(AInt(sl, if inclusive { eh } else { eh - 1 }), t)
            (AInt(sl, _), _) => AbsCell::new(AInt(sl, 1000000), t)
            _ => AbsCell::new(ATop, t)
          }
          // The body is analysed on a COPY of the loop's entry state, and the
          // state after the loop is the JOIN of the entry state with the
          // body's. The loop may run ZERO times, and a body that changes the
          // state must not be allowed to erase that: the body's own
          // statements write into the state they are given -- `arr.push(x)`
          // grows the array -- so the entry state has to be a copy of its
          // own, or the join would be with the body's own state and the
          // zero-iteration case would be lost.
          let entry = copy_state(st)
          let mut cur = copy_state(st)
          for n in names {
            entry.env[n] = binder
            cur.env[n] = binder
            drop_length_bounds(entry, n)
            drop_length_bounds(cur, n)
          }
          // The range's END is the length of an array: the binder is below
          // that length, and the relation says so.
          //
          // An INCLUSIVE range is not: its last value IS the length, and an
          // index AT the length is out of bounds.
          if !inclusive {
            match end_e.kind {
              EMethod(recv, m, _) =>
                if m == "length" {
                  for n in names {
                    record_length_bound(entry, n, recv.render())
                    record_length_bound(cur, n, recv.render())
                  }
                }
              _ => ()
            }
          }
          // The loop may run MANY times, so the body is analysed once per
          // iteration, with the state joined and widened between them -- the
          // way the WHILE loop is analysed.
          //
          // One analysis is not enough: a body that pushes to an array grows
          // it once per iteration, and a single analysis would leave the
          // array's length at ONE element. Every refinement of that length
          // would then be wrong -- "the array is not empty" would leave it
          // with exactly one element, and a test for "exactly one" would
          // look unreachable.
          let mut round = 0
          while round < 6 {
            let body_in = copy_state(cur)
            // The binder is bound again in every iteration: what the body
            // did to it does not carry over.
            for n in names {
              body_in.env[n] = binder
            }
            let after = abs_block(ctx, body_in, eva, body)
            let next = abs_join_state(cur, after)
            let widened = if round >= 3 { abs_widen(cur, next) } else { next }
            if abs_state_equal(widened, cur) {
              cur = widened
              break
            }
            cur = widened
            round = round + 1
          }
          abs_join_state(entry, cur)
        }
        _ => {
          let ci = abs_eval(ctx, st, eva, iter)
          // The same copy the range branch makes: the body may change the
          // state, and the loop may run zero times.
          let entry = copy_state(st)
          let mut cur = copy_state(st)
          let binder = AbsCell::new(ATop, ci.t)
          for n in names {
            entry.env[n] = binder
            cur.env[n] = binder
          }
          let mut round = 0
          while round < 6 {
            let body_in = copy_state(cur)
            for n in names {
              body_in.env[n] = binder
            }
            let after = abs_block(ctx, body_in, eva, body)
            let next = abs_join_state(cur, after)
            let widened = if round >= 3 { abs_widen(cur, next) } else { next }
            if abs_state_equal(widened, cur) {
              cur = widened
              break
            }
            cur = widened
            round = round + 1
          }
          abs_join_state(entry, cur)
        }
      }
      eva.loop_depth = outer_depth
      result
    }
    SReturn(e) => {
      match e {
        Some(x) => ignore(abs_eval(ctx, st, eva, x))
        None => ()
      }
      st
    }
    SExpr(e) => {
      ignore(abs_eval(ctx, st, eva, e))
      st
    }
    SBlock(inner) | STry(inner) => abs_block(ctx, st, eva, inner)
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
    ESlice(a, s, en) => {
      collect_names(a, out)
      match s {
        Some(x) => collect_names(x, out)
        None => ()
      }
      match en {
        Some(x) => collect_names(x, out)
        None => ()
      }
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
/// The abstract values of the module's GLOBAL REGION.
///
/// The globals are evaluated in DEPENDENCY order with the same abstract
/// domain the functions are analysed in, so a global that holds a constant
/// integer contributes that constant everywhere it is read -- and an integer
/// operation that leaves the type's range in a global's INITIALIZER is
/// reported where the initializer is, not where it is used.
fn eval_globals_abs(
  findings : Array[Finding],
  ranges : Map[String, AbsRange],
  rets : Map[String, String],
  ast : ModuleAst,
  max_steps : Int32,
) -> Map[String, AbsCell] {
  let table = globals_of(ast)
  let (order, _unresolved) = global_order(table)
  let mutated = globals_mutated(ast)
  let out : Map[String, AbsCell] = Map([])
  for name in order {
    match table.get(name) {
      Some(g) =>
        if mutated.contains(name) {
          // A mutated global's value at the point of use is not its
          // initializer's value.
          out[name] = AbsCell::new(ATop, TClean)
        } else {
          let ctx : AbsContext = {
            fn_name: "<global>",
            file: g.file,
            findings,
            ranges,
            globals: out,
            steps: 0,
            max_steps,
          }
          let st = AbsState::new()
          let eva = EvaState::new(rets)
          out[name] = abs_eval(ctx, st, eva, g.init)
        }
      None => ()
    }
  }
  out
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
  // The function table, so the EVOLVED VALUE ANALYSIS knows the width and
  // the Option-ness of what a call returns.
  let rets : Map[String, String] = Map::new()
  for f in ast.all_funcs() {
    rets[f.name] = f.ret_ty
  }
  // The GLOBAL REGION is computed once, before the functions are analysed:
  // the top-level bindings are constants of the module, and their abstract
  // values are what a function that reads a global sees.
  let global_cells = eval_globals_abs(findings, ranges, rets, ast, max_steps)
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
      globals: global_cells,
      steps: 0,
      max_steps,
    }
    let st = AbsState::new()
    // The EVA facts are per FUNCTION: a name that is None in one function
    // says nothing about the same name in another.
    let eva = EvaState::new(rets)
    for p in f.params {
      st.env[p.name] = initial_cell(p.ty)
      record_abs_range(ctx, p.name, st.env[p.name])
      // A parameter of an Option type may be None: that is the null
      // dereference class, and it starts at the parameter.
      let w = eva_width_of_type(p.ty)
      if w != 0 {
        eva.width[p.name] = w
      }
      if eva_type_is_option(p.ty) {
        eva.none[p.name] = true
      }
    }
    ignore(abs_block(ctx, st, eva, f.body))
    steps = steps + ctx.steps
    count = count + 1
  }
  { findings, ranges, functions: count, steps, iterations: 6, }
}
