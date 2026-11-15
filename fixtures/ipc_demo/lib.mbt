// The IPC AND BUFFER fixture: the reads that can come back short, the views
// that go stale, the buffers two sides write -- and the shapes that are safe.
//
// Every claim here was settled by RUNNING the real core, not by reading it:
//
//  - `read_into` returns the NUMBER OF BYTES IT READ, and that number can be
//    smaller than the buffer. Measured: a 16-byte buffer pre-filled with
//    0xFF, a pipe with 3 bytes in it, one `read_into` -> returned 3, and the
//    buffer afterwards was 61 62 63 FF FF FF ... FF. The bytes past the count
//    were never written: they still held what the buffer held before.
//  - `read_into(buf, offset=8)` returned 3 and wrote at buf[8..11]. The
//    caller has to advance the offset by the count itself.
//  - At EOF `read_into` returns 0 and `read()` returns None, so 0 is both
//    "no progress" and "the stream ended".
//  - `peek` returns a VIEW into the reader's own buffer, and the core says
//    the caller must not use it after any other operation on the same
//    reader. Measured: peeked 61 62 63; after two reads the SAME view read
//    78 79 7A.
//  - A pending write is NOT a snapshot. Measured: a 4-byte buffer of 'A'
//    handed to `write` and then overwritten with 'B' while the write was
//    pending delivered the 'B's to the reader.
//
// THE ANALYZER MATCHES THE METHOD NAME -- it does not infer types -- so the
// reader and the writer below carry the core's API names, and that is what
// the analyzer sees. The bodies follow the core's measured semantics, and the
// fixture never blocks: the analyzer RUNS the module it analyses.

///|
/// A reader with the core's `BinaryReader` shape.
pub struct Reader {
  data : FixedArray[Byte]
  mut pos : Int32
}

///|
/// The reader's constructor.
pub fn Reader::Reader(data : FixedArray[Byte]) -> Reader {
  Reader::{ data, pos: 0, }
}

///|
/// Fill `dst` and return how many bytes were ACTUALLY written. That number
/// can be smaller than the buffer: the bytes past it were never written.
pub fn Reader::read_into(self : Reader, dst : FixedArray[Byte]) -> Int32 {
  let mut n = 0
  while n < dst.length() && self.pos + n < self.data.length() {
    dst[n] = self.data[self.pos + n]
    n = n + 1
  }
  self.pos = self.pos + n
  n
}

///|
/// A view into the reader's own buffer. The core says the caller must not
/// use it after any other operation on the same reader, because the reader
/// keeps ONE buffer and reuses it.
pub fn Reader::peek(self : Reader) -> BytesView? {
  if self.pos >= self.data.length() {
    return None
  }
  let all : Bytes = self.data.unsafe_reinterpret_as_bytes()
  Some(all[self.pos:])
}

///|
/// A writer with the core's `BinaryWriter` shape.
pub struct Writer {
  sent : Array[Byte]
}

///|
/// The writer's constructor.
pub fn Writer::Writer() -> Writer {
  Writer::{ sent: [], }
}

///|
/// Hand every byte of the view over. The core's `write` is EXHAUSTIVE: it
/// loops until all of them are handed over.
pub fn Writer::write(self : Writer, data : BytesView) -> Unit {
  for b in data.iter() {
    self.sent.push(b)
  }
}

///|
/// Read the first `n` bytes of the buffer. The buffer is mentioned, so the
/// analyzer sees that its CONTENTS are used.
fn use_first(buf : FixedArray[Byte], n : Int32) -> Unit {
  let mut i = 0
  while i < n {
    if i < buf.length() {
      ignore(buf[i])
    }
    i = i + 1
  }
}

///|
/// Use the bytes of a view.
fn use_bytes(b : BytesView) -> Unit {
  ignore(b.length())
}

///|
/// A reader with three bytes in it.
fn three_bytes() -> Reader {
  Reader::Reader([b'a', b'b', b'c'])
}

///|
/// A read whose COUNT IS DISCARDED, and whose buffer is then used as a whole.
/// The read can come back short, and the bytes past the count still hold
/// whatever the buffer held before. This is the shape that must be reported.
pub fn partial_read() -> Unit {
  let reader = three_bytes()
  let buf = FixedArray::make(16, b'\xff')
  ignore(reader.read_into(buf))
  use_first(buf, buf.length())
}

///|
/// The SAME read, with the count KEPT and the buffer used up to the count.
/// Nothing says the read filled the buffer, so this must NOT be reported.
pub fn checked_read() -> Unit {
  let reader = three_bytes()
  let buf = FixedArray::make(16, b'\xff')
  let n = reader.read_into(buf)
  use_first(buf, n)
}

///|
/// A loop that reads until the stream ends, with the count DISCARDED. The
/// count is the only thing that could report the end of the stream, so the
/// loop cannot see it. This is the shape that must be reported.
pub fn read_until_eof() -> Unit {
  let reader = three_bytes()
  let buf = FixedArray::make(16, b'\xff')
  let mut i = 0
  while i < 3 {
    ignore(reader.read_into(buf))
    i = i + 1
  }
}

///|
/// A view taken with `peek` and USED AFTER the reader has run again. The
/// reader reuses its buffer, so the bytes the view shows are not the bytes
/// that were read. This is the shape that must be reported.
pub fn stale_view() -> Unit {
  let reader = three_bytes()
  let buf = FixedArray::make(16, b'\xff')
  let v = reader.peek().unwrap()
  let n = reader.read_into(buf)
  use_first(buf, n)
  use_bytes(v)
}

///|
/// The SAME view, used BEFORE the reader runs again. The core's contract
/// allows it, so this must NOT be reported.
pub fn view_used_before_the_next_read() -> Unit {
  let reader = three_bytes()
  let buf = FixedArray::make(16, b'\xff')
  let v = reader.peek().unwrap()
  use_bytes(v)
  let n = reader.read_into(buf)
  use_first(buf, n)
}

///|
/// A buffer that a task writes and the function that started the task then
/// uses. A pending write is not a snapshot, so the two sides can both decide
/// what the buffer holds. This is the shape that must be reported.
pub async fn shared_buffer() -> Unit {
  let writer = Writer::Writer()
  let buf = FixedArray::make(16, b'\xff')
  let tasks : Array[async () -> Unit] = []
  tasks.push(async fn() -> Unit {
    writer.write(buf.unsafe_reinterpret_as_bytes())
  })
  ignore(@async.all(tasks))
  buf[0] = b'z'
}

///|
/// A task that writes a buffer of its OWN. Nothing is shared, so this must
/// NOT be reported.
pub async fn private_buffer() -> Unit {
  let writer = Writer::Writer()
  let tasks : Array[async () -> Unit] = []
  tasks.push(async fn() -> Unit {
    let own = FixedArray::make(16, b'\xff')
    writer.write(own.unsafe_reinterpret_as_bytes())
  })
  ignore(@async.all(tasks))
}
