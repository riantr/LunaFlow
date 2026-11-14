///|
pub fn format_double(d : Double) -> String {
  if d == d.to_int().to_double() && d.abs() < 1.0e15 {
    d.to_int().to_string()
  } else {
    d.to_string()
  }
}

///|
pub fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = text.get_char(i)
    if c == Some('\n') {
      let end = if i > 0 && text.get_char(i - 1) == Some('\r') {
        i - 1
      } else {
        i
      }
      out.push(text[start:end].to_string())
      start = i + 1
    }
    i = i + 1
  }
  if start <= n {
    let tail = text[start:].to_string()
    if tail != "" || out.length() == 0 {
      out.push(tail)
    }
  }
  out
}

///|
pub fn basename(path : String) -> String {
  let mut idx = -1
  let mut i = 0
  while i < path.length() {
    let c = path.get_char(i)
    if c == Some('/') || c == Some('\\') {
      idx = i
    }
    i = i + 1
  }
  if idx < 0 {
    path
  } else {
    path[idx + 1:].to_string()
  }
}

///|
pub fn dirname(path : String) -> String {
  let mut idx = -1
  let mut i = 0
  while i < path.length() {
    let c = path.get_char(i)
    if c == Some('/') || c == Some('\\') {
      idx = i
    }
    i = i + 1
  }
  if idx <= 0 {
    "."
  } else {
    path[:idx].to_string()
  }
}

///|
pub fn path_join(a : String, b : String) -> String {
  if a == "" {
    b
  } else if b == "" {
    a
  } else {
    let last = a.get_char(a.length() - 1)
    if last == Some('/') || last == Some('\\') {
      a + b
    } else {
      a + "/" + b
    }
  }
}

///|
/// Turns an arbitrary string (module coordinate, version, manifest-derived
/// name) into a single path component safe to append under `--out`.
///
/// The report file stem is built from values that come from an *analysed*
/// module's `moon.mod`, i.e. from untrusted input. `coord_file_stem` only
/// replaced `/`, which left `..\..\..\` chains working on Windows: a hostile
/// `version` field wrote artefacts outside `--out` (measured before this
/// function existed). Everything outside `[A-Za-z0-9_@-]` and `.` becomes `_`,
/// `.` runs collapse to one, and leading separators/dots are stripped, so the
/// result can never name a parent directory.
pub fn safe_stem(s : String) -> String {
  let out = StringBuilder::new()
  let mut prev_dot = false
  for c in s {
    let code = c.to_int()
    let alnum = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122)
    if c == '.' {
      if not(prev_dot) {
        out.write_char('.')
        prev_dot = true
      }
    } else if alnum || c == '_' || c == '-' || c == '@' {
      out.write_char(c)
      prev_dot = false
    } else {
      out.write_char('_')
      prev_dot = false
    }
  }
  let t = out.to_string()
  let mut i = 0
  while i < t.length() {
    let c = t.get_char(i)
    if c == Some('.') || c == Some('_') {
      i = i + 1
    } else {
      break
    }
  }
  let body = t[i:].to_owned()
  if body == "" {
    "module"
  } else {
    body
  }
}

///|
pub fn strip_ext(path : String) -> String {
  let mut idx = -1
  let mut i = 0
  while i < path.length() {
    if path.get_char(i) == Some('.') {
      idx = i
    }
    i = i + 1
  }
  if idx <= 0 {
    path
  } else {
    path[:idx].to_string()
  }
}

