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
fn record_length_bound(
  st : AbsState,
  index_name : String,
  base : String,
) -> Unit {
  st.env[IDXLEN_PREFIX + index_name] = AbsCell::new(AStr([base]), TClean)
}

///|
/// The array whose length bounds this index, when there is one.
fn length_bound_of(st : AbsState, index_name : String) -> String? {
  match st.env.get(IDXLEN_PREFIX + index_name) {
    Some(cell) =>
      match cell.v {
        AStr(xs) => if xs.length() == 1 { Some(xs[0]) } else { None }
        _ => None
      }
    None => None
  }
}

///|
/// Do these two cells hold the SAME length bound?
fn same_length_bound(a : AbsCell, b : AbsCell) -> Bool {
  match (a.v, b.v) {
    (AStr(xs), AStr(ys)) =>
      xs.length() == 1 && ys.length() == 1 && xs[0] == ys[0]
    _ => false
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
fn drop_length_bounds(st : AbsState, name : String) -> Unit {
  for pair in st.env.to_array() {
    let key = pair.0
    if key.has_prefix(IDXLEN_PREFIX) {
      let drop = if key == IDXLEN_PREFIX + name {
        true
      } else {
        match pair.1.v {
          AStr(xs) => xs.length() == 1 && xs[0] == name
          _ => false
        }
      }
      if drop {
        ignore(st.env.remove(key))
      }
    }
  }
}

///|
/// Keep only the length bounds that hold on BOTH sides of a join.
///
/// A relation that holds on one side of a branch and not on the other does
/// not hold after the branch: the code after it may be reached either way.
fn prune_length_bounds(out : AbsState, a : AbsState, b : AbsState) -> Unit {
  for pair in out.env.to_array() {
    let key = pair.0
    if key.has_prefix(IDXLEN_PREFIX) {
      let same = match (a.env.get(key), b.env.get(key)) {
        (Some(x), Some(y)) => same_length_bound(x, y)
        _ => false
      }
      if !same {
        ignore(out.env.remove(key))
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
    EName(i) =>
      match length_bound_of(st, i) {
        Some(bound) => bound == base.render()
        None => false
      }
    _ => false
  }
}
