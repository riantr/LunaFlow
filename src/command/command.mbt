///|
struct Opts {
  mut coord : String
  mut dir : String
  mut out : String
  mut trials : Int32
  mut max_functions : Int32
  mut slice : String
  mut direction : String
  mut coverage_path : String
  mut max_cfg : Int32
  mut max_taint : Int32
  mut max_slice : Int32
  mut quiet : Bool
  mut function_name : String
  mut list_functions : Bool
  mut level : String
  mut funnel : Bool
}

///|
fn Opts::default() -> Opts {
  {
    coord: "",
    dir: "",
    out: "reports",
    trials: 8,
    max_functions: 150,
    slice: "",
    direction: "backward",
    coverage_path: "",
    max_cfg: 8,
    max_taint: 40,
    max_slice: 40,
    quiet: false,
    function_name: "",
    list_functions: false,
    level: "1",
    funnel: false,
  }
}

///|
fn usage() -> String {
  (
    #|LunaFlow — dynamic-first CFG / taint / range / slicing visualizer
    #|
    #|Usage:
    #|  LunaFlow analyze <author>/<module>[@<version>|@latest] [options]
    #|  LunaFlow analyze --dir <path> [options]
    #|  LunaFlow <author>/<module>[@<version>|@latest] [options]
    #|
    #|The last form is "analyze" with the coordinate where the subcommand
    #|would be. It exists because "moonx" hands the TARGET to the program as
    #|its first argument: "moonx riantr/LunaFlow@latest riantr/LunaFlow@latest"
    #|runs this binary with "riantr/LunaFlow@latest" as argv[1].
    #|
    #|Options:
    #|  --dir <path>        analyze a local directory instead of a registry module
    #|  --out <dir>         report directory (default: reports)
    #|  --trials <n>        synthesized input trials per function (default: 8)
    #|  --max-functions <n> cap on interpreted functions (default: 150)
    #|  --slice <crit>      slice criterion: <var>@<fn>, <fn>:<line>, or <var>
    #|  --function <fn>     interpret only this function (default: all)
    #|  --level <1|2|3>     proof strength: 1 interpreter, 2 values, 3 contracts (default 1)
    #|  --funnel            run L1 -> L2 -> L3 with escalation (implies level 3)
    #|  --forward           forward slice (default: backward)
    #|  --coverage <xml>    import a Cobertura XML from `moon coverage report`
    #|  --max-cfg <n>       CFG diagrams to render (default: 8)
    #|  --quiet             only print the report path
  )
}

///|
fn arg_value(args : Array[String], i : Int32) -> String {
  if i + 1 < args.length() {
    args[i + 1]
  } else {
    ""
  }
}

///|
/// Value of a path/criterion option. An absent or empty value keeps the default
/// (before this, `--out` with no value silently wrote artefacts into the
/// working directory instead of failing or falling back to `reports/`).
fn arg_or(args : Array[String], i : Int32, fallback : String) -> String {
  let v = arg_value(args, i)
  if v == "" {
    fallback
  } else {
    v
  }
}

///|
/// True when `s` is a registry coordinate: `<author>/<module>` or
/// `<author>/<module>@<version>`.
///
/// This shape is recognised because `moonx` passes the TARGET as the first
/// program argument — `moonx riantr/LunaFlow@latest riantr/LunaFlow@latest`
/// runs the module's root package with `riantr/LunaFlow@latest` as argv[1].
/// Without this, that invocation would print the usage text and analyse
/// nothing, which looks like a tool that does not work.
///
/// A local path is NOT a coordinate: `./fixtures` and `C:/tmp` both contain a
/// slash but are not `<author>/<module>`, so the author part has to be a plain
/// name, and the module part has to survive the optional `@version` suffix.
/// The author rule is what separates a coordinate from a path: a path's first
/// segment starts with a dot or a drive letter, and neither is a name.
fn is_coord(s : String) -> Bool {
  let parts = s.split("/").to_array()
  if parts.length() != 2 {
    return false
  }
  let author = parts[0].to_owned()
  let module_part = parts[1].to_owned()
  if author.length() == 0 || module_part.length() == 0 {
    return false
  }
  for ch in author {
    let code = ch.to_int()
    let digit = code >= 48 && code <= 57
    let upper = code >= 65 && code <= 90
    let lower = code >= 97 && code <= 122
    if !(digit || upper || lower || code == 45 || code == 95) {
      return false
    }
  }
  let name = match module_part.find("@") {
    Some(i) => module_part[0:i].to_owned()
    None => module_part
  }
  name.length() > 0
}

