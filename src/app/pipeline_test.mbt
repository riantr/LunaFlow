///|
fn demo_events() -> Array[TraceEvent] {
  [
    TraceEvent::new(
      EvSource,
      "f",
      "a.mbt",
      1,
      0,
      "p",
      "7",
      true,
      0,
      "parameter",
    ),
    TraceEvent::new(EvDef, "f", "a.mbt", 2, 1, "i", "7", true, 0, "p"),
    TraceEvent::new(EvIndex, "f", "a.mbt", 3, 2, "buf", "7", true, 0, "i"),
  ]
}

///|
test "taint graph links source through definition to sink" {
  let events = demo_events()
  let findings = [
    Finding::new(
      FTaintIndex,
      "a.mbt",
      3,
      "f",
      "tainted index",
      "dynamic",
      0.8,
      "buf[7]",
    ),
  ]
  let g = build_taint(events, findings)
  assert_eq(g.nodes.length(), 3)
  assert_eq(g.edges.length(), 2)
  assert_eq(g.sinks.length(), 1)
  let mut sources = 0
  let mut sinks = 0
  for n in g.nodes {
    if n.kind == TSource {
      sources = sources + 1
    }
    if n.kind == TSink {
      sinks = sinks + 1
    }
  }
  assert_eq(sources, 1)
  assert_eq(sinks, 1)
}

///|
test "backward slice reaches the parameter source" {
  let events = demo_events()
  let sf = parse_file("a.mbt", "fn f(p : Int) -> Int {\n  let i = p\n  i\n}\n")
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [sf],
    manifest_deps: [],
    manifest_target: "native",
  }
  let graph = build_dep_graph(events)
  let s = slice_graph(graph, ast, "i@f", SliceBackward, 20)
  assert_true(s.nodes.length() >= 2)
  let mut has_source = false
  for n in s.nodes {
    if n.kind == "source" {
      has_source = true
    }
  }
  assert_true(has_source)
}

///|
test "forward slice from a source reaches the sink" {
  let events = demo_events()
  let sf = parse_file("a.mbt", "fn f(p : Int) -> Int {\n  let i = p\n  i\n}\n")
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [sf],
    manifest_deps: [],
    manifest_target: "native",
  }
  let graph = build_dep_graph(events)
  let s = slice_graph(graph, ast, "p@f", SliceForward, 20)
  let mut has_index = false
  for n in s.nodes {
    if n.kind == "index" {
      has_index = true
    }
  }
  assert_true(has_index)
}

///|
test "mermaid validator accepts a clean diagram" {
  let mm = "flowchart TD\n  n0[\"entry\"]\n  n1[\"exit\"]\n  n0 --> n1\n"
  inspect(validate_mermaid(mm).length(), content="0")
}

///|
test "mermaid validator rejects unbalanced quotes" {
  let mm = "flowchart TD\n  n0[\"entry]\n  n0 --> n1\n"
  assert_true(validate_mermaid(mm).length() > 0)
}

///|
test "cobertura parser counts covered and total lines" {
  let xml =
    #|<coverage>
    #|  <packages>
    #|    <package name=".">
    #|      <classes>
    #|        <class name="a.mbt" filename="a.mbt">
    #|          <lines>
    #|            <line number="3" hits="1"/>
    #|            <line number="4" hits="0"/>
    #|            <line number="5" hits="7"/>
    #|          </lines>
    #|        </class>
    #|      </classes>
    #|    </package>
    #|  </packages>
    #|</coverage>
  let cov = parse_cobertura(xml, "cov.xml")
  inspect(cov.total, content="3")
  inspect(cov.covered, content="2")
  inspect(cov.hits_at("a.mbt", 5), content="Some(7)")
  inspect(cov.hits_at("a.mbt", 4), content="Some(0)")
}

///|
test "range union keeps the observed interval" {
  let a = Ranges::new()
  a.observe("f", "x", -2.0, "-2", "f:1")
  a.observe("f", "x", 1.0, "1", "f:1")
  let b = Ranges::new()
  b.observe("f", "x", 9.0, "9", "f:2")
  a.merge_from(b)
  let st = a.get("f", "x").unwrap()
  inspect(format_double(st.min), content="-2")
  inspect(format_double(st.max), content="9")
  inspect(st.count, content="3")
}

///|
test "fixture pipeline produces taint and control-flow findings" {
  let sf = parse_file(
    "fixtures/vuln_demo/lib.mbt",
    (
      #|pub fn copy_prefix(buffer : Array[Int], len : Int) -> Int {
      #|  let mut total = 0
      #|  let mut i = 0
      #|  while i < len {
      #|    total = total + buffer[i]
      #|    i = i + 1
      #|  }
      #|  total
      #|}
    ),
  )
  let ast : ModuleAst = {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [sf],
    manifest_deps: [],
    manifest_target: "native",
  }
  let opts : RunOptions = {
    trials: 6,
    max_steps: 500,
    max_depth: 4,
    max_functions: 10,
    entry_filter: "",
  }
  let run = run_module(ast, opts)
  let taint = build_taint(run.events, run.findings)
  assert_true(run.events.length() > 0)
  assert_true(taint.sinks.length() >= 1)
  let cfg = build_cfg(sf.funcs[0])
  assert_true(cfg.nodes.length() > 0)
}
