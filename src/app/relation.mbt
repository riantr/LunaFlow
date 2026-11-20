///|
/// The RELATION between an index and the length of the array it indexes.
///
/// The abstract domain's intervals cannot say "this index is below that
/// array's length". The two intervals are independent of one another -- the
/// index's upper bound and the length's lower bound are two different
/// numbers -- so the comparison of them says the index MAY be past the end
/// even when the code says it cannot be. That is how
///
///     for i in 0..<xs.length() {
///       xs[i]
///     }
///
/// came to be reported as an out-of-bounds access, when the range's own
/// definition says the index is below the length.
///
/// The relation is kept as its OWN fact: the name of the index, and the
/// array it indexes -- written as the array's rendering, so that a chain of
/// fields (`d.params`) is matched as the same thing it is in the source. It
/// is stored in the state's environment under a key that no source name can
/// have, so it travels with the state the way a value does.
///
/// The relation is set in three places, and all three say the same thing --
/// the index is below that array's length:
///
///  - a comparison that says so: `i < xs.length()`;
///  - the FALSE side of a comparison that says the opposite: `if i >=
///    xs.length() { return }` leaves `i < xs.length()` behind;
///  - a RANGE whose end is that length: `for i in 0..<xs.length()`.
///
/// It is dropped when the index is bound again -- the index may be a
/// different number now -- or when the array it names is bound again, and
/// it survives a join only when it holds on BOTH sides.

///|
/// The prefix of the environment key that holds a length bound. A MoonBit
/// name cannot start with `@`, so no source name can collide with it.
const IDXLEN_PREFIX : String = "@idxlen:"

///|
/// Record that `index_name` is below the length of the array `base`.
///
/// An index can be below SEVERAL lengths at once, and the relation keeps all
/// of them: `for i in 0..<xs.length()` says the index is below `xs`'s
/// length, and a guard `if i >= other.length() { continue }` says it is
/// below `other`'s length too. Keeping only one of them made the other
/// disappear -- and an index that is provably inside the array it indexes was
/// then reported as an offset that untrusted input chose.
fn record_length_bound(
  st : AbsState,
  index_name : String,
  base : String,
) -> Unit {
  let key = IDXLEN_PREFIX + index_name
  let xs : Array[String] = []
  match st.env.get(key) {
    Some(cell) =>
      match cell.v {
        AStr(old) =>
          for x in old {
            if x != base {
              xs.push(x)
            }
          }
        _ => ()
      }
    None => ()
  }
  xs.push(base)
  st.env[key] = AbsCell::new(AStr(xs), [])
}

///|
/// The arrays whose length bounds this index.
///
/// It is a LIST and not a single one: the index may be below more than one
/// length, and the relation has to be able to say so.
fn length_bounds_of(st : AbsState, index_name : String) -> Array[String] {
  match st.env.get(IDXLEN_PREFIX + index_name) {
    Some(cell) =>
      match cell.v {
        AStr(xs) => xs.copy()
        _ => []
      }
    None => []
  }
}

///|
/// Drop every length bound that mentions `name`.
///
/// `name` may be the INDEX -- the index may be a different number now -- or
/// the ARRAY, when the array is a plain name: the array may be a different
/// array now, and the length that bounded the index is not its length any
/// more. A chain of fields (`d.params`) names a parameter or a field, and
/// neither can be rebound, so it needs no invalidation.
///
/// An index may be below several lengths, so dropping one of them leaves the
/// others in place: the bound is dropped only when NOTHING is left.
fn drop_length_bounds(st : AbsState, name : String) -> Unit {
  for pair in st.env.to_array() {
    let key = pair.0
    if key.has_prefix(IDXLEN_PREFIX) {
      if key == IDXLEN_PREFIX + name {
        ignore(st.env.remove(key))
      } else {
        match pair.1.v {
          AStr(xs) => {
            let kept : Array[String] = []
            let mut dropped = false
            for x in xs {
              if x == name {
                dropped = true
              } else {
                kept.push(x)
              }
            }
            if dropped {
              if kept.length() == 0 {
                ignore(st.env.remove(key))
              } else {
                st.env[key] = AbsCell::new(AStr(kept), [])
              }
            }
          }
          _ => ()
        }
      }
    }
  }
}

