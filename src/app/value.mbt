///|
pub(all) enum Value {
  VInt(Int32)
  VDouble(Double)
  VBool(Bool)
  VStr(String)
  VChar(Char)
  VUnit
  VArr(Array[Value])
  VTuple(Array[Value])
  VUnknown
}

///|
pub fn Value::repr(self : Value) -> String {
  match self {
    VInt(n) => n.to_string()
    VDouble(d) => format_double(d)
    VBool(b) => if b { "true" } else { "false" }
    VStr(s) => "\"" + truncate(s, 40) + "\""
    VChar(c) => "'" + c.to_string() + "'"
    VUnit => "()"
    VArr(xs) => {
      let parts : Array[String] = []
      for x in xs {
        parts.push(x.repr())
      }
      "[" + parts.join(", ") + "]"
    }
    VTuple(xs) => {
      let parts : Array[String] = []
      for x in xs {
        parts.push(x.repr())
      }
      "(" + parts.join(", ") + ")"
    }
    VUnknown => "?"
  }
}

///|
pub fn Value::numeric(self : Value) -> Double? {
  match self {
    VInt(n) => Some(n.to_double())
    VDouble(d) => Some(d)
    VBool(b) => Some(if b { 1.0 } else { 0.0 })
    VUnknown => None
    _ => None
  }
}

///|
pub fn Value::bool_of(self : Value) -> Bool? {
  match self {
    VBool(b) => Some(b)
    VInt(n) => Some(n != 0)
    VUnknown => None
    _ => None
  }
}

///|
pub fn Value::len_of(self : Value) -> Int32? {
  match self {
    VArr(xs) => Some(xs.length())
    VStr(s) => Some(s.length())
    VUnknown => None
    _ => None
  }
}

///|
pub struct Val {
  v : Value
  tainted : Bool
}

///|
pub fn Val::new(v : Value, tainted : Bool) -> Val {
  { v, tainted, }
}

///|
pub fn clean(v : Value) -> Val {
  { v, tainted: false, }
}

///|
pub fn tainted_value(v : Value) -> Val {
  { v, tainted: true, }
}

///|
pub fn is_numeric_type(ty : String) -> Bool {
  ty.contains("Int") ||
  ty.contains("Double") ||
  ty.contains("UInt") ||
  ty.contains("Byte")
}

///|
pub fn is_string_type(ty : String) -> Bool {
  ty.contains("String") || ty.contains("Char")
}

///|
pub fn is_array_type(ty : String) -> Bool {
  ty.contains("Array") || ty.has_prefix("Array") || ty.contains("FixedArray")
}

///|
pub fn int_candidates() -> Array[Value] {
  [VInt(-1), VInt(0), VInt(1), VInt(2), VInt(5)]
}

///|
pub fn double_candidates() -> Array[Value] {
  [VDouble(0.0), VDouble(1.0), VDouble(-1.5), VDouble(1024.0)]
}

///|
pub fn string_candidates() -> Array[Value] {
  [
    VStr(""),
    VStr("abc"),
    VStr("../../etc/passwd"),
    VStr("0000000000000000000000000000000000000000000000000000000000000000"),
  ]
}

///|
pub fn array_candidates(ty : String) -> Array[Value] {
  let ints : Array[Value] = [VInt(0), VInt(1), VInt(-1), VInt(5)]
  let doubles : Array[Value] = [VDouble(0.0), VDouble(1.5), VDouble(-2.0)]
  let strs : Array[Value] = [VStr(""), VStr("x")]
  let elems = if ty.contains("Double") {
    doubles
  } else if ty.contains("String") {
    strs
  } else {
    ints
  }
  let empty : Array[Value] = []
  let e0 = elems[0]
  let e1 = if elems.length() > 1 { elems[1] } else { e0 }
  let e2 = if elems.length() > 2 { elems[2] } else { e0 }
  [VArr(empty), VArr([e0]), VArr([e0, e1, e2]), VArr([e1, e0])]
}

///|
pub fn candidates_for(ty : String) -> Array[Value] {
  if is_array_type(ty) {
    array_candidates(ty)
  } else if ty.contains("Bool") {
    [VBool(false), VBool(true)]
  } else if ty.contains("Double") {
    double_candidates()
  } else if is_string_type(ty) {
    string_candidates()
  } else if ty.contains("Int") || ty.contains("UInt") || ty.contains("Byte") {
    int_candidates()
  } else {
    [VUnknown]
  }
}

///|
pub struct InputSet {
  args : Array[Val]
}

///|
pub fn synthesize(fn_name : Func, max_trials : Int32) -> Array[InputSet] {
  let per_param : Array[Array[Value]] = []
  for p in fn_name.params {
    per_param.push(candidates_for(p.ty))
  }
  let out : Array[InputSet] = []
  if per_param.length() == 0 {
    out.push({ args: [], })
    return out
  }
  let n = per_param.length()
  let idxs : Array[Int32] = []
  let mut i = 0
  while i < n {
    idxs.push(0)
    i = i + 1
  }
  let mut produced = 0
  while produced < max_trials {
    let args : Array[Val] = []
    let mut j = 0
    while j < n {
      let candidates = per_param[j]
      let pick = if candidates.length() == 0 {
        VUnknown
      } else {
        candidates[idxs[j] % candidates.length()]
      }
      args.push(tainted_value(pick))
      j = j + 1
    }
    out.push({ args, })
    produced = produced + 1
    let mut k = n - 1
    let mut carry = true
    while k >= 0 && carry {
      let cands = per_param[k]
      let next = idxs[k] + 1
      if next >= cands.length() {
        idxs[k] = 0
        k = k - 1
      } else {
        idxs[k] = next
        carry = false
      }
    }
    if carry {
      break
    }
  }
  out
}
