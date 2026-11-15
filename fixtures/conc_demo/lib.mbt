// The CONCURRENCY fixture: two tasks, one shared cell, and the shapes that
// lose an update next to the shape that does not.
//
// Every claim here was settled by RUNNING the real toolchain:
//
//  - MoonBit tasks do NOT run MoonBit code on several OS threads. A
//    spin-lock whose spin loop has no `await` inside HANGS: the spinner
//    printed "spinner started, spinning" and the second task never printed
//    at all, because it never got to run. The runtime's thread pool
//    executes the blocking I/O; the coroutine waits on the event-loop
//    thread.
//  - So a task yields ONLY at an await point, and an await point is where
//    another task may run.
//  - A read-modify-write with NO await inside it loses nothing (measured:
//    8 tasks x 200 000 increments = exactly 1 600 000 counted). A
//    read-AWAIT-write over a shared `Ref[Int]` lost 21 000 of 24 000
//    updates -- and the SAME interleaving every run.
//
// The defect class here is therefore INTERLEAVING sensitivity, not a
// thread-level data race: there is no second OS thread for the MoonBit code
// to race with.

///|
/// A counter shared by two tasks, with an await point between the read and
/// the write. The update is NOT atomic with its read, so the other task's
/// write can land between them and this update is LOST.
pub async fn lost_update() -> Unit {
  let counter = @ref.Ref(0)
  let tasks : Array[async () -> Unit] = []
  for _ in 0..<2 {
    tasks.push(async fn() -> Unit {
      let v = counter.val
      @async.sleep(1)
      counter.val = v + 1
    })
  }
  ignore(@async.all(tasks))
}

///|
/// The SAME counter, protected by a mutex. The two accesses are under a
/// COMMON lock, so they are ordered against each other and the update
/// cannot be lost. This is the shape that must NOT be reported.
pub async fn safe_counter() -> Unit {
  let counter = @ref.Ref(0)
  let lock = @async.Mutex::Mutex()
  let tasks : Array[async () -> Unit] = []
  for _ in 0..<2 {
    tasks.push(async fn() -> Unit {
      lock.acquire()
      let v = counter.val
      @async.sleep(1)
      counter.val = v + 1
      lock.release()
    })
  }
  ignore(@async.all(tasks))
}

///|
/// The ABBA deadlock. The two tasks take the two mutexes in OPPOSITE
/// orders, and each yields while it holds one of them, so the second
/// acquire really blocks:
///
///   task 1: holds A, waits for B
///   task 2: holds B, waits for A
///
/// Each task holds a resource the next one is waiting for, so neither can
/// proceed.
pub async fn deadlock_abba() -> Unit {
  let a = @async.Mutex::Mutex()
  let b = @async.Mutex::Mutex()
  let tasks : Array[async () -> Unit] = []
  tasks.push(async fn() -> Unit {
    a.acquire()
    @async.sleep(1)
    b.acquire()
    b.release()
    a.release()
  })
  tasks.push(async fn() -> Unit {
    b.acquire()
    @async.sleep(1)
    a.acquire()
    a.release()
    b.release()
  })
  ignore(@async.all(tasks))
}

///|
/// A lock that is acquired and NEVER released. Every later acquire of it
/// waits forever, because the permit is never given back.
pub async fn lock_never_released() -> Unit {
  let lock = @async.Mutex::Mutex()
  let tasks : Array[async () -> Unit] = []
  tasks.push(async fn() -> Unit {
    lock.acquire()
    @async.sleep(1)
  })
  ignore(@async.all(tasks))
}

///|
/// A counter that only ONE task touches. There is nothing to lose the
/// update against, so this must NOT be reported.
pub async fn single_task_counter() -> Unit {
  let counter = @ref.Ref(0)
  let tasks : Array[async () -> Unit] = []
  tasks.push(async fn() -> Unit {
    let v = counter.val
    @async.sleep(1)
    counter.val = v + 1
  })
  ignore(@async.all(tasks))
}