///|
/// Keep only the length bounds that hold after a join.
///
/// A relation that holds on one side of a branch and not on the other does
/// not hold after the branch: the code after it may be reached either way.
///
/// There is one case where it holds anyway, and it is the case a LOOP makes.
/// The index keeps the value it had before the loop when the loop never ran,
/// so the relation holds after the loop when that value is below the length
/// as well -- and a NEGATIVE index is below every length, because a length
/// is never negative.
///
/// MEASURED (2026-11-20): without this rule the relation was lost at the
/// loop's join, and the index it spoke about could not be shown to be inside
/// the array it indexes -- which is how a whole family of false positives
/// survived: the array the index was below was not the array it indexed, and
/// the equality between the two was not known either.
fn prune_length_bounds(out : AbsState, a : AbsState, b : AbsState) -> Unit {
  for pair in out.env.to_array() {
    let key = pair.0
    if key.has_prefix(IDXLEN_PREFIX) {
      let xs = match a.env.get(key) {
        Some(x) =>
          match x.v {
            AStr(p) => p
            _ => []
          }
        None => []
      }
      let ys = match b.env.get(key) {
        Some(x) =>
          match x.v {
            AStr(q) => q
            _ => []
          }
        None => []
      }
      let kept : Array[String] = []
      for x in xs {
        if ys.contains(x) && !kept.contains(x) {
          kept.push(x)
        }
      }
      // The side that does not carry the relation may still carry a value
      // that is below the length. This is only worth looking for when the
      // INTERSECTION dropped something -- and looking for it costs a walk of
      // the state, so the common case must not pay for it.
      if kept.length() == 0 && (xs.length() > 0 || ys.length() > 0) {
        let index = index_name_of_key(out, key)
        if index != "" {
          for x in xs {
            if !kept.contains(x) && index_below_length(b, index, x) {
              kept.push(x)
            }
          }
          for y in ys {
            if !kept.contains(y) && index_below_length(a, index, y) {
              kept.push(y)
            }
          }
        }
      }
      if kept.length() == 0 {
        ignore(out.env.remove(key))
      } else {
        out.env[key] = AbsCell::new(AStr(kept), [])
      }
    }
  }
}

///|
/// The index a length bound speaks about.
///
/// The relation is keyed by the index's name, and every index it speaks
/// about is a NAME IN THE STATE -- the index is a variable, and a variable
/// is bound. So the name is found by looking for the one whose key is this
/// one, which needs no string surgery.
fn index_name_of_key(st : AbsState, key : String) -> String {
  for pair in st.env.to_array() {
    let name = pair.0
    if !name.has_prefix("@") && IDXLEN_PREFIX + name == key {
      return name
    }
  }
  ""
}

///|
/// Is the index named `index` PROVABLY below the length of the array
/// `array`?
///
/// The array's length is an interval, and only its lower bound is a promise:
/// the index is below the length when the index's upper bound is below that
/// lower bound. A negative index is below every length.
fn index_below_length(st : AbsState, index : String, array : String) -> Bool {
  match st.env.get(index) {
    Some(cell) =>
      match cell.v {
        AInt(_, hi) =>
          match st.env.get(array) {
            Some(acell) =>
              match acell.v {
                AArr(lo, _) => hi < lo
                _ => false
              }
            None => false
          }
        _ => false
      }
    None => false
  }
}

