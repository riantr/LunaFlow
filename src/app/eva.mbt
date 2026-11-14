///|
/// THE EVOLVED VALUE ANALYSIS (EVA).
///
/// The value analysis that existed before this one asked ONE question about a
/// value: *what is its range?* EVA asks the second question, which is the one
/// a defect actually turns on: *what happens when this value is USED?*
///
/// An index that escapes its array, a divisor that may be zero, an integer
/// operation that leaves its type's range, an Option that may be None where
/// it is unwrapped, an element read before it was written — every one of those
/// is a question about the USE of a value, and every one of them is decidable
/// from the ranges the abstract interpreter already computes. So EVA is not a
/// second engine: it rides on the L2 fixpoint and asks the extra questions
/// where the values are computed.
///
/// ## Why these classes are worth a family each
///
/// The classes themselves are the classic memory-safety taxonomy, and MoonBit
/// is not a C-like language, so each one had to be mapped onto what MoonBit
/// actually does. Every mapping below was settled by RUNNING the real
/// toolchain, not by reading it:
///
/// | The C-style class | What MoonBit does | The family |
/// |---|---|---|
/// | buffer overflow | `Buffer` grows, so there is no fixed capacity to overflow; a fixed-size array's bounds are checked | `INDEX-OOB` |
/// | out-of-bounds read/write | `a[i]` panics for `i < 0` and for `i >= len` | `INDEX-OOB` |
/// | integer overflow | integer arithmetic WRAPS silently — no panic | `INTEGER-OVERFLOW` |
/// | division by zero | `1 / 0` is `RuntimeError: divide by zero` | `DIVISION-BY-ZERO` |
/// | null pointer dereference | there are no null pointers; `None.unwrap()` panics | `NONE-DEREF` |
/// | uninitialized memory read | `UninitializedArray` read before `set` returns an indeterminate value, and does NOT panic | `UNINITIALIZED-READ` |
/// | use-after-free | no raw pointers, a collector owns the storage, values are immutable | RESERVED |
/// | illegal pointer arithmetic | no pointer type in safe MoonBit | RESERVED |
/// | memory leak | the collector reclaims unreachable storage; there is no manual free | RESERVED |
/// | format string | there are no format strings: the language interpolates with a typed `\{expr}` and the core has no printf | RESERVED |
/// | invalid type cast | `as` is a trait-object downcast only; `Double::to_int` SATURATES silently | `INVALID-CAST` |
///
/// The four RESERVED families are in the roster so that `--explain` can answer
/// for them, and their contracts say why they never fire. A roster that
/// silently omitted them would read as "this tool does not look for that",
/// which is a different claim from "that cannot happen here".
///
/// ## The one that is worth more here than elsewhere
///
/// `INTEGER-OVERFLOW` is the class MoonBit makes WORSE than a trapping
/// language. `Int::MAX_VALUE + 1` is `Int::MIN_VALUE` in MoonBit, with no
/// panic and no diagnostic: the program keeps running with a value the author
/// did not intend. In a language that traps, the bug is a crash; here it is
/// silent corruption, which is exactly the kind of defect an analyzer is for.
///
/// The bound is the TYPE's bound. MoonBit's `Int` is a 32-bit signed integer
/// (measured: `Int::MAX_VALUE + 1` is `-2147483648`), `Int64` is 64-bit, and
/// an unsigned literal range stops at 2^31-1 as well.

///|
/// The per-name facts EVA tracks ALONGSIDE the abstract state.
///
/// They are joined with the state, so they are flow-sensitive: a name that is
/// assigned `Some` after being assigned `None` is not None any more, and a
/// name that is None on one branch of an `if` is None on the join.
struct EvaState {
  /// A name's value may be None.
  none : Map[String, Bool]
  /// A name's integer type: the bit count, NEGATIVE for an unsigned type.
  width : Map[String, Int32]
  /// An UninitializedArray's slot count.
  uninit_len : Map[String, Int32]
  /// The slot indices written into an UninitializedArray.
  uninit_set : Map[String, Array[Int32]]
  /// An UninitializedArray written inside a loop: its written set is
  /// unbounded, so a read cannot be called uninitialized.
  uninit_any : Array[String]
  /// The nesting depth of the loop the analysis is currently inside.
  mut loop_depth : Int32
  /// Each function's return type, so the width of a call's result is known.
  rets : Map[String, String]
}

