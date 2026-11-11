///|
pub(all) struct ReportOptions {
  max_cfg : Int32
  max_taint_nodes : Int32
  max_slice_nodes : Int32
  max_path_events : Int32
}

///|
pub fn ReportOptions::default() -> ReportOptions {
  { max_cfg: 8, max_taint_nodes: 40, max_slice_nodes: 40, max_path_events: 24, }
}

///|
pub(all) struct ReportInput {
  coord : String
  version : String
  pinning : String
  root : String
  target : String
  deps : Array[String]
  files : Int32
  funcs : Int32
  stmts : Int32
  unsupported : Int32
  issues : Int32
  cfgs : Array[Cfg]
  cfg_findings : Array[Finding]
  run : RunResult
  taint : TaintGraph
  slices : Array[SliceResult]
  coverage : Coverage?
  opts : ReportOptions
  elapsed_ms : Int32
  level : Int32
  funnel : FunnelResult?
  abstract : AbsResult?
  proof : ProofResult?
}

///|
fn cfg_shape(kind : NodeKind) -> (String, String, String) {
  match kind {
    NEntry => ("([", "])", "entryNode")
    NExit => ("([", "])", "exitNode")
    NBranch => ("{", "}", "branchNode")
    NLoop => ("{{", "}}", "loopNode")
    NMerge => ("(", ")", "mergeNode")
    NDead => ("[", "]", "deadNode")
    NStmt => ("[", "]", "stmtNode")
  }
}

///|
pub fn cfg_mermaid(cfg : Cfg) -> String {
  let out = StringBuilder::new()
  out.write_string("flowchart TD\n")
  out.write_string(
    "  classDef entryNode fill:#dcedc8,stroke:#33691e,stroke-width:2px\n",
  )
  out.write_string(
    "  classDef exitNode fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px\n",
  )
  out.write_string("  classDef branchNode fill:#fff9c4,stroke:#f9a825\n")
  out.write_string("  classDef loopNode fill:#e1bee7,stroke:#6a1b9a\n")
  out.write_string("  classDef mergeNode fill:#eceff1,stroke:#607d8b\n")
  out.write_string("  classDef deadNode fill:#eeeeee,stroke:#9e9e9e\n")
  out.write_string("  classDef stmtNode fill:#e3f2fd,stroke:#1565c0\n")
  for n in cfg.nodes {
    let (open, close, class_name) = cfg_shape(n.kind)
    let label = mermaid_label(n.label)
    out.write_string(
      "  n" +
      n.id.to_string() +
      open +
      "\"" +
      label +
      "\"" +
      close +
      ":::" +
      class_name +
      "\n",
    )
  }
  for e in cfg.edges {
    let arrow = if e.kind == EBack { " -.->" } else { " -->" }
    let label = match e.kind {
      ETrue => "|true|"
      EFalse => "|false|"
      EBack => "|back|"
      ESeq => ""
    }
    out.write_string(
      "  n" +
      e.from.to_string() +
      arrow +
      label +
      " n" +
      e.to.to_string() +
      "\n",
    )
  }
  out.to_string()
}

///|
pub fn taint_mermaid(g : TaintGraph, cap : Int32) -> String {
  let out = StringBuilder::new()
  out.write_string("flowchart LR\n")
  out.write_string(
    "  classDef src fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px\n",
  )
  out.write_string("  classDef step fill:#fff9c4,stroke:#f9a825\n")
  out.write_string(
    "  classDef sink fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px\n",
  )
  let keep : Map[Int32, Bool] = Map::new()
  let mut count = 0
  for n in g.nodes {
    if count < cap {
      keep[n.id] = true
      count = count + 1
      let shape = match n.kind {
        TSource => ("[\"", "\"]", "src")
        TSink => ("[[\"", "\"]]", "sink")
        TStep => ("[\"", "\"]", "step")
      }
      out.write_string(
        "  t" +
        n.id.to_string() +
        shape.0 +
        mermaid_label(n.label) +
        shape.1 +
        ":::" +
        shape.2 +
        "\n",
      )
    }
  }
  for e in g.edges {
    if keep.contains(e.from) && keep.contains(e.to) {
      out.write_string(
        "  t" +
        e.from.to_string() +
        " -->|" +
        mermaid_label(e.label) +
        "| t" +
        e.to.to_string() +
        "\n",
      )
    }
  }
  out.to_string()
}

