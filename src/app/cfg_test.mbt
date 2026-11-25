///|
fn cfg_of(src : String) -> Cfg {
  let f = parse_file("t.mbt", src)
  build_cfg(f.funcs[0])
}

///|
test "cfg has entry, exit and branch edges" {
  let cfg = cfg_of(
    (
      #|fn f(x : Int) -> Int {
      #|  if x > 0 {
      #|    return 1
      #|  } else {
      #|    return 2
      #|  }
      #|}
    ),
  )
  inspect(cfg.entry, content="0")
  assert_true(cfg.nodes.length() >= 5)
  let mut true_edges = 0
  let mut false_edges = 0
  for e in cfg.edges {
    if e.kind == ETrue {
      true_edges = true_edges + 1
    }
    if e.kind == EFalse {
      false_edges = false_edges + 1
    }
  }
  inspect(true_edges, content="1")
  inspect(false_edges, content="1")
}

///|
test "cfg marks dead statements after return" {
  let cfg = cfg_of(
    (
      #|fn f() -> Int {
      #|  return 1
      #|  let x = 2
      #|  x
      #|}
    ),
  )
  let findings = cfg_findings(cfg)
  let mut dead = 0
  for f in findings {
    if f.kind == FDead {
      dead = dead + 1
    }
  }
  inspect(dead, content="2")
}

///|
test "cfg detects constant true loop without exit" {
  let cfg = cfg_of(
    (
      #|fn spin() -> Unit {
      #|  while true {
      #|    let x = 1
      #|  }
      #|}
    ),
  )
  let findings = cfg_findings(cfg)
  let mut infinite = 0
  for f in findings {
    if f.kind == FInfinite {
      infinite = infinite + 1
    }
  }
  inspect(infinite, content="1")
}

///|
test "cfg keeps an exit for conditional loop" {
  let cfg = cfg_of(
    (
      #|fn walk(n : Int) -> Unit {
      #|  while n > 0 {
      #|    n = n - 1
      #|  }
      #|}
    ),
  )
  let findings = cfg_findings(cfg)
  let mut infinite = 0
  for f in findings {
    if f.kind == FInfinite {
      infinite = infinite + 1
    }
  }
  inspect(infinite, content="0")
}

///|
test "cfg of for loop has back edge" {
  let cfg = cfg_of(
    (
      #|fn sum(n : Int) -> Int {
      #|  let mut s = 0
      #|  for i = 0; i < n; i = i + 1 {
      #|    s = s + i
      #|  }
      #|  s
      #|}
    ),
  )
  let mut backs = 0
  for e in cfg.edges {
    if e.kind == EBack {
      backs = backs + 1
    }
  }
  inspect(backs, content="1")
}

///|
/// THE CFG SELF-LOOP, AND THE SHAPE THAT PRODUCES IT.
///
/// An EMPTY loop body leaves the loop with nothing to put in it, so
/// `last_node` falls back to the loop HEADER -- and the back edge then runs
/// from the header to ITSELF. A loop WITH a body gets a body node, and its
/// back edge runs body -> header.
///
/// BOTH ARE CORRECT, THEY ARE DIFFERENT, AND NOTHING PINNED THAT. The audit
/// of 2026-11-25 measured 59 loops in the embedded corpus and ZERO with an
/// empty body, and 713 loops in this analyser's own source and ZERO -- so
/// the self-loop was right by the fallback in `last_node` and not by a test.
/// Change that fallback and every test still passed. These two tests are the
/// answer: the shape, and the CONTROL beside it.
test "an empty loop body makes the header its own back edge" {
  let src =
    #|fn spin() -> Unit {
    #|  while true {
    #|  }
    #|}
  let cfg = cfg_of(src)
  let mut self_loops = 0
  for e in cfg.edges {
    // A self-loop is an edge whose two ENDS are the same node. The KIND is
    // checked too: a sequential edge from a node to itself would be a
    // different defect, and this test must not excuse it.
    if e.from == e.to && e.kind == @app.EBack {
      self_loops = self_loops + 1
    }
  }
  inspect(self_loops, content="1")
}

///|
/// THE CONTROL, and it is what makes the test above mean anything: a CFG that
/// collapsed EVERY loop to a self-loop would pass it. The same loop WITH a
/// body must keep its back edge on two DIFFERENT nodes.
test "a loop with a body keeps its back edge off the header" {
  let src =
    #|fn spin() -> Unit {
    #|  while true {
    #|    let x = 1
    #|  }
    #|}
  let cfg = cfg_of(src)
  let mut back_edges = 0
  let mut self_loops = 0
  for e in cfg.edges {
    if e.kind == @app.EBack {
      back_edges = back_edges + 1
      if e.from == e.to {
        self_loops = self_loops + 1
      }
    }
  }
  // The loop DID produce a back edge -- otherwise the zero below would read
  // zero for the wrong reason (no loop recognised at all).
  inspect(back_edges, content="1")
  inspect(self_loops, content="0")
}