///|
fn EvaState::new(rets : Map[String, String]) -> EvaState {
  {
    none: Map::new(),
    width: Map::new(),
    uninit_len: Map::new(),
    uninit_set: Map::new(),
    uninit_any: [],
    loop_depth: 0,
    rets,
  }
}

///|
/// Join two fact states the way the abstract state is joined: a fact is true
/// on the join if it is true on EITHER side, because the join is the union of
/// the two paths.
fn eva_join(a : EvaState, b : EvaState) -> EvaState {
  let out = EvaState::new(a.rets)
  for pair in a.none.to_array() {
    let (k, v) = pair
    out.none[k] = v
  }
  for pair in b.none.to_array() {
    let (k, v) = pair
    let cur = match out.none.get(k) {
      Some(x) => x
      None => false
    }
    out.none[k] = cur || v
  }
  for pair in a.width.to_array() {
    let (k, v) = pair
    out.width[k] = v
  }
  for pair in b.width.to_array() {
    let (k, v) = pair
    let cur = match out.width.get(k) {
      Some(x) => x
      None => 0
    }
    // Two different widths on the two paths mean the join is not one type:
    // the fact is dropped rather than guessed at.
    if cur != 0 && cur != v {
      out.width[k] = 0
    } else {
      out.width[k] = v
    }
  }
  for pair in a.uninit_len.to_array() {
    let (k, v) = pair
    out.uninit_len[k] = v
  }
  for pair in b.uninit_len.to_array() {
    let (k, v) = pair
    let cur = match out.uninit_len.get(k) {
      Some(x) => x
      None => 0
    }
    if cur != 0 && cur != v {
      out.uninit_len[k] = 0
    } else {
      out.uninit_len[k] = v
    }
  }
  for pair in a.uninit_set.to_array() {
    let (k, v) = pair
    out.uninit_set[k] = v
  }
  for pair in b.uninit_set.to_array() {
    let (k, v) = pair
    let cur = match out.uninit_set.get(k) {
      Some(x) => x
      None => []
    }
    let merged : Array[Int32] = []
    for x in cur {
      merged.push(x)
    }
    for x in v {
      if !merged.contains(x) {
        merged.push(x)
      }
    }
    out.uninit_set[k] = merged
  }
  for n in a.uninit_any {
    if !out.uninit_any.contains(n) {
      out.uninit_any.push(n)
    }
  }
  for n in b.uninit_any {
    if !out.uninit_any.contains(n) {
      out.uninit_any.push(n)
    }
  }
  out.loop_depth = if a.loop_depth > b.loop_depth {
    a.loop_depth
  } else {
    b.loop_depth
  }
  out
}

///|
/// A DEEP copy of the facts.
///
/// The maps are reference types, so a plain struct copy would share them and
/// the copy would change with the original. The copy exists so a branch can
/// be analysed from the same starting facts as its sibling.
fn eva_copy(a : EvaState) -> EvaState {
  let out = EvaState::new(a.rets)
  for pair in a.none.to_array() {
    out.none[pair.0] = pair.1
  }
  for pair in a.width.to_array() {
    out.width[pair.0] = pair.1
  }
  for pair in a.uninit_len.to_array() {
    out.uninit_len[pair.0] = pair.1
  }
  for pair in a.uninit_set.to_array() {
    let copied : Array[Int32] = []
    for x in pair.1 {
      copied.push(x)
    }
    out.uninit_set[pair.0] = copied
  }
  for n in a.uninit_any {
    out.uninit_any.push(n)
  }
  out.loop_depth = a.loop_depth
  out
}