///|
pub fn slice_mermaid(s : SliceResult, cap : Int32) -> String {
  let out = StringBuilder::new()
  out.write_string("flowchart TD\n")
  out.write_string("  classDef sliceNode fill:#e3f2fd,stroke:#1565c0\n")
  let ids : Map[String, Int32] = Map::new()
  let mut i = 0
  for n in s.nodes {
    if i >= cap {
      break
    }
    ids[n.key] = i
    let prefix = if n.kind == "source" {
      "src"
    } else if n.kind == "index" || n.kind == "alloc" || n.kind == "sink" {
      "sink"
    } else if n.kind == "cond" {
      "cond"
    } else {
      "stmt"
    }
    out.write_string(
      "  s" +
      i.to_string() +
      "[\"" +
      mermaid_label(prefix + " L" + n.line.to_string() + ": " + n.text) +
      "\"]:::sliceNode\n",
    )
    i = i + 1
  }
  for e in s.edges {
    match (ids.get(e.from), ids.get(e.to)) {
      (Some(a), Some(b)) =>
        out.write_string(
          "  s" +
          a.to_string() +
          " -->|" +
          mermaid_label(e.label) +
          "| s" +
          b.to_string() +
          "\n",
        )
      _ => ()
    }
  }
  out.to_string()
}

///|
pub fn validate_mermaid(text : String) -> Array[String] {
  let issues : Array[String] = []
  let lines = split_lines(text)
  if lines.length() == 0 {
    issues.push("empty diagram")
    return issues
  }
  let head = lines[0].trim().to_owned()
  if !(head.has_prefix("flowchart") || head.has_prefix("graph")) {
    issues.push("diagram does not start with flowchart/graph")
  }
  let mut i = 0
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    if line.contains("\n") {
      issues.push("line \{i + 1} contains a raw newline")
    }
    let opens = count_occurrences(line, "[")
    let closes = count_occurrences(line, "]")
    if opens != closes && line.contains("\"") {
      issues.push("line \{i + 1} has unbalanced square brackets")
    }
    let q = count_occurrences(line, "\"")
    if q % 2 != 0 {
      issues.push("line \{i + 1} has an odd number of quotes")
    }
    i = i + 1
  }
  issues
}

///|
/// How much of the module the CFG pass covered. The pass takes the FIRST
/// functions in file order, so a module with more functions than the window
/// leaves the rest with NO CFG -- and a file's findings then depend on how
/// many functions happen to precede it. Saying so is the difference between
/// "this module is clean" and "this module was not looked at".
fn cfg_coverage_line(input : ReportInput) -> String {
  cfg_coverage(input.cfgs.length(), input.funcs)
}

///|
/// How much of the module the CFG pass covered. The pass takes the FIRST
/// functions in file order, so a module with more functions than the window
/// leaves the rest with NO CFG -- and a file's findings then depend on how
/// many functions happen to precede it. Saying so is the difference between
/// "this module is clean" and "this module was not looked at".
pub fn cfg_coverage(have : Int32, total : Int32) -> String {
  if have >= total {
    return total.to_string() +
      " of " +
      total.to_string() +
      " — every function"
  }
  have.to_string() +
  " of " +
  total.to_string() +
  " — the first " +
  have.to_string() +
  " in file order; " +
  (total - have).to_string() +
  " functions had no CFG and can carry no CFG finding"
}

///|
fn finding_row(f : Finding) -> String {
  "| " +
  f.kind.code() +
  " | " +
  f.kind.severity() +
  " | " +
  md_escape(f.fn_name) +
  " | " +
  f.file +
  ":" +
  f.line.to_string() +
  " | " +
  md_escape(f.message) +
  " | " +
  f.mode +
  " | " +
  format_double(f.confidence) +
  " |\n"
}

///|
fn findings_table(fs : Array[Finding]) -> String {
  if fs.length() == 0 {
    return "_No findings._\n"
  }
  let out = StringBuilder::new()
  out.write_string(
    "| Rule | Severity | Function | Location | Message | Method | Confidence |\n",
  )
  out.write_string("| --- | --- | --- | --- | --- | --- | --- |\n")
  for f in fs {
    out.write_string(finding_row(f))
  }
  out.to_string()
}

