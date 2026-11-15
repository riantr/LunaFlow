///|
/// The INDEX AND LENGTH RELATION.
///
/// The abstract domain's intervals cannot say "this index is below that
/// array's length". The two intervals are independent of one another -- the
/// index's upper bound and the length's lower bound are two different
/// numbers -- so the comparison of them says the index MAY be past the end
/// even when the code says it cannot be.
///
/// The relation is kept as its own fact, and the tests below pin the three
/// shapes that produce it, the shapes that must NOT produce it, and the
/// shapes that must still be reported.

///|
fn rel_ast(src : String) -> @app.ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn rel_findings(src : String) -> Array[@app.Finding] {
  let ast = rel_ast(src)
  let abs = @app.run_abstract(ast, 10, 1000)
  abs.findings
}

///|
fn rel_count(src : String, kind : @app.FindingKind) -> Int32 {
  let mut n = 0
  for f in rel_findings(src) {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
test "a range over an array's length indexes that array safely" {
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  for i in 0..<xs.length() {
    #|    total = total + xs[i]
    #|  }
    #|  total
    #|}
  inspect(rel_count(src, @app.FIndexOob), content="0")
}

///|
test "a loop over an array's length indexes that array safely" {
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < xs.length() {
    #|    total = total + xs[i]
    #|    i = i + 1
    #|  }
    #|  total
    #|}
  inspect(rel_count(src, @app.FIndexOob), content="0")
}

///|
test "a guard that returns leaves the index below the length" {
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut i = 0
    #|  if i >= xs.length() {
    #|    return 0
    #|  }
    #|  xs[i]
    #|}
  inspect(rel_count(src, @app.FIndexOob), content="0")
}

///|
test "a guard that returns does not make a NEGATIVE index safe" {
  // The guard says the index is below the length. It does not say the index
  // is not negative, and a negative index is out of bounds on the other
  // side -- so the analyzer still reports it.
  let src =
    #|pub fn f(xs : Array[Int], i : Int) -> Int {
    #|  if i >= xs.length() {
    #|    return 0
    #|  }
    #|  xs[i]
    #|}
  inspect(rel_count(src, @app.FIndexOob), content="1")
}

///|
test "an index below the length is not a tainted offset" {
  // The index is inside the array, so untrusted input cannot make it an
  // offset that is out of bounds.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  for i in 0..<xs.length() {
    #|    total = total + xs[i]
    #|  }
    #|  total
    #|}
  inspect(rel_count(src, @app.FTaintIndex), content="0")
}

///|
test "an index into a DIFFERENT array is still a tainted offset" {
  // The relation says the index is below the length of the array the LOOP
  // walks, not of the array it indexes here. The two are different arrays,
  // and the relation does not hold for the second one.
  let src =
    #|pub fn f(xs : Array[Int], other : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  for i in 0..<xs.length() {
    #|    total = total + other[i]
    #|  }
    #|  total
    #|}
  inspect(rel_count(src, @app.FIndexOob), content="1")
}

///|
test "a comparison with an overlapping interval is not always false" {
  // `x` is in `[-1000000, 1000000]`, so `x < 0` can hold and can fail. It
  // used to read as neither: the condition was impossible, both branches
  // were reported as unreachable, and the code after them was analysed as
  // dead.
  let src =
    #|pub fn f(x : Int) -> Int {
    #|  if x < 0 {
    #|    return 1
    #|  }
    #|  2
    #|}
  let mut dead = 0
  for f in rel_findings(src) {
    if f.kind == @app.FUnreachable {
      dead = dead + 1
    }
  }
  inspect(dead, content="0")
}

///|
test "a branch that is unreachable in one iteration of a loop is not reported" {
  // `i` is zero in the first iteration and one in the second, so the branch
  // IS taken -- the claim that it is unreachable is a claim about one
  // iteration, and the analyzer does not make it.
  let src =
    #|pub fn f(xs : Array[Int]) -> Int {
    #|  let mut total = 0
    #|  let mut i = 0
    #|  while i < xs.length() {
    #|    if i > 0 {
    #|      total = total + 1
    #|    }
    #|    i = i + 1
    #|  }
    #|  total
    #|}
  let mut dead = 0
  for f in rel_findings(src) {
    if f.kind == @app.FUnreachable {
      dead = dead + 1
    }
  }
  inspect(dead, content="0")
}

///|
test "a branch that is unreachable outside a loop is reported" {
  // The shape next to the one above: the same condition, but with a number
  // the parameter's interval cannot hold, so the branch really is
  // unreachable.
  let src =
    #|pub fn f(x : Int) -> Int {
    #|  if x == 1000001 {
    #|    return 1
    #|  }
    #|  2
    #|}
  inspect(rel_count(src, @app.FUnreachable), content="1")
}

///|
test "a loop that may run ZERO times keeps the array's length open" {
  // The loop may not run at all, so the array may still be EMPTY. The body
  // is analysed on a copy of the loop's entry state, or the body's own state
  // would be joined with itself and the empty case would be lost.
  let src =
    #|pub fn f(n : Int) -> Int {
    #|  let mut xs : Array[Int] = []
    #|  for i in 0..<n {
    #|    xs.push(i)
    #|  }
    #|  if xs.length() == 0 {
    #|    return 0
    #|  }
    #|  xs[0]
    #|}
  inspect(rel_count(src, @app.FUnreachable), content="0")
}

///|
test "a loop that grows an array does not leave it with one element" {
  // The loop may run any number of times, so the array's length is not one
  // element: the body is analysed once per iteration, with the state joined
  // and widened between them. One analysis would leave the length at ONE,
  // and "the array is not empty" would leave it at exactly one -- and the
  // test for "exactly one" would look unreachable.
  let src =
    #|pub fn f(n : Int) -> Int {
    #|  let mut xs : Array[Int] = []
    #|  for i in 0..<n {
    #|    xs.push(i)
    #|  }
    #|  if xs.length() == 0 {
    #|    return 0
    #|  }
    #|  if xs.length() != 1 {
    #|    return 0
    #|  }
    #|  xs[0]
    #|}
  inspect(rel_count(src, @app.FUnreachable), content="0")
}

///|
test "a tainted index into a KNOWN array is an array index" {
  let src =
    #|pub fn f(xs : Array[Int], i : Int) -> Int {
    #|  xs[i]
    #|}
  inspect(rel_count(src, @app.FTaintIndex), content="1")
}

///|
test "a tainted index into an OPAQUE container is not claimed" {
  // The container is a FIELD of a struct, and the analyzer does not know its
  // type: it may be a MAP, where the index is a key -- and a key cannot be
  // out of bounds and is not an offset that untrusted input chose. So the
  // claim "a tainted value may reach an array index" is not made about a
  // container the analyzer cannot see.
  let src =
    #|pub struct Box {
    #|  items : Array[Int]
    #|}
    #|pub fn f(b : Box, key : Int) -> Int {
    #|  b.items[key]
    #|}
  inspect(rel_count(src, @app.FTaintIndex), content="0")
}
