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
