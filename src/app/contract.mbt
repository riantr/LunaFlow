///|
pub struct Contract {
  requires : Array[Expr]
  ensures : Array[Expr]
  invariants : Array[Expr]
  assigns : Array[String]
  raw : Array[String]
  errors : Array[String]
}

///|
pub fn Contract::empty() -> Contract {
  {
    requires: [],
    ensures: [],
    invariants: [],
    assigns: [],
    raw: [],
    errors: [],
  }
}

///|
pub fn Contract::has_spec(self : Contract) -> Bool {
  // Annotations are cumulative: a function specified only by `//@ invariant`
  // still has a contract (the invariant is an assumption, design §4.3). Before
  // this, invariant-only functions were skipped entirely and produced no VC.
  self.requires.length() > 0 ||
  self.ensures.length() > 0 ||
  self.invariants.length() > 0
}

///|
fn clause_text(line : String) -> String {
  let t = line.trim().to_owned()
  if t.has_prefix("requires") {
    t[8:].to_owned().trim().to_owned()
  } else if t.has_prefix("ensures") {
    t[7:].to_owned().trim().to_owned()
  } else if t.has_prefix("invariant") {
    t[9:].to_owned().trim().to_owned()
  } else if t.has_prefix("assigns") {
    t[7:].to_owned().trim().to_owned()
  } else {
    t
  }
}

///|
fn normalize_spec_text(text : String) -> String {
  text
  .replace_all(old="\\result", new="__result")
  .replace_all(old="\\nothing", new="__nothing")
  .replace_all(old="\\old", new="__old")
  .to_string()
}

///|
pub fn parse_spec_expr(text : String, file : String, line : Int32) -> Expr? {
  let t = normalize_spec_text(text)
  if t.trim().length() == 0 {
    return None
  }
  let toks = lex(t)
  let p = P::new(file, toks)
  let e = parse_expr(p, 0)
  match e.kind {
    EUnknown(_) => None
    _ => Some(e)
  }
}

///|
pub fn parse_contract(
  raw : Array[String],
  file : String,
  line : Int32,
) -> Contract {
  let c = Contract::empty()
  for item in raw {
    c.raw.push(item)
    for clause in item.split(";") {
      let t = clause.trim().to_owned()
      if t.length() == 0 {
        continue
      }
      let body = clause_text(t)
      if t.has_prefix("requires") {
        match parse_spec_expr(body, file, line) {
          Some(e) => c.requires.push(e)
          None => c.errors.push("bad requires: " + body)
        }
      } else if t.has_prefix("ensures") {
        match parse_spec_expr(body, file, line) {
          Some(e) => c.ensures.push(e)
          None => c.errors.push("bad ensures: " + body)
        }
      } else if t.has_prefix("invariant") {
        match parse_spec_expr(body, file, line) {
          Some(e) => c.invariants.push(e)
          None => c.errors.push("bad invariant: " + body)
        }
      } else if t.has_prefix("assigns") {
        for name in split_commas(body) {
          // `\nothing` is the documented spelling; the normalized form is
          // `__nothing`. Both must be accepted, or `assigns \nothing` records a
          // bogus target named "\nothing".
          if name != "__nothing" && name != "\\nothing" && name != "" {
            c.assigns.push(name)
          }
        }
      } else {
        c.errors.push("unsupported contract clause: " + t)
      }
    }
  }
  c
}

///|
pub fn contract_above(
  text : String,
  file : String,
  start_line : Int32,
) -> Contract {
  let lines = split_lines(text)
  let mut k = start_line - 2
  let mut earliest = start_line - 1
  while k >= 0 {
    let t = lines[k].trim().to_owned()
    if t.has_prefix("//@") {
      earliest = k
      k = k - 1
    } else if t.has_prefix("///") || t.length() == 0 {
      k = k - 1
    } else {
      break
    }
  }
  let raw : Array[String] = []
  let mut j = earliest
  while j <= start_line - 2 && j < lines.length() {
    let t = lines[j].trim().to_owned()
    if t.has_prefix("//@") {
      raw.push(t[3:].to_owned().trim().to_owned())
    }
    j = j + 1
  }
  parse_contract(raw, file, start_line)
}

