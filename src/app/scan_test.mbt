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