///|
/// Is this index PROVABLY inside the array it indexes?
///
/// The relation says the index is below the array's length. That is half of
/// what is needed: the index must also not be negative, because a negative
/// index is out of bounds on the other side.
///
/// The array the index is below does not have to be THE array it indexes: two
/// arrays that grow together have the same length, so a bound below one of
/// them is a bound below the other.
fn index_is_bounded_by(
  st : AbsState,
  base : Expr,
  idx : Expr,
  index_lo : Int32,
) -> Bool {
  if index_lo < 0 {
    return false
  }
  match idx.kind {
    EName(i) => index_below(st, i, base.render())
    // `i - k` is below a length when `i` is: it is SMALLER than `i`. The
    // relation names the index, and `i - k` is not a name, so the name has to
    // be found inside the expression.
    EBin(OpSub, lhs, rhs) =>
      match rhs.kind {
        EInt(k) =>
          if k >= 0 {
            match lhs.kind {
              EName(i) => index_below(st, i, base.render())
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
/// Is the index named `i` provably below the length of the array `base`?
///
/// The array the index is below does not have to be THE array it indexes: two
/// arrays that grow together have the same length, so a bound below one of
/// them is a bound below the other.
fn index_below(st : AbsState, i : String, base : String) -> Bool {
  for b in length_bounds_of(st, i) {
    if b == base {
      return true
    }
    // The array `b` and the array being indexed have the SAME LENGTH, so an
    // index below `b` is below the array being indexed too.
    for p in length_eq_of(st, b) {
      if p == base {
        return true
      }
    }
  }
  false
}

///|
/// Relate a newly bound array to the array it grows together with.
///
/// The relation is only established when the two lengths are KNOWN and EQUAL:
/// the partner's length must be an exact value, and the same one. A partner
/// whose length the analyzer only knows as a range -- a parameter, say -- is
/// not a partner, because the two arrays need not have started the same
/// length.
///
/// MEASURED (2026-11-20): without this relation the layer filed eight false
/// positives on this repository's own `family_count_table`, and could not
/// tell that shape from the same code with one of the two pushes removed.
fn relate_lockstep(
  eva : EvaState,
  st : AbsState,
  name : String,
  v : AbsVal,
) -> Unit {
  match v {
    AArr(l, h) =>
      if l == h {
        match eva.lockstep.get(name) {
          Some(partner) =>
            match st.env.get(partner) {
              Some(cell) =>
                match cell.v {
                  AArr(pl, ph) =>
                    if pl == l && ph == h {
                      record_length_eq(st, name, partner)
                      record_length_eq(st, partner, name)
                    }
                  _ => ()
                }
              None => ()
            }
          None => ()
        }
      }
    _ => ()
  }
}

///|
/// The prefix of the environment key that holds a length EQUALITY. A MoonBit
/// name cannot start with `@`, so no source name can collide with it.
const LENEQ_PREFIX : String = "@leneq:"

///|
/// Record that two arrays have the SAME LENGTH.
///
/// It is the relation between two ARRAYS, and it is what lets a bound below
/// one array's length be used for the other: an index into `counts` that is
/// below `codes`'s length is below `counts`'s length too, when the two arrays
/// grow together.
fn record_length_eq(st : AbsState, a : String, b : String) -> Unit {
  let key = LENEQ_PREFIX + a
  let xs : Array[String] = []
  match st.env.get(key) {
    Some(cell) =>
      match cell.v {
        AStr(old) =>
          for x in old {
            if x != b {
              xs.push(x)
            }
          }
        _ => ()
      }
    None => ()
  }
  xs.push(b)
  st.env[key] = AbsCell::new(AStr(xs), [])
}

///|
/// The arrays whose length is the same as this one's.
fn length_eq_of(st : AbsState, name : String) -> Array[String] {
  match st.env.get(LENEQ_PREFIX + name) {
    Some(cell) =>
      match cell.v {
        AStr(xs) => xs.copy()
        _ => []
      }
    None => []
  }
}

///|
/// Drop every length equality that mentions `name`.
///
/// The name may be bound to a different array now, and then its length is
/// not the length it had.
fn drop_length_eq(st : AbsState, name : String) -> Unit {
  for pair in st.env.to_array() {
    let key = pair.0
    if key.has_prefix(LENEQ_PREFIX) {
      if key == LENEQ_PREFIX + name {
        ignore(st.env.remove(key))
      } else {
        match pair.1.v {
          AStr(xs) => {
            let kept : Array[String] = []
            let mut dropped = false
            for x in xs {
              if x == name {
                dropped = true
              } else {
                kept.push(x)
              }
            }
            if dropped {
              if kept.length() == 0 {
                ignore(st.env.remove(key))
              } else {
                st.env[key] = AbsCell::new(AStr(kept), [])
              }
            }
          }
          _ => ()
        }
      }
    }
  }
}

///|
/// Keep only the length equalities that hold on BOTH sides of a join.
///
/// A relation that holds on one side of a branch and not on the other does
/// not hold after the branch: the code after it may be reached either way.
fn prune_length_eq(out : AbsState, a : AbsState, b : AbsState) -> Unit {
  for pair in out.env.to_array() {
    let key = pair.0
    if key.has_prefix(LENEQ_PREFIX) {
      let xs = match a.env.get(key) {
        Some(x) =>
          match x.v {
            AStr(p) => p
            _ => []
          }
        None => []
      }
      let ys = match b.env.get(key) {
        Some(x) =>
          match x.v {
            AStr(q) => q
            _ => []
          }
        None => []
      }
      let kept : Array[String] = []
      for x in xs {
        if ys.contains(x) && !kept.contains(x) {
          kept.push(x)
        }
      }
      if kept.length() == 0 {
        ignore(out.env.remove(key))
      } else {
        out.env[key] = AbsCell::new(AStr(kept), [])
      }
    }
  }
}

///|
/// Carry a length bound from one name to another.
///
/// `at = j` gives `at` the value `j` has, so a bound below `j` is a bound
/// below `at`. Without this the bound was lost at the assignment, and an
/// index that is provably inside the array it indexes was reported as one
/// that may be past the end.
fn inherit_length_bound(st : AbsState, dst : String, src : String) -> Unit {
  let srcs = length_bounds_of(st, src)
  if srcs.length() == 0 {
    return
  }
  let list : Array[String] = []
  for x in srcs {
    if !list.contains(x) {
      list.push(x)
    }
  }
  st.env[IDXLEN_PREFIX + dst] = AbsCell::new(AStr(list), [])
}
