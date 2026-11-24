///|
/// The LAYOUT STABILITY self-check.
///
/// The same analysis, re-sampled with different sample sizes, and the findings
/// compared row by row. A finding class whose rows appear in EVERY run does
/// not depend on the sample; one that appears in SOME of them does, and the
/// report says so instead of presenting it as a property of the program.
///
/// The MAIN run is part of the comparison: a class that only the main run
/// found is exactly the class a reader would mistake for a property of the
/// program, so it has to be in the table.
///
/// The abstract layer's findings are passed as the CONSTANT set: they are a
/// may-analysis over the whole input abstraction, so they do not depend on
/// the sample and re-running them would only re-measure what is already
/// known. The interpreter's findings are the ones the sample decides.
///
/// The cost is one extra interpreter run per sample size, so the check is
/// opt-in.
fn stability_check(
  ast : @app.ModuleAst,
  run_opts : @app.RunOptions,
  per_function : Bool,
  per_package : Bool,
  max_total_steps : Int32,
  family_include : Array[String],
  family_exclude : Array[String],
  constant : Array[@app.Finding],
  main_findings : Array[@app.Finding],
) -> @app.StabilityResult {
  let sizes : Array[Int32] = [1, 2, 4]
  let runs : Array[Array[@app.Finding]] = []
  for s in sizes {
    let o : @app.RunOptions = {
      trials: s,
      max_steps: run_opts.max_steps,
      max_depth: run_opts.max_depth,
      max_functions: run_opts.max_functions,
      entry_filter: run_opts.entry_filter,
    }
    // The SAME MODE as the main run.  The check compares the main run with
    // the re-sampled ones, so a re-sample that scanned a DIFFERENT set of
    // functions would be comparing two different analyses and calling the
    // difference "instability".
    let (r, _packages) = @app.run_module_packages(
      ast,
      o,
      per_function~,
      max_total_steps~,
      per_package~,
    )
    runs.push(@app.filter_findings(r.findings, family_include, family_exclude))
  }
  sizes.push(run_opts.trials)
  runs.push(main_findings)
  @app.compare_runs(sizes, runs, constant~)
}

///|
struct Opts {
  mut coord : String
  mut dir : String
  mut out : String
  mut trials : Int32
  /// The COUNT cap on entered functions. 0 = no count cap: the default bound
  /// is the module-wide step budget below.
  mut max_functions : Int32
  /// The MODULE-WIDE STEP BUDGET of the dynamic layer. 0 = no budget.
  mut max_total_steps : Int32
  mut slice : String
  mut direction : String
  mut coverage_path : String
  mut max_cfg : Int32
  mut max_cfg_functions : Int32
  mut max_taint : Int32
  mut max_slice : Int32
  /// The rows a findings table may show. The findings the table does not
  /// show are in the report's `_findings.jsonl` sidecar, so the bound costs
  /// the reader nothing.
  mut max_findings : Int32
  mut quiet : Bool
  mut function_name : String
  mut list_functions : Bool
  mut level : String
  mut funnel : Bool
  /// Directory NAMES to skip during the walk. Repeatable.
  excludes : Array[String]
  /// The family profile: which finding codes are reported.
  family_include : Array[String]
  family_exclude : Array[String]
  /// A CONTRACT REQUEST, not a scan: `--explain <code>` prints one family's
  /// contract and stops, `--explain-all` prints the roster and stops.
  mut explain_code : String
  mut explain_all : Bool
  /// Print the ADEQUACY block.
  mut metrics : Bool
  /// Enter EVERY function as an entry point, with no `--max-functions` cap.
  mut per_function : Bool
  /// Scan PACKAGE BY PACKAGE, each package with its own step budget.
  mut per_package : Bool
  /// Re-sample the analysis and report which findings depend on the sample.
  mut stability : Bool
  /// Re-run each finding an execution produced on its own input, and shrink
  /// that input to the smallest one that still reproduces it.
  mut counterexamples : Bool
  /// How many findings the counterexample minimisation may cover.
  mut counterexample_limit : Int32
}

///|
fn Opts::default() -> Opts {
  {
    coord: "",
    dir: "",
    out: "reports",
    trials: 8,
    max_functions: 0,
    max_total_steps: @app.DEFAULT_MAX_TOTAL_STEPS,
    slice: "",
    direction: "backward",
    coverage_path: "",
    max_cfg: 8,
    max_cfg_functions: 600,
    max_taint: 40,
    max_slice: 40,
    max_findings: 300,
    quiet: false,
    function_name: "",
    list_functions: false,
    level: "1",
    funnel: false,
    excludes: [],
    family_include: [],
    family_exclude: [],
    explain_code: "",
    explain_all: false,
    metrics: false,
    per_function: false,
    per_package: false,
    stability: false,
    counterexamples: false,
    counterexample_limit: 64,
  }
}

