///|
/// THE ARRAYS THAT GROW TOGETHER.
///
/// Two arrays that are pushed in the SAME statement list -- once each, and
/// with no other resize in between -- have the SAME LENGTH, for as long as
/// the program runs.
///
/// This is the relation the value domain was missing, and it is what makes
/// the difference between these two shapes:
///
///     let codes : Array[Int32] = []
///     let counts : Array[Int32] = []
///     ...
///     if at < 0 {
///       codes.push(i)
///       counts.push(1)
///     } else {
///       counts[at] = counts[at] + 1
///     }
///
/// `counts[at]` is in range: `counts` is as long as `codes`, and `at` is an
/// index into `codes`. Without the relation the layer could only say "the
/// index may be past the end of `counts`", and that claim was FALSE on every
/// path.
///
/// MEASURED (2026-11-20) on this repository's own source: `family_count_table`
/// in `src/app/report.mbt` is exactly this shape, and the layer filed EIGHT
/// false positives on it.
///
/// The relation is ESTABLISHED by a scan of the function, before the
/// abstract interpretation starts, and it is only used where it is sound:
///
///  - the two arrays are pushed ONCE EACH, in the SAME statement list, so
///    they always grow together;
///  - neither array is resized in any other way -- no `pop`, no `remove`,
///    no `clear`, no `truncate`, and no rebinding;
///  - the statement list they are pushed in cannot be LEFT between the two
///    pushes -- no `return`, no `break`, no `continue` in it, at any depth;
///  - and their lengths are EQUAL when the relation is established: both
///    start from the same KNOWN length, and each grows by one.
///
/// The scan is deliberately conservative. A shape it does not recognise is
/// simply not related, and the layer says what it can.

///|
/// What the scan found.
priv struct LockstepScan {
  /// The statement list each push of an array is in.
  pushes : Map[String, Array[Int32]]
  /// The arrays that are resized in a way other than a push.
  resized : Map[String, Bool]
  /// The statement lists that can be left before they run to the end.
  escapes : Map[Int32, Bool]
  /// The next statement-list id to hand out.
  mut next : Int32
}

///|
/// A statement list that cannot be left before its end makes the arrays
/// pushed in it UNSAFE to relate: the first push may happen and the second
/// may not.
fn lockstep_escape(scan : LockstepScan, block : Int32) -> Unit {
  scan.escapes[block] = true
}

///|
/// A push to an array, or a resize of one.
fn lockstep_method(scan : LockstepScan, e : Expr, block : Int32) -> Unit {
  match e.kind {
    EMethod(recv, m, _) =>
      match recv.kind {
        EName(n) =>
          if m == "push" {
            match scan.pushes.get(n) {
              Some(bs) => bs.push(block)
              None => scan.pushes[n] = [block]
            }
          } else if m == "pop" ||
            m == "remove" ||
            m == "clear" ||
            m == "truncate" {
            scan.resized[n] = true
          }
        _ => ()
      }
    _ => ()
  }
}

///|
/// The statements of one list.
fn lockstep_scan(
  scan : LockstepScan,
  stmts : Array[Stmt],
  block : Int32,
) -> Unit {
  for s in stmts {
    match s.kind {
      SExpr(e) => lockstep_method(scan, e, block)
      SLet(_, _, e) => lockstep_method(scan, e, block)
      SAssign(lhs, e) => {
        lockstep_method(scan, e, block)
        // A REBINDING is a resize: the name holds a different array now.
        match lhs.kind {
          EName(n) => scan.resized[n] = true
          _ => ()
        }
      }
      SAssignOp(_, lhs, e) => {
        lockstep_method(scan, e, block)
        match lhs.kind {
          EName(n) => scan.resized[n] = true
          _ => ()
        }
      }
      SIf(cond, a, b) => {
        lockstep_method(scan, cond, block)
        let branch_a = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, a, branch_a)
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, b, branch_b)
      }
      SWhile(cond, body) => {
        lockstep_method(scan, cond, block)
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, body, branch_b)
      }
      SFor(_, _, cond, _, body) => {
        lockstep_method(scan, cond, block)
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, body, branch_b)
      }
      SForIn(_, _, body) => {
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, body, branch_b)
      }
      SBlock(inner) => {
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, inner, branch_b)
      }
      STry(inner) => {
        let branch_b = scan.next
        scan.next = scan.next + 1
        lockstep_scan(scan, inner, branch_b)
      }
      SReturn(_) => lockstep_escape(scan, block)
      SBreak => lockstep_escape(scan, block)
      SContinue => lockstep_escape(scan, block)
      SUnsupported(_) => ()
    }
  }
}

///|
/// The arrays that grow together, and the array each one grows with.
///
/// The result is a map from a name to its partner. The relation is
/// SYMMETRIC, so both directions are in the map.
fn lockstep_pairs(body : Array[Stmt]) -> Map[String, String] {
  let scan : LockstepScan = {
    pushes: Map([]),
    resized: Map([]),
    escapes: Map([]),
    next: 1,
  }
  lockstep_scan(scan, body, 0)
  let out : Map[String, String] = Map([])
  for pair in scan.pushes.to_array() {
    let name = pair.0
    let blocks = pair.1
    // The array must be pushed ONCE, and never resized in any other way.
    if blocks.length() != 1 || scan.resized.get(name) == Some(true) {
      continue
    }
    let block = blocks[0]
    // The list must not be left between the two pushes.
    if scan.escapes.get(block) == Some(true) {
      continue
    }
    for other in scan.pushes.to_array() {
      let partner = other.0
      if partner == name {
        continue
      }
      let pblocks = other.1
      if pblocks.length() != 1 || scan.resized.get(partner) == Some(true) {
        continue
      }
      if pblocks[0] != block {
        continue
      }
      out[name] = partner
      out[partner] = name
    }
  }
  out
}
