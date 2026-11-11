///|
pub struct Manifest {
  mut name : String
  mut version : String
  deps : Array[String]
  mut target : String
}

///|
pub fn Manifest::empty() -> Manifest {
  { name: "", version: "0.0.0", deps: [], target: "", }
}

///|
pub struct Coord {
  author : String
  name : String
  version : String
}

///|
pub fn parse_coord(s : String) -> Coord? {
  let at = s.find("@")
  let body = match at {
    Some(i) => s[:i].to_owned()
    None => s
  }
  let version = match at {
    Some(i) => s[i + 1:].to_owned()
    None => "latest"
  }
  let slash = body.find("/")
  match slash {
    Some(i) =>
      Some({
        author: body[:i].to_owned(),
        name: body[i + 1:].to_owned(),
        version,
      })
    None => None
  }
}

///|
pub fn Coord::to_string(self : Coord) -> String {
  if self.version == "" {
    self.author + "/" + self.name
  } else {
    self.author + "/" + self.name + "@" + self.version
  }
}

///|
pub fn version_parts(v : String) -> Array[Int32] {
  let parts : Array[Int32] = []
  for part in v.split(".") {
    let digits = if part.length() > 0 { part.to_owned() } else { "0" }
    parts.push(parse_int(digits, 0))
  }
  while parts.length() < 3 {
    parts.push(0)
  }
  parts
}

///|
pub fn compare_versions(a : String, b : String) -> Int32 {
  let pa = version_parts(a)
  let pb = version_parts(b)
  let mut i = 0
  while i < 3 {
    if pa[i] < pb[i] {
      return -1
    } else if pa[i] > pb[i] {
      return 1
    }
    i = i + 1
  }
  0
}

///|
pub fn parse_manifest(text : String) -> Manifest {
  let m = Manifest::empty()
  let mut in_import = false
  let mut version = "0.0.0"
  let mut name = ""
  let mut target = ""
  for raw in split_lines(text) {
    let line = raw.trim().to_owned()
    if line.has_prefix("import") {
      in_import = true
      continue
    }
    if in_import {
      if line.has_prefix("}") {
        in_import = false
        continue
      }
      let q1 = line.find("\"")
      match q1 {
        Some(i) => {
          let rest = line[i + 1:].to_owned()
          match rest.find("\"") {
            Some(j) => m.deps.push(rest[:j].to_owned())
            None => ()
          }
        }
        None => ()
      }
      continue
    }
    if line.has_prefix("version") && version == "0.0.0" {
      version = quoted_value(line).unwrap_or("0.0.0")
    } else if line.has_prefix("name") && name == "" {
      name = quoted_value(line).unwrap_or("")
    } else if line.has_prefix("preferred_target") && target == "" {
      target = quoted_value(line).unwrap_or("")
    }
  }
  m.version = version
  m.name = name
  m.target = target
  m
}