///|
fn parse_args(args : Array[String]) -> (String, Opts)? {
  if args.length() < 2 {
    return None
  }
  let mut cmd = args[1]
  if cmd == "help" || cmd == "--help" || cmd == "-h" {
    return Some(("help", Opts::default()))
  }
  let o = Opts::default()
  if cmd != "analyze" {
    // A BARE COORDINATE IS AN IMPLICIT "analyze". The coordinate lands in
    // argv[1] — where a subcommand would be — because that is where "moonx"
    // puts the target.
    if !is_coord(cmd) {
      return None
    }
    o.coord = cmd
    cmd = "analyze"
  }
  let mut i = 2
  while i < args.length() {
    let a = args[i]
    if a == "--dir" {
      o.dir = arg_or(args, i, o.dir)
      i = i + 2
    } else if a == "--out" {
      o.out = arg_or(args, i, o.out)
      i = i + 2
    } else if a == "--trials" {
      o.trials = @app.parse_int(arg_value(args, i), o.trials)
      i = i + 2
    } else if a == "--max-functions" {
      o.max_functions = @app.parse_int(arg_value(args, i), o.max_functions)
      i = i + 2
    } else if a == "--slice" {
      o.slice = arg_or(args, i, o.slice)
      i = i + 2
    } else if a == "--forward" {
      o.direction = "forward"
      i = i + 1
    } else if a == "--backward" {
      o.direction = "backward"
      i = i + 1
    } else if a == "--coverage" {
      o.coverage_path = arg_or(args, i, o.coverage_path)
      i = i + 2
    } else if a == "--max-cfg" {
      o.max_cfg = @app.parse_int(arg_value(args, i), o.max_cfg)
      i = i + 2
    } else if a == "--max-taint" {
      o.max_taint = @app.parse_int(arg_value(args, i), o.max_taint)
      i = i + 2
    } else if a == "--max-slice" {
      o.max_slice = @app.parse_int(arg_value(args, i), o.max_slice)
      i = i + 2
    } else if a == "--quiet" {
      o.quiet = true
      i = i + 1
    } else if a == "--function" {
      o.function_name = arg_or(args, i, o.function_name)
      i = i + 2
    } else if a == "--list-functions" {
      o.list_functions = true
      i = i + 1
    } else if a == "--level" {
      o.level = arg_or(args, i, o.level)
      i = i + 2
    } else if a == "--funnel" {
      o.funnel = true
      o.level = "3"
      i = i + 1
    } else if a.has_prefix("--") {
      i = i + 1
    } else {
      if o.coord == "" {
        o.coord = a
      }
      i = i + 1
    }
  }
  Some((cmd, o))
}

///|
async fn write_text(path : String, text : String) -> Bool {
  @fs.write_text(path, text) catch {
    _ => return false
  }
  true
}

///|
async fn read_text(path : String) -> String? {
  let text = @fs.read_text(path) catch { _ => return None }
  Some(text)
}

///|
fn event_json(ev : @app.TraceEvent) -> String {
  let out = StringBuilder::new()
  out.write_string("{\"k\":\"")
  out.write_string(ev.kind.tag())
  out.write_string("\",\"fn\":\"")
  out.write_string(@app.json_escape(ev.fn_name))
  out.write_string("\",\"file\":\"")
  out.write_string(@app.json_escape(ev.file))
  out.write_string("\",\"line\":")
  out.write_string(ev.line.to_string())
  out.write_string(",\"stmt\":")
  out.write_string(ev.stmt.to_string())
  out.write_string(",\"name\":\"")
  out.write_string(@app.json_escape(ev.name))
  out.write_string("\",\"value\":\"")
  out.write_string(@app.json_escape(ev.value))
  out.write_string("\",\"tainted\":")
  out.write_string(if ev.tainted { "true" } else { "false" })
  out.write_string(",\"trial\":")
  out.write_string(ev.trial.to_string())
  out.write_string(",\"detail\":\"")
  out.write_string(@app.json_escape(ev.detail))
  out.write_string("\"}\n")
  out.to_string()
}

