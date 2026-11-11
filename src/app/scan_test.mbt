///|
/// Tests for the `moon fetch` log parsing.
///
/// The fetch log is free-form text and its shape differs between platforms,
/// so the version is cut from it by a rule rather than by a sentence pattern.
/// These tests pin that rule against the two log shapes that actually occur:
/// the Windows one and the Linux one.
test "log_version_candidates: the Windows log shape" {
  // MEASURED on Windows: `moon fetch` prints "already exists at <path>" and
  // the resolved path carries the version.
  let log = "Latest version of riantr/moonbit_doubleML is 0.164.64\nInfo: riantr/moonbit_doubleML@0.164.64 already exists at D:\\work\\.repos\\riantr\\moonbit_doubleML\\0.164.64"
  let got = @app.log_version_candidates(log, "moonbit_doubleML")
  assert_true(got.contains("0.164.64"))
}

///|
test "log_version_candidates: the Linux log shape does not swallow the log" {
  // MEASURED on the Linux CI runner: the fetch prints a download block whose
  // lines contain "Success" and "Successfully fetched <coord>@<version>".
  // The old scan took everything up to the next " to ", which produced the
  // version "0.164.64\nSuccess\nSuccessfully fetched ..." -- a name that
  // matches no directory, so the analyzer analysed an empty tree and exited 0.
  let log = "Downloading riantr/moonbit_doubleML@0.164.64\nSuccess\nSuccessfully fetched riantr/moonbit_doubleML@0.164.64 to /home/runner/work/LunaFlow/LunaFlow/.repos/riantr/moonbit_doubleML/0.164.64"
  let got = @app.log_version_candidates(log, "moonbit_doubleML")
  assert_true(got.contains("0.164.64"))
  // The candidate must be the version ALONE: no log text inside it.
  for c in got {
    assert_true(c.has_suffix("0.164.64"))
  }
}

///|
test "log_version_candidates: no version in the log is no candidate" {
  let log = "Info: nothing to do"
  let got = @app.log_version_candidates(log, "moonbit_doubleML")
  assert_eq(got.length(), 0)
}

///|
test "log_version_candidates: a version directory in the path is found" {
  // The path form: the version is the last component of the directory.
  let log = "Downloading to /home/runner/.repos/riantr/moonbit_doubleML/0.164.62"
  let got = @app.log_version_candidates(log, "moonbit_doubleML")
  assert_true(got.contains("0.164.62"))
}

///|
test "log_version_candidates: a dot is not a version" {
  // MEASURED on Windows, analysing the module with ITSELF. The fetch log
  // prints the resolved path, and the module name is a SUFFIX of the
  // repository directory name -- "moonbit_LunaFlow" for the module
  // "LunaFlow" -- so the text after the name begins with "\.repos\". The
  // leading dot used to be cut out as a version-shaped token.
  let log = "Latest version of riantr/LunaFlow is 0.1.3\nInfo: riantr/LunaFlow@0.1.3 already exists at D:\\src\\MiniMax\\Projects\\MoonBit\\moonbit_LunaFlow\\.repos\\riantr\\LunaFlow\\0.1.3"
  let got = @app.log_version_candidates(log, "LunaFlow")
  for c in got {
    assert_true(c != ".")
    assert_true(c.has_prefix("0.1.3"))
  }
  assert_true(got.contains("0.1.3"))
}

///|
test "pin_version: a real directory wins over a log token" {
  let log = "Info: riantr/LunaFlow@0.1.3 already exists at D:\\src\\moonbit_LunaFlow\\.repos\\riantr\\LunaFlow\\0.1.3"
  // The listing is the authority: only "0.1.3" is a real directory there.
  assert_eq(@app.pin_version(log, "LunaFlow", ["0.1.3"]), "0.1.3")
}

///|
test "pin_version: a token that is not a directory is not pinned" {
  // "." resolves to the base directory itself, so an "exists" test would
  // accept it. It names no version, and the newest real directory wins.
  let log = "Info: riantr/LunaFlow@0.1.3 already exists at D:\\src\\moonbit_LunaFlow\\.repos\\riantr\\LunaFlow\\0.1.3"
  assert_eq(@app.pin_version(log, "LunaFlow", ["0.1.1", "0.1.3"]), "0.1.3")
  assert_eq(@app.pin_version(log, "LunaFlow", ["0.1.1"]), "0.1.1")
}

///|
test "pin_version: no directory and no log candidate is no version" {
  assert_eq(@app.pin_version("Info: nothing to do", "LunaFlow", []), "")
}
