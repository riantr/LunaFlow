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
  st.env[key] = AbsCell::new(AStr(xs), TClean)
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
                st.env[key] = AbsCell::new(AStr(kept), TClean)
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
/// Keep only the length bounds that hold on BOTH sides of a join.
///
/// A relation that holds on one side of a branch and not on the other does
/// not hold after the branch: the code after it may be reached either way.
/// With several lengths per index, what survives is the INTERSECTION: the
/// arrays whose length bounds the index on both sides.
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
      if kept.length() == 0 {
        ignore(out.env.remove(key))
      } else {
        out.env[key] = AbsCell::new(AStr(kept), TClean)
      }
    }
  }
}

///|
/// Is this index PROVABLY inside the array it indexes?
///
/// The relation says the index is below the array's length. That is half of
/// what is needed: the index must also not be negative, because a negative
/// index is out of bounds on the other side.
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
    EName(i) => {
      let mut found = false
      for b in length_bounds_of(st, i) {
        if b == base.render() {
          found = true
          break
        }
      }
      found
    }
    _ => false
  }
}