///|
fn event_label(ev : TraceEvent) -> String {
  let kind = match ev.kind {
    EvEnter => "enter"
    EvDef => "def"
    EvRead => "read"
    EvCond => "cond"
    EvCall => "call"
    EvIndex => "index"
    EvAlloc => "alloc"
    EvLoop => "loop"
    EvReturn => "ret"
    EvSource => "src"
    EvSink => "sink"
    EvAbort => "abort"
    EvBudget => "budget"
    EvUnsupported => "gap"
  }
  kind + "@" + ev.line.to_string()
}

///|
fn path_of(
  run : RunResult,
  fn_name : String,
  limit : Int32,
) -> Array[TraceEvent] {
  let out : Array[TraceEvent] = []
  for ev in run.events {
    if ev.fn_name == fn_name && ev.trial == 0 {
      if ev.kind != EvSource && ev.kind != EvEnter {
        if out.length() < limit {
          out.push(ev)
        }
      }
    }
  }
  out
}

///|
fn site_table(events : Array[TraceEvent], cap : Int32) -> String {
  let m : Map[String, Array[String]] = Map::new()
  let order : Array[String] = []
  for ev in events {
    if ev.kind == EvDef && ev.name != "<ret>" {
      let key = ev.fn_name + "|" + ev.line.to_string() + "|" + ev.name
      match m.get(key) {
        Some(xs) =>
          if !xs.contains(ev.value) && xs.length() < 6 {
            xs.push(ev.value)
          }
        None => {
          let xs : Array[String] = []
          xs.push(ev.value)
          m[key] = xs
          order.push(key)
        }
      }
    }
  }
  let keys = sort_strings(order)
  if keys.length() == 0 {
    return "_No definition events recorded._\n"
  }
  let out = StringBuilder::new()
  out.write_string("| Function | Line | Variable | Observed values |\n")
  out.write_string("| --- | --- | --- | --- |\n")
  let mut i = 0
  for key in keys {
    if i >= cap {
      out.write_string(
        "| ... | ... | ... | (truncated at " + cap.to_string() + " rows) |\n",
      )
      break
    }
    let parts = key.split("|").to_array()
    if parts.length() >= 3 {
      let fn_name = parts[0].to_owned()
      let line = parts[1].to_owned()
      let name = parts[2].to_owned()
      match m.get(key) {
        Some(xs) =>
          out.write_string(
            "| " +
            md_escape(fn_name) +
            " | " +
            line +
            " | " +
            md_escape(name) +
            " | " +
            md_escape(truncate(xs.join(", "), 60)) +
            " |\n",
          )
        None => ()
      }
    }
    i = i + 1
  }
  out.to_string()
}

///|
fn ranges_table(ranges : Ranges) -> String {
  let keys = ranges.stats.keys().to_array()
  let sorted = sort_strings(keys)
  if sorted.length() == 0 {
    return "_No numeric observations were recorded._\n"
  }
  let out = StringBuilder::new()
  out.write_string(
    "| Function | Variable | Min | Max | Samples | Observed values | First site |\n",
  )
  out.write_string("| --- | --- | --- | --- | --- | --- | --- |\n")
  for key in sorted {
    match ranges.stats.get(key) {
      Some(st) => {
        let parts = key.split("::").to_array()
        let fn_name = if parts.length() > 0 { parts[0].to_owned() } else { key }
        let name = if parts.length() > 1 { parts[1].to_owned() } else { "" }
        out.write_string(
          "| " +
          md_escape(fn_name) +
          " | " +
          md_escape(name) +
          " | " +
          format_double(st.min) +
          " | " +
          format_double(st.max) +
          " | " +
          st.count.to_string() +
          " | " +
          md_escape(truncate(st.values.join(", "), 48)) +
          " | " +
          md_escape(ranges.site(fn_name, name)) +
          " |\n",
        )
      }
      None => ()
    }
  }
  out.to_string()
}

