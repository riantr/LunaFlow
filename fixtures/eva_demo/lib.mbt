///|
/// The EVOLVED VALUE ANALYSIS fixture.
///
/// Every function here is written to be COMPILED and RUN by the real
/// toolchain, so the claims the analyzer makes about it can be checked
/// against what MoonBit actually does. The positive cases panic or corrupt
/// a value; the negative cases are the ordinary shapes that must NOT be
/// reported.
///
/// The defects in the positive half were settled by RUNNING the toolchain:
/// `Int::MAX_VALUE + 1` wraps to `Int::MIN_VALUE`, `1 / 0` is
/// `RuntimeError: divide by zero`, `a[5]` on a three-element array is
/// `RuntimeError: unreachable`, `None.unwrap()` is `RuntimeError:
/// unreachable`, a read of an uninitialized `UninitializedArray` element
/// returns an indeterminate value, and `1.0e300.to_int()` is 2147483647.

// ---------------------------------------------------------------------------
// POSITIVES: each of these is a defect the analyzer must report.
// ---------------------------------------------------------------------------

///|
/// INTEGER OVERFLOW, definite. MoonBit wraps it silently, so the result is
/// `Int::MIN_VALUE` and nothing says so.
pub fn overflow_literal() -> Int32 {
  let a = 2147483647
  a + 1
}

///|
/// INTEGER OVERFLOW, may. The multiply can leave the type's range.
pub fn overflow_multiply(a : Int32, b : Int32) -> Int32 {
  a * b
}

///|
/// DIVISION BY ZERO, may. The divisor's range contains zero.
pub fn divide_by_parameter(n : Int32) -> Int32 {
  100 / n
}

///|
/// DIVISION BY ZERO, definite. The divisor IS zero.
pub fn divide_by_zero() -> Int32 {
  100 / 0
}

///|
/// DIVISION BY ZERO through a modulo.
pub fn modulo_by_zero(n : Int32) -> Int32 {
  100 % n
}

///|
/// OUT OF BOUNDS, definite. The index is past the end of a three-element
/// array.
pub fn index_past_end() -> Int32 {
  let a = [1, 2, 3]
  a[5]
}

///|
/// OUT OF BOUNDS, negative. The runtime panics for a negative index too.
pub fn index_negative() -> Int32 {
  let a = [1, 2, 3]
  a[-1]
}

///|
/// NONE DEREFERENCE, definite. `None.unwrap()` panics.
pub fn unwrap_none() -> Int32 {
  let x : Int32? = None
  x.unwrap()
}

///|
/// NONE DEREFERENCE, may. One branch leaves the Option empty.
pub fn unwrap_maybe_none(flag : Bool) -> Int32 {
  let mut x : Int32? = None
  if flag {
    x = Some(1)
  }
  x.unwrap()
}

///|
/// UNINITIALIZED READ. The element is read before it is written, so the
/// value read is whatever was in the slot.
pub fn read_uninitialized() -> Int32 {
  let a = UninitializedArray::make(3)
  a[0]
}

///|
/// INVALID CAST. `Double::to_int` saturates: the value silently becomes
/// 2147483647.
pub fn saturating_cast() -> Int32 {
  let d = 3000000000.0
  d.to_int()
}

// ---------------------------------------------------------------------------
// NEGATIVES: the ordinary shapes that must NOT be reported.
// ---------------------------------------------------------------------------

///|
/// Safe arithmetic: the sum is nowhere near the bound.
pub fn safe_sum() -> Int32 {
  let a = 100
  let b = 200
  a + b
}

///|
/// Safe division: the divisor is a constant and is not zero.
pub fn safe_divisor() -> Int32 {
  let d = 10
  100 / d
}

///|
/// Safe index: the array's length is known and the index is inside it.
pub fn safe_index() -> Int32 {
  let a = [1, 2, 3]
  a[0]
}

///|
/// Safe Option: the value is a `Some`, so the unwrap cannot fail.
pub fn safe_some() -> Int32 {
  let x = Some(1)
  x.unwrap()
}

///|
/// Safe Option, assigned on every branch. The idiomatic mutable Option
/// must NOT be reported, which is why the facts are flow-sensitive.
pub fn safe_some_on_both_branches(flag : Bool) -> Int32 {
  let mut x : Int32? = None
  if flag {
    x = Some(1)
  } else {
    x = Some(2)
  }
  x.unwrap()
}

///|
/// Safe initialization: the slot is written before it is read.
pub fn safe_initialized() -> Int32 {
  let a = UninitializedArray::make(3)
  a.set(0, 7)
  a[0]
}

///|
/// Safe cast: the value is representable in the target type.
pub fn safe_cast() -> Int32 {
  let d = 3.5
  d.to_int()
}