///|
fn usage() -> String {
  (
    #|LunaFlow — dynamic-first CFG / taint / range / slicing visualizer
    #|
    #|Usage:
    #|  LunaFlow [analyze] [<target>] [options]
    #|  LunaFlow analyze --dir <path> [options]
    #|  LunaFlow <author>/<module>[@<version>|@latest] [options]
    #|
    #|  <target>   a registry coordinate (author/module[@version]) OR a local
    #|             directory. With NO target at all, the CURRENT DIRECTORY is
    #|             analysed — the same rule the peer analyzer uses, so the two
    #|             tools take the same invocation.
    #|
    #|The last form is "analyze" with the coordinate where the subcommand
    #|would be. It exists because "moonx" hands the TARGET to the program as
    #|its first argument: "moonx riantr/LunaFlow@latest riantr/LunaFlow@latest"
    #|runs this binary with "riantr/LunaFlow@latest" as argv[1].
    #|
    #|Options:
    #|  --dir <path>        analyze a local directory (same as a path target)
    #|  --out <dir>         report directory (default: reports)
    #|  --trials <n>        synthesized input trials per function (default: 8)
    #|  --max-functions <n> cap on interpreted functions (default: 0, no cap;
    #|                      the default scan enters EVERY function)
    #|  --max-total-steps <n>
    #|                      the step budget of the dynamic layer: the module's
    #|                      own by default, and EACH PACKAGE's own under
    #|                      --per-package (default: 100000; 0 = no budget)
    #|  --slice <crit>      slice criterion: <var>@<fn>, <fn>:<line>, or <var>
    #|  --function <fn>     interpret only this function (default: all)
    #|  --level <1|2|3>     proof strength: 1 interpreter, 2 values, 3 contracts (default 1)
    #|  --funnel            run L1 -> L2 -> L3 with escalation (implies level 3)
    #|  --forward           forward slice (default: backward)
    #|  --coverage <xml>    import a Cobertura XML from `moon coverage report`
    #|  --max-cfg <n>       CFG diagrams to render (default: 8)
    #|  --max-cfg-functions <n>
    #|                      functions the CFG pass covers (default: 600; the
    #|                      FIRST ones in file order, so a larger module
    #|                      leaves the rest with no CFG and no CFG finding)
    #|  --exclude <name>    a directory name to skip, repeatable
    #|  --max-findings <n>  rows a findings table may show (default: 300); the
    #|                      findings it does not show are in the report's
    #|                      _findings.jsonl sidecar, and the table says how
    #|                      many of each family there are in the whole set
    #|  --families <codes>  report ONLY these finding codes (comma or space
    #|                      separated); --exclude-families drops them instead
    #|  --explain <code>    print one family's contract and STOP -- no scan
    #|  --explain-all       print the family roster and STOP -- no scan
    #|  --metrics           print the ADEQUACY block: what was read, what was
    #|                      understood, what was entered, what was found
    #|  --per-function      enter EVERY function as an entry point, with the
    #|                      step budget and the --max-functions cap lifted
    #|  --per-package       scan PACKAGE BY PACKAGE, each package with its own
    #|                      step budget, and write one trace per package
    #|  --counterexamples   re-run each finding an execution produced on its own
    #|                      input, and shrink that input to the smallest one
    #|                      that still reproduces it (report 5.12)
    #|  --counterexample-limit <n>
    #|                      how many findings the minimisation may cover
    #|                      (default 64)
    #|  --quiet             only print the report path
  )
}

///|
fn arg_value(args : Array[String], i : Int32) -> String {
  // The index is bounded at BOTH ends. The upper bound was there; the lower
  // one was not, and it came from the callers -- every one of which passes an
  // index into `args`, so a negative one would read before the first
  // argument. MEASURED: the self-scan reported `index may be out of bounds on
  // some inputs` here, with the evidence `index [-999999,1000001]`.
  if i >= 0 && i + 1 < args.length() {
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
/// Parse the command line.
///
/// The TARGET SLOT follows the peer analyzer's rule, so the two tools take
/// the same invocation:
///
///   * no target at all → the CURRENT DIRECTORY is analysed;
///   * a target that is a coordinate → it is fetched and analysed;
///   * a target that is NOT a coordinate → it is a local path, and it is
///     analysed where it stands.
///
/// The difference from the peer is that this analyzer still has an `analyze`
/// subcommand, and that `--dir` still names a tree. Both are kept: they are
/// in the published documentation and in every QA harness.
fn parse_args(args : Array[String]) -> (String, Opts)? {
  let o = Opts::default()
  // NO TARGET IS NOT AN ERROR. The current directory is the default, and the
  // peer analyzer defaults the same way.
  if args.length() < 2 {
    return Some(("analyze", o))
  }
  let mut cmd = args[1]
  if cmd == "help" || cmd == "--help" || cmd == "-h" {
    return Some(("help", Opts::default()))
  }
  let mut i = 1
  if cmd == "analyze" {
    i = 2
  } else if !cmd.has_prefix("--") {
    // THE TARGET SLOT. A coordinate is fetched; anything else is a path.
    if is_coord(cmd) {
      o.coord = cmd
    } else {
      o.dir = cmd
    }
    i = 2
  }
  cmd = "analyze"
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
    } else if a == "--max-total-steps" {
      o.max_total_steps = @app.parse_int(arg_value(args, i), o.max_total_steps)
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
    } else if a == "--max-cfg-functions" {
      o.max_cfg_functions = @app.parse_int(
        arg_value(args, i),
        o.max_cfg_functions,
      )
      i = i + 2
    } else if a == "--max-taint" {
      o.max_taint = @app.parse_int(arg_value(args, i), o.max_taint)
      i = i + 2
    } else if a == "--max-slice" {
      o.max_slice = @app.parse_int(arg_value(args, i), o.max_slice)
      i = i + 2
    } else if a == "--max-findings" {
      o.max_findings = @app.parse_int(arg_value(args, i), o.max_findings)
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
    } else if a == "--exclude" {
      // A DIRECTORY NAME to skip. Repeatable.
      let v = arg_value(args, i)
      if v == "" {
        println("ERROR\t--exclude needs a directory name")
        return None
      }
      o.excludes.push(v)
      i = i + 2
    } else if a == "--families" {
      // The family PROFILE: report ONLY these finding codes.
      let v = arg_value(args, i)
      if v == "" {
        println("ERROR\t--families needs a list of family codes")
        return None
      }
      for c in @app.split_codes(v) {
        o.family_include.push(c)
      }
      i = i + 2
    } else if a == "--exclude-families" {
      // Report everything EXCEPT these finding codes.
      let v = arg_value(args, i)
      if v == "" {
        println("ERROR\t--exclude-families needs a list of family codes")
        return None
      }
      for c in @app.split_codes(v) {
        o.family_exclude.push(c)
      }
      i = i + 2
    } else if a == "--explain" {
      o.explain_code = arg_value(args, i)
      if o.explain_code == "" {
        println(
          "ERROR\t--explain needs a family code; --explain-all lists them",
        )
        return None
      }
      i = i + 2
    } else if a == "--explain-all" {
      o.explain_all = true
      i = i + 1
    } else if a == "--metrics" {
      o.metrics = true
      i = i + 1
    } else if a == "--per-function" {
      o.per_function = true
      i = i + 1
    } else if a == "--per-package" {
      o.per_package = true
      i = i + 1
    } else if a == "--stability" {
      o.stability = true
      i = i + 1
    } else if a == "--counterexamples" {
      o.counterexamples = true
      i = i + 1
    } else if a == "--counterexample-limit" {
      o.counterexample_limit = @app.parse_int(
        arg_value(args, i),
        o.counterexample_limit,
      )
      i = i + 2
    } else if a.has_prefix("--") {
      i = i + 1
    } else {
      // A TARGET after the first slot. The first one wins; a coordinate that
      // follows a `--dir` LABELS the local scan, which is what it did before
      // the target slot learned about paths.
      if o.coord == "" && o.dir == "" {
        if is_coord(a) {
          o.coord = a
        } else {
          o.dir = a
        }
      } else if o.coord == "" && is_coord(a) {
        o.coord = a
      }
      i = i + 1
    }
  }
  Some((cmd, o))
}

