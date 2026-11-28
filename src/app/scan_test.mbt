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

///|
test "version_parts: the build hash is not part of the number" {
  // A toolchain module's version is a DATE with a build hash on the end:
  // "0.1.20261126+3c0520448". The third segment is the number 20261126 and
  // the hash is not a number at all.
  let parts = @app.version_parts("0.1.20261126+3c0520448")
  assert_eq(parts.length(), 3)
  assert_eq(parts[0], 0)
  assert_eq(parts[1], 1)
  assert_eq(parts[2], 20261126)
}

///|
test "pin_version: a version with a build hash is ordered by its date" {
  // MEASURED 2026-11-28: `moon fetch moonbitlang/core` had just written
  // 0.1.20261126+3c0520448 -- the registry's latest -- and the analyzer
  // analysed 0.1.20261102+97801ee1b, the OLDEST of the three, 24 days older.
  //
  // The build hash made the whole third segment unparseable, so every
  // toolchain version compared EQUAL to every other one, and the first
  // directory in the list won. The list is sorted, so the oldest won.
  let versions = [
    "0.1.20261102+97801ee1b", "0.1.20261105+65efd5b93", "0.1.20261126+3c0520448",
  ]
  assert_eq(@app.pin_version(versions), "0.1.20261126+3c0520448")
}
