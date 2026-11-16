// The FOREIGN ADDRESS SPACE fixture: the C boundary, exercised.
//
// Every case here was settled by RUNNING the real toolchain, and the file
// compiles under it.
//
// The C declarations are behind `#cfg(target = "native")`, which is the
// toolchain's own idiom for a native-only declaration: the wasm backend
// REJECTS `extern "C"` (E4156), so a module that declares one has to say
// so. The analyzer reads the SOURCE, so it sees the declarations whatever
// the target is.
//
// What MoonBit actually does, measured:
//  - `extern "C" fn name(args) -> Ret = "c_symbol"` is the only C form, and
//    the `= "c_symbol"` part is REQUIRED;
//  - the wasm backend rejects `extern "C"` (E4156) and native rejects a
//    module import, so the two forms are not interchangeable;
//  - `#external type T` is an OPAQUE type: natively a GC-managed external
//    object whose payload the C side owns;
//  - a pointer-typed parameter needs `#borrow(x)` or `#owned(x)`; without
//    one the toolchain reports E0055 and says the current default -- which
//    is `#owned` -- will change;
//  - the annotation is NOT enforced: an `#owned` argument used after the
//    call compiles clean;
//  - two declarations claiming the same C symbol with different signatures
//    ALSO compile clean: the toolchain does not notice.

///|
// An opaque foreign type: the C side owns the payload.
#external
pub type Reg

///|
// A C function that reads a register.
#cfg(target="native")
pub extern "C" fn read_reg(name : Reg) -> UInt32 = "read_reg"

///|
// A C function that takes ownership of a buffer.
#cfg(target="native")
#owned(buffer)
pub extern "C" fn write_reg(name : Reg, buffer : Bytes) -> Unit = "write_reg"

///|
// A C function that maps a page and returns a foreign address.
#cfg(target="native")
pub extern "C" fn map_page(base : UInt64, size : UInt64) -> Reg = "map_page"

///|
// A C function that writes a register at a fixed address.
#cfg(target="native")
pub extern "C" fn poke(base : UInt64, value : UInt32) -> Unit = "poke"

///|
// A SECOND declaration of the same C symbol, with a different signature.
// The C function has ONE prototype, so one of the two claims is wrong -- and
// the toolchain does not notice.
#cfg(target="native")
pub extern "C" fn read_reg_wide(name : Reg) -> UInt64 = "read_reg"

///|
// A foreign address used as a foreign address: the region is named by the
// symbol that produced it.
#cfg(target="native")
pub fn read_status() -> UInt32 {
  read_reg(map_page(1073741824, 4096))
}

///|
// An `#owned` argument used AFTER the call: the C side owns the buffer now,
// and the toolchain lets this through.
#cfg(target="native")
pub fn hand_over_then_use() -> Unit {
  let buffer = b"payload"
  write_reg(map_page(1073741824, 4096), buffer)
  println(buffer)
}

///|
// A constant address handed to C.
#cfg(target="native")
pub fn poke_register() -> Unit {
  poke(1073741824, 7)
}

///|
// The same slot computed at the call site: the address cannot be named.
#cfg(target="native")
pub fn poke_dynamic(base : UInt64) -> Unit {
  poke(base, 7)
}

///|
// A C function that RELEASES what it is given -- it frees the buffer.
//
// The annotation is `#borrow` on purpose: the release is recognised by the
// SYMBOL's NAME, and an `#owned` argument would ALSO be reported as a
// use-after-move, so the two defects would arrive together and the fixture
// could not show which check found what.
#cfg(target="native")
#borrow(buffer)
pub extern "C" fn release_buffer(buffer : Bytes) -> Unit = "free_buffer"

///|
// A C function that copies `len` bytes out of `src`.
//
// The source is BORROWED: the C side reads it and the MoonBit side keeps
// it. The toolchain's E0055 requires an annotation on a pointer parameter,
// and this one says what actually happens.
#cfg(target="native")
#borrow(src)
pub extern "C" fn copy_bytes(src : Bytes, len : Int32) -> Unit = "copy_bytes"

///|
// The same buffer released TWICE. The C side frees memory it has already
// taken back.
#cfg(target="native")
pub fn release_twice() -> Unit {
  let buffer = b"payload"
  release_buffer(buffer)
  release_buffer(buffer)
}

///|
// A buffer the C side has released, used afterwards.
#cfg(target="native")
pub fn use_after_release() -> Unit {
  let buffer = b"payload"
  release_buffer(buffer)
  println(buffer)
}