///|
#derive(Eq)
pub(all) enum VCStatus {
  VCProved
  VCFailed
  VCUnknown
}

///|
pub extend VCStatus with Eq::{not_equal, equal}

///|
pub fn VCStatus::code(self : VCStatus) -> String {
  match self {
    VCProved => "proved"
    VCFailed => "failed"
    VCUnknown => "unknown"
  }
}

///|
pub struct VC {
  fn_name : String
  kind : String
  file : String
  line : Int32
  goal : String
  status : VCStatus
  detail : String
}

///|
pub struct ProofResult {
  vcs : Array[VC]
  mut functions_checked : Int32
  mut functions_with_contract : Int32
  spec_gaps : Array[String]
}

///|
pub fn ProofResult::new() -> ProofResult {
  { vcs: [], functions_checked: 0, functions_with_contract: 0, spec_gaps: [], }
}

///|
fn prove_expr(
  goal : Expr,
  facts : Array[Expr],
  lo : Map[String, Double],
  hi : Map[String, Double],
) -> Tri {
  match goal.kind {
    EBin(OpAnd, a, b) => {
      let x = prove_expr(a, facts, lo, hi)
      let y = prove_expr(b, facts, lo, hi)
      match (x, y) {
        (TriFalse, _) | (_, TriFalse) => TriFalse
        (TriTrue, TriTrue) => TriTrue
        _ => TriUnknown
      }
    }
    EBin(OpOr, a, b) => {
      let x = prove_expr(a, facts, lo, hi)
      let y = prove_expr(b, facts, lo, hi)
      match (x, y) {
        (TriTrue, _) | (_, TriTrue) => TriTrue
        (TriFalse, TriFalse) => TriFalse
        _ => TriUnknown
      }
    }
    _ => {
      let goal_text = goal.render()
      for f in facts {
        if f.render() == goal_text {
          return TriTrue
        }
      }
      eval_tri(goal, lo, hi)
    }
  }
}

///|
fn prove_from_facts(goal : Expr, facts : Array[Expr]) -> (VCStatus, String) {
  let lo : Map[String, Double] = Map::new()
  let hi : Map[String, Double] = Map::new()
  for f in facts {
    absorb_fact(f, lo, hi)
  }
  match prove_expr(goal, facts, lo, hi) {
    TriTrue => (VCProved, "entailed by preconditions or interval arithmetic")
    TriFalse => (VCFailed, "preconditions or intervals refute the goal")
    TriUnknown => (VCUnknown, "insufficient facts for a decision")
  }
}

///|
fn lit_value(e : Expr) -> Double? {
  match e.kind {
    EInt(n) => Some(n.to_double())
    EDouble(d) => Some(d)
    _ => None
  }
}

