///|
/// THE PER-PACKAGE MODE, AND WHAT IT BUYS.
///
/// The step budget is a bound on the WORK, and the work of a module is the
/// work of its PACKAGES.  A module-wide budget is therefore spent on the
/// first packages in file order, and the rest of the tree is never
/// interpreted -- MEASURED on `riantr/moonbit_doubleML@0.164.64`, the
/// module-wide budget entered 275 of 1,411 functions and stopped inside the
/// module.
///
/// These tests hold the mode to that claim with the SAME budget on both
/// sides: the per-package mode enters functions the module-wide mode never
/// reaches, because the budget is spent again in the next package.
///
/// The module is built BY HAND, with its packages set by hand, so the test
/// needs no filesystem and no tree: what is under test is the RUN, not the
/// walk.  The walk's own measurement -- which directory holds which
/// `moon.pkg` -- is measured by `scripts/qa/per_package.mjs`, against a
/// real tree.

///|
fn pkg_file(path : String, pkg : String, src : String) -> SourceFile {
  let sf = parse_file(path, src)
  sf.set_package_path(pkg)
  sf
}

///|
/// A module of TWO packages: `src/a` with two functions and `src/b` with
/// one.  The order is the file order, so the module-wide scan reaches
/// `src/a` first and spends its budget there.

///|
fn two_package_ast() -> ModuleAst {
  let files = [
    pkg_file("src/a/one.mbt", "src/a", "fn one() -> Int {\n  1\n}\n"),
    pkg_file("src/a/two.mbt", "src/a", "fn two() -> Int {\n  2\n}\n"),
    pkg_file("src/b/three.mbt", "src/b", "fn three() -> Int {\n  3\n}\n"),
  ]
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files,
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn small_opts() -> RunOptions {
  {
    trials: 1,
    max_steps: 2000,
    max_depth: 6,
    max_functions: 0,
    entry_filter: "",
  }
}

///|
fn capped_opts() -> RunOptions {
  {
    trials: 1,
    max_steps: 2000,
    max_depth: 6,
    max_functions: 1,
    entry_filter: "",
  }
}

///|
test "the per-package mode spends the budget again in the next package" {
  let ast = two_package_ast()
  let opts = small_opts()
  // The MODULE-WIDE budget of one step: the first function is entered, it
  // costs more than one step, and the budget is spent -- so the scan stops
  // INSIDE the first package and never reaches the second.
  let wide = run_module(ast, opts, max_total_steps=1)
  inspect(wide.functions_run, content="1")
  inspect(wide.stopped_by_budget, content="true")
  // The PER-PACKAGE budget, the SAME one step: it is spent again in the next
  // package, so the second package is reached.
  let (per, packages) = run_module_packages(
    ast,
    opts,
    max_total_steps=1,
    per_package=true,
  )
  inspect(per.functions_run, content="2")
  inspect(per.stopped_by_budget, content="true")
  inspect(packages.length(), content="2")
  inspect(packages[0].name, content="src/a")
  inspect(packages[1].name, content="src/b")
  // The first package spent its budget; the second ran out of FUNCTIONS, not
  // out of budget, and the two are different facts.
  inspect(packages[0].functions_run, content="1")
  inspect(packages[0].functions_skipped, content="1")
  inspect(packages[0].stopped_by_budget, content="true")
  inspect(packages[1].functions_run, content="1")
  inspect(packages[1].functions_skipped, content="0")
  inspect(packages[1].stopped_by_budget, content="false")
}

///|
test "the per-package mode enters everything when the budget is enough" {
  let ast = two_package_ast()
  let opts = small_opts()
  let (per, packages) = run_module_packages(
    ast,
    opts,
    max_total_steps=100000,
    per_package=true,
  )
  // The same three functions the module-wide scan would enter.
  inspect(per.functions_run, content="3")
  inspect(per.stopped_by_budget, content="false")
  inspect(packages.length(), content="2")
  inspect(packages[0].functions_run, content="2")
  inspect(packages[1].functions_run, content="1")
  // The steps are the MODULE's steps, split by package: the two halves add
  // up to the whole, which is what says the split lost nothing.
  inspect(packages[0].steps + packages[1].steps, content=per.steps.to_string())
}

///|
test "the count cap stays module-wide in the per-package mode" {
  let ast = two_package_ast()
  let opts = capped_opts()
  let (per, packages) = run_module_packages(
    ast,
    opts,
    max_total_steps=100000,
    per_package=true,
  )
  // ONE function in the whole module, not one per package: a reader who
  // asked for "150 functions" did not ask for "150 functions per package".
  inspect(per.functions_run, content="1")
  inspect(per.stopped_by_count, content="true")
  inspect(packages[0].functions_run, content="1")
  inspect(packages[1].functions_run, content="0")
}

///|
test "the module-wide mode reports no per-package breakdown" {
  let ast = two_package_ast()
  let opts = small_opts()
  let (_run, packages) = run_module_packages(ast, opts, max_total_steps=100000)
  // There was no per-package run, so there is no per-package result: an
  // empty list, not a list with one row for the whole module.
  inspect(packages.length(), content="0")
}

///|
test "a package's events are the events of its own files" {
  let ast = two_package_ast()
  let opts = small_opts()
  let (per, packages) = run_module_packages(
    ast,
    opts,
    max_total_steps=100000,
    per_package=true,
  )
  // Every event belongs to the package of the file it names, and the counts
  // add up to the module's: nothing is left out of the split.
  let mut total = 0
  for p in packages {
    total = total + p.events
  }
  inspect(total, content=per.events.length().to_string())
  inspect(packages[0].events > 0, content="true")
  inspect(packages[1].events > 0, content="true")
}
