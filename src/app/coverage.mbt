///|
fn attr_of(s : String, key : String) -> String? {
  let needle = key + "=\""
  match s.find(needle) {
    Some(i) => {
      let rest = s[i + needle.length():].to_owned()
      match rest.find("\"") {
        Some(j) => Some(rest[:j].to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
pub fn parse_cobertura(text : String, source : String) -> Coverage {
  let cov = Coverage::new(source)
  let mut current : String? = None
  for raw in split_lines(text) {
    let line = raw.trim().to_owned()
    if line.has_prefix("<class ") {
      current = attr_of(line, "filename")
    } else if line.has_prefix("</class") {
      current = None
    } else if line.contains("<line ") {
      match current {
        Some(file) => {
          let mut rest = line
          while rest.contains("<line ") {
            match rest.find("<line ") {
              Some(i) => {
                let chunk = rest[i:].to_owned()
                let close = match chunk.find("/>") {
                  Some(j) => chunk[:j + 2].to_owned()
                  None => chunk
                }
                let num = attr_of(close, "number")
                let hits = attr_of(close, "hits")
                match (num, hits) {
                  (Some(n), Some(h)) =>
                    cov.add(file, parse_int(n, -1), parse_int(h, 0))
                  _ => ()
                }
                let next = match chunk.find("/>") {
                  Some(j) => chunk[j + 2:].to_owned()
                  None => ""
                }
                rest = next
              }
              None => break
            }
          }
        }
        None => ()
      }
    }
  }
  cov
}
