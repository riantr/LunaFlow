///|
/// Tests for the version pinning that follows a `moon fetch`.
///
/// The version is not scanned out of the fetch log any more: the fetch runs
/// quiet, and the version comes from the directories the fetch wrote. These
/// tests pin that rule, because the rule is what keeps a green run from
/// describing an empty tree.
test "pin_version: the newest version directory wins" {
  assert_eq(@app.pin_version(["0.1.1", "0.1.3"]), "0.1.3")
  assert_eq(@app.pin_version(["0.164.62", "0.164.64"]), "0.164.64")
}

///|
test "pin_version: the comparison is numeric, not lexicographic" {
  // "0.9.0" is NEWER than "0.10.0" as a string and OLDER as a version. A
  // lexicographic comparison would pin the wrong tree.
  assert_eq(@app.pin_version(["0.9.0", "0.10.0"]), "0.10.0")
}

///|
test "pin_version: no directory is no version" {
  // The empty tree is the failure this rule exists to prevent: the analyzer
  // used to read it and report 0 statements with exit 0.
  assert_eq(@app.pin_version([]), "")
}

///|
test "pin_version: a single directory is the version" {
  assert_eq(@app.pin_version(["0.1.3"]), "0.1.3")
}

///|
test "version_parts: a version is read as numbers" {
  let parts = @app.version_parts("0.164.64")
  assert_eq(parts.length(), 3)
  assert_eq(parts[0], 0)
  assert_eq(parts[2], 64)
}