///|
fn quoted_value(line : String) -> String? {
  let i = line.find("\"")
  match i {
    Some(a) => {
      let rest = line[a + 1:].to_owned()
      match rest.find("\"") {
        Some(b) => Some(rest[:b].to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
/// The versions a `moon fetch` log names, in the order they appear.
///
/// The log is free-form and its shape differs between platforms, so this does
/// not try to parse a sentence. It looks for the module NAME followed by a
/// path separator -- `/` or `\`, because the separator is a property of the
/// platform -- and takes the version-shaped token that follows: the name of
/// the directory the fetch wrote.
///
/// The name is matched without the author prefix on purpose. The Windows log
/// prints the resolved path with backslashes
/// (`.repos\riantr\moonbit_doubleML\0.164.64`), so a marker built from the
/// coordinate `riantr/moonbit_doubleML/` never matches there.
///
/// MEASURED (the Linux CI runner): the toolchain prints a download block
/// whose lines contain "Success" and "Successfully fetched
/// riantr/moonbit_doubleML@0.164.64", and the previous scan -- to the next
/// " to " -- turned that into the version
///
///     0.164.64\nSuccess\nSuccessfully fetched riantr/moonbit_doubleML@0.164.64
///
/// which names no directory. The analyzer then read an empty tree and
/// reported 0 statements, 0 coverage and 0 findings with exit 0: a green
/// run over nothing. The token is cut at the first character that cannot be
/// part of a version instead, so it is "0.164.64".
pub fn log_version_candidates(log : String, name : String) -> Array[String] {
  let out : Array[String] = []
  for line in log.split("\n") {
    let mut rest = line
    let mut hops = 0
    while hops < 16 {
      hops = hops + 1
      match rest.find(name) {
        None => break
        Some(i) => {
          let after = rest[i + name.length():].to_owned()
          // The name has to be followed by a path separator. The coordinate
          // form (`name@version`) is not a directory and is skipped.
          if after.has_prefix("/") || after.has_prefix("\\") {
            let token = version_token(after[1:].to_owned())
            if token != "" && not(out.contains(token)) {
              out.push(token)
            }
          }
          rest = after
        }
      }
    }
  }
  out
}

///|
/// The leading version-shaped token of `s`: digits and dots, up to the first
/// character that cannot be part of a version.
///
/// A token needs at least one DIGIT. Dots alone are not a version: the
/// Windows fetch log prints the resolved path, and when the module name is a
/// SUFFIX of a directory name -- `moonbit_LunaFlow` for the module
/// `LunaFlow` -- the text after the name starts with `\.repos\`, whose
/// leading dot used to be cut out as the token ".". A trailing dot is dropped
/// for the same reason: "0.1." is a path fragment, not a version.
fn version_token(s : String) -> String {
  let buf = StringBuilder::new()
  let mut digits = 0
  for c in s {
    let code = c.to_int()
    if (code >= 48 && code <= 57) || c == '.' {
      if code >= 48 && code <= 57 {
        digits = digits + 1
      }
      buf.write_char(c)
    } else {
      break
    }
  }
  if digits == 0 {
    return ""
  }
  let mut out = buf.to_string()
  while out.has_suffix(".") {
    out = out[0:out.length() - 1].to_owned()
  }
  out
}

///|
/// The version to pin, given the fetch log and the directories the fetch wrote.
///
/// THE DIRECTORY LIST IS THE AUTHORITY. A log candidate is accepted only when
/// it is a real ENTRY of `versions` -- not when a path built from it merely
/// EXISTS, because `base + "/."` resolves to `base` itself. That test let a
/// log token of "." through, and the analysis pinned itself to the BASE
/// directory: the report claimed the resolved version was "." and the source
/// root was "./.repos/<author>/<module>/.".
///
/// When no candidate is a real directory, the NEWEST directory wins: the
/// fetch wrote it, and the version directory is what the analysis reads.
pub fn pin_version(
  log : String,
  name : String,
  versions : Array[String],
) -> String {
  for candidate in log_version_candidates(log, name) {
    if versions.contains(candidate) {
      return candidate
    }
  }
  let mut best = ""
  for v in versions {
    if best == "" || compare_versions(v, best) > 0 {
      best = v
    }
  }
  best
}

///|
pub struct FetchResult {
  root : String
  version : String
  ok : Bool
  log : String
}

///|
pub async fn fetch_module(coord : Coord, cwd : String) -> FetchResult {
  let spec = coord.author + "/" + coord.name
  let pinned = coord.version != "" && coord.version != "latest"
  let request = if pinned { spec + "@" + coord.version } else { spec }
  // `moonbitlang/core/async/process` has no `collect_output`: the
  // child's streams are redirected to `read_from_process()` and read back off
  // the `ProcessResult`. The same three facts come out — exit code, stdout,
  // stderr — so the caller does not change.
  //
  // `run` does NOT raise: a spawn that fails comes back as a non-zero exit
  // code with an empty log, not as an error to catch. That is the shape the
  // call below assumes, and it is why there is no `catch` here.
  let result = @process.run(
    "moon",
    ["fetch", request, "--no-update"],
    inherit_env=true,
    stdout=@process.read_from_process(),
    stderr=@process.read_from_process(),
    cwd~,
    no_console_window=true,
  )
  let code = result.exit_code
  let log = (result.stdout_text() catch { _ => "" }) +
    (result.stderr_text() catch { _ => "" })
  let base = path_join(
    path_join(path_join(cwd, ".repos"), coord.author),
    coord.name,
  )
  // THE FILESYSTEM IS THE AUTHORITY ON THE VERSION. The log only names a
  // candidate, and a candidate is only accepted when the directory it names
  // really exists. Without that check a log-shaped quirk becomes an analysed
  // tree of zero files that still exits 0.
  let versions = @fs.readdir(base, sort=true) catch { _ => [] }
  let mut version = if pinned { coord.version } else { "" }
  if version == "" {
    version = pin_version(log, coord.name, versions)
  }
  let root = if version == "" { base } else { path_join(base, version) }
  { root, version, ok: code == 0 && version != "" && @fs.exists(root), log, }
}

///|
pub struct ScanStats {
  mut files : Int32
  mut funcs : Int32
  mut stmts : Int32
  mut unsupported : Int32
  mut issues : Int32
  skipped_files : Array[String]
}

///|
pub fn ScanStats::new() -> ScanStats {
  {
    files: 0,
    funcs: 0,
    stmts: 0,
    unsupported: 0,
    issues: 0,
    skipped_files: [],
  }
}

///|
pub fn ScanStats::parse_rate(self : ScanStats) -> Double {
  let total = self.stmts + self.unsupported
  if total == 0 {
    1.0
  } else {
    self.stmts.to_double() / total.to_double()
  }
}

///|
struct WalkState {
  files : Array[String]
  mut truncated : Bool
}

///|
async fn walk_dir(
  dir : String,
  rel : String,
  st : WalkState,
  limit : Int32,
  depth : Int32,
) -> Unit {
  if st.files.length() >= limit || depth > 24 {
    st.truncated = true
    return
  }
  let entries = @fs.readdir(dir, include_hidden=false, sort=true) catch {
    _ => return
  }
  for name in entries {
    if st.files.length() >= limit {
      st.truncated = true
      return
    }
    // Vendored and build trees are not the analysed module. `.repos` holds
    // fetched registry modules and `.mooncakes` holds the vendored
    // dependencies of this one: a `--dir .` scan of a workspace that has them
    // would otherwise ingest a third party's source (measured: 362 of the 384
    // files in LunaFlow's own self-scan came from `moonbitlang/async`).
    if name == "_build" ||
      name == ".git" ||
      name == ".mooncakes" ||
      name == ".repos" ||
      name == "target" ||
      name == "node_modules" {
      continue
    }
    let full = path_join(dir, name)
    let rel_path = if rel == "" { name } else { rel + "/" + name }
    let kind = @fs.kind(full) catch { _ => @fs.Unknown }
    if kind == @fs.Directory {
      walk_dir(full, rel_path, st, limit, depth + 1)
    } else if kind == @fs.Regular && name.has_suffix(".mbt") {
      st.files.push(rel_path)
    }
  }
}

///|
pub async fn load_module(
  root : String,
  coord : String,
  version : String,
  file_limit : Int32,
) -> (ModuleAst, ScanStats) {
  let st : WalkState = { files: [], truncated: false, }
  walk_dir(root, "", st, file_limit, 0)
  let files : Array[SourceFile] = []
  let stats = ScanStats::new()
  for rel in st.files {
    let full = path_join(root, rel)
    let text = @fs.read_text(full) catch { _ => continue }
    let sf = parse_file(rel, text)
    stats.files = stats.files + 1
    stats.funcs = stats.funcs + sf.funcs.length()
    stats.stmts = stats.stmts + sf.parsed_stmts
    stats.unsupported = stats.unsupported + sf.unsupported_stmts
    stats.issues = stats.issues + sf.issues.length()
    files.push(sf)
  }
  if st.truncated {
    stats.skipped_files.push("file limit reached")
  }
  let manifest_path = path_join(root, "moon.mod")
  let manifest = if @fs.exists(manifest_path) {
    let d = @fs.read_text(manifest_path) catch {
      _ =>
        return (
          {
            coord,
            version,
            root,
            files,
            manifest_deps: [],
            manifest_target: "",
          },
          stats,
        )
    }
    parse_manifest(d)
  } else {
    Manifest::empty()
  }
  (
    {
      coord,
      version,
      root,
      files,
      manifest_deps: manifest.deps,
      manifest_target: manifest.target,
    },
    stats,
  )
}