///|
/// Overwrite the facts in place.
///
/// The facts travel a_longside the abstract state as a shared box, so a join
/// has to be written BACK into it rather than returned.
fn eva_assign(target : EvaState, src : EvaState) -> Unit {
  for pair in target.none.to_array() {
    target.none.remove(pair.0)
  }
  for pair in src.none.to_array() {
    target.none[pair.0] = pair.1
  }
  for pair in target.width.to_array() {
    target.width.remove(pair.0)
  }
  for pair in src.width.to_array() {
    target.width[pair.0] = pair.1
  }
  for pair in target.uninit_len.to_array() {
    target.uninit_len.remove(pair.0)
  }
  for pair in src.uninit_len.to_array() {
    target.uninit_len[pair.0] = pair.1
  }
  for pair in target.uninit_set.to_array() {
    target.uninit_set.remove(pair.0)
  }
  for pair in src.uninit_set.to_array() {
    let copied : Array[Int32] = []
    for x in pair.1 {
      copied.push(x)
    }
    target.uninit_set[pair.0] = copied
  }
  target.uninit_any.clear()
  for n in src.uninit_any {
    target.uninit_any.push(n)
  }
  target.loop_depth = src.loop_depth
}

///|
/// The facts for a binding.
///
/// The declared type wins over the expression's own type, because the
/// annotation is what the author wrote and the inference is the analyzer's
/// guess. A name bound to `None`, or to a call that returns an Option, may
/// be None; a name bound to `Some` may not.
fn eva_bind(eva : EvaState, name : String, ty : String, e : Expr) -> Unit {
  let declared_none = eva_type_is_option(ty) && !eva_is_some(e)
  let may_none = eva_may_be_none(eva, e) || declared_none
  if may_none {
    eva.none[name] = true
  } else {
    eva.none.remove(name)
  }
  let w = eva_width_of_type(ty)
  if w != 0 {
    eva.width[name] = w
  } else {
    let inferred = eva_width_of_expr(eva, e)
    if inferred != 0 {
      eva.width[name] = inferred
    } else {
      eva.width.remove(name)
    }
  }
  eva_note_uninit(eva, name, e)
}

///|
/// Note that a name holds an UNINITIALIZED array.
///
/// The size has to be a literal: an array whose length the analysis does not
/// know cannot be checked, and guessing its length would produce findings
/// about slots that do not exist.
fn eva_note_uninit(eva : EvaState, name : String, e : Expr) -> Unit {
  match e.kind {
    ECall(f, args) =>
      // The parser reads a qualified path as a field read, so the call's
      // name comes out as `UninitializedArray.make`. The `::` spelling is
      // accepted as well, because a caller may build the expression itself.
      if (f == "UninitializedArray.make" || f == "UninitializedArray::make") &&
        args.length() > 0 {
        match args[0].kind {
          EInt(n) => {
            eva.uninit_len[name] = n
            eva.uninit_set[name] = []
          }
          _ => ()
        }
      }
    _ => ()
  }
}

