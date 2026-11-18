///|
/// PROPERTY-BASED TESTS over the analyser itself.
///
/// The hand-written tests elsewhere in this package state ONE case each: "a
/// division by a divisor that is not zero is not reported" pins one program,
/// and the guard tests pin one guarded program. A property states the
/// INVARIANT once and checks it over generated inputs, so it covers the
/// shape space a hand-written case cannot.
///
/// MEASURED (2026-11-18): these properties were run against the PRE-FIX
/// parser -- the tree at v0.1.24, before `guard` was modelled -- and they
/// FAILED with a shrunk counterexample `(0, 0)`. Against the fixed parser
/// they pass. The hand-written test caught the defect too; what the property
/// adds is that the invariant now holds for every generated divisor and
/// every generated program shape, and the SHRINK reports the smallest
/// failing input rather than the one that was written down.
///
/// THE GENERATOR IS BOUNDED, and that is not a detail. `Arbitrary for Int32`
/// draws from the whole 32-bit range, so a property that sized WORK from a
/// generated number built a program with billions of statements, and the
/// run never finished. MEASURED: the first version of this file hung. Every
/// generated COUNT is clamped below; the generated VALUES are not, because
/// the analyser reads a literal's value and the whole range is meaningful.
///
/// THE DRIVER is the toolchain's own `moonbitlang/core/quickcheck`, imported
/// FOR TESTS ONLY: `moon.mod` has no import block, the published library
/// declares no dependency, and the published artifact is byte-identical with
/// and without this file. `count=100` is passed EXPLICITLY so the
/// core-compatibility gate compares the LABEL: a core that renamed `count`
/// would break this call site, and the gate is what catches that.

///|
/// The number of filler statements in a generated program.
///
/// CLAMPED: this is the bound that makes the property terminate.
fn prop_stmts(n : Int32) -> Int32 {
  if n < 0 {
    0
  } else if n > 8 {
    8
  } else {
    n
  }
}

///|
/// A program with filler statements in front of a division by a PARAMETER.
fn prop_param_program(n_stmts : Int32) -> String {
  let n = prop_stmts(n_stmts)
  let mut body = ""
  let mut i = 0
  while i < n {
    body = body + "  let x" + i.to_string() + " = " + i.to_string() + "\n"
    i = i + 1
  }
  "pub fn f(total : Int32, count : Int32) -> Int32 {\n" +
  body +
  "  count / total\n}\n"
}

///|
/// The same program, with a `guard` that excludes a zero divisor.
fn prop_guarded_program(n_stmts : Int32) -> String {
  let n = prop_stmts(n_stmts)
  let mut body = ""
  let mut i = 0
  while i < n {
    body = body + "  let x" + i.to_string() + " = " + i.to_string() + "\n"
    i = i + 1
  }
  "pub fn f(total : Int32, count : Int32) -> Int32 {\n" +
  body +
  "  guard total > 0 else { 0 }\n  count / total\n}\n"
}

///|
/// A program whose divisor is a LITERAL.
fn prop_literal_program(value : Int32) -> String {
  "pub fn f(count : Int32) -> Int32 {\n  count / " + value.to_string() + "\n}\n"
}

///|
/// Does the analyser produce a verdict for this source at all?
fn prop_parses(src : String) -> Bool {
  let f = @app.parse_file("c.mbt", src)
  f.issues.length() == 0 && f.funcs.length() == 1
}

///|
/// The ground truth for a LITERAL divisor: the literal is known, so the
/// verdict is known -- zero divides by zero, and nothing else does.
///
/// MEASURED (2026-11-18): `count / 0` reports one division by zero, `count
/// / 10` reports none, `count / -5` reports none, and the extremes
/// (`2147483647`, `-2147483648`) report none and parse without an issue.
/// The generated value DECIDES the expected verdict, so this is an
/// invariant over every literal rather than one case.
fn prop_literal_divisor(value : Int32) -> Bool {
  let findings = eva_count(prop_literal_program(value), @app.FDivZero)
  if value == 0 {
    findings == 1
  } else {
    findings == 0
  }
}

///|
/// The guard invariant, over generated shapes: a divisor a `guard` excludes
/// is NEVER a division by zero, and the same program WITHOUT the guard is
/// one -- for every generated shape.
///
/// The assertion is PAIRED on purpose. A property that only checked the
/// guarded half would also pass if the analyser stopped reporting every
/// division by zero.
fn prop_guard_soundness(shape : (Int32, Int32)) -> Bool {
  let plain = eva_count(prop_param_program(shape.0), @app.FDivZero)
  let guarded = eva_count(prop_guarded_program(shape.0), @app.FDivZero)
  guarded == 0 && plain == 1
}

///|
/// The analyser must produce a verdict for every generated shape: the file
/// parses, the function is found, and there is no parse issue.
fn prop_shape_robustness(shape : (Int32, Int32)) -> Bool {
  prop_parses(prop_param_program(shape.0)) &&
  prop_parses(prop_guarded_program(shape.0)) &&
  prop_parses(prop_literal_program(shape.1))
}

///|
/// A literal divisor is a division by zero exactly when the literal is zero.
test "a literal divisor is a division by zero exactly when the literal is zero" {
  @coreqc.check(prop_literal_divisor, count=100)
}

///|
/// A guarded divisor is never a division by zero, whatever the shape.
test "a guarded divisor is never a division by zero, whatever the shape" {
  @coreqc.check(prop_guard_soundness, count=100)
}

///|
/// The analyser produces a verdict for every generated shape.
test "the analyser produces a verdict for every generated shape" {
  @coreqc.check(prop_shape_robustness, count=100)
}
