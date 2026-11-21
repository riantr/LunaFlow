///|
/// IFDS PHASE 2 -- the SIZE of a container, and the taint of its CONTENTS.
///
/// These assertions pin the separation the phase introduced: the taint that
/// reaches a container's **size** is not the taint that reaches its
/// **contents**.
///
/// The defect they pin is not the one the `constant_size` guard covers. The
/// guard removes the cases the layer's own value domain refutes -- a size
/// whose interval is a single point. What was left was this:
///
///   let a = Array::make(n, 0)   // n is untrusted
///   let e = a[0]                 // e is the ZERO that was put in the array
///   Array::make(e, 0)            // the size is e -- a constant
///
/// The claim was "a tainted value from parameter `n` may control an
/// allocation size", and `n` says how MANY elements there are, not what they
/// are: the size's taint had leaked into the contents' taint. The repair puts
/// the size's taint in the array VALUE (`AbsVal`'s `AArr` carries it) and
/// leaves the contents' taint to the contents.
///
/// The assertions come in pairs on purpose. A repair that made every size
/// clean would pass the first half and fail the second: the TRUE claims --
/// a size that the untrusted input really does choose -- have to survive.
///
/// The measurements these pin are in `docs/qa/IFDS_PHASE2.md`.

///|
fn size_ast(src : String) -> ModuleAst {
  {
    coord: "demo/size",
    version: "1.0.0",
    root: ".",
    files: [parse_file("s.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn size_count(src : String, kind : FindingKind) -> Int32 {
  let ast = size_ast(src)
  let abs = run_abstract(ast, 10, 1000)
  let mut n = 0
  for f in abs.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn size_messages(src : String, kind : FindingKind) -> Array[String] {
  let ast = size_ast(src)
  let abs = run_abstract(ast, 10, 1000)
  let out : Array[String] = []
  for f in abs.findings {
    if f.kind == kind {
      out.push(f.message)
    }
  }
  out
}

// ---------------------------------------------------------------------------
// The NEGATIVE half: the size is NOT the untrusted input's to choose.
// ---------------------------------------------------------------------------

///|
test "the length of a container whose ELEMENTS are tainted is not a tainted size" {
  // The array holds ONE element, so its length is 1 whatever that element is.
  // The count of the elements says nothing about the taint of the values in
  // them, so the size is clean and the claim is not made.
  let src =
    #|pub fn one_len(user : String) -> Array[Int] {
    #|  let a = [user]
    #|  Array::make(a.length(), 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="0")
}

///|
test "the same holds through a binding" {
  // The length read into a variable is the same length.
  let src =
    #|pub fn bound_len(user : String) -> Array[Int] {
    #|  let a = [user]
    #|  let n = a.length()
    #|  Array::make(n, 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="0")
}

///|
test "the same holds after a push" {
  // The count is 2, a constant, and the pushed element's taint says nothing
  // about the count.
  let src =
    #|pub fn pushed_len(user : String) -> Array[Int] {
    #|  let mut a = [user]
    #|  a.push(0)
    #|  Array::make(a.length(), 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="0")
}

///|
test "the ELEMENTS of a sized array do not carry the size's taint" {
  // The false claim this phase removes. `a` holds ZEROS, so `a[0]` is a zero
  // and the second allocation's size is a constant. `n` says how many
  // elements there are -- not what they are -- so `n` does not control that
  // size. ONE claim, for the first allocation, whose size IS `n`.
  let src =
    #|pub fn element_of_sized(n : Int) -> Array[Int] {
    #|  let a = Array::make(n, 0)
    #|  let e = a[0]
    #|  Array::make(e, 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="1")
}

// ---------------------------------------------------------------------------
// The POSITIVE half: the size IS the untrusted input's to choose.
// ---------------------------------------------------------------------------

///|
test "a size that is a parameter is still a size untrusted input chose" {
  let src =
    #|pub fn make_window(n : Int) -> Array[Int] {
    #|  Array::make(n, 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="1")
}

///|
test "the length of an array PARAMETER is still a size untrusted input chose" {
  // The caller chose how many elements the array has, so the length is the
  // caller's to choose too.
  let src =
    #|pub fn param_len(groups : Array[Int]) -> Array[Int] {
    #|  let n = groups.length()
    #|  Array::make(n, 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="1")
}

///|
test "the length of a string PARAMETER is still a size untrusted input chose" {
  let src =
    #|pub fn str_len(s : String) -> Array[Int] {
    #|  Array::make(s.length(), 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="1")
}

///|
test "the length of a string BUILT from untrusted input is still a size untrusted input chose" {
  // The input's LENGTH decides the size, so the claim stands.
  let src =
    #|pub fn built_len(user : String) -> Array[Int] {
    #|  let s = "x" + user
    #|  Array::make(s.length(), 0)
    #|}
  inspect(size_count(src, FTaintAlloc), content="1")
}

///|
test "the claim names only the sources that decide the SIZE" {
  // `Array::make(n, user)`: the size is `n`, and `user` is the ELEMENT. The
  // label must not name `user` as a source that may control the size.
  let src =
    #|pub fn make_from(n : Int, user : String) -> Array[Int] {
    #|  Array::make(n, user)
    #|}
  let msgs = size_messages(src, FTaintAlloc)
  inspect(msgs.length(), content="1")
  inspect(msgs[0].contains("`n`"), content="true")
  inspect(msgs[0].contains("`user`"), content="false")
}

///|
test "the length of a sized array names only the sources that decide the COUNT" {
  // THE SHAPE THAT SEPARATES THE TWO TAINTS, with a count that is NOT a
  // constant -- so the `constant_size` guard cannot mask it.
  //
  // `a` holds `n` copies of `user`. Its LENGTH is `n`: the caller chose how
  // many elements there are, and `user` says what is in them. So the size of
  // the second allocation is `n`, and the label must name `n` and NOT `user`.
  //
  // Before the repair the length inherited the CONTENTS' taint, so the label
  // named `user` as well -- a source that cannot decide how many elements
  // there are. That is the second direction of the defect, and this assertion
  // is what catches it: the literal shape above cannot, because there the
  // count is a constant and the guard suppresses the claim either way.
  let src =
    #|pub fn len_of_made(n : Int, user : String) -> Array[Int] {
    #|  let a = Array::make(n, user)
    #|  let len = a.length()
    #|  Array::make(len, 0)
    #|}
  let msgs = size_messages(src, FTaintAlloc)
  // Two claims: the first allocation's size is `n`, and the second one's size
  // is the length of an array of `n` elements -- which is `n` again.
  inspect(msgs.length(), content="2")
  for m in msgs {
    inspect(m.contains("`n`"), content="true")
    inspect(m.contains("`user`"), content="false")
  }
}