///|
/// Note a write into an uninitialized array.
///
/// A write inside a loop makes the written set unbounded, so the array is
/// marked as "written somewhere" and a later read cannot be called
/// uninitialized.
fn eva_note_uninit_set(eva : EvaState, recv : Expr, index : Int32) -> Unit {
  match recv.kind {
    EName(n) =>
      match eva.uninit_len.get(n) {
        Some(len) => {
          if index < 0 || index >= len {
            return
          }
          if eva.loop_depth > 0 {
            if !eva.uninit_any.contains(n) {
              eva.uninit_any.push(n)
            }
            return
          }
          let written = match eva.uninit_set.get(n) {
            Some(w) => w
            None => []
          }
          if !written.contains(index) {
            written.push(index)
            eva.uninit_set[n] = written
          }
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// The bit width of an integer type, negative for an unsigned one, and 0 when
/// the type is not an integer type or is not known.
///
/// The type names are matched EXACTLY on purpose: a type like `Array[Int]`
/// contains "Int", and reading a width out of it would be a guess.
fn eva_width_of_type(ty : String) -> Int32 {
  let t = ty.trim()
  if t == "Int64" {
    return 64
  }
  if t == "UInt64" {
    return -64
  }
  if t == "Int" || t == "Int32" {
    return 32
  }
  if t == "UInt" || t == "UInt32" {
    return -32
  }
  if t == "Byte" {
    return -8
  }
  0
}

///|
/// Is this declared type an Option?
///
/// MoonBit has TWO spellings for the same type: `Option[Int32]` and
/// `Int32?`. The formatter rewrites one into the other — `moon fmt` turns
/// `Option[Int32]` into `Int32?` — so a check that only knows the first
/// spelling silently stops working the moment the file is formatted.
fn eva_type_is_option(ty : String) -> Bool {
  if ty.contains("Option") {
    return true
  }
  ty.trim().has_suffix("?")
}

///|
/// The width of an EXPRESSION, from the facts and the function table.
fn eva_width_of_expr(eva : EvaState, e : Expr) -> Int32 {
  match e.kind {
    EName(n) =>
      match eva.width.get(n) {
        Some(w) => w
        None => 0
      }
    // An unsuffixed literal is `Int`, and `Int` is 32 bits.
    EInt(_) => 32
    ECall(f, _) =>
      match eva.rets.get(f) {
        Some(t) => eva_width_of_type(t)
        None => 0
      }
    EBin(_, a, b) => {
      let wa = eva_width_of_expr(eva, a)
      let wb = eva_width_of_expr(eva, b)
      if wa != 0 && wb != 0 {
        if wa == wb {
          wa
        } else {
          0
        }
      } else if wa != 0 {
        wa
      } else {
        wb
      }
    }
    EUn(_, a) => eva_width_of_expr(eva, a)
    _ => 0
  }
}

///|
/// Does this expression definitely hold a `Some`?
fn eva_is_some(e : Expr) -> Bool {
  match e.kind {
    ECall(f, _) => f == "Some"
    _ => false
  }
}

///|
/// May this expression evaluate to `None`?
fn eva_may_be_none(eva : EvaState, e : Expr) -> Bool {
  match e.kind {
    ECall(f, _) =>
      if f == "None" {
        true
      } else {
        match eva.rets.get(f) {
          Some(t) => eva_type_is_option(t)
          None => false
        }
      }
    EName(n) =>
      match eva.none.get(n) {
        Some(b) => b
        None => false
      }
    _ => false
  }
}

///|
/// Record an EVA finding.
///
/// It carries the mode `L2-EVA`, so the report can tell an evolved value
/// analysis finding from a classic abstract one, and it is deduplicated the
/// same way: a loop iteration that reaches the same line must not report the
/// same thing twice.
fn eva_add_finding(
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
      "L2-EVA",
      confidence,
      evidence,
    ),
  )
}

///|
/// The bounds of a width, as the pair a signed or unsigned integer of that
/// width can hold.
fn eva_bounds(w : Int32) -> (Int64, Int64) {
  if w == 64 {
    (-9223372036854775808L, 9223372036854775807L)
  } else if w == -64 {
    // The unsigned 64-bit bound does not fit in an Int64, and a 64-bit
    // operation is skipped by the overflow check anyway.
    (0L, 9223372036854775807L)
  } else if w == -32 {
    (0L, 4294967295L)
  } else if w == -8 {
    (0L, 255L)
  } else {
    (-2147483648L, 2147483647L)
  }
}

///|
/// INTEGER OVERFLOW.
///
/// MoonBit's integer arithmetic WRAPS: it does not trap. `Int::MAX_VALUE + 1`
/// is `Int::MIN_VALUE`, silently. An overflow is therefore a wrong value the
/// program keeps running with, which is harder to find than a panic.
///
/// The bound is the TYPE's bound, and the abstract domain's integer interval
/// is 32 bits wide, so a 64-bit operation cannot be checked here and is
/// SKIPPED rather than guessed at. The width of an operand is its declared
/// type when it has one, the return type of the call it came from when it does
/// not, and the default `Int` otherwise — MoonBit's unsuffixed integer type.
fn eva_check_overflow(
  ctx : AbsContext,
  eva : EvaState,
  op : BinOp,
  a_expr : Expr,
  b_expr : Expr,
  al : Int32,
  ah : Int32,
  bl : Int32,
  bh : Int32,
) -> Unit {
  let wa = eva_width_of_expr(eva, a_expr)
  let wb = eva_width_of_expr(eva, b_expr)
  let w = if wa != 0 && wb != 0 && wa != wb {
    0
  } else if wa != 0 {
    wa
  } else if wb != 0 {
    wb
  } else {
    32
  }
  // A 64-bit operation is out of the domain's reach: the interval is 32 bits
  // wide, so checking it here would report a wrong bound.
  if w == 64 || w == -64 {
    return
  }
  let (lo_bound, hi_bound) = eva_bounds(w)
  let a_lo = al.to_int64()
  let a_hi = ah.to_int64()
  let b_lo = bl.to_int64()
  let b_hi = bh.to_int64()
  let (rlo, rhi) = match op {
    OpAdd => (a_lo + b_lo, a_hi + b_hi)
    OpSub => (a_lo - b_hi, a_hi - b_lo)
    OpMul => {
      let p1 = a_lo * b_lo
      let p2 = a_lo * b_hi
      let p3 = a_hi * b_lo
      let p4 = a_hi * b_hi
      (min4i(p1, p2, p3, p4), max4i(p1, p2, p3, p4))
    }
    _ => return
  }
  if rlo >= lo_bound && rhi <= hi_bound {
    return
  }
  let definite = al == ah && bl == bh
  eva_add_finding(
    ctx,
    FIntOverflow,
    a_expr.span.start_line,
    if definite {
      "the result leaves the range of its integer type, and MoonBit wraps it silently"
    } else {
      "the result may leave the range of its integer type, and MoonBit wraps it silently"
    },
    if definite {
      0.95
    } else {
      0.7
    },
    "result [" +
    rlo.to_string() +
    "," +
    rhi.to_string() +
    "] vs type [" +
    lo_bound.to_string() +
    "," +
    hi_bound.to_string() +
    "]",
  )
}

///|
/// Clamp an interval computed in 64 bits back into the domain's 32-bit
/// range.
///
/// The domain is 32 bits wide, and MoonBit's own arithmetic wraps — so a
/// result that does not fit would wrap to a WRONG bound, and a wrong bound
/// downstream is a false finding somewhere else. Clamping is the sound
/// answer: the overflow that caused it has already been reported by
/// `eva_check_overflow`.
fn eva_clamp32(lo : Int64, hi : Int64) -> (Int32, Int32) {
  let l = if lo < -2147483648L {
    -2147483648
  } else if lo > 2147483647L {
    2147483647
  } else {
    lo.to_int()
  }
  let h = if hi < -2147483648L {
    -2147483648
  } else if hi > 2147483647L {
    2147483647
  } else {
    hi.to_int()
  }
  (l, h)
}

///|
/// The smallest of four values.
fn min4i(a : Int64, b : Int64, c : Int64, d : Int64) -> Int64 {
  let m = if a < b { a } else { b }
  let n = if c < d { c } else { d }
  if m < n {
    m
  } else {
    n
  }
}

///|
/// The largest of four values.
fn max4i(a : Int64, b : Int64, c : Int64, d : Int64) -> Int64 {
  let m = if a > b { a } else { b }
  let n = if c > d { c } else { d }
  if m > n {
    m
  } else {
    n
  }
}

///|
/// DIVISION BY ZERO.
///
/// `1 / 0` is `RuntimeError: divide by zero` in MoonBit, and so is `1 % 0`.
/// The divisor's interval is the abstract one, so a zero inside it is a real
/// possibility rather than a guess.
fn eva_check_divzero(
  ctx : AbsContext,
  al : Int32,
  ah : Int32,
  bl : Int32,
  bh : Int32,
  line : Int32,
) -> Unit {
  if !(bl <= 0 && bh >= 0) {
    return
  }
  let definite = bl == 0 && bh == 0
  eva_add_finding(
    ctx,
    FDivZero,
    line,
    if definite {
      "the divisor is zero, and the runtime turns that into a panic"
    } else {
      "the divisor may be zero, and the runtime turns that into a panic"
    },
    if definite {
      0.95
    } else {
      0.7
    },
    "divisor [" + bl.to_string() + "," + bh.to_string() + "]",
  )
  ignore(al)
  ignore(ah)
}

///|
/// NONE DEREFERENCE.
///
/// MoonBit has no null pointers. Its equivalent is the `Option`: `None` is
/// the absence of a value, and `unwrap()` on it is a panic —
/// `RuntimeError: unreachable` at `Option::unwrap`. This is the null
/// dereference class, and it is reported where the Option's None-ness is
/// known.
fn eva_check_none_deref(
  ctx : AbsContext,
  eva : EvaState,
  recv : Expr,
  line : Int32,
) -> Unit {
  match recv.kind {
    EName(n) =>
      match eva.none.get(n) {
        Some(b) =>
          if b {
            eva_add_finding(
              ctx,
              FNoneDeref,
              line,
              "the unwrapped Option may be None, and the runtime turns that into a panic",
              0.7,
              n,
            )
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// UNINITIALIZED READ.
///
/// `UninitializedArray::make(n)` allocates n slots that hold no value yet.
/// Reading one before it is written gives an INDETERMINATE value — and
/// MoonBit does NOT panic, so the program keeps running with whatever was
/// there. The writes are tracked per array, and a write inside a loop makes
/// the written set unbounded, which is why a read after a loop is not called.
fn eva_check_uninit_read(
  ctx : AbsContext,
  eva : EvaState,
  base : Expr,
  idx : Expr,
  il : Int32,
  ih : Int32,
  line : Int32,
) -> Unit {
  match base.kind {
    EName(n) =>
      match eva.uninit_len.get(n) {
        Some(len) => {
          if len <= 0 {
            return
          }
          if eva.uninit_any.contains(n) {
            return
          }
          let written = match eva.uninit_set.get(n) {
            Some(w) => w
            None => []
          }
          // The indices that are certainly unwritten inside the read's range.
          let unwritten : Array[Int32] = []
          let mut k = if il < 0 { 0 } else { il }
          while k <= ih && k < len {
            if !written.contains(k) {
              unwritten.push(k)
            }
            k = k + 1
          }
          if unwritten.length() == 0 {
            return
          }
          let parts : Array[String] = []
          for x in unwritten {
            parts.push(x.to_string())
          }
          eva_add_finding(
            ctx,
            FUninitRead,
            line,
            "the element is read before it is written, so the value read is indeterminate",
            0.85,
            n + "[" + parts.join(",") + "] of " + len.to_string() + " slots",
          )
        }
        None => ()
      }
    _ => ()
  }
  ignore(idx)
}

///|
/// INDEX OUT OF BOUNDS.
///
/// An index is a value USED to address storage, so the question "what happens
/// when this value is used?" applies to it directly. The array's length and
/// the index's interval are both known, so the comparison covers the whole
/// input abstraction rather than one observed execution — and a read or a
/// write outside the array is a `RuntimeError: unreachable` at `Array::at`.
///
/// The proof is the interval one the abstract domain already computes; what
/// changes here is the FILING. The finding carries the mode `L2-EVA`, so the
/// report lists it with the other evolved value findings instead of leaving
/// it among the classic abstract ones, where a reader looking for the
/// out-of-bounds class would not find it.
fn eva_check_index_oob(
  ctx : AbsContext,
  il : Int32,
  ih : Int32,
  lo_len : Int32,
  hi_len : Int32,
  line : Int32,
) -> Unit {
  if !(il < 0 || ih >= lo_len) {
    return
  }
  let definite = ih < 0 || il >= hi_len
  eva_add_finding(
    ctx,
    FIndexOob,
    line,
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

///|
/// INVALID CAST.
///
/// `as` in MoonBit is a trait-object downcast and nothing else: a numeric
/// `as` is a compile error. The conversion that CAN lose a value silently is
/// `Double::to_int`, which SATURATES: a value above the Int range becomes
/// `Int::MAX_VALUE`, and a NaN becomes 0. The program keeps running with a
/// number the author did not intend, and nothing says so.
fn eva_check_invalid_cast(
  ctx : AbsContext,
  method : String,
  lo : Double,
  hi : Double,
  line : Int32,
) -> Unit {
  let (b_lo, b_hi) = if method == "to_int64" {
    (-9223372036854775808.0, 9223372036854775807.0)
  } else {
    (-2147483648.0, 2147483647.0)
  }
  if lo >= b_lo && hi <= b_hi {
    return
  }
  eva_add_finding(
    ctx,
    FInvalidCast,
    line,
    "the value is outside the target type's range, and the conversion saturates it silently",
    0.7,
    "value [" + format_double(lo) + "," + format_double(hi) + "]",
  )
}
