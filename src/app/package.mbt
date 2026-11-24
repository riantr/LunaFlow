///|
/// THE PACKAGE OF A FILE, AND THE RUN OF A PACKAGE.
///
/// A MoonBit package is the DIRECTORY that holds its `moon.pkg`: the files of
/// a directory belong to it until one of them holds its own.  The module's
/// ROOT package is "", and that is the name of the package of a file that
/// sits at the module root.
///
/// The package of a file is a property of the TREE, not of the file: the same
/// source file is in a different package when it is fetched into a different
/// tree.  So it is MEASURED by the walk that reads the tree, and it is
/// recorded on the file itself (`SourceFile::package_path`).
///
/// WHY IT MATTERS.  The analyser merges a directory tree into ONE module, and
/// the step budget that stops the scan is the MODULE's.  So a module-wide
/// budget is spent on the FIRST packages in file order, and the rest of the
/// tree is never interpreted.  MEASURED on
/// `riantr/moonbit_static_analysis@0.5.4` (17 packages): the module-wide
/// budget entered 711 of 1,437 functions and stopped inside `src/flow`,
/// while the per-package mode entered 1,212 and reached every other package
/// whole.  Scanning PACKAGE BY PACKAGE gives each package its own budget, so
/// the budget of a module of N packages is N times the one -- and the part
/// of the tree that the module-wide scan never reached is reached.
///
/// THE GROUPS ARE MAPS, AND THAT IS DELIBERATE.  A package's functions and a
/// package's counters are looked up BY THE PACKAGE'S NAME, and a name is
/// not an index.  The alternative -- an array per package, and an index into
/// it -- needs the analyser to relate the lengths of two arrays it has not
/// measured, and it cannot: MEASURED, the self-scan reported `INDEX-OOB` on
/// `groups[at]` while the guard was on the OTHER array.  A map has no index
/// to be out of bounds.

///|
pub fn module_packages(ast : ModuleAst) -> Array[String] {
  let out : Array[String] = []
  for f in ast.files {
    if !out.contains(f.package_path) {
      out.push(f.package_path)
    }
  }
  out
}

///|
/// The package of each FILE of the module.
///
/// The map the trace splitter and the package table both use, so that
/// "which package does this event belong to" has ONE answer.

///|
pub fn package_of_files(ast : ModuleAst) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for f in ast.files {
    m[f.path] = f.package_path
  }
  m
}

///|
/// The FUNCTIONS of each package, by the package's name.
///
/// The functions are the module's own: the test blocks are not entries, and
/// that is the same rule `ModuleAst::all_funcs` uses -- so the package table
/// and the module-wide count are about the same functions.

///|
pub fn functions_by_package(ast : ModuleAst) -> Map[String, Array[Func]] {
  let groups : Map[String, Array[Func]] = Map([])
  for f in ast.files {
    let g = match groups.get(f.package_path) {
      Some(g) => g
      None => {
        let fresh : Array[Func] = []
        groups[f.package_path] = fresh
        fresh
      }
    }
    for fn_name in f.funcs {
      if !fn_name.is_test {
        g.push(fn_name)
      }
    }
  }
  groups
}

///|
/// One PACKAGE's run.
///
/// The per-package mode scans the module package by package, and each package
/// is a RUN of its own: it has its own step budget, its own count of
/// functions entered, and its own trace.  This is what the mode buys -- the
/// budget is a bound on the WORK of ONE package, so the work of a module of N
/// packages is bounded N times over instead of once.
///
/// The counts are what a reader needs to see WHICH package the scan stopped
/// in: a scan that entered every function of every package but one is a
/// different thing from a scan that stopped in the middle of the first
/// package, and only the per-package counts tell the two apart.

///|
pub struct PackageRun {
  /// The package's path: the directory that holds its `moon.pkg`.  The
  /// module's ROOT package is "".
  name : String
  /// The functions that were ENTERED as entry points.
  functions_run : Int32
  /// The functions that were NOT entered: this package's own budget ran out,
  /// or the function had no body.
  functions_skipped : Int32
  /// The interpreted steps this package cost.
  steps : Int32
  /// The trace events this package produced.  The events of the module's
  /// GLOBAL region belong to the package that DECLARES them, so nothing is
  /// left out of the count.
  events : Int32
  /// The findings this package produced.
  findings : Int32
  /// Whether this package's OWN step budget is what stopped it.
  stopped_by_budget : Bool
}

///|
/// The number of trace events each package produced.
///
/// The events are counted by the FILE they name, mapped through the same
/// file-to-package map the rest of the per-package mode uses.  An event whose
/// file is not in the module is counted for NO package: it is not this
/// module's event, and giving it to the nearest package would be a lie.

///|
fn count_events_by_package(
  ast : ModuleAst,
  events : Array[TraceEvent],
) -> Map[String, Int32] {
  let counts : Map[String, Int32] = Map([])
  let map = package_of_files(ast)
  for e in events {
    match map.get(e.file) {
      Some(p) => {
        let n = match counts.get(p) {
          Some(n) => n + 1
          None => 1
        }
        counts[p] = n
      }
      None => ()
    }
  }
  counts
}