///|
#cfg(any(target="native", target="wasm"))
async fn write_text(path : String, text : String) -> Bool {
  @fs.write_text(path, text) catch {
    _ => return false
  }
  true
}

///|
#cfg(any(target="native", target="wasm"))
async fn read_text(path : String) -> String? {
  let text = @fs.read_text(path) catch { _ => return None }
  Some(text)
}

///|
fn event_json(ev : @app.TraceEvent) -> String {
  let out = StringBuilder()
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
  let out = StringBuilder()
  for ev in events {
    out.write_string(event_json(ev))
  }
  out.to_string()
}

///|
/// The name of a package, as a FILE NAME.
///
/// The module's ROOT package is "", and a file name cannot end in nothing, so
/// the root package is called "root".  The rest is the package's path with
/// the separators flattened, so `src/app` becomes `src_app` -- and
/// `safe_stem` is what makes the result safe to append under `--out`.
fn package_stem(name : String) -> String {
  if name == "" {
    "root"
  } else {
    @app.safe_stem(name)
  }
}

///|
/// The trace, SPLIT BY PACKAGE: one file per package.
///
/// THE SPLIT IS THE POINT.  A trace the registry has to read is a file with
/// a SIZE, and the largest archive the registry has served held one
/// 39,479,846-byte entry -- so a single trace of 77 MB cannot be published at
/// all, whatever it compresses to.  Split by package, every entry is one
/// package's own trace, and the module's evidence becomes a SET of entries
/// instead of one oversized one.
///
/// The events are written in ONE pass into one builder per package, so the
/// memory is the size of the trace and not the size of the trace PLUS a copy
/// of it.  MEASURED on the toolchain this tree is written against: a
/// `StringBuilder` held in an `Array` keeps the writes -- `arr[0].write(..)`
/// twice reads back as both writes, not as the last one.
///
/// THE BUILDERS ARE A MAP, AND THAT IS DELIBERATE.  A package is named, not
/// indexed, and a builder in an ARRAY would need an index -- and the index
/// would need the lengths of two arrays the analyser cannot relate.  MEASURED:
/// the self-scan reported `TAINT-INDEX`, `TAINT-INDEX-RANGE` and `INDEX-OOB`
/// on the array version, and the map has no index to be out of bounds.  The
/// write-back through a local binding was measured too: `b.write_string(..)`
/// on a builder fetched with `get` DOES reach the map.
///
/// The events of the module's GLOBAL region belong to the package that
/// DECLARES them, so nothing is left out of the split.  An event whose file
/// is not in the module is written to NO file: it is not this module's
/// event, and putting it in the nearest package would be a lie.
async fn write_package_traces(
  ast : @app.ModuleAst,
  events : Array[@app.TraceEvent],
  out : String,
  stem : String,
) -> Array[String] {
  let names = @app.module_packages(ast)
  let map = @app.package_of_files(ast)
  let builders : Map[String, StringBuilder] = Map([])
  for n in names {
    builders[n] = StringBuilder()
  }
  for e in events {
    match map.get(e.file) {
      Some(p) =>
        match builders.get(p) {
          Some(b) => b.write_string(event_json(e))
          None => ()
        }
      None => ()
    }
  }
  let written : Array[String] = []
  // The names are walked BY VALUE, with no index at all.  MEASURED: the
  // self-scan reported `TAINT-INDEX` on `names[i]` while the loop was
  // bounded by `names.length()` -- the analyser could not tell that the
  // list is not empty, and an index into a list that might be empty is a
  // read it will not discharge.
  for n in names {
    let path = @app.path_join(
      out,
      stem + "_" + package_stem(n) + "_trace.jsonl",
    )
    match builders.get(n) {
      Some(b) => {
        let _ = write_text(path, b.to_string()) catch { _ => false }
      }
      None => ()
    }
    written.push(path)
  }
  written
}