///|
// The C side is told to copy four bytes out of a three-byte object.
#cfg(target="native")
pub fn wrong_length() -> Unit {
  copy_bytes(b"abc", 4)
}

///|
// The same call with the object's OWN length: the two agree, so this must NOT
// be reported.
#cfg(target="native")
pub fn right_length() -> Unit {
  let payload = b"abc"
  copy_bytes(payload, payload.length())
}

// ---------------------------------------------------------------------------
// The classes that safe MoonBit cannot express, and that the C boundary CAN.
//
// Every shape here was measured against the real toolchain: the file compiles
// under it, and the analyzer's verdict on it is asserted by the QA gate.
//
// The names matter as much as the shapes. The analyzer cannot see the C
// source, so it reads the symbol's NAME to know whether a call allocates,
// whether it releases, and whether a parameter is a format slot. The names
// below are the ones the C world uses for those things.
//
// The constants are chosen so that they do not collide with the ones above:
// the ADDRESS-CONFLICT family reports a constant that reaches two different C
// symbols, and these shapes must not add rows of their own to that family.
// They also fit the frontend's 32-bit literal field -- a base above 2^31-1
// is stored negative, so the analyzer cannot name it.
// ---------------------------------------------------------------------------

///|
// A C function that CARVES OUT a region and returns the base address.
//
// "alloc_region" is an allocator name and the return type is a foreign
// address, so the analyzer knows the module received an allocation.
#cfg(target="native")
pub extern "C" fn alloc_region(base : UInt64, size : UInt64) -> Reg = "alloc_region"

///|
// A C function that RELEASES a region.
//
// The release is recognised by the symbol's NAME, the same way the fixture's
// own `free_buffer` is.
#cfg(target="native")
pub extern "C" fn release_region(region : Reg) -> Unit = "free_region"

///|
// A C function that WRITES into a region at an address.
#cfg(target="native")
pub extern "C" fn poke_region(addr : UInt64, value : UInt32) -> Unit = "poke_region"

///|
// A C function whose parameter is a FORMAT.
//
// The slot's NAME says the C side interprets it.
#cfg(target="native")
#borrow(fmt)
pub extern "C" fn log_msg(fmt : String) -> Unit = "log_msg"

// ---------------------------------------------------------------------------
// The LEAK at the boundary: an allocation the module never releases.
// ---------------------------------------------------------------------------

///|
// The region is allocated and NEVER released: the C side owns it, and it is
// still held when the module ends.
#cfg(target="native")
pub fn leak_the_region() -> Unit {
  let region = alloc_region(268435456, 8192)
  ignore(region)
}

///|
// The region is allocated and then RELEASED: the release is recognised by the
// symbol's name, and the slot holds the foreign type the allocator returned.
// This half must NOT be reported.
#cfg(target="native")
pub fn release_the_region() -> Unit {
  let region = alloc_region(268435456, 8192)
  release_region(region)
}

///|
// The region is allocated and handed BACK to the caller: whoever holds it now
// owns it, so it is not a leak. This half must NOT be reported.
#cfg(target="native")
pub fn hand_back_the_region() -> Reg {
  alloc_region(268435456, 8192)
}

// ---------------------------------------------------------------------------
// The FORMAT STRING at the boundary.
// ---------------------------------------------------------------------------

///|
// The format slot is handed a string from OUTSIDE this function, so the C
// side reads whatever the caller put there as a format.
#cfg(target="native")
pub fn log_untrusted(message : String) -> Unit {
  log_msg(message)
}

///|
// The format slot is handed a string the MODULE wrote out itself: the module
// chose that text, so there is nothing for the caller to steer. This half
// must NOT be reported.
#cfg(target="native")
pub fn log_own_text() -> Unit {
  log_msg("hello")
}

// ---------------------------------------------------------------------------
// The ADDRESS out of bounds at the boundary.
// ---------------------------------------------------------------------------

///|
// The address handed to C is the base plus an offset that is NOT smaller
// than the region: it points past the end of the region.
#cfg(target="native")
pub fn write_past_the_end() -> Unit {
  let region = alloc_region(268435456, 8192)
  poke_region(268435456 + 16384, 11)
  release_region(region)
}

///|
// The address handed to C is the base plus an offset that IS smaller than the
// region: the address is inside it. This half must NOT be reported.
#cfg(target="native")
pub fn write_inside_the_region() -> Unit {
  let region = alloc_region(268435456, 8192)
  poke_region(268435456 + 16, 11)
  release_region(region)
}
