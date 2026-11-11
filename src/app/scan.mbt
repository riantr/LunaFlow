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

///|
/// The version to pin, given the directories the fetch wrote.
///
/// THE DIRECTORY LIST IS THE AUTHORITY. The directories under
/// `.repos/<author>/<module>/` are the versions that were actually fetched,
/// and the newest of them is the one `@latest` resolved to. Nothing is
/// scanned out of the fetch log: the fetch runs QUIET, so there is no log to
/// scan, and a log that is parsed is a log that can be wrong.
///
/// The list is the authority and not a path that merely EXISTS, because
/// `base + "/."` resolves to `base` itself. A version-shaped token of "."
/// passes such a test while naming no version at all. MEASURED: a self
/// analysis once pinned itself to the BASE directory that way, and the report
/// claimed the resolved version was ".".
pub fn pin_version(versions : Array[String]) -> String {
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
  note : String
}

///|
pub async fn fetch_module(coord : Coord, cwd : String) -> FetchResult {
  let spec = coord.author + "/" + coord.name
  let pinned = coord.version != "" && coord.version != "latest"
  let request = if pinned { spec + "@" + coord.version } else { spec }
  // THE FETCH'S OUTPUT IS NOT CAPTURED, and that is a decision rather than
  // a limitation.
  //
  // The redirection API of `moonbitlang/core/async/process` changed shape
  // between the core versions the toolchain ships. MEASURED, core 0.10.19 ->
  // 0.10.20:
  //
  //   read_from_process()  -> &ProcessOutput
  //                        -> (ReadFromProcess, SharedProcessOutput) raise
  //   run's stdout~        : &ProcessOutput = @stdio.stdout
  //                        : ProcessOutput = Inherit
  //
  // So a call that captures the output compiles against ONE core version and
  // not the other, and the toolchain -- not this module -- decides which core
  // is in play. The call below uses only the part of the API that is the same
  // in both.
  //
  // The version comes from the FILESYSTEM, which is the authority anyway: the
  // directories the fetch wrote are the thing that is actually analysed, and
  // nothing has to be parsed out of free-form log text to find them.
  //
  // The fetch runs QUIET, so it prints nothing on success, and it inherits the
  // parent's streams, so its error message -- the useful part -- reaches the
  // user directly.
  let result = @process.run(
    "moon",
    ["fetch", request, "--no-update", "--quiet"],
    inherit_env=true,
    cwd~,
    no_console_window=true,
  )
  let code = result.exit_code
  let base = path_join(
    path_join(path_join(cwd, ".repos"), coord.author),
    coord.name,
  )
  let versions = @fs.readdir(base, sort=true) catch { _ => [] }
  let mut version = if pinned { coord.version } else { "" }
  if version == "" {
    version = pin_version(versions)
  }
  let root = if version == "" { base } else { path_join(base, version) }
  let ok = code == 0 && version != "" && @fs.exists(root)
  let note = if ok {
    "fetched " + request + " -> " + root
  } else {
    "`moon fetch " +
    request +
    "` exited with code " +
    code.to_string() +
    "; no version directory under " +
    base
  }
  { root, version, ok, note, }
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
