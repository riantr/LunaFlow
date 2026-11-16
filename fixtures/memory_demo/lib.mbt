// The MEMORY LAYOUT fixture: the global region, the allocation classes and
// the tail value of a function body.
//
// Every case here was settled by RUNNING the real toolchain, and the file
// compiles and runs under it.
//
// What MoonBit actually does, measured:
//  - a top-level `let` is a GLOBAL: it lives for the whole module;
//  - top-level bindings are IMMUTABLE: `let mut` at the top level is a parse
//    error (E3002, "unexpected token `mut`"), so a global is a constant of
//    the module;
//  - top-level bindings are resolved by DEPENDENCY, not by file order, so a
//    global may read a global declared later in the file;
//  - a function body ends with its last EXPRESSION, and that expression is
//    the function's value;
//  - there is no pointer type and no address, so the only placement question
//    is whether an allocation escapes the function that made it.

// A global that reads a global declared LATER in the file. The dependency
// order is what makes this 12 and not an unknown value.

///|
pub fn read_late_global() -> Int32 {
  derived
}

// A global bound to a plain constant.

///|
const LIMIT : Int32 = 100

// A global whose initializer leaves the type's range: MoonBit WRAPS it
// silently, so the value is -2147483648 and nothing says so.

///|
pub fn overflowing_global() -> Int32 {
  overflowing
}

// A global that is read through another global.

///|
pub fn read_through_global() -> Int32 {
  doubled
}

// An allocation that does NOT escape: it could live in the frame.

///|
pub fn frame_allocation() -> Int32 {
  let a = [1, 2, 3]
  a[0]
}

// An allocation that ESCAPES: it is returned, so it outlives the frame.

///|
pub fn escaping_allocation() -> Array[Int32] {
  let a = [1, 2, 3]
  a
}

// An allocation handed to a call the analyzer cannot see into: it MAY
// outlive the frame, so it is treated as escaping.

///|
pub fn handed_over(all : Array[Int32]) -> Int32 {
  let b = [4, 5, 6]
  consume(b) + all.length()
}

// A function whose body ends with an expression: the expression is its value.

///|
pub fn tail_value() -> Int32 {
  42
}

// The globals, in the order the dependency order puts them in.

///|
let derived : Int32 = base + 2

///|
let base : Int32 = 10

///|
let overflowing : Int32 = 2147483647 + 1

///|
let doubled : Int32 = LIMIT * 2

///|
fn consume(xs : Array[Int32]) -> Int32 {
  xs.length()
}

// ---------------------------------------------------------------------------
// A COLLECTION THAT ONLY GROWS.
//
// The MEMORY-LEAK class is inexpressible in safe MoonBit: there is no
// `free`, and every allocation is the collector's business. One shape
// survives that, and it is the shape the analyzer reports: a module-level
// collection that is only ever added to, inside a loop whose trip count the
// analyzer cannot bound.
//
// A top-level `let` is IMMUTABLE in MoonBit (the toolchain rejects `let mut`
// at the top level), but the collection it HOLDS is mutable, and that is
// enough: the module keeps every element it is given.
// ---------------------------------------------------------------------------

///|
// A module-level collection. It lives for as long as the module does.
let ledger : Array[Int32] = []

///|
// A module-level collection that IS trimmed.
let ring : Array[Int32] = []

///|
// A module-level collection filled a fixed number of times.
let few : Array[Int32] = []

///|
// It is added to inside a loop whose trip count the analyzer cannot bound,
// and nothing in the module ever removes an element from it.
pub fn record_every(n : Int32) -> Unit {
  for i in 0..<n {
    ledger.push(i)
  }
}

///|
// The same shape, but the collection IS trimmed: so it does not grow without
// bound. This half must NOT be reported.
pub fn record_and_trim(n : Int32) -> Unit {
  for i in 0..<n {
    ring.push(i)
  }
  while ring.length() > 0 {
    ignore(ring.pop())
  }
}

///|
// A LOCAL collection: it dies with the function that made it. This half must
// NOT be reported.
pub fn collect_locally(n : Int32) -> Int32 {
  let scratch : Array[Int32] = []
  for i in 0..<n {
    scratch.push(i)
  }
  scratch.length()
}

///|
// A module-level collection added to inside a loop whose trip count IS a
// compile-time constant: the analyzer can bound it, so the growth is
// bounded too. This half must NOT be reported.
pub fn record_a_few() -> Unit {
  for i in 0..<4 {
    few.push(i)
  }
}