///|
fn key_of(e : Expr) -> String? {
  match e.kind {
    EName(n) => Some(n)
    EMethod(a, "length", args) =>
      if args.length() == 0 {
        match a.kind {
          EName(n) => Some(n + ".len")
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn bound_lo(lo : Map[String, Double], key : String, v : Double) -> Unit {
  match lo.get(key) {
    Some(cur) => if v > cur { lo[key] = v }
    None => lo[key] = v
  }
}

///|
fn bound_hi(hi : Map[String, Double], key : String, v : Double) -> Unit {
  match hi.get(key) {
    Some(cur) => if v < cur { hi[key] = v }
    None => hi[key] = v
  }
}

///|
fn absorb_fact(
  f : Expr,
  lo : Map[String, Double],
  hi : Map[String, Double],
) -> Unit {
  match f.kind {
    EBin(OpAnd, a, b) => {
      absorb_fact(a, lo, hi)
      absorb_fact(b, lo, hi)
    }
    EBin(op, a, b) =>
      match (key_of(a), lit_value(b)) {
        (Some(k), Some(v)) =>
          match op {
            OpGe => bound_lo(lo, k, v)
            OpGt => bound_lo(lo, k, v + 1.0)
            OpLe => bound_hi(hi, k, v)
            OpLt => bound_hi(hi, k, v - 1.0)
            OpEq => {
              bound_lo(lo, k, v)
              bound_hi(hi, k, v)
            }
            _ => ()
          }
        _ =>
          match (lit_value(a), key_of(b)) {
            (Some(v), Some(k)) =>
              match op {
                OpLe => bound_lo(lo, k, v)
                OpLt => bound_lo(lo, k, v + 1.0)
                OpGe => bound_hi(hi, k, v)
                OpGt => bound_hi(hi, k, v - 1.0)
                _ => ()
              }
            _ => ()
          }
      }
    _ => ()
  }
}

///|
pub(all) enum Tri {
  TriTrue
  TriFalse
  TriUnknown
}

///|
fn interval_of(
  e : Expr,
  lo : Map[String, Double],
  hi : Map[String, Double],
) -> (Double, Double)? {
  match e.kind {
    EInt(n) => Some((n.to_double(), n.to_double()))
    EDouble(d) => Some((d, d))
    EName(n) =>
      Some(
        (lo.get(n).unwrap_or(-1000000000.0), hi.get(n).unwrap_or(1000000000.0)),
      )
    EMethod(a, "length", args) =>
      if args.length() == 0 {
        match a.kind {
          EName(n) =>
            Some(
              (
                lo.get(n + ".len").unwrap_or(-1000000000.0),
                hi.get(n + ".len").unwrap_or(1000000000.0),
              ),
            )
          _ => None
        }
      } else {
        None
      }
    EBin(op, a, b) =>
      match (interval_of(a, lo, hi), interval_of(b, lo, hi)) {
        (Some((al, ah)), Some((bl, bh))) =>
          match op {
            OpAdd => Some((al + bl, ah + bh))
            OpSub => Some((al - bh, ah - bl))
            OpMul =>
              Some(
                (
                  min4(al * bl, al * bh, ah * bl, ah * bh),
                  max4(al * bl, al * bh, ah * bl, ah * bh),
                ),
              )
            OpDiv =>
              if bl <= 0.0 && bh >= 0.0 {
                None
              } else {
                Some(
                  (
                    min4(al / bl, al / bh, ah / bl, ah / bh),
                    max4(al / bl, al / bh, ah / bl, ah / bh),
                  ),
                )
              }
            OpMod =>
              Some(
                (
                  0.0,
                  if ah.abs() > bh.abs() {
                    ah.abs() - 1.0
                  } else {
                    bh.abs() - 1.0
                  },
                ),
              )
            _ => None
          }
        _ => None
      }
    EUn(UnNeg, a) =>
      match interval_of(a, lo, hi) {
        Some((l, h)) => Some((-h, -l))
        None => None
      }
    _ => None
  }
}

///|
fn min4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let m1 = if a < b { a } else { b }
  let m2 = if c < d { c } else { d }
  if m1 < m2 {
    m1
  } else {
    m2
  }
}

///|
fn max4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let m1 = if a > b { a } else { b }
  let m2 = if c > d { c } else { d }
  if m1 > m2 {
    m1
  } else {
    m2
  }
}

///|
fn eval_tri(
  e : Expr,
  lo : Map[String, Double],
  hi : Map[String, Double],
) -> Tri {
  match e.kind {
    EBool(b) => if b { TriTrue } else { TriFalse }
    EBin(OpAnd, a, b) => {
      let x = eval_tri(a, lo, hi)
      let y = eval_tri(b, lo, hi)
      match (x, y) {
        (TriFalse, _) | (_, TriFalse) => TriFalse
        (TriTrue, TriTrue) => TriTrue
        _ => TriUnknown
      }
    }
    EBin(OpOr, a, b) => {
      let x = eval_tri(a, lo, hi)
      let y = eval_tri(b, lo, hi)
      match (x, y) {
        (TriTrue, _) | (_, TriTrue) => TriTrue
        (TriFalse, TriFalse) => TriFalse
        _ => TriUnknown
      }
    }
    EUn(UnNot, a) =>
      match eval_tri(a, lo, hi) {
        TriTrue => TriFalse
        TriFalse => TriTrue
        TriUnknown => TriUnknown
      }
    EBin(op, a, b) =>
      match op {
        OpLt | OpLe | OpGt | OpGe | OpEq | OpNe =>
          match (interval_of(a, lo, hi), interval_of(b, lo, hi)) {
            (Some((al, ah)), Some((bl, bh))) =>
              match op {
                OpLt =>
                  if ah < bl {
                    TriTrue
                  } else if al >= bh {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                OpLe =>
                  if ah <= bl {
                    TriTrue
                  } else if al > bh {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                OpGt =>
                  if al > bh {
                    TriTrue
                  } else if ah <= bl {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                OpGe =>
                  if al >= bh {
                    TriTrue
                  } else if ah < bl {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                OpEq =>
                  if al == ah && bl == bh && al == bl {
                    TriTrue
                  } else if ah < bl || bh < al {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                OpNe =>
                  if ah < bl || bh < al {
                    TriTrue
                  } else if al == ah && bl == bh && al == bl {
                    TriFalse
                  } else {
                    TriUnknown
                  }
                _ => TriUnknown
              }
            _ => TriUnknown
          }
        _ => TriUnknown
      }
    _ => TriUnknown
  }
}

///|
fn subst(e : Expr, state : Map[String, Expr]) -> Expr {
  match e.kind {
    EName(n) =>
      match state.get(n) {
        Some(v) => v
        None => e
      }
    EBin(op, a, b) =>
      Expr::new(e.span, EBin(op, subst(a, state), subst(b, state)))
    EUn(op, a) => Expr::new(e.span, EUn(op, subst(a, state)))
    EIndex(a, b) => Expr::new(e.span, EIndex(subst(a, state), subst(b, state)))
    EMethod(a, m, args) => {
      let xs : Array[Expr] = []
      for x in args {
        xs.push(subst(x, state))
      }
      Expr::new(e.span, EMethod(subst(a, state), m, xs))
    }
    ECall(f, args) => {
      let xs : Array[Expr] = []
      for x in args {
        xs.push(subst(x, state))
      }
      Expr::new(e.span, ECall(f, xs))
    }
    EField(a, f) => Expr::new(e.span, EField(subst(a, state), f))
    EArray(xs) => {
      let ys : Array[Expr] = []
      for x in xs {
        ys.push(subst(x, state))
      }
      Expr::new(e.span, EArray(ys))
    }
    ETuple(xs) => {
      let ys : Array[Expr] = []
      for x in xs {
        ys.push(subst(x, state))
      }
      Expr::new(e.span, ETuple(ys))
    }
    _ => e
  }
}

///|
fn assigned_names(stmts : Array[Stmt], out : Array[String]) -> Unit {
  for s in stmts {
    match s.kind {
      SLet(n, _, _) => if !out.contains(n) { out.push(n) }
      SAssign(lhs, _) =>
        match lhs.kind {
          EName(n) => if !out.contains(n) { out.push(n) }
          _ => ()
        }
      SAssignOp(_, lhs, _) =>
        match lhs.kind {
          EName(n) => if !out.contains(n) { out.push(n) }
          _ => ()
        }
      SIf(_, a, b) => {
        assigned_names(a, out)
        assigned_names(b, out)
      }
      SWhile(_, body)
      | SForIn(_, _, body)
      | SFor(_, _, _, _, body)
      | SBlock(body)
      | STry(body) => assigned_names(body, out)
      _ => ()
    }
  }
}

///|
fn havoc(state : Map[String, Expr], names : Array[String]) -> Unit {
  for n in names {
    state[n] = Expr::new(Span::empty(""), EUnknown(n))
  }
}

///|
fn add_vc(
  vcs : Array[VC],
  fn_name : String,
  kind : String,
  file : String,
  line : Int32,
  goal : Expr,
  facts : Array[Expr],
) -> Unit {
  let (status, detail) = prove_from_facts(goal, facts)
  vcs.push({ fn_name, kind, file, line, goal: goal.render(), status, detail, })
}

///|
fn collect_expr_vcs(
  e : Expr,
  state : Map[String, Expr],
  facts : Array[Expr],
  fn_name : String,
  file : String,
  line : Int32,
  vcs : Array[VC],
) -> Unit {
  match e.kind {
    EIndex(base, idx) => {
      let b = subst(base, state)
      let i = subst(idx, state)
      let goal = Expr::new(
        e.span,
        EBin(
          OpAnd,
          Expr::new(e.span, EBin(OpGe, i, Expr::new(e.span, EInt(0)))),
          Expr::new(
            e.span,
            EBin(OpLt, i, Expr::new(e.span, EMethod(b, "length", []))),
          ),
        ),
      )
      add_vc(vcs, fn_name, "index-bounds", file, line, goal, facts)
      collect_expr_vcs(base, state, facts, fn_name, file, line, vcs)
      collect_expr_vcs(idx, state, facts, fn_name, file, line, vcs)
    }
    EBin(op, a, b) => {
      if op == OpDiv || op == OpMod {
        let d = subst(b, state)
        let goal = Expr::new(e.span, EBin(OpNe, d, Expr::new(e.span, EInt(0))))
        add_vc(vcs, fn_name, "div-nonzero", file, line, goal, facts)
      }
      collect_expr_vcs(a, state, facts, fn_name, file, line, vcs)
      collect_expr_vcs(b, state, facts, fn_name, file, line, vcs)
    }
    ECall(f, args) => {
      if f == "Array::make" || f == "FixedArray::make" {
        if args.length() > 0 {
          let n = subst(args[0], state)
          let goal = Expr::new(
            e.span,
            EBin(OpGe, n, Expr::new(e.span, EInt(0))),
          )
          add_vc(vcs, fn_name, "alloc-size", file, line, goal, facts)
        }
      }
      if f == "assert_true" || f == "require" {
        if args.length() > 0 {
          let g = subst(args[0], state)
          add_vc(vcs, fn_name, "assert", file, line, g, facts)
        }
      }
      for a in args {
        collect_expr_vcs(a, state, facts, fn_name, file, line, vcs)
      }
    }
    EMethod(a, _, args) => {
      collect_expr_vcs(a, state, facts, fn_name, file, line, vcs)
      for x in args {
        collect_expr_vcs(x, state, facts, fn_name, file, line, vcs)
      }
    }
    EUn(_, a) => collect_expr_vcs(a, state, facts, fn_name, file, line, vcs)
    EField(a, _) => collect_expr_vcs(a, state, facts, fn_name, file, line, vcs)
    EArray(xs) | ETuple(xs) =>
      for x in xs {
        collect_expr_vcs(x, state, facts, fn_name, file, line, vcs)
      }
    _ => ()
  }
}

///|
fn exec_contract_stmts(
  stmts : Array[Stmt],
  state : Map[String, Expr],
  facts : Array[Expr],
  fn_name : String,
  file : String,
  vcs : Array[VC],
  ensures : Array[Expr],
) -> Unit {
  for s in stmts {
    match s.kind {
      SLet(n, _, e) => {
        collect_expr_vcs(e, state, facts, fn_name, file, s.span.start_line, vcs)
        state[n] = subst(e, state)
      }
      SAssign(lhs, e) => {
        collect_expr_vcs(
          lhs,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        collect_expr_vcs(e, state, facts, fn_name, file, s.span.start_line, vcs)
        match lhs.kind {
          EName(n) => state[n] = subst(e, state)
          _ => ()
        }
      }
      SAssignOp(op, lhs, e) => {
        collect_expr_vcs(
          lhs,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        collect_expr_vcs(e, state, facts, fn_name, file, s.span.start_line, vcs)
        match lhs.kind {
          EName(n) => {
            let cur = match state.get(n) {
              Some(v) => v
              None => Expr::new(s.span, EName(n))
            }
            state[n] = Expr::new(s.span, EBin(op, cur, subst(e, state)))
          }
          _ => ()
        }
      }
      SExpr(e) =>
        collect_expr_vcs(e, state, facts, fn_name, file, s.span.start_line, vcs)
      SReturn(Some(e)) => {
        collect_expr_vcs(e, state, facts, fn_name, file, s.span.start_line, vcs)
        let ret = subst(e, state)
        let st = state.copy()
        st["__result"] = ret
        for ens in ensures {
          let goal = subst(ens, st)
          add_vc(vcs, fn_name, "ensures", file, s.span.start_line, goal, facts)
        }
      }
      SReturn(None) =>
        for ens in ensures {
          let goal = subst(ens, state)
          add_vc(vcs, fn_name, "ensures", file, s.span.start_line, goal, facts)
        }
      SIf(cond, a, b) => {
        collect_expr_vcs(
          cond,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        let names : Array[String] = []
        assigned_names(a, names)
        assigned_names(b, names)
        let sa = state.copy()
        let sb = state.copy()
        exec_contract_stmts(a, sa, facts, fn_name, file, vcs, ensures)
        exec_contract_stmts(b, sb, facts, fn_name, file, vcs, ensures)
        havoc(state, names)
      }
      SWhile(cond, body) => {
        collect_expr_vcs(
          cond,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        let names : Array[String] = []
        assigned_names(body, names)
        let sb = state.copy()
        exec_contract_stmts(body, sb, facts, fn_name, file, vcs, ensures)
        havoc(state, names)
      }
      SFor(n, init, cond, step, body) => {
        collect_expr_vcs(
          init,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        state[n] = subst(init, state)
        collect_expr_vcs(
          cond,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        collect_expr_vcs(
          step,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        let names : Array[String] = [n]
        assigned_names(body, names)
        let sb = state.copy()
        exec_contract_stmts(body, sb, facts, fn_name, file, vcs, ensures)
        havoc(state, names)
      }
      SForIn(n, iter, body) => {
        collect_expr_vcs(
          iter,
          state,
          facts,
          fn_name,
          file,
          s.span.start_line,
          vcs,
        )
        let names : Array[String] = [n]
        assigned_names(body, names)
        let sb = state.copy()
        exec_contract_stmts(body, sb, facts, fn_name, file, vcs, ensures)
        havoc(state, names)
      }
      SBlock(inner) | STry(inner) =>
        exec_contract_stmts(inner, state, facts, fn_name, file, vcs, ensures)
      SUnsupported(_) => havoc(state, assigned_names_of_stmt(s))
      _ => ()
    }
  }
}

///|
fn assigned_names_of_stmt(s : Stmt) -> Array[String] {
  let out : Array[String] = []
  match s.kind {
    SLet(n, _, _) => out.push(n)
    SAssign(lhs, _) =>
      match lhs.kind {
        EName(n) => out.push(n)
        _ => ()
      }
    _ => ()
  }
  out
}

///|
pub fn check_contracts(ast : ModuleAst, only : Array[String]) -> ProofResult {
  let out = ProofResult::new()
  for f in ast.all_funcs() {
    if only.length() > 0 && !only.contains(f.name) {
      continue
    }
    let c = f.contract
    if c.errors.length() > 0 {
      out.vcs.push({
        fn_name: f.name,
        kind: "contract-syntax",
        file: f.file,
        line: f.start_line,
        goal: c.errors[0],
        status: VCFailed,
        detail: "malformed contract annotation",
      })
    }
    if !c.has_spec() {
      if only.contains(f.name) {
        out.spec_gaps.push(
          f.name + " (" + f.file + ":" + f.start_line.to_string() + ")",
        )
      }
      continue
    }
    out.functions_with_contract = out.functions_with_contract + 1
    out.functions_checked = out.functions_checked + 1
    let facts : Array[Expr] = []
    for r in c.requires {
      facts.push(r)
    }
    for inv in c.invariants {
      facts.push(inv)
    }
    let state : Map[String, Expr] = Map::new()
    for p in f.params {
      state[p.name] = Expr::new(f.span, EName(p.name))
    }
    let vcs : Array[VC] = []
    let mut tail : Expr? = None
    let prefix : Array[Stmt] = []
    let mut idx = 0
    while idx < f.body.length() {
      if idx == f.body.length() - 1 {
        match f.body[idx].kind {
          SExpr(e) => tail = Some(e)
          _ => prefix.push(f.body[idx])
        }
      } else {
        prefix.push(f.body[idx])
      }
      idx = idx + 1
    }
    exec_contract_stmts(prefix, state, facts, f.name, f.file, vcs, c.ensures)
    match tail {
      Some(e) => {
        collect_expr_vcs(
          e,
          state,
          facts,
          f.name,
          f.file,
          f.span.start_line,
          vcs,
        )
        let ret = subst(e, state)
        let st2 = state.copy()
        st2["__result"] = ret
        for ens in c.ensures {
          let goal = subst(ens, st2)
          add_vc(vcs, f.name, "ensures", f.file, f.span.start_line, goal, facts)
        }
      }
      None => ()
    }
    for vc in vcs {
      out.vcs.push(vc)
    }
  }
  out
}
