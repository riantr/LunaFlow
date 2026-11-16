///|
/// THE CLASSES SAFE MOONBIT CANNOT EXPRESS, AND THAT THE C BOUNDARY CAN.
///
/// Safe MoonBit has no raw pointer, no `free`, no format string and no
/// pointer arithmetic, so the four families that would report those classes
/// -- USE-AFTER-FREE, MEMORY-LEAK, POINTER-ARITHMETIC and FORMAT-STRING --
/// never fire in the evolved value analysis. Their contracts say so.
///
/// The classes are REAL on the other side of a C boundary, and this file
/// pins the checks that report them there, plus the MoonBit-side growth
/// family that comes closest to MEMORY-LEAK in safe code.
///
/// Every claim here was settled by RUNNING the real toolchain:
///
///  - a C function is an allocation when its NAME says so AND it returns an
///    address -- a foreign type, which is one by construction, or an integer,
///    which may be one;
///  - a release is recognised by the NAME, the same way the release list
///    recognises one;
///  - a format slot is recognised by the parameter's NAME, and the rule is
///    the one GCC's -Wformat-security uses: a format slot with no other
///    argument after it;
///  - a region is nameable when its base and its size are both CONSTANTS;
///  - a top-level `let` is a global, and the collection it HOLDS is mutable
///    even though the binding is not: `records.push(i)` on a global compiles
///    clean.
///
/// The tests below pin BOTH directions: the defect is found, and the
/// ordinary shape next to it is not.

///|
fn bnd_ast(src : String) -> @app.ModuleAst {
  {
    coord: "demo/x",
    version: "1.0.0",
    root: ".",
    files: [@app.parse_file("c.mbt", src)],
    manifest_deps: [],
    manifest_target: "native",
  }
}

///|
fn bnd_ffi(src : String) -> @app.FfiModel {
  @app.analyze_ffi(bnd_ast(src))
}

///|
fn bnd_ffi_count(src : String, kind : @app.FindingKind) -> Int32 {
  let m = bnd_ffi(src)
  let mut n = 0
  for f in m.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
fn bnd_growth_count(src : String) -> Int32 {
  let fs = @app.analyze_growth(bnd_ast(src))
  let mut n = 0
  for f in fs {
    if f.kind == @app.FUnboundedGrowth {
      n = n + 1
    }
  }
  n
}

// ---------------------------------------------------------------------------
// The LEAK at the boundary.
// ---------------------------------------------------------------------------

///|
test "an allocation the module never releases is reported" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|
    #|pub fn leak() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  ignore(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="1")
}

///|
test "an allocation the module releases is not reported" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|extern "C" fn release_region(region : Reg) -> Unit = "free_region"
    #|
    #|pub fn release_it() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  release_region(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="0")
}

///|
test "an allocation the module hands back is not a leak" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|
    #|pub fn hand_back() -> Reg {
    #|  alloc_region(268435456, 8192)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="0")
}

///|
test "a release in ANOTHER function does not cancel this function's allocation" {
  // The scan is per function: a name is only released where the release
  // happens. A module-wide name table would cancel the two.
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|extern "C" fn release_region(region : Reg) -> Unit = "free_region"
    #|
    #|pub fn leak() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  ignore(region)
    #|}
    #|
    #|pub fn release_it() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  release_region(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="1")
}

///|
test "a C function whose name is not an allocator is not an allocation" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn map_page(base : UInt64, size : UInt64) -> Reg = "map_page"
    #|
    #|pub fn f() -> Unit {
    #|  let region = map_page(268435456, 8192)
    #|  ignore(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="0")
}

///|
test "a C function that does not return an address is not an allocation" {
  let src =
    #|extern "C" fn create_handle(id : Int32) -> Int32 = "create_handle"
    #|
    #|pub fn f() -> Unit {
    #|  let handle = create_handle(3)
    #|  ignore(handle)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAllocationNotReleased), content="0")
}

// ---------------------------------------------------------------------------
// The FORMAT STRING at the boundary.
// ---------------------------------------------------------------------------

///|
test "a format slot handed a string from outside the function is reported" {
  let src =
    #|extern "C" fn log_msg(fmt : String) -> Unit = "log_msg"
    #|
    #|pub fn log_it(message : String) -> Unit {
    #|  log_msg(message)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiFormatString), content="1")
}

///|
test "a format slot handed a literal is not reported" {
  let src =
    #|extern "C" fn log_msg(fmt : String) -> Unit = "log_msg"
    #|
    #|pub fn log_it() -> Unit {
    #|  log_msg("hello")
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiFormatString), content="0")
}

///|
test "a format slot the module fills with its own text is not reported" {
  let src =
    #|extern "C" fn log_msg(fmt : String) -> Unit = "log_msg"
    #|
    #|pub fn log_it() -> Unit {
    #|  let own = "hello"
    #|  log_msg(own)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiFormatString), content="0")
}