///|
pub fn json_escape(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    let code = c.to_int()
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c == '\t' {
      out.write_string("\\t")
    } else if code < 32 {
      out.write_string("\\u")
      out.write_string(hex4(code))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
pub fn hex4(n : Int32) -> String {
  let digits = "0123456789abcdef"
  let a = n / 4096 % 16
  let b = n / 256 % 16
  let c = n / 16 % 16
  let d = n % 16
  let out = StringBuilder::new()
  out.write_char(digits.get_char(a).unwrap_or('0'))
  out.write_char(digits.get_char(b).unwrap_or('0'))
  out.write_char(digits.get_char(c).unwrap_or('0'))
  out.write_char(digits.get_char(d).unwrap_or('0'))
  out.to_string()
}

///|
pub fn truncate(s : String, limit : Int32) -> String {
  if s.length() <= limit {
    s
  } else if limit <= 3 {
    s[:limit].to_string()
  } else {
    s[:limit - 3].to_string() + "..."
  }
}

///|
pub fn normalize_ws(s : String) -> String {
  let out = StringBuilder::new()
  let mut space = false
  let mut started = false
  for c in s {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      space = true
    } else {
      if space && started {
        out.write_char(' ')
      }
      space = false
      started = true
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
pub fn is_ident_start(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || c == '_'
}

///|
pub fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c.to_int() >= 48 && c.to_int() <= 57)
}

///|
pub fn is_digit(c : Char) -> Bool {
  c.to_int() >= 48 && c.to_int() <= 57
}

///|
pub fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
pub fn mermaid_id(prefix : String, n : Int32) -> String {
  prefix + n.to_string()
}

///|
pub fn mermaid_label(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    if c == '"' {
      out.write_string("#quot;")
    } else if c == '\\' {
      out.write_string("/")
    } else if c == '<' {
      out.write_string("#lt;")
    } else if c == '>' {
      out.write_string("#gt;")
    } else if c == '\n' || c == '\r' || c == '\t' {
      out.write_char(' ')
    } else if c == '|' {
      out.write_string("&#124;")
    } else {
      out.write_char(c)
    }
  }
  truncate(out.to_string(), 90)
}

///|
pub fn md_escape(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    if c == '|' {
      out.write_string("\\|")
    } else if c == '\n' || c == '\r' {
      out.write_char(' ')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
pub fn code_span(s : String) -> String {
  let t = s.replace_all(old="`", new="'").to_string()
  "`" + truncate(t, 80) + "`"
}

///|
pub fn pct(a : Int32, b : Int32) -> String {
  if b <= 0 {
    "n/a"
  } else {
    let v = (a.to_double() / b.to_double() * 1000.0).to_int()
    "\{v / 10}.\{v % 10}%"
  }
}

///|
pub fn read_line_at(lines : Array[String], line : Int32) -> String {
  if line >= 1 && line <= lines.length() {
    lines[line - 1]
  } else {
    ""
  }
}

///|
pub fn count_occurrences(s : String, needle : String) -> Int32 {
  if needle == "" {
    return 0
  }
  let mut count = 0
  let mut i = 0
  while i + needle.length() <= s.length() {
    if s[i:i + needle.length()] == needle {
      count = count + 1
      i = i + needle.length()
    } else {
      i = i + 1
    }
  }
  count
}

///|
pub fn split_commas(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  let mut depth = 0
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i)
    if c == Some('(') || c == Some('[') || c == Some('{') || c == Some('<') {
      depth = depth + 1
    } else if c == Some(')') ||
      c == Some(']') ||
      c == Some('}') ||
      c == Some('>') {
      depth = depth - 1
    } else if c == Some(',') && depth == 0 {
      out.push(s[start:i].to_owned().trim().to_owned())
      start = i + 1
    }
    i = i + 1
  }
  let tail = s[start:].to_owned().trim().to_owned()
  if tail != "" {
    out.push(tail)
  }
  out
}

///|
pub fn parse_int(s : String, fallback : Int32) -> Int32 {
  let t = s.trim()
  if t == "" {
    return fallback
  }
  let mut i = 0
  let mut neg = false
  if t.get_char(0) == Some('-') {
    neg = true
    i = 1
  }
  let mut value = 0
  while i < t.length() {
    let c = t.get_char(i).unwrap_or('0')
    if !is_digit(c) {
      return fallback
    }
    value = value * 10 + (c.to_int() - 48)
    i = i + 1
  }
  if neg {
    -value
  } else {
    value
  }
}

///|
pub fn sort_strings(xs : Array[String]) -> Array[String] {
  let out = xs.copy()
  out.sort()
  out
}

///|
/// The coordinate WITHOUT its version marker: `riantr/LunaFlow@latest`
/// becomes `riantr/LunaFlow`.
///
/// A coordinate may arrive carrying a version marker, and a coordinate may
/// carry only ONE. Composing `coord + "@" + version` on a coordinate that
/// already has one produces `riantr/LunaFlow@latest@0.1.13`, which does not
/// resolve -- so the marker is stripped before anything is composed with it.
///
/// The scan is by CHARACTER rather than by `find` + slice: the two agree on
/// ASCII, and a coordinate is ASCII by construction, but the character walk
/// does not depend on that being true.
pub fn coord_without_version(coord : String) -> String {
  let mut out = ""
  let mut i = 0
  let n = coord.length()
  while i < n {
    let c = coord.get_char(i)
    if c == Some('@') {
      return out
    }
    out = out + c.unwrap_or(' ').to_string()
    i = i + 1
  }
  out
}