///|
fn top_funcs(cfgs : Array[Cfg], n : Int32) -> Array[Cfg] {
  let sorted = cfgs.copy()
  let mut i = 0
  while i < sorted.length() {
    let mut j = 0
    while j + 1 < sorted.length() - i {
      if sorted[j].cyclomatic < sorted[j + 1].cyclomatic {
        let tmp = sorted[j]
        sorted[j] = sorted[j + 1]
        sorted[j + 1] = tmp
      }
      j = j + 1
    }
    i = i + 1
  }
  let out : Array[Cfg] = []
  let mut k = 0
  while k < sorted.length() && k < n {
    out.push(sorted[k])
    k = k + 1
  }
  out
}

///|
fn coverage_table(cov : Coverage, cfgs : Array[Cfg]) -> String {
  let out = StringBuilder::new()
  out.write_string(
    "Imported coverage: **" + cov.ratio() + "** of instrumented lines hit",
  )
  out.write_string(
    " (" +
    cov.covered.to_string() +
    "/" +
    cov.total.to_string() +
    "), source `" +
    cov.source +
    "`.\n\n",
  )
  out.write_string("| Function | CFG nodes | Nodes hit | Node coverage |\n")
  out.write_string("| --- | --- | --- | --- |\n")
  for cfg in cfgs {
    let mut hit = 0
    let mut total = 0
    for n in cfg.nodes {
      if n.kind != NEntry && n.kind != NExit && n.kind != NMerge {
        total = total + 1
        match cov.hits_at(n.file, n.line) {
          Some(h) => if h > 0 { hit = hit + 1 }
          None => ()
        }
      }
    }
    out.write_string(
      "| " +
      md_escape(cfg.fn_name) +
      " | " +
      total.to_string() +
      " | " +
      hit.to_string() +
      " | " +
      pct(hit, total) +
      " |\n",
    )
  }
  out.to_string()
}

///|
fn funcs_with_findings(cfgs : Array[Cfg], findings : Array[Finding]) -> Int32 {
  let m : Map[String, Bool] = Map::new()
  for f in findings {
    m[f.fn_name] = true
  }
  let mut n = 0
  for c in cfgs {
    if m.contains(c.fn_name) {
      n = n + 1
    }
  }
  n
}

///|
fn name_list(names : Array[String], cap : Int32) -> String {
  let parts : Array[String] = []
  let mut i = 0
  for n in names {
    if i < cap {
      parts.push("`" + md_escape(n) + "`")
    }
    i = i + 1
  }
  let extra = if names.length() > cap {
    " ... (+" + (names.length() - cap).to_string() + " more)"
  } else {
    ""
  }
  parts.join(", ") + extra
}

///|
fn level_definitions_table() -> String {
  "| Level | Name | Engine | Input model | Result strength |\n" +
  "| --- | --- | --- | --- | --- |\n" +
  "| L1 | Interpreter | concrete execution on the formal interpreter | concrete boundary values (`--trials`) | observed facts; may miss unexecuted inputs and paths |\n" +
  "| L2 | Value | abstract interpretation over a value-set / interval domain | whole input sets (`Int` intervals, `Bool`/`String` sets, array length intervals) | exhaustive over the abstract state; may-taint and may-range alarms (false positives possible) |\n" +
  "| L3 | Proof-by-contract | WP-style weakest-precondition VC generation + interval decision | ACSL-style `//@ requires` / `//@ ensures` specs | `proved` / `failed` / `unknown` per verification condition; specs are mandatory |\n"
}

///|
fn funnel_mermaid(f : FunnelResult) -> String {
  let out = StringBuilder::new()
  out.write_string("flowchart LR\n")
  out.write_string("  classDef l1 fill:#dcedc8,stroke:#33691e\n")
  out.write_string("  classDef l2 fill:#fff9c4,stroke:#f9a825\n")
  out.write_string("  classDef l3 fill:#e1bee7,stroke:#6a1b9a\n")
  out.write_string(
    "  L1[\"L1 concrete: " + f.level1.to_string() + " findings\"]:::l1\n",
  )
  out.write_string(
    "  L2[\"L2 abstract: " +
    f.level2.to_string() +
    " findings, " +
    f.new_level2.length().to_string() +
    " new\"]:::l2\n",
  )
  out.write_string(
    "  L3[\"L3 contracts: " +
    f.proved.to_string() +
    " proved / " +
    f.failed.to_string() +
    " failed / " +
    f.unknown.to_string() +
    " unknown\"]:::l3\n",
  )
  out.write_string("  L1 -->|\"dedup, escalate\"| L2\n")
  out.write_string("  L2 -->|\"critical functions\"| L3\n")
  out.to_string()
}