///|
test "a slot that is not named like a format is not a format" {
  let src =
    #|extern "C" fn log_msg(message : String) -> Unit = "log_msg"
    #|
    #|pub fn log_it(message : String) -> Unit {
    #|  log_msg(message)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiFormatString), content="0")
}

///|
test "a C function with another argument after the format is not claimed" {
  // The rule is the one GCC's -Wformat-security uses: a format slot with no
  // other argument after it.
  let src =
    #|extern "C" fn log_msg(fmt : String, value : Int32) -> Unit = "log_msg"
    #|
    #|pub fn log_it(message : String) -> Unit {
    #|  log_msg(message, 1)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiFormatString), content="0")
}

// ---------------------------------------------------------------------------
// The ADDRESS out of bounds at the boundary.
// ---------------------------------------------------------------------------

///|
test "an address past the end of the region is reported" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|extern "C" fn poke_region(addr : UInt64, value : UInt32) -> Unit = "poke_region"
    #|
    #|pub fn write_past_the_end() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  poke_region(268435456 + 16384, 11)
    #|  ignore(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAddressOob), content="1")
}

///|
test "an address inside the region is not reported" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|extern "C" fn poke_region(addr : UInt64, value : UInt32) -> Unit = "poke_region"
    #|
    #|pub fn write_inside() -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  poke_region(268435456 + 16, 11)
    #|  ignore(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAddressOob), content="0")
}

///|
test "an address whose base belongs to no region is not claimed" {
  let src =
    #|extern "C" fn poke_region(addr : UInt64, value : UInt32) -> Unit = "poke_region"
    #|
    #|pub fn f() -> Unit {
    #|  poke_region(268435456 + 16384, 11)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAddressOob), content="0")
}

///|
test "an address computed at run time is not claimed" {
  let src =
    #|#external
    #|pub type Reg
    #|
    #|extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"
    #|extern "C" fn poke_region(addr : UInt64, value : UInt32) -> Unit = "poke_region"
    #|
    #|pub fn write(offset : UInt64) -> Unit {
    #|  let region = alloc_region(268435456, 8192)
    #|  poke_region(268435456 + offset, 11)
    #|  ignore(region)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiAddressOob), content="0")
}

// ---------------------------------------------------------------------------
// One defect is one finding.
// ---------------------------------------------------------------------------

///|
test "a double free inside a nested statement is reported once" {
  // The walk descends itself, so the collector must NOT descend as well: a
  // collector that did would visit the nested statement twice and report one
  // defect twice.
  let src =
    #|extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"
    #|
    #|pub fn nested() -> Unit {
    #|  let buffer = b"payload"
    #|  if true {
    #|    release_buffer(buffer)
    #|    release_buffer(buffer)
    #|  }
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiDoubleFree), content="1")
}

///|
test "a double free at the top level of a body is reported once" {
  let src =
    #|extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"
    #|
    #|pub fn flat() -> Unit {
    #|  let buffer = b"payload"
    #|  release_buffer(buffer)
    #|  release_buffer(buffer)
    #|}
  inspect(bnd_ffi_count(src, @app.FFfiDoubleFree), content="1")
}

// ---------------------------------------------------------------------------
// The MoonBit-side growth family.
// ---------------------------------------------------------------------------

///|
test "a global collection that only grows is reported" {
  let src =
    #|let ledger : Array[Int] = []
    #|
    #|pub fn record_every(n : Int) -> Unit {
    #|  for i in 0..<n {
    #|    ledger.push(i)
    #|  }
    #|}
  inspect(bnd_growth_count(src), content="1")
}

///|
test "a global collection that is trimmed is not reported" {
  let src =
    #|let ring : Array[Int] = []
    #|
    #|pub fn record_and_trim(n : Int) -> Unit {
    #|  for i in 0..<n {
    #|    ring.push(i)
    #|  }
    #|  while ring.length() > 0 {
    #|    ignore(ring.pop())
    #|  }
    #|}
  inspect(bnd_growth_count(src), content="0")
}

///|
test "a local collection that only grows is not reported" {
  let src =
    #|pub fn collect_locally(n : Int) -> Int {
    #|  let scratch : Array[Int] = []
    #|  for i in 0..<n {
    #|    scratch.push(i)
    #|  }
    #|  scratch.length()
    #|}
  inspect(bnd_growth_count(src), content="0")
}

///|
test "a global collection filled in a bounded loop is not reported" {
  let src =
    #|let few : Array[Int] = []
    #|
    #|pub fn record_a_few() -> Unit {
    #|  for i in 0..<4 {
    #|    few.push(i)
    #|  }
    #|}
  inspect(bnd_growth_count(src), content="0")
}

///|
test "a global that is not a collection is not reported" {
  let src =
    #|let counter : Int = 0
    #|
    #|pub fn bump(n : Int) -> Unit {
    #|  for i in 0..<n {
    #|    ignore(i)
    #|  }
    #|}
  inspect(bnd_growth_count(src), content="0")
}
