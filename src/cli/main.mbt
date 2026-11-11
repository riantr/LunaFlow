///|
/// The published CLI coordinate: a thin entrypoint over `src/command`.
///
/// The implementation lives in a non-main package because the module has two
/// executables -- this one and the module's root package, which is what
/// `moonx` resolves -- and two main packages cannot import each other.
async fn main {
  @command.run(@env.args())
}