///|
/// The findings of the report, each ONCE.
///
/// A finding that appears in two of the report's tables appears ONCE here.
/// The key is the finding's identity -- its family, its place, its function
/// and its message -- and not its position, so a reader can count the
/// findings without counting a table twice.
fn unique_findings(fs : Array[@app.Finding]) -> Array[@app.Finding] {
  let out : Array[@app.Finding] = []
  let seen : Map[String, Bool] = Map([])
  for f in fs {
    let key = f.kind.code() +
      "|" +
      f.file +
      "|" +
      f.line.to_string() +
      "|" +
      f.fn_name +
      "|" +
      f.message
    if seen.get_or_default(key, false) {
      continue
    }
    seen[key] = true
    out.push(f)
  }
  out
}

///|
/// The COUNTEREXAMPLE RUN BUDGET: how many executions the minimisation may
/// spend before it stops and says so.  The minimisation re-runs a function
/// once per candidate it tries, so the cost is a function of the module, and
/// a bound that is not stated would be a bound the reader cannot see.
const COUNTEREXAMPLE_RUN_BUDGET = 4000

///|
/// The report, rendered from the analysis.
///
/// The arguments are the same for every render of one run, so they are
/// gathered here rather than written twice: the report is rendered twice
/// when the counterexample minimisation is on -- once to learn which
/// findings the report shows, and once with the counterexamples in it.
fn render_report(
  input : @app.ReportInput,
  per_function : Bool,
  globals : Array[@app.GlobalRow],
  allocs : Array[@app.AllocSite],
  growth : Array[@app.Finding],
  stability : @app.StabilityResult?,
  issues : Array[@app.ParseIssue],
  ffi : @app.FfiModel,
  conc : @app.ConcModel,
  ipc : @app.IpcModel,
  findings_out : Array[@app.Finding],
  counterexamples : @app.MinimizeResult?,
  packages : Array[@app.PackageRun],
) -> String {
  @app.render_report(
    input,
    per_function~,
    globals~,
    allocs~,
    growth~,
    stability~,
    issues~,
    ffi=Some(ffi),
    conc=Some(conc),
    ipc=Some(ipc),
    findings_out~,
    counterexamples~,
    packages~,
  )
}

///|
/// Every counterexample, one JSON object per line.
///
/// This is the machine-readable half of the report's §5.12: the report says
/// what a reader needs to see, and this says what a program needs to read.
/// The `indices` are the positions the values took in the analyser's own
/// candidate lists, so a reader can check the value against the candidate
/// it came from without parsing a rendered value.
fn counterexamples_jsonl(res : @app.MinimizeResult) -> String {
  let out = StringBuilder()
  for cx in res.counterexamples {
    out.write_string("{\"rule\":\"")
    out.write_string(cx.kind.code())
    out.write_string("\",\"file\":\"")
    out.write_string(@app.json_escape(cx.file))
    out.write_string("\",\"line\":")
    out.write_string(cx.line.to_string())
    out.write_string(",\"fn\":\"")
    out.write_string(@app.json_escape(cx.fn_name))
    out.write_string("\",\"entry\":\"")
    out.write_string(@app.json_escape(cx.entry))
    out.write_string("\",\"params\":[")
    let mut i = 0
    while i < cx.params.length() {
      if i > 0 {
        out.write_string(",")
      }
      out.write_string("\"")
      out.write_string(@app.json_escape(cx.params[i]))
      out.write_string("\"")
      i = i + 1
    }
    out.write_string("],\"types\":[")
    let mut t = 0
    while t < cx.types.length() {
      if t > 0 {
        out.write_string(",")
      }
      out.write_string("\"")
      out.write_string(@app.json_escape(cx.types[t]))
      out.write_string("\"")
      t = t + 1
    }
    out.write_string("],\"candidates\":[")
    let mut c = 0
    while c < cx.candidates.length() {
      if c > 0 {
        out.write_string(",")
      }
      out.write_string("[")
      let mut d = 0
      while d < cx.candidates[c].length() {
        if d > 0 {
          out.write_string(",")
        }
        out.write_string("\"")
        out.write_string(@app.json_escape(cx.candidates[c][d]))
        out.write_string("\"")
        d = d + 1
      }
      out.write_string("]")
      c = c + 1
    }
    out.write_string("],\"args\":[")
    let mut j = 0
    while j < cx.args.length() {
      if j > 0 {
        out.write_string(",")
      }
      out.write_string("\"")
      out.write_string(@app.json_escape(cx.args[j]))
      out.write_string("\"")
      j = j + 1
    }
    out.write_string("],\"indices\":[")
    let mut k = 0
    while k < cx.indices.length() {
      if k > 0 {
        out.write_string(",")
      }
      out.write_string(cx.indices[k].to_string())
      k = k + 1
    }
    out.write_string("],\"tried\":")
    out.write_string(cx.tried.to_string())
    out.write_string("}\n")
  }
  out.to_string()
}