///|
fn abstract_findings(fs : Array[Finding]) -> Array[Finding] {
  let out : Array[Finding] = []
  for f in fs {
    if f.mode == "L2-abstract" {
      out.push(f)
    }
  }
  out
}

///|
fn abstract_ranges_table(ranges : Map[String, AbsRange]) -> String {
  let keys = sort_strings(ranges.keys().to_array())
  if keys.length() == 0 {
    return "_No abstract numeric ranges recorded._\n"
  }
  let out = StringBuilder::new()
  out.write_string("| Function | Variable | May-range | Observations |\n")
  out.write_string("| --- | --- | --- | --- |\n")
  for key in keys {
    match ranges.get(key) {
      Some(r) => {
        let parts = key.split("::").to_array()
        let fn_name = if parts.length() > 0 { parts[0].to_owned() } else { key }
        let name = if parts.length() > 1 { parts[1].to_owned() } else { "" }
        out.write_string(
          "| " +
          md_escape(fn_name) +
          " | " +
          md_escape(name) +
          " | [" +
          format_double(r.lo) +
          ", " +
          format_double(r.hi) +
          "] | " +
          r.seen.to_string() +
          " |\n",
        )
      }
      None => ()
    }
  }
  out.to_string()
}

///|
fn vc_table(vcs : Array[VC]) -> String {
  if vcs.length() == 0 {
    return "_No verification condition generated._\n"
  }
  let out = StringBuilder::new()
  out.write_string(
    "| Function | VC kind | Location | Status | Goal | Detail |\n",
  )
  out.write_string("| --- | --- | --- | --- | --- | --- |\n")
  for vc in vcs {
    out.write_string(
      "| " +
      md_escape(vc.fn_name) +
      " | " +
      vc.kind +
      " | " +
      vc.file +
      ":" +
      vc.line.to_string() +
      " | " +
      vc.status.code() +
      " | " +
      code_span(vc.goal) +
      " | " +
      md_escape(vc.detail) +
      " |\n",
    )
  }
  out.to_string()
}

///|
pub fn proof_counts(vcs : Array[VC]) -> (Int32, Int32, Int32) {
  let mut proved = 0
  let mut failed = 0
  let mut unknown = 0
  for vc in vcs {
    match vc.status {
      VCProved => proved = proved + 1
      VCFailed => failed = failed + 1
      VCUnknown => unknown = unknown + 1
    }
  }
  (proved, failed, unknown)
}