///|
fn traces_jsonl(events : Array[@app.TraceEvent]) -> String {
  let out = StringBuilder::new()
  for ev in events {
    out.write_string(event_json(ev))
  }
  out.to_string()
}

///|
fn count_kind(fs : Array[@app.Finding], kind : @app.FindingKind) -> Int32 {
  let mut n = 0
  for f in fs {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn summary_json(input : @app.ReportInput, report_path : String) -> String {
  let out = StringBuilder::new()
  out.write_string("{\n")
  out.write_string("  \"module\": \"" + @app.json_escape(input.coord) + "\",\n")
  out.write_string(
    "  \"version\": \"" + @app.json_escape(input.version) + "\",\n",
  )
  out.write_string("  \"report\": \"" + @app.json_escape(report_path) + "\",\n")
  out.write_string("  \"files\": " + input.files.to_string() + ",\n")
  out.write_string("  \"functions\": " + input.funcs.to_string() + ",\n")
  out.write_string("  \"statements\": " + input.stmts.to_string() + ",\n")
  out.write_string(
    "  \"unsupported_statements\": " + input.unsupported.to_string() + ",\n",
  )
  out.write_string(
    "  \"trace_events\": " + input.run.events.length().to_string() + ",\n",
  )
  out.write_string("  \"steps\": " + input.run.steps.to_string() + ",\n")
  out.write_string("  \"elapsed_ms\": " + input.elapsed_ms.to_string() + ",\n")
  out.write_string(
    "  \"dead_code\": " +
    count_kind(input.cfg_findings, @app.FDead).to_string() +
    ",\n",
  )
  out.write_string(
    "  \"unreachable\": " +
    count_kind(input.cfg_findings, @app.FUnreachable).to_string() +
    ",\n",
  )
  out.write_string(
    "  \"infinite_loop\": " +
    count_kind(input.cfg_findings, @app.FInfinite).to_string() +
    ",\n",
  )
  out.write_string(
    "  \"taint_sinks\": " + input.taint.sinks.length().to_string() + ",\n",
  )
  out.write_string(
    "  \"range_vars\": " + input.run.ranges.stats.length().to_string() + ",\n",
  )
  let abs_count = match input.abstract {
    Some(a) => a.findings.length()
    None => 0
  }
  let (proved, failed, unknown) = match input.proof {
    Some(p) => @app.proof_counts(p.vcs)
    None => (0, 0, 0)
  }
  out.write_string("  \"level\": " + input.level.to_string() + ",\n")
  out.write_string("  \"abstract_findings\": " + abs_count.to_string() + ",\n")
  out.write_string("  \"vcs_proved\": " + proved.to_string() + ",\n")
  out.write_string("  \"vcs_failed\": " + failed.to_string() + ",\n")
  out.write_string("  \"vcs_unknown\": " + unknown.to_string() + ",\n")
  out.write_string("  \"slices\": " + input.slices.length().to_string() + "\n")
  out.write_string("}\n")
  out.to_string()
}

///|
fn coord_file_stem(coord : String) -> String {
  let base = coord.replace_all(old="/", new="_").to_string()
  if base == "" {
    "module"
  } else {
    base
  }
}

///|
async fn analyze(opts : Opts) -> Unit {
  if opts.coord == "" && opts.dir == "" {
    println(usage())
    return
  }
  let t0 = @async.now()
  let mut coord = opts.coord
  let mut version = ""
  let mut root = opts.dir
  let mut pinning = ""
  if root != "" {
    let manifest_text = read_text(@app.path_join(root, "moon.mod"))
    match manifest_text {
      Some(t) => {
        let m = @app.parse_manifest(t)
        if coord == "" {
          coord = if m.name == "" { "local/module" } else { m.name }
        }
        version = m.version
        pinning = "explicit local directory; no registry resolution performed"
      }
      None => {
        if coord == "" {
          coord = "local/module"
        }
        version = "0.0.0"
        pinning = "explicit local directory without moon.mod"
      }
    }
  } else {
    match @app.parse_coord(coord) {
      None => {
        println("ERROR\tcoordinate must be <author>/<module>[@version]")
        return
      }
      Some(c) => {
        let fetched = @app.fetch_module(c, ".") catch {
          _ => {
            println(
              "ERROR\tmoon fetch failed; run `moon fetch " +
              coord +
              "` and retry with --dir .repos/<author>/<module>/<version>",
            )
            return
          }
        }
        if !fetched.ok {
          println("ERROR\tcould not resolve " + coord)
          if !opts.quiet {
            println(fetched.log)
          }
          return
        }
        root = fetched.root
        version = fetched.version
        pinning = if c.version == "" || c.version == "latest" {
          "`@latest` resolved through `moon fetch` (local registry index, newest non-yanked version) and pinned to `" +
          version +
          "` for ingestion, execution and reporting"
        } else {
          "explicit version `" + version + "`; no resolution step"
        }
      }
    }
  }
  let (ast, stats) = @app.load_module(root, coord, version, 2000) catch {
    _ => {
      println("ERROR\tfailed to read module sources at " + root)
      return
    }
  }
  let version2 = if version == "" { "0.0.0" } else { version }
  if opts.list_functions {
    println("FUNCTION\tFILE\tSTATEMENTS")
    for fd in ast.all_funcs_including_tests() {
      println(fd.name + "\t" + fd.file + "\t" + fd.body.length().to_string())
    }
    return
  }
  let funcs = ast.all_funcs()
  let cfgs : Array[@app.Cfg] = []
  let cfg_findings : Array[@app.Finding] = []
  let mut i = 0
  while i < funcs.length() && i < 600 {
    let c = @app.build_cfg(funcs[i])
    cfgs.push(c)
    for f in @app.cfg_findings(c) {
      cfg_findings.push(f)
    }
    i = i + 1
  }
  let run_opts : @app.RunOptions = {
    trials: opts.trials,
    max_steps: 2000,
    max_depth: 6,
    max_functions: opts.max_functions,
    entry_filter: opts.function_name,
  }
  let run = @app.run_module(ast, run_opts)
  if opts.slice != "" {
    match opts.slice.find("@") {
      Some(i) => {
        let target = opts.slice[i + 1:].to_owned()
        let extra = @app.run_function_by_name(ast, target, run_opts)
        for e in extra.events {
          run.events.push(e)
        }
        for f in extra.findings {
          run.findings.push(f)
        }
        run.ranges.merge_from(extra.ranges)
      }
      None => ()
    }
  }
  let taint = @app.build_taint(run.events, run.findings)
  let level = @app.parse_int(opts.level, 1)
  let abs_result : @app.AbsResult? = if opts.funnel || level >= 2 {
    Some(@app.run_abstract(ast, opts.max_functions, 200000))
  } else {
    None
  }
  let critical = @app.critical_functions(run.findings)
  match abs_result {
    Some(a) =>
      for f in a.findings {
        if f.fn_name != "" && !critical.contains(f.fn_name) {
          critical.push(f.fn_name)
        }
      }
    None => ()
  }
  let proof_result : @app.ProofResult? = if opts.funnel || level >= 3 {
    for extra in @app.funcs_with_contracts(ast) {
      if !critical.contains(extra) {
        critical.push(extra)
      }
    }
    Some(@app.check_contracts(ast, critical))
  } else {
    None
  }
  let funnel_result : @app.FunnelResult? = if opts.funnel {
    match abs_result {
      Some(a) => {
        let pr = match proof_result {
          Some(p) => p
          None => @app.ProofResult::new()
        }
        Some(@app.build_funnel(run.findings, a, pr, critical))
      }
      None => None
    }
  } else {
    None
  }
  let slices : Array[@app.SliceResult] = []
  if opts.slice != "" {
    let graph = @app.build_dep_graph(run.events)
    let direction = if opts.direction == "forward" {
      @app.SliceForward
    } else {
      @app.SliceBackward
    }
    let s = @app.slice_graph(
      graph,
      ast,
      opts.slice,
      direction,
      opts.max_slice * 4,
    )
    slices.push(s)
  }
  let coverage : @app.Coverage? = if opts.coverage_path != "" {
    match read_text(opts.coverage_path) {
      Some(text) => Some(@app.parse_cobertura(text, opts.coverage_path))
      None => None
    }
  } else {
    None
  }
  let r_opts : @app.ReportOptions = {
    max_cfg: opts.max_cfg,
    max_taint_nodes: opts.max_taint,
    max_slice_nodes: opts.max_slice,
    max_path_events: 24,
  }
  let elapsed = (@async.now() - t0).to_int()
  let input : @app.ReportInput = {
    coord,
    version: version2,
    pinning,
    root,
    target: ast.manifest_target,
    deps: ast.manifest_deps,
    files: stats.files,
    funcs: stats.funcs,
    stmts: stats.stmts,
    unsupported: stats.unsupported,
    issues: stats.issues,
    cfgs,
    cfg_findings,
    run,
    taint,
    slices,
    coverage,
    opts: r_opts,
    elapsed_ms: elapsed,
    level,
    funnel: funnel_result,
    abstract: abs_result,
    proof: proof_result,
  }
  @fs.mkdir(opts.out, recursive=true, allow_exist=true) catch {
    _ => ()
  }
  let stem = @app.safe_stem(coord_file_stem(coord) + "_" + version2)
  let report_path = @app.path_join(opts.out, stem + ".md")
  let trace_path = @app.path_join(opts.out, stem + "_trace.jsonl")
  let summary_path = @app.path_join(opts.out, stem + "_summary.json")
  let md = @app.render_report(input)
  let _ = write_text(report_path, md) catch { _ => false }
  let _ = write_text(trace_path, traces_jsonl(input.run.events)) catch {
    _ => false
  }
  let _ = write_text(summary_path, summary_json(input, report_path)) catch {
    _ => false
  }
  if opts.quiet {
    println("REPORT\t" + report_path)
    return
  }
  println("module\t" + coord + "@" + version2)
  println("root\t" + root)
  println("files\t" + stats.files.to_string())
  println("functions\t" + stats.funcs.to_string())
  println("statements\t" + stats.stmts.to_string())
  println("unsupported\t" + stats.unsupported.to_string())
  println("trace_events\t" + input.run.events.length().to_string())
  println("steps\t" + input.run.steps.to_string())
  println("dead_code\t" + count_kind(cfg_findings, @app.FDead).to_string())
  println(
    "unreachable\t" + count_kind(cfg_findings, @app.FUnreachable).to_string(),
  )
  println(
    "infinite_loop\t" + count_kind(cfg_findings, @app.FInfinite).to_string(),
  )
  println("taint_sinks\t" + input.taint.sinks.length().to_string())
  println("level\t" + level.to_string())
  match input.abstract {
    Some(a) => println("abstract_findings\t" + a.findings.length().to_string())
    None => ()
  }
  match input.proof {
    Some(p) => {
      let (proved, failed, unknown) = @app.proof_counts(p.vcs)
      println("vcs_proved\t" + proved.to_string())
      println("vcs_failed\t" + failed.to_string())
      println("vcs_unknown\t" + unknown.to_string())
    }
    None => ()
  }
  println("elapsed_ms\t" + elapsed.to_string())
  println("REPORT\t" + report_path)
  println("TRACE\t" + trace_path)
  println("SUMMARY\t" + summary_path)
}

///|
/// Run the CLI with `args`.
///
/// The entry point is a FUNCTION and not the special `main`, because the
/// module has two executables -- the root package, which is what `moonx`
/// resolves, and `src/cli`, which is the published CLI coordinate. Both call
/// this one function, so there is ONE implementation of the CLI and two ways
/// to reach it.
pub async fn run(args : Array[String]) -> Unit {
  match parse_args(args) {
    None => println(usage())
    Some((cmd, opts)) =>
      if cmd == "help" {
        println(usage())
      } else {
        analyze(opts)
      }
  }
}