///|
/// Every finding the report shows, one JSON object per line.
///
/// The report's findings tables are bounded, so the Markdown alone no longer
/// holds every finding. This is where the rest of them are, and it is
/// LOSSLESS: the set is exactly the set the report rendered, because the
/// report filled the list.
fn findings_jsonl(fs : Array[@app.Finding]) -> String {
  let out = StringBuilder()
  for f in fs {
    out.write_string("{\"rule\":\"")
    out.write_string(f.kind.code())
    out.write_string("\",\"severity\":\"")
    // The POLICY's severity, not the family's: an undecided claim carries the
    // severity the policy gives it, and the report's table reads the same
    // value, so the two cannot disagree.
    out.write_string(f.severity())
    out.write_string("\",\"verdict\":\"")
    out.write_string(f.verdict.code())
    out.write_string("\",\"fn\":\"")
    out.write_string(@app.json_escape(f.fn_name))
    out.write_string("\",\"file\":\"")
    out.write_string(@app.json_escape(f.file))
    out.write_string("\",\"line\":")
    out.write_string(f.line.to_string())
    out.write_string(",\"message\":\"")
    out.write_string(@app.json_escape(f.message))
    out.write_string("\",\"method\":\"")
    out.write_string(@app.json_escape(f.mode))
    out.write_string("\",\"confidence\":")
    out.write_string(@app.format_double(f.confidence))
    out.write_string(",\"evidence\":\"")
    out.write_string(@app.json_escape(f.evidence))
    out.write_string("\"}\n")
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
fn summary_json(
  input : @app.ReportInput,
  report_path : String,
  findings_path : String,
  findings_count : Int32,
) -> String {
  let out = StringBuilder()
  out.write_string("{\n")
  out.write_string("  \"module\": \"" + @app.json_escape(input.coord) + "\",\n")
  out.write_string(
    "  \"version\": \"" + @app.json_escape(input.version) + "\",\n",
  )
  out.write_string("  \"report\": \"" + @app.json_escape(report_path) + "\",\n")
  out.write_string(
    "  \"findings_jsonl\": \"" + @app.json_escape(findings_path) + "\",\n",
  )
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
  let abs_count = match input.abstract_result {
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
  out.write_string("  \"slices\": " + input.slices.length().to_string() + ",\n")
  out.write_string("  \"findings\": " + findings_count.to_string() + "\n")
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
  // NO TARGET AT ALL MEANS THE CURRENT DIRECTORY. The peer analyzer defaults
  // the same way, so `moonx riantr/LunaFlow@latest` and
  // `moonx riantr/moonbit_static_analysis@latest` do the same thing.
  let default_target = opts.coord == "" && opts.dir == ""
  let dir = if default_target { "." } else { opts.dir }
  // THE PROFILE IS VALIDATED BEFORE THE SCAN RUNS, and the two rules are
  // different on purpose:
  //
  //   * a code that names NO family is a WARNING, and the scan still runs. A
  //     family added in a later release must not make an older analyzer's
  //     profile unusable, and a typo must be loud rather than fatal.
  //   * a code that is BOTH included and excluded is an ERROR, and the scan
  //     does not run at all. The two rules contradict each other, so there is
  //     no reading of the profile that satisfies both, and which one won
  //     would be decided by the order of two `if`s inside the scanner.
  let (profile_warnings, profile_error) = @app.validate_profile(
    opts.family_include,
    opts.family_exclude,
  )
  for w in profile_warnings {
    println("WARNING\t" + w)
  }
  if profile_error != "" {
    println("ERROR\t" + profile_error)
    return
  }
  let t0 = @async.now()
  let mut coord = opts.coord
  let mut version = ""
  let mut root = dir
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
        pinning = if default_target {
          "the current directory, by default; no registry resolution performed"
        } else {
          "explicit local directory; no registry resolution performed"
        }
      }
      None => {
        if coord == "" {
          coord = "local/module"
        }
        version = "0.0.0"
        pinning = if default_target {
          "the current directory, by default, and it has no moon.mod"
        } else {
          "explicit local directory without moon.mod"
        }
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
            println(fetched.note)
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
  let (ast, stats) = @app.load_module(
    root,
    coord,
    version,
    2000,
    excludes=opts.excludes,
  ) catch {
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
  while i < funcs.length() && i < opts.max_cfg_functions {
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
  // The per-package mode scans the module package by package, each package
  // with its own step budget, and says what each package cost.  The
  // breakdown is EMPTY in the module-wide mode: there was no per-package
  // run, so there is no per-package result to report.
  let (run, packages) = @app.run_module_packages(
    ast,
    run_opts,
    per_function=opts.per_function,
    max_total_steps=opts.max_total_steps,
    per_package=opts.per_package,
  )
  // The GLOBAL REGION and the allocation classes are computed from the AST,
  // so they are a property of the module and not of the run.
  let global_rows = @app.global_rows(
    ast,
    @app.global_values_from_events(run.events),
  )
  let allocs = @app.analyze_allocations(ast)
  // The GROWTH check: a module-level collection that only ever grows. It is
  // computed from the AST, so it is a property of the module and not of the
  // run.
  let growth = @app.analyze_growth(ast)
  // The FOREIGN ADDRESS SPACE: the C boundary, computed from the AST, so it
  // is a property of the module and not of the run.
  let ffi_model = @app.analyze_ffi(ast)
  // The CONCURRENCY model: the tasks, the shared cells and the waits, also
  // computed from the AST, so it is a property of the module and not of the
  // run.
  let conc_model = @app.analyze_conc(ast)
  // The IPC AND BUFFER model: the reads that can come back short, the views
  // that go stale and the buffers two sides write. Also computed from the
  // AST, so it is a property of the module and not of the run.
  let ipc_model = @app.analyze_ipc(ast)
  // The parse issues, so the report can LIST them and not only count them.
  let parse_issues : Array[@app.ParseIssue] = []
  for f in ast.files {
    for i in f.issues {
      parse_issues.push(i)
    }
  }
  // The LAYOUT STABILITY self-check: the same analysis, re-sampled. It costs
  // one extra run per sample size, which is why it is opt-in. It is computed
  // after the abstract layer, because the abstract findings are part of the
  // comparison.
  let mut stability : @app.StabilityResult? = None
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
  // THE FAMILY PROFILE IS APPLIED TO THE FINDINGS THEMSELVES, and it is
  // applied at ONE point: after every finding has been collected (the slice
  // pass adds its own) and before the taint graph is built, so the graph's
  // sinks and the report's counts describe the SAME set of findings the
  // reader can see.
  let kept_run_findings = @app.filter_findings(
    run.findings,
    opts.family_include,
    opts.family_exclude,
  )
  run.findings.clear()
  for f in kept_run_findings {
    run.findings.push(f)
  }
  let kept_cfg_findings = @app.filter_findings(
    cfg_findings,
    opts.family_include,
    opts.family_exclude,
  )
  cfg_findings.clear()
  for f in kept_cfg_findings {
    cfg_findings.push(f)
  }
  let taint = @app.build_taint(run.events, run.findings)
  let level = @app.parse_int(opts.level, 1)
  // The ABSTRACT LAYER'S SCOPE IS THE WHOLE MODULE, and it is NOT the
  // interpreter's entry-point cap. It used to be `--max-functions` -- 150 by
  // default -- so on a 957-function module the abstract layer analysed 16 % of
  // the code and the report's L2 section said "_No findings._" without saying
  // that the other 84 % had never been looked at. The two caps bound
  // different things: the interpreter's cap bounds the TRACE, which is what
  // the A12 size budget is about, and the abstract layer's own step budget
  // bounds the abstract analysis.
  //
  // The universe is every function the module's AST holds that has a body --
  // and `ast.all_funcs()` EXCLUDES THE `test` BLOCKS, because the filter is
  // on the FUNCTION (`fn.is_test`), not on the FILE. A plain helper that
  // happens to live in a `_test.mbt` file is not a test block and stays in the
  // universe: the scanner reads every `.mbt` file it finds (it excludes build
  // and vendored trees, not `_test.mbt`), so a module's test files' HELPERS
  // are analysed while its `test "..." { }` blocks are not.
  //
  // That is deliberate: the layer's claim is "exhaustive over the input
  // abstraction", and the input abstraction is the module as it was scanned.
  // It is worth knowing for a module whose tests are most of its code
  // (doubleML: 129 of its 220 `.mbt` files are test files) -- and the finding
  // split is what says how much of the output is about test code rather than
  // production code.
  let mut abs_universe = 0
  for f in ast.all_funcs() {
    if f.body.length() > 0 {
      abs_universe = abs_universe + 1
    }
  }
  // The FLOW pass's universe: the functions the CFG pass was given. It is
  // the count of the functions that are not test blocks -- NOT the scanner's
  // count, which includes them. The coverage line divides by this, so the
  // number it reports is about the functions the pass could have covered.
  let cfg_universe = ast.all_funcs().length()
  let abs_result : @app.AbsResult? = if opts.funnel || level >= 2 {
    Some(@app.run_abstract(ast, abs_universe, 200000))
  } else {
    None
  }
  match abs_result {
    Some(a) => {
      let kept_abs = @app.filter_findings(
        a.findings,
        opts.family_include,
        opts.family_exclude,
      )
      a.findings.clear()
      for f in kept_abs {
        a.findings.push(f)
      }
    }
    None => ()
  }
  // The stability self-check needs the abstract findings, so it runs here.
  if opts.stability {
    let constant : Array[@app.Finding] = []
    match abs_result {
      Some(a) =>
        for f in a.findings {
          constant.push(f)
        }
      None => ()
    }
    stability = Some(
      stability_check(
        ast,
        run_opts,
        opts.per_function,
        opts.per_package,
        opts.max_total_steps,
        opts.family_include,
        opts.family_exclude,
        constant,
        run.findings,
      ),
    )
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
    max_findings: opts.max_findings,
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
    abstract_result: abs_result,
    proof: proof_result,
    abs_universe,
    cfg_universe,
  }
  ensure_dir(opts.out)
  let stem = @app.safe_stem(coord_file_stem(coord) + "_" + version2)
  let report_path = @app.path_join(opts.out, stem + ".md")
  let trace_path = @app.path_join(opts.out, stem + "_trace.jsonl")
  let summary_path = @app.path_join(opts.out, stem + "_summary.json")
  let findings_path = @app.path_join(opts.out, stem + "_findings.jsonl")
  let counterexamples_path = @app.path_join(
    opts.out,
    stem + "_counterexamples.jsonl",
  )
  // The report's findings tables are BOUNDED, so the report alone no longer
  // holds every finding. The sidecar does, and the report is what decides
  // what a finding is -- the sink is filled by the report itself, so the
  // sidecar cannot drift from the tables it complements.
  //
  // THE COUNTEREXAMPLES.  The minimisation's targets are the findings the
  // REPORT shows -- a counterexample is only useful for a claim the reader
  // can see -- so the report is rendered once to learn them, and once more
  // with the counterexamples in it.  The second render is the one that is
  // written; the first is how the minimisation learns its targets.  The
  // render is string building, and the minimisation is what costs.
  let shown : Array[@app.Finding] = []
  let mut minimize_result : @app.MinimizeResult? = None
  if opts.counterexamples {
    let _ = render_report(
      input,
      opts.per_function,
      global_rows,
      allocs,
      growth,
      stability,
      parse_issues,
      ffi_model,
      conc_model,
      ipc_model,
      shown,
      None,
      packages,
    )
    minimize_result = Some(
      @app.minimize_counterexamples(
        ast,
        run_opts,
        shown,
        opts.counterexample_limit,
        COUNTEREXAMPLE_RUN_BUDGET,
      ),
    )
  }
  let rendered : Array[@app.Finding] = []
  let md = render_report(
    input,
    opts.per_function,
    global_rows,
    allocs,
    growth,
    stability,
    parse_issues,
    ffi_model,
    conc_model,
    ipc_model,
    rendered,
    minimize_result,
    packages,
  )
  let _ = write_text(report_path, md) catch { _ => false }
  // The TRACE.  In the module-wide mode it is ONE file; in the per-package
  // mode it is ONE FILE PER PACKAGE, and the split is what makes a large
  // trace publishable: the registry reads files, and a file has a size.
  let trace_paths : Array[String] = []
  if opts.per_package {
    for p in write_package_traces(ast, input.run.events, opts.out, stem) {
      trace_paths.push(p)
    }
  } else {
    let _ = write_text(trace_path, traces_jsonl(input.run.events)) catch {
      _ => false
    }
    trace_paths.push(trace_path)
  }
  let uniq = unique_findings(rendered)
  let _ = write_text(
    summary_path,
    summary_json(input, report_path, findings_path, uniq.length()),
  ) catch {
    _ => false
  }
  let _ = write_text(findings_path, findings_jsonl(uniq)) catch { _ => false }
  match minimize_result {
    Some(res) => {
      let _ = write_text(counterexamples_path, counterexamples_jsonl(res)) catch {
        _ => false
      }
    }
    None => ()
  }
  if opts.metrics {
    for line in metrics_lines(input, ast, packages) {
      println(line)
    }
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
  match input.abstract_result {
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
  for p in trace_paths {
    println("TRACE\t" + p)
  }
  println("FINDINGS\t" + findings_path)
  println("SUMMARY\t" + summary_path)
}

///|
/// The ADEQUACY block: how much of the target was actually understood.
///
/// The shape is the peer's: TAB-separated `METRICS` lines, one per lens, and
/// every line carries its own coverage — a number without its coverage is
/// half a number.
fn metrics_lines(
  input : @app.ReportInput,
  ast : @app.ModuleAst,
  packages : Array[@app.PackageRun],
) -> Array[String] {
  let out : Array[String] = []
  // READ: how many files were read, and how many of them were understood.
  let mut partial = 0
  for f in ast.files {
    if f.issues.length() > 0 {
      partial = partial + 1
    }
  }
  let read = ast.files.length()
  let parsed = read - partial
  out.push(
    "METRICS\tread\tfiles=" +
    read.to_string() +
    "\tparsed=" +
    parsed.to_string() +
    "\tpartial=" +
    partial.to_string() +
    "\tunderstood=" +
    @app.pct(parsed, read),
  )
  // STATEMENTS: the frontend's coverage, which is the number the report's
  // ingestion table is built on.
  out.push(
    "METRICS\tstmts\tstatements=" +
    (input.stmts + input.unsupported).to_string() +
    "\tunderstood=" +
    input.stmts.to_string() +
    "\tunsupported=" +
    input.unsupported.to_string() +
    "\tunderstood-share=" +
    @app.pct(input.stmts, input.stmts + input.unsupported),
  )
  // FUNCTIONS: how many were extracted, and how many the interpreter
  // actually entered. The difference is the BOUND that stopped the scan --
  // and the bound is a WORK budget, not a count, so the line says which one
  // it was: a reader who sees "entered" below "functions" has to be able to
  // tell a budget from a count from a filter.
  let entered = input.run.functions_run
  let skipped = input.run.functions_skipped.length()
  out.push(
    "METRICS\tfuncs\tfunctions=" +
    input.funcs.to_string() +
    "\tentered=" +
    entered.to_string() +
    "\tskipped=" +
    skipped.to_string() +
    "\tentered-share=" +
    @app.pct(entered, input.funcs) +
    "\tstep-budget=" +
    input.run.max_total_steps.to_string() +
    "\tsteps=" +
    input.run.steps.to_string() +
    "\tstopped-by=" +
    (if input.run.stopped_by_budget {
      "budget"
    } else if input.run.stopped_by_count {
      "count"
    } else {
      "none"
    }),
  )
  // PACKAGES: the per-package breakdown, and the budget each package had.
  // The line is only there in the per-package mode, because a number about
  // packages in a mode that does not scan per package would be a number
  // about nothing.
  if packages.length() > 0 {
    let mut spent = 0
    let mut pkg_steps = 0
    let mut pkg_events = 0
    let mut pkg_findings = 0
    for p in packages {
      if p.stopped_by_budget {
        spent = spent + 1
      }
      pkg_steps = pkg_steps + p.steps
      pkg_events = pkg_events + p.events
      pkg_findings = pkg_findings + p.findings
    }
    out.push(
      "METRICS\tpackages\tpackages=" +
      packages.length().to_string() +
      "\tbudget-spent=" +
      spent.to_string() +
      "\tper-package-budget=" +
      input.run.max_total_steps.to_string() +
      "\tsteps=" +
      pkg_steps.to_string() +
      "\tevents=" +
      pkg_events.to_string() +
      "\tfindings=" +
      pkg_findings.to_string(),
    )
  }
  // FINDINGS: the total, split by severity, over the SAME set the report
  // shows. The reportable set is the CFG findings, the dynamic infinite-loop
  // and budget findings, the taint sinks (already deduped by site) and the
  // abstract findings -- NOT the raw observation list, which holds one entry
  // per trial and per loop iteration and would say 83 findings where the
  // report shows 12.
  let reportable : Array[@app.Finding] = []
  for f in input.cfg_findings {
    reportable.push(f)
  }
  for f in input.run.findings {
    if f.kind == @app.FInfinite || f.kind == @app.FBudget {
      reportable.push(f)
    }
  }
  for f in input.taint.sinks {
    reportable.push(f)
  }
  match input.abstract_result {
    Some(a) =>
      for f in a.findings {
        reportable.push(f)
      }
    None => ()
  }
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  for f in reportable {
    match f.kind.severity() {
      "error" => errors = errors + 1
      "warning" => warnings = warnings + 1
      _ => infos = infos + 1
    }
  }
  out.push(
    "METRICS\tfindings\ttotal=" +
    reportable.length().to_string() +
    "\terror=" +
    errors.to_string() +
    "\twarning=" +
    warnings.to_string() +
    "\tinfo=" +
    infos.to_string(),
  )
  out
}

///|
/// The command line, normalized per backend.
///
/// On Node, `env.args()` is `process.argv`: the node executable AND the
/// script path come before the user's arguments, so the command lands at
/// index 2 instead of index 1.
#cfg(target="js")
fn cli_args(args : Array[String]) -> Array[String] {
  // Keep argv[0] (the program name) and drop argv[1] (the script path), so
  // the command lands at index 1 like it does on every other backend.
  let out : Array[String] = []
  if args.length() > 0 {
    out.push(args[0])
  }
  let mut i = 2
  while i < args.length() {
    out.push(args[i])
    i = i + 1
  }
  out
}

///|
#cfg(not(target="js"))
fn cli_args(args : Array[String]) -> Array[String] {
  args
}

///|
/// Run the CLI with `args`.
///
/// The entry point is a FUNCTION and not the special `main`, because the
/// module has two executables -- the root package, which is what `moonx`
/// resolves, and `src/cli`, which is the published CLI coordinate. Both call
/// this one function, so there is ONE implementation of the CLI and two ways
/// to reach it.
pub async fn run(raw_args : Array[String]) -> Unit {
  let args = cli_args(raw_args)
  match parse_args(args) {
    // A BAD ARGUMENT IS ALREADY REPORTED. The parser prints the ERROR line
    // itself, so the usage text is not repeated on top of it.
    None => ()
    Some((cmd, opts)) =>
      if cmd == "help" {
        println(usage())
      } else if opts.explain_all {
        // A CONTRACT REQUEST IS NOT A SCAN. It answers before the profile is
        // validated and before any file is read, so `--explain` cannot be
        // broken by the tree it is run in.
        println(@app.explain_roster())
      } else if opts.explain_code != "" {
        println(@app.explain_family(opts.explain_code))
      } else {
        analyze(opts)
      }
  }
}

///|
#cfg(any(target="native", target="wasm"))
async fn ensure_dir(path : String) -> Unit {
  // NO `allow_exist` LABEL, and that is deliberate.
  //
  // MEASURED (2026-11-17): the registry's newest core -- 0.10.21, the one the
  // CI runner's toolchain bundles -- RENAMED that label:
  //
  //   core 0.10.20:  allow_exist~    : Bool = false
  //   core 0.10.21:  allow_existing~ : Bool = false
  //
  // so a call that passes `allow_exist=true` compiles against the old core
  // and is REJECTED by the new one ("This function has no parameter with
  // label allow_exist"). A module that has to build against every toolchain
  // a user may have cannot pass a label that was renamed under it.
  //
  // The label is also REDUNDANT here: the error it suppresses is AlreadyExists,
  // and this function swallows every error anyway. Without the label, an
  // existing directory raises AlreadyExists, the catch below ignores it, and
  // the directory is there exactly as before.
  @fs.mkdir(path, recursive=true) catch {
    _ => ()
  }
}

///|
#cfg(not(any(target="native", target="wasm")))
fn ensure_dir(path : String) -> Unit {

}

///|
#cfg(not(any(target="native", target="wasm")))
async fn write_text(path : String, text : String) -> Bool {
  false
}

///|
#cfg(not(any(target="native", target="wasm")))
async fn read_text(path : String) -> String? {
  None
}