///|
pub fn render_report(input : ReportInput) -> String {
  let out = StringBuilder::new()
  let md = "docs/design.md"
  out.write_string(
    "# LunaFlow analysis report — " +
    input.coord +
    "@" +
    input.version +
    "\n\n",
  )
  out.write_string(
    "> Trace-driven (dynamic-first) control-flow, data-flow, value-range and slicing analysis for a mooncakes.io module.\n\n",
  )
  out.write_string("## 1. Acquisition and version pinning\n\n")
  out.write_string("| Item | Value |\n| --- | --- |\n")
  out.write_string("| Requested coordinate | `" + input.coord + "` |\n")
  out.write_string("| Resolved version | `" + input.version + "` |\n")
  out.write_string("| Pinning strategy | " + md_escape(input.pinning) + " |\n")
  out.write_string("| Source root | `" + md_escape(input.root) + "` |\n")
  out.write_string("| Declared target | `" + md_escape(input.target) + "` |\n")
  out.write_string(
    "| Direct dependencies | " +
    md_escape(
      if input.deps.length() == 0 {
        "(none)"
      } else {
        input.deps.join(", ")
      },
    ) +
    " |\n\n",
  )
  out.write_string("## 2. Ingestion statistics\n\n")
  out.write_string("| Metric | Value |\n| --- | --- |\n")
  out.write_string(
    "| Source files parsed | " + input.files.to_string() + " |\n",
  )
  out.write_string(
    "| Functions extracted | " + input.funcs.to_string() + " |\n",
  )
  out.write_string(
    "| Statements understood | " + input.stmts.to_string() + " |\n",
  )
  out.write_string(
    "| Statements unsupported | " + input.unsupported.to_string() + " |\n",
  )
  out.write_string(
    "| Frontend coverage | " +
    pct(input.stmts, input.stmts + input.unsupported) +
    " |\n",
  )
  out.write_string("| Parse issues | " + input.issues.to_string() + " |\n")
  out.write_string("| CFG functions | " + cfg_coverage_line(input) + " |\n")
  out.write_string(
    "| Trace events | " + input.run.events.length().to_string() + " |\n",
  )
  out.write_string(
    "| Interpreted steps | " + input.run.steps.to_string() + " |\n",
  )
  out.write_string(
    "| Observed functions | " + input.run.functions_run.to_string() + " |\n",
  )
  out.write_string(
    "| Wall time (analyzer) | " + input.elapsed_ms.to_string() + " ms |\n",
  )
  let funnel_note = if input.funnel is Some(_) {
    " (funnel: L1 → L2 → L3)"
  } else {
    ""
  }
  out.write_string(
    "| Selected level | L" + input.level.to_string() + funnel_note + " |\n\n",
  )
  out.write_string("## 3. Proof-strength levels and funnel\n\n")
  out.write_string(
    "The same program is analyzed at three proof strengths. Levels are cumulative: L2 adds abstract interpretation on top of L1, L3 adds contract verification on top of the escalated functions. `--funnel` runs all three and reports what each level adds.\n\n",
  )
  out.write_string("### 3.1 Level definitions\n\n")
  out.write_string(level_definitions_table())
  out.write_string("\n### 3.2 Funnel\n\n")
  if input.funnel is Some(f) {
    out.write_string("```mermaid\n")
    out.write_string(funnel_mermaid(f))
    out.write_string("```\n\n")
    out.write_string(
      "| Level | Checks | New vs previous | Functions / VCs | Note |\n",
    )
    out.write_string("| --- | --- | --- | --- | --- |\n")
    out.write_string(
      "| L1 concrete | " +
      f.level1.to_string() +
      " findings | — | " +
      input.run.functions_run.to_string() +
      " functions | observed facts |\n",
    )
    out.write_string(
      "| L2 abstract | " +
      f.level2.to_string() +
      " findings | " +
      f.new_level2.length().to_string() +
      " | " +
      f.abstract_functions.to_string() +
      " functions, " +
      f.abstract_steps.to_string() +
      " steps | exhaustive over the input abstraction |\n",
    )
    out.write_string(
      "| L3 contracts | " +
      (f.proved + f.failed + f.unknown).to_string() +
      " VCs | " +
      f.failed.to_string() +
      " failed, " +
      f.unknown.to_string() +
      " unknown | " +
      f.critical.length().to_string() +
      " critical functions | specs required |\n\n",
    )
    out.write_string("### 3.3 Escalation and specification gaps\n\n")
    out.write_string(
      "Escalated functions (have at least one L1/L2 finding or a contract): ",
    )
    if f.critical.length() == 0 {
      out.write_string("_none_\n\n")
    } else {
      let parts : Array[String] = []
      for n in f.critical {
        parts.push("`" + md_escape(n) + "`")
      }
      out.write_string(parts.join(", ") + "\n\n")
    }
    out.write_string(
      "Functions escalated without any contract (spec gap at L3): ",
    )
    if f.spec_gaps.length() == 0 {
      out.write_string("_none_\n\n")
    } else {
      let parts : Array[String] = []
      for n in f.spec_gaps {
        parts.push("`" + md_escape(n) + "`")
      }
      out.write_string(parts.join(", ") + "\n\n")
    }
  } else {
    out.write_string(
      "_Funnel not requested._ Run with `--funnel` (or `--level 2` / `--level 3`) to add the stronger levels.\n\n",
    )
  }
  out.write_string("## 4. Control-flow analysis\n\n")
  out.write_string(
    "CFG nodes are built from the parsed statement tree; execution paths come from the concrete-execution trace engine. " +
    "Dead/unreachable detection is static; path coverage and budget findings are dynamic. See `" +
    md +
    "` §5 for the mapping rules.\n\n",
  )
  let truncated = top_funcs(input.cfgs, input.opts.max_cfg)
  out.write_string(
    "### 4.1 CFG diagrams (top " +
    truncated.length().to_string() +
    " by cyclomatic complexity)\n\n",
  )
  for cfg in truncated {
    out.write_string("#### `" + cfg.fn_name + "` (" + cfg.file + ")\n\n")
    if cfg.nodes.length() > 90 {
      out.write_string(
        "_Diagram omitted: " +
        cfg.nodes.length().to_string() +
        " nodes exceeds the readability cap (90). Findings for this function are listed below._\n\n",
      )
      continue
    }
    out.write_string("```mermaid\n")
    out.write_string(cfg_mermaid(cfg))
    out.write_string("```\n\n")
    let path_events = path_of(
      input.run,
      cfg.fn_name,
      input.opts.max_path_events,
    )
    if path_events.length() > 0 {
      out.write_string(
        "Observed path (trial 0, first " +
        path_events.length().to_string() +
        " events): ",
      )
      let parts : Array[String] = []
      for ev in path_events {
        parts.push("`" + event_label(ev) + "`")
      }
      out.write_string(parts.join(" -> ") + "\n\n")
    }
  }
  out.write_string("### 4.2 CFG findings\n\n")
  let cfg_only : Array[Finding] = []
  for f in input.cfg_findings {
    cfg_only.push(f)
  }
  for f in input.run.findings {
    if f.kind == FInfinite || f.kind == FBudget {
      cfg_only.push(f)
    }
  }
  out.write_string(findings_table(cfg_only))
  out.write_string("\n### 4.3 Static vs dynamic attribution\n\n")
  out.write_string(
    "| Signal | Method | What a hit means | Known limitation |\n| --- | --- | --- | --- |\n" +
    "| Unreachable statement | static | no CFG predecessor; often after `return`/`break` | parser gaps can hide real predecessors |\n" +
    "| Infinite loop | static + dynamic | constant-true condition without break, or iteration cap reached | loops whose exit depends on unmodelled calls are reported as *budget*, not proven infinite |\n" +
    "| Uncovered code | dynamic (coverage import) | zero hits in the observed test suite | absence of execution is not proof of dead code |\n\n",
  )
  if input.coverage is Some(cov) {
    out.write_string("### 4.4 Imported execution coverage\n\n")
    out.write_string(coverage_table(cov, input.cfgs))
    out.write_string("\n")
  }
  out.write_string("## 5. Data flow and taint\n\n")
  out.write_string(
    "Sources are entry-function parameters (and `@env.args` when the frontend sees it); propagation follows recorded definitions and the variables read by each statement; sinks are array-index expressions and allocation sizes. The graph below is the *observed* propagation, not a may-analysis over all inputs.\n\n",
  )
  out.write_string("```mermaid\n")
  out.write_string(taint_mermaid(input.taint, input.opts.max_taint_nodes))
  out.write_string("```\n\n")
  out.write_string("### 5.1 Taint sinks\n\n")
  out.write_string(findings_table(input.taint.sinks))
  out.write_string("\n### 5.2 L2 abstract findings (may-analysis)\n\n")
  if input.abstract is Some(abs) {
    out.write_string(
      "Abstract interpretation joins all paths and widens loops, so these alarms are *may* properties: a hit means the abstract state cannot exclude the defect, not that a concrete input was observed.\n\n",
    )
    out.write_string(findings_table(abstract_findings(abs.findings)))
  } else {
    out.write_string(
      "_Level 2 was not executed._ Run with `--level 2` or `--funnel`.\n\n",
    )
  }
  out.write_string("\n## 6. Value ranges\n\n")
  out.write_string(
    "Ranges are the union of concrete samples across synthesized input trials. They are *observed* intervals, not abstract-interpretation fixpoints: a missing input can hide a wider interval.\n\n",
  )
  out.write_string("### 6.1 Per-program-point observations\n\n")
  out.write_string(
    "Every definition event is keyed by function, source line and variable, so a value can be inspected at the exact program point that produced it (the full stream is in the JSONL trace).\n\n",
  )
  out.write_string(site_table(input.run.events, 300))
  out.write_string("\n### 6.2 Function-level range union (L1)\n\n")
  out.write_string(ranges_table(input.run.ranges))
  out.write_string("\n### 6.3 Abstract may-ranges (L2)\n\n")
  if input.abstract is Some(abs) {
    out.write_string(
      "These intervals are the abstract interpreter's fixpoint approximation at widening, not observed samples; they cover the whole input abstraction and therefore over-approximate.\n\n",
    )
    out.write_string(abstract_ranges_table(abs.ranges))
  } else {
    out.write_string("_Level 2 was not executed._\n")
  }
  out.write_string("\n## 7. Program slicing\n\n")
  if input.slices.length() == 0 {
    out.write_string("_No slice requested._\n\n")
  } else {
    for s in input.slices {
      out.write_string(
        "### " +
        s.direction.code() +
        " slice on `" +
        md_escape(s.criterion) +
        "`\n\n",
      )
      out.write_string("```mermaid\n")
      out.write_string(slice_mermaid(s, input.opts.max_slice_nodes))
      out.write_string("```\n\n")
      out.write_string(
        "| Line | Kind | Statement | Site |\n| --- | --- | --- | --- |\n",
      )
      for n in s.nodes {
        out.write_string(
          "| " +
          n.line.to_string() +
          " | " +
          n.kind +
          " | " +
          code_span(n.text) +
          " | " +
          n.file +
          " |\n",
        )
      }
      out.write_string("\n")
    }
  }
  out.write_string("## 8. Contracts and verification conditions (L3)\n\n")
  if input.proof is Some(p) {
    let (proved, failed, unknown) = proof_counts(p.vcs)
    out.write_string(
      "Deductive verification is WP-style: each contract becomes verification conditions (postconditions at every `return`, plus safety obligations for every index, allocation size, division and assertion). A condition is `proved` only when the preconditions entail it by interval reasoning; otherwise it is `failed` or `unknown`. This is not a substitute for an SMT-backed WP: `unknown` is an honest third state.\n\n",
    )
    out.write_string("| Metric | Value |\n| --- | --- |\n")
    out.write_string(
      "| Functions with a contract | " +
      p.functions_with_contract.to_string() +
      " |\n",
    )
    out.write_string(
      "| Functions checked | " + p.functions_checked.to_string() + " |\n",
    )
    out.write_string("| VCs proved | " + proved.to_string() + " |\n")
    out.write_string("| VCs failed | " + failed.to_string() + " |\n")
    out.write_string("| VCs unknown | " + unknown.to_string() + " |\n\n")
    out.write_string(vc_table(p.vcs))
    out.write_string("\n")
    if p.spec_gaps.length() > 0 {
      out.write_string(
        "Specification gaps (escalated, no `//@ requires`/`//@ ensures`): ",
      )
      let parts : Array[String] = []
      for n in p.spec_gaps {
        parts.push("`" + md_escape(n) + "`")
      }
      out.write_string(parts.join(", ") + "\n\n")
    }
  } else {
    out.write_string(
      "_Level 3 was not executed._ Run with `--level 3` or `--funnel`.\n\n",
    )
  }
  out.write_string("## 9. Method summary\n\n")
  out.write_string(
    "| Capability | Engine | Precision statement |\n| --- | --- | --- |\n" +
    "| CFG + dead/unreachable | static (syntax-directed) | sound relative to the parsed subset; parser gaps are reported |\n" +
    "| Path coverage | dynamic (trace) | exact for executed trials; no guarantee for unexecuted paths |\n" +
    "| Taint (L1) | dynamic + symbolic labels | flow-sensitive within a trial; container field sensitivity is coarse |\n" +
    "| Taint (L2) | abstract interpretation | may-analysis over the input abstraction; loop widening loses precision |\n" +
    "| Ranges (L1) | dynamic sampling | union of observed values; not a proof |\n" +
    "| Ranges (L2) | interval / value-set domain | over-approximation at widening; sound relative to the abstract semantics |\n" +
    "| Contracts (L3) | WP-style VC + interval decision | `proved` only from entailed preconditions; `unknown` when facts are insufficient |\n" +
    "| Slicing | dynamic dependence graph | exact for the recorded trace; not a static closure |\n\n",
  )
  out.write_string("## 10. Reproduction\n\n")
  out.write_string(
    "```text\nLunaFlow analyze " +
    input.coord +
    "@latest --out reports/ --funnel\n",
  )
  out.write_string("```\n\n")
  out.write_string(
    "Full method description, comparison with Frama-C/TIS, Joern, CodeQL, SVF and Soot, and the acceptance tests are in `" +
    md +
    "`.\n",
  )
  out.to_string()
}
