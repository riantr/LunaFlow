///|
pub fn copy_prefix(buffer : Array[Int32], len : Int32) -> Int32 {
  let mut total = 0
  let mut i = 0
  while i < len {
    total = total + buffer[i]
    i = i + 1
  }
  total
}

///|
pub fn lookup(values : Array[Int32], index : Int32) -> Int32 {
  if index < 0 {
    return 0
  }
  values[index]
}

///|
pub fn make_window(n : Int32) -> Array[Int32] {
  Array::make(n, 0)
}

///|
pub fn parse_len(s : String) -> Int32 {
  let n = s.length()
  let arr = Array::make(n, 0)
  arr[n - 1]
}

///|
pub fn unreachable_demo(x : Int32) -> Int32 {
  return x
  let y = x + 1
  y
}

///|
pub fn spin() -> Int32 {
  let mut n = 0
  while true {
    n = n + 1
  }
  n
}

///|
pub fn classify(x : Int32) -> Int32 {
  if x < 0 {
    return -1
  } else if x == 0 {
    return 0
  } else {
    return 1
  }
}

///|
pub fn sum_to(n : Int32) -> Int32 {
  let mut total = 0
  for i = 0; i < n; i = i + 1 {
    total = total + i
  }
  total
}
//@ requires n >= 0;
//@ requires n < values.length();
//@ ensures \result >= 0;

///|
pub fn get_checked(values : Array[Int32], n : Int32) -> Int32 {
  values[n]
}

//@ requires n >= 0;
//@ ensures \result >= 0;

///|
pub fn get_unsafe(values : Array[Int32], n : Int32) -> Int32 {
  values[n]
}

//@ requires n < 0;

///|
pub fn get_negative(values : Array[Int32], n : Int32) -> Int32 {
  values[n]
}

//@ requires n >= 0;
//@ ensures \result >= 0;

///|
pub fn double(n : Int32) -> Int32 {
  n + n
}
