///|
/// The module's ROOT package: a thin forwarder to `src/command`.
///
/// It exists so `moonx riantr/LunaFlow@latest <target>` works without
/// naming a package — `moonx` resolves the ROOT package of a module
/// coordinate, and with no root executable it fails with "Prebuilt wasm asset
/// does not exist". No other package in this module depends on the root, and
/// nothing outside the module imports the bare module path.
async fn main {
  @command.run(@env.args())
}
