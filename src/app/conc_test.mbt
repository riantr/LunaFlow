///|
fn conc_ast(src : String) -> @app.ModuleAst {
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
/// How many findings of one kind the concurrency model produces.
fn conc_count(src : String, kind : @app.FindingKind) -> Int32 {
  let m = @app.analyze_conc(conc_ast(src))
  let mut n = 0
  for f in m.findings {
    if f.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
/// How many findings of any kind the concurrency model produces.
fn conc_total(src : String) -> Int32 {
  @app.analyze_conc(conc_ast(src)).findings.length()
}

///|
/// The fixture the whole model rests on: one task body, written inside a
/// loop so that more than one instance of it runs, a shared cell, and an
/// await point between the read and the write.
const CONC_SRC : String =
  #|pub async fn lost_update() -> Unit {
  #|  let counter = @ref.Ref(0)
  #|  let tasks : Array[async () -> Unit] = []
  #|  for _ in 0..<2 {
  #|    tasks.push(async fn() -> Unit {
  #|      let v = counter.val
  #|      @async.sleep(1)
  #|      counter.val = v + 1
  #|    })
  #|  }
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
/// The same counter, protected by a mutex: the two accesses are under a
/// COMMON lock, so they are ordered against each other.
const CONC_SAFE_SRC : String =
  #|pub async fn safe_counter() -> Unit {
  #|  let counter = @ref.Ref(0)
  #|  let lock = @async.Mutex::Mutex()
  #|  let tasks : Array[async () -> Unit] = []
  #|  for _ in 0..<2 {
  #|    tasks.push(async fn() -> Unit {
  #|      lock.acquire()
  #|      let v = counter.val
  #|      @async.sleep(1)
  #|      counter.val = v + 1
  #|      lock.release()
  #|    })
  #|  }
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
/// The ABBA deadlock: the two tasks take the two mutexes in OPPOSITE orders.
const CONC_DEADLOCK_SRC : String =
  #|pub async fn deadlock_abba() -> Unit {
  #|  let a = @async.Mutex::Mutex()
  #|  let b = @async.Mutex::Mutex()
  #|  let tasks : Array[async () -> Unit] = []
  #|  tasks.push(async fn() -> Unit {
  #|    a.acquire()
  #|    @async.sleep(1)
  #|    b.acquire()
  #|    b.release()
  #|    a.release()
  #|  })
  #|  tasks.push(async fn() -> Unit {
  #|    b.acquire()
  #|    @async.sleep(1)
  #|    a.acquire()
  #|    a.release()
  #|    b.release()
  #|  })
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
/// A lock that is acquired and never released.
const CONC_UNRELEASED_SRC : String =
  #|pub async fn lock_never_released() -> Unit {
  #|  let lock = @async.Mutex::Mutex()
  #|  let tasks : Array[async () -> Unit] = []
  #|  tasks.push(async fn() -> Unit {
  #|    lock.acquire()
  #|    @async.sleep(1)
  #|  })
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
/// A cell that only ONE task touches: there is nothing to lose the update
/// against.
const CONC_SINGLE_SRC : String =
  #|pub async fn single_task_counter() -> Unit {
  #|  let counter = @ref.Ref(0)
  #|  let tasks : Array[async () -> Unit] = []
  #|  tasks.push(async fn() -> Unit {
  #|    let v = counter.val
  #|    @async.sleep(1)
  #|    counter.val = v + 1
  #|  })
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
/// A read whose value is used after an await point, while another task
/// writes the same cell.
const CONC_STALE_SRC : String =
  #|pub async fn stale_read() -> Unit {
  #|  let counter = @ref.Ref(0)
  #|  let tasks : Array[async () -> Unit] = []
  #|  for _ in 0..<2 {
  #|    tasks.push(async fn() -> Unit {
  #|      let v = counter.val
  #|      @async.sleep(1)
  #|      ignore(v)
  #|    })
  #|  }
  #|  tasks.push(async fn() -> Unit {
  #|    counter.val = 99
  #|  })
  #|  ignore(@async.all(tasks))
  #|}
  #|

///|
test "the parser captures the closure body of a task" {
  let f = @app.parse_file("c.mbt", CONC_SRC)
  inspect(f.closures.length(), content="1")
  inspect(f.closures[0].body.length(), content="3")
}

///|
test "the concurrency model finds the task" {
  let m = @app.analyze_conc(conc_ast(CONC_SRC))
  inspect(m.tasks.length(), content="1")
}

///|
test "a closure written inside a loop may run more than once" {
  let m = @app.analyze_conc(conc_ast(CONC_SRC))
  inspect(m.tasks[0].instances, content="2")
}

///|
test "the read-modify-write split by an await point loses the update" {
  inspect(conc_count(CONC_SRC, @app.FFconcLostUpdate), content="1")
}

///|
test "a common lock orders the two accesses, so nothing is lost" {
  inspect(conc_total(CONC_SAFE_SRC), content="0")
}

///|
test "the two tasks that take the locks in opposite orders deadlock" {
  inspect(conc_count(CONC_DEADLOCK_SRC, @app.FFconcDeadlockCycle), content="1")
}

///|
test "a lock that is never released is reported" {
  inspect(
    conc_count(CONC_UNRELEASED_SRC, @app.FFconcResourceUnreleased),
    content="1",
  )
}

///|
test "a cell that only one task touches is not a race" {
  inspect(conc_total(CONC_SINGLE_SRC), content="0")
}

///|
test "a read used after an await point may already be out of date" {
  inspect(conc_count(CONC_STALE_SRC, @app.FFconcStaleRead), content="1")
}

///|
test "the model does not claim a thread-level data race" {
  let m = @app.analyze_conc(conc_ast(CONC_SRC))
  inspect(m.cells.length(), content="1")
  // The cell is qualified by the function that binds it: two functions may
  // each bind `counter` to a `Ref` of their own.
  inspect(m.cells[0].name, content="lost_update.counter")
  inspect(m.cells[0].varname, content="counter")
}

///|
test "the tasks of two functions that never call each other do not interleave" {
  // The two functions each spawn a task over their OWN `counter`. The
  // tasks never run at the same time, so there is no conflict between
  // them -- and neither `counter` is shared with the other.
  let src =
    #|pub async fn one() -> Unit {
    #|  let counter = @ref.Ref(0)
    #|  let tasks : Array[async () -> Unit] = []
    #|  for _ in 0..<2 {
    #|    tasks.push(async fn() -> Unit {
    #|      let v = counter.val
    #|      @async.sleep(1)
    #|      counter.val = v + 1
    #|    })
    #|  }
    #|  ignore(@async.all(tasks))
    #|}
    #|pub async fn two() -> Unit {
    #|  let counter = @ref.Ref(0)
    #|  let tasks : Array[async () -> Unit] = []
    #|  for _ in 0..<2 {
    #|    tasks.push(async fn() -> Unit {
    #|      let v = counter.val
    #|      @async.sleep(1)
    #|      counter.val = v + 1
    #|    })
    #|  }
    #|  ignore(@async.all(tasks))
    #|}
    #|
  let m = @app.analyze_conc(conc_ast(src))
  // Two cells, one per function: they are not the same `Ref`.
  inspect(m.cells.length(), content="2")
  // Each one loses its update -- but only against ITSELF, the other
  // instance of its own body.
  inspect(conc_count(src, @app.FFconcLostUpdate), content="2")
}

///|
test "a task that is spawned by a function the owner calls may interleave with it" {
  // `outer` calls `inner`, so the tasks of `inner` run inside the tasks of
  // `outer`: the two bodies share a cell and may interleave.
  let src =
    #|async fn inner(counter : @ref.Ref[Int]) -> Unit {
    #|  let tasks : Array[async () -> Unit] = []
    #|  for _ in 0..<2 {
    #|    tasks.push(async fn() -> Unit {
    #|      let v = counter.val
    #|      @async.sleep(1)
    #|      counter.val = v + 1
    #|    })
    #|  }
    #|  ignore(@async.all(tasks))
    #|}
    #|pub async fn outer() -> Unit {
    #|  let counter = @ref.Ref(0)
    #|  let tasks : Array[async () -> Unit] = []
    #|  for _ in 0..<2 {
    #|    tasks.push(async fn() -> Unit {
    #|      @async.sleep(1)
    #|      inner(counter)
    #|    })
    #|  }
    #|  ignore(@async.all(tasks))
    #|}
    #|
  // The two bodies reach the SAME cell and neither is ordered by a lock.
  inspect(conc_total(src) > 0, content="true")
}
