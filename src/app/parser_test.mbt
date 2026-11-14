///|
test "lexer keeps strings and skips comments" {
  let src = "// c\nlet s = \"a b\" + \"c\"\n"
  let toks = lex(src)
  let texts : Array[String] = []
  for t in toks {
    if t.kind != TNewline {
      texts.push(t.text)
    }
  }
  inspect(texts.join("|"), content="let|s|=|a b|+|c|")
}

///|
test "parser extracts function shape" {
  let src =
    #|///|
    #|fn pick(xs : Array[Int], i : Int) -> Int {
    #|  let n = xs.length()
    #|  if i >= n {
    #|    return -1
    #|  }
    #|  xs[i]
    #|}
  let f = parse_file("demo.mbt", src)
  inspect(f.funcs.length(), content="1")
  let fd = f.funcs[0]
  inspect(fd.name, content="pick")
  inspect(fd.params.length(), content="2")
  inspect(fd.params[0].name, content="xs")
  inspect(fd.params[0].ty, content="Array[Int]")
  inspect(fd.ret_ty, content="Int")
  inspect(fd.body.length(), content="3")
  match fd.body[0].kind {
    SLet(name, ty, _) => {
      inspect(name, content="n")
      inspect(ty, content="")
    }
    _ => fail("expected let")
  }
  match fd.body[1].kind {
    SIf(_, then_body, else_body) => {
      inspect(then_body.length(), content="1")
      inspect(else_body.length(), content="0")
    }
    _ => fail("expected if")
  }
}

///|
test "parser captures while and for forms" {
  let src =
    #|///|
    #|fn loops(n : Int) -> Int {
    #|  let mut total = 0
    #|  for i = 0; i < n; i = i + 1 {
    #|    total += i
    #|  }
    #|  while total > 100 {
    #|    total = total - 1
    #|  }
    #|  for x in [1, 2] {
    #|    total += x
    #|  }
    #|  total
    #|}
  let f = parse_file("loops.mbt", src)
  let fd = f.funcs[0]
  let mut saw_for = false
  let mut saw_while = false
  let mut saw_for_in = false
  for s in fd.body {
    match s.kind {
      SFor(_, _, _, _, _) => saw_for = true
      SWhile(_, _) => saw_while = true
      SForIn(_, _, _) => saw_for_in = true
      _ => ()
    }
  }
  assert_true(saw_for)
  assert_true(saw_while)
  assert_true(saw_for_in)
}

///|
test "parser records unsupported match as gap" {
  let src =
    #|///|
    #|fn m(x : Int) -> Int {
    #|  match x {
    #|    0 => 1
    #|    _ => 2
    #|  }
    #|}
  let f = parse_file("m.mbt", src)
  let fd = f.funcs[0]
  inspect(fd.body.length(), content="1")
  match fd.body[0].kind {
    SUnsupported(name) => inspect(name, content="match")
    _ => fail("expected unsupported")
  }
  inspect(f.unsupported_stmts, content="1")
}

///|
test "parser handles methods and indexing expressions" {
  let src =
    #|///|
    #|fn g(a : Array[Int], i : Int) -> Int {
    #|  let x = a[i]
    #|  a.push(x + 1)
    #|  x
    #|}
  let f = parse_file("g.mbt", src)
  let fd = f.funcs[0]
  match fd.body[0].kind {
    SLet(_, _, e) =>
      match e.kind {
        EIndex(base, idx) => {
          inspect(base.render(), content="a")
          inspect(idx.render(), content="i")
        }
        _ => fail("expected index")
      }
    _ => fail("expected let")
  }
}

///|
test "a type annotation ends at the = and does not swallow the initializer" {
  // The type used to run on through the initializer: `let x : Int32 = 5`
  // recorded the type as "Int32 = 5", which is not a type name. It went
  // unnoticed because every use of the type was a `contains` on the PREFIX,
  // and the prefix was still right -- but a check that matches a type NAME
  // cannot use it.
  let src =
    #|fn f() -> Int {
    #|  let x : Int32 = 5
    #|  let y : Option[Int32] = None
    #|  let z : Int32? = None
    #|  x
    #|}
  let f = parse_file("t.mbt", src)
  let body = f.funcs[0].body
  match body[0].kind {
    SLet(_, ty, _) => inspect(ty, content="Int32")
    _ => fail("expected let")
  }
  match body[1].kind {
    SLet(_, ty, _) => inspect(ty, content="Option[Int32]")
    _ => fail("expected let")
  }
  // The shorthand spelling is the same type, and the formatter rewrites one
  // into the other, so both have to survive.
  match body[2].kind {
    SLet(_, ty, _) => inspect(ty.trim().has_suffix("?"), content="true")
    _ => fail("expected let")
  }
}
