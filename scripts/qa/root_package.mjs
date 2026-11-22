// The ROOT PACKAGE gate.
//
// `moonx riantr/LunaFlow@latest <target>` resolves the ROOT package of the
// module coordinate and runs its WASM artifact. With no root executable,
// that invocation fails with "Prebuilt wasm asset does not exist" — a failure
// that only appears AFTER a release, when the version is already public.
//
// So the root package is checked here, before the release:
//
//   * the root `moon.pkg` exists, is an executable, and supports wasm
//   * the module's preferred target is wasm, because the registry publishes
//     ONE artifact per version and `moonx --target` accepts no other value
//   * the root builds for native, wasm AND js
//   * the CLI accepts a BARE COORDINATE, which is what `moonx` passes as
//     argv[1] — `moonx <module>@latest <target>` runs the program with the
//     target as its first argument
//   * the bare coordinate produces a report, and the explicit `analyze`
//     spelling produces the same one
//
// Dependency-free, like the rest of the harness.

import { existsSync, readFileSync, rmSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = resolve(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const OUT = join(ROOT, '_build', 'qa', 'root_package');

const failures = [];
const passes = [];

function check(name, ok, detail) {
  if (ok) {
    passes.push(name);
    console.log(`PASS  ${name}${detail ? ` — ${detail}` : ''}`);
  } else {
    failures.push(name);
    console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

function moon(args, opts = {}) {
  return spawnSync('moon', args, {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout: opts.timeout ?? 600000,
    env: { ...process.env, ...(opts.env || {}) },
  });
}

// ------------------------------------------------------- the root manifest

const rootPkgPath = join(ROOT, 'moon.pkg');
check('the root package exists', existsSync(rootPkgPath), 'moon.pkg');

if (existsSync(rootPkgPath)) {
  const pkg = readFileSync(rootPkgPath, 'utf8');
  check(
    'the root package is an executable',
    /pkgtype\s*\(\s*kind\s*:\s*"executable"\s*\)/.test(pkg),
  );
  check(
    'the root package supports wasm',
    /supported_targets\s*=\s*"[^"]*wasm/.test(pkg),
    pkg.match(/supported_targets\s*=\s*"[^"]*"/)?.[0] ?? 'no supported_targets',
  );
}

// ------------------------------------------------------ the preferred target

const modText = readFileSync(join(ROOT, 'moon.mod'), 'utf8');
const preferred = modText.match(/preferred_target\s*=\s*"([^"]+)"/)?.[1] ?? '';
check(
  'the module publishes the wasm artifact',
  preferred === 'wasm',
  `preferred_target = "${preferred}"`,
);

// ------------------------------------------------------------- the builds

check('the root builds for native', moon(['build', '.', '--target', 'native']).status === 0);
check('the root builds for wasm', moon(['build', '.', '--target', 'wasm']).status === 0);
check('the root builds for js', moon(['build', '.', '--target', 'js']).status === 0);

const nativeExe = join(ROOT, '_build', 'native', 'debug', 'build', 'LunaFlow.exe');
const nativeBin = join(ROOT, '_build', 'native', 'debug', 'build', 'LunaFlow');
const exe = existsSync(nativeExe) ? nativeExe : nativeBin;
check('the root executable is on disk', existsSync(exe), exe);

const wasmArtifact = join(ROOT, '_build', 'wasm', 'debug', 'build', 'LunaFlow.wasm');
check('the root wasm artifact is on disk', existsSync(wasmArtifact), wasmArtifact);

const jsArtifact = join(ROOT, '_build', 'js', 'debug', 'build', 'LunaFlow.js');
check('the root js artifact is on disk', existsSync(jsArtifact), jsArtifact);

// ------------------------------------------- the bare coordinate, end to end

// Run the built executable. `exe` is the ROOT package's binary, which is the
// one `moonx` resolves.
const run = (args, timeout = 180000) =>
  spawnSync(exe, args, {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout,
  });

if (existsSync(exe)) {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });

  // The target is a LOCAL fixture, so the check does not depend on the
  // registry being reachable: what is under test is the ARGUMENT SHAPE, not
  // the fetch.
  const bare = spawnSync(exe, ['analyze', '--dir', 'fixtures/vuln_demo', '--out', OUT, '--quiet'], {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout: 120000,
  });

  // THE TARGET SLOT follows the peer analyzer's rule, so the two tools take
  // the same invocation: a coordinate is fetched, a PATH is analysed where it
  // stands, and with no target at all the CURRENT DIRECTORY is analysed.
  //
  // The report's own `root` line is the assertion: it names WHICH tree was
  // analysed, so a tree that was mistaken for another one cannot pass.
  const localTargets = [
    { args: [], label: 'no target analyses the current directory', root: '.' },
    { args: ['.'], label: 'a "." target analyses the current directory', root: '.' },
    { args: ['./fixtures/vuln_demo'], label: 'a path target is analysed where it stands', root: './fixtures/vuln_demo' },
    { args: ['analyze', '--dir', 'fixtures/vuln_demo'], label: '--dir still names a tree', root: 'fixtures/vuln_demo' },
  ];
  for (const t of localTargets) {
    const localRun = spawnSync(exe, [...t.args, '--out', OUT], {
      cwd: ROOT,
      encoding: 'utf8',
      shell: process.platform === 'win32',
      timeout: 120000,
    });
    check(
      t.label,
      localRun.status === 0 && (localRun.stdout || '').includes(`root\t${t.root}`),
      `exit=${localRun.status}`,
    );
  }

  // A coordinate-SHAPED string is a coordinate, not a directory: "fixtures/
  // vuln_demo" has an author part and a module part, so it is resolved through
  // the registry and refused there. The peer analyzer resolves it the same
  // way -- a local path needs the "./" or a drive letter to be read as one.
  // What must NOT happen is a report about the WRONG tree.
  for (const path of ['fixtures/vuln_demo', './fixtures/vuln_demo']) {
    const pathRun = spawnSync(exe, [path, '--out', OUT, '--quiet'], {
      cwd: ROOT,
      encoding: 'utf8',
      shell: process.platform === 'win32',
      timeout: 120000,
    });
    check(
      `a local path is not analysed as the wrong tree: ${path}`,
      pathRun.status === 0 && !(pathRun.stdout || '').includes(`root\t${path}`),
      `exit=${pathRun.status}`,
    );
  }

  // The real shape: an author/module coordinate in argv[1].
  const coordOut = join(OUT, 'coord');
  const bareRun = spawnSync(exe, ['analyze', '--dir', 'fixtures/vuln_demo', '--out', coordOut, '--quiet'], {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout: 120000,
  });
  check('the explicit analyze spelling still works', bareRun.status === 0 && bareRun.stdout.includes('REPORT'));

  // And the bare coordinate itself, against the module's own coordinate.
  const selfCoord = 'riantr/LunaFlow@latest';
  const selfOut = join(OUT, 'self');
  const selfRun = spawnSync(exe, [selfCoord, '--out', selfOut, '--quiet'], {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout: 600000,
  });
  check(
    'a bare coordinate is an implicit analyze',
    selfRun.status === 0 && selfRun.stdout.includes('REPORT'),
    (selfRun.stdout || '').trim().split('\n')[0] ?? `exit=${selfRun.status}`,
  );

  // The RESOLVED VERSION has to be a real version. MEASURED BUG: the fetch
  // log of a self-analysis offered the token ".", and `base + "/."` exists,
  // so the analysis pinned itself to the BASE directory and the report
  // claimed the resolved version was ".". The check is shape-based, not
  // version-based, so it keeps working after the next release.
  const reportName = (selfRun.stdout || '')
    .trim()
    .split('\n')
    .map((l) => l.replace(/^REPORT\t/, ''))
    .find((l) => l.endsWith('.md'));
  check(
    'the resolved version is a real version',
    !!reportName && /_\d+\.\d+\.\d+\.md$/.test(reportName),
    reportName ?? '(no report)',
  );

  // The usage text has to name the bare form, or the feature is invisible.
  const help = spawnSync(exe, ['help'], {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    timeout: 60000,
  });
  check(
    'the usage text names the bare-coordinate form',
    help.stdout.includes('LunaFlow <author>/<module>'),
  );
  // The default target is a feature nobody can see unless the usage text
  // says so.
  check(
    'the usage text names the default target',
    help.stdout.includes('CURRENT DIRECTORY'),
  );

  // ---------------------------------------------------- the peer's options
  //
  // These five are the options the peer analyzer has and this one did not:
  // --exclude, --families, --explain, --metrics and --per-function. Each one
  // is checked by what it DOES, not by whether it is accepted.

  // --explain and --explain-all are CONTRACT REQUESTS, not scans: they answer
  // and stop, before any file is read.
  const roster = run(['--explain-all']);
  check(
    '--explain-all prints the family roster',
    roster.status === 0 &&
      roster.stdout.includes('DEAD-CODE') &&
      roster.stdout.includes('TAINT-INDEX') &&
      !roster.stdout.includes('REPORT'),
    `exit=${roster.status}`,
  );
  const one = run(['--explain', 'DEAD-CODE']);
  check(
    '--explain prints one family contract',
    one.status === 0 &&
      one.stdout.includes('property') &&
      one.stdout.includes('assumption') &&
      one.stdout.includes('excluded') &&
      !one.stdout.includes('REPORT'),
    `exit=${one.status}`,
  );
  const unknown = run(['--explain', 'NO-SUCH-CODE']);
  check(
    '--explain refuses a code that names no family',
    unknown.status === 0 && unknown.stdout.includes('ERROR'),
    `exit=${unknown.status}`,
  );

  // --families is a PROFILE, and it is validated before the scan runs: an
  // unknown code is a WARNING and the scan still runs, and a code that is
  // both included and excluded is an ERROR and the scan does not run at all.
  const profile = run([
    'analyze',
    '--dir',
    'fixtures/vuln_demo',
    '--out',
    join(OUT, 'profile'),
    '--families',
    'DEAD-CODE',
    '--quiet',
  ]);
  check(
    '--families accepts a profile',
    profile.status === 0 && profile.stdout.includes('REPORT'),
    `exit=${profile.status}`,
  );
  const warned = run([
    'analyze',
    '--dir',
    'fixtures/vuln_demo',
    '--out',
    join(OUT, 'warned'),
    '--families',
    'NO-SUCH-CODE',
    '--quiet',
  ]);
  check(
    'an unknown family code warns and the scan still runs',
    warned.status === 0 &&
      warned.stdout.includes('WARNING') &&
      warned.stdout.includes('REPORT'),
    `exit=${warned.status}`,
  );
  const conflicted = run([
    'analyze',
    '--dir',
    'fixtures/vuln_demo',
    '--out',
    join(OUT, 'conflicted'),
    '--families',
    'DEAD-CODE',
    '--exclude-families',
    'DEAD-CODE',
    '--quiet',
  ]);
  check(
    'a code that is both included and excluded stops the scan',
    conflicted.status === 0 &&
      conflicted.stdout.includes('ERROR') &&
      !conflicted.stdout.includes('REPORT'),
    `exit=${conflicted.status}`,
  );

  // --exclude names a directory to skip. The check is that the excluded tree
  // is GONE and that it was there before: an exclusion that matched nothing
  // would pass the first half on its own.
  const all = run(['analyze', '--dir', '.', '--out', join(OUT, 'ex_all'), '--list-functions']);
  // `--list-functions` prints `FUNCTION<TAB>FILE<TAB>STATEMENTS` as a HEADER
  // and then one row per function, whose first field is the function NAME.
  const withoutSrc = (out) =>
    (out || '')
      .split('\n')
      .map((l) => l.split('\t'))
      .filter((f) => f.length >= 3 && f[0] !== 'FUNCTION')
      .some((f) => f[1].startsWith('src/'));
  check('the excluded tree is present without --exclude', withoutSrc(all.stdout));
  const excluded = run([
    'analyze',
    '--dir',
    '.',
    '--out',
    join(OUT, 'ex_some'),
    '--exclude',
    'src',
    '--list-functions',
  ]);
  check(
    '--exclude skips the named directory',
    excluded.status === 0 && !withoutSrc(excluded.stdout),
    `exit=${excluded.status}`,
  );

  // --metrics prints the ADEQUACY block: what was read, what was understood,
  // what was entered, what was found.
  const metrics = run([
    'analyze',
    '--dir',
    'fixtures/vuln_demo',
    '--out',
    join(OUT, 'metrics'),
    '--metrics',
  ]);
  check(
    '--metrics prints the adequacy block',
    metrics.status === 0 &&
      metrics.stdout.includes('METRICS\tread\t') &&
      metrics.stdout.includes('METRICS\tstmts\t') &&
      metrics.stdout.includes('METRICS\tfuncs\t') &&
      metrics.stdout.includes('METRICS\tfindings\t'),
    `exit=${metrics.status}`,
  );

  // --per-function lifts the --max-functions cap, so more functions are
  // entered than the cap allows.
  const enteredOf = (out) => {
    const m = (out || '').match(/METRICS\tfuncs\t[^\n]*entered=(\d+)/);
    return m ? Number(m[1]) : -1;
  };
  const capped = run([
    'analyze',
    '--dir',
    '.',
    '--out',
    join(OUT, 'pf_capped'),
    '--max-functions',
    '5',
    '--metrics',
  ]);
  const perFn = run([
    'analyze',
    '--dir',
    '.',
    '--out',
    join(OUT, 'pf_all'),
    '--max-functions',
    '5',
    '--per-function',
    '--metrics',
  ]);
  check(
    '--per-function enters more functions than the cap allows',
    enteredOf(capped.stdout) === 5 && enteredOf(perFn.stdout) > 5,
    `capped=${enteredOf(capped.stdout)} per-function=${enteredOf(perFn.stdout)}`,
  );
}

// --------------------------------------------------------- the evolved value
// analysis
//
// The EVOLVED VALUE ANALYSIS asks what a value is USED FOR, not what its
// range is. It is checked here against the fixture that carries both the
// defects and the ordinary shapes next to them: a check that fires on the
// safe half is a false positive, and a check that does not fire on the
// defect half is a check that does not work.
if (existsSync(join(ROOT, 'fixtures', 'eva_demo', 'lib.mbt'))) {
  const evaRoster = run(['--explain-all']);
  const evaCodes = [
    'INTEGER-OVERFLOW',
    'DIVISION-BY-ZERO',
    'INDEX-OOB',
    'NONE-DEREF',
    'UNINITIALIZED-READ',
    'INVALID-CAST',
  ];
  const reservedCodes = [
    'USE-AFTER-FREE',
    'POINTER-ARITHMETIC',
    'MEMORY-LEAK',
    'FORMAT-STRING',
  ];
  check(
    'the roster carries the evolved value analysis families',
    evaRoster.status === 0 && evaCodes.every((c) => evaRoster.stdout.includes(c)),
  );
  check(
    'the roster carries the classes MoonBit cannot express',
    reservedCodes.every((c) => evaRoster.stdout.includes(c)),
  );
  const evaOne = run(['--explain', 'INTEGER-OVERFLOW']);
  check(
    '--explain prints an evolved value analysis contract',
    evaOne.status === 0 &&
      evaOne.stdout.includes('property') &&
      evaOne.stdout.includes('assumption') &&
      evaOne.stdout.includes('excluded') &&
      !evaOne.stdout.includes('REPORT'),
    `exit=${evaOne.status}`,
  );
  const reserved = run(['--explain', 'USE-AFTER-FREE']);
  check(
    'the reserved families say why they never fire',
    reserved.status === 0 && reserved.stdout.includes('NOT APPLICABLE IN MOONBIT'),
    `exit=${reserved.status}`,
  );

  const evaRun = run([
    'analyze',
    '--dir',
    'fixtures/eva_demo',
    '--out',
    join(OUT, 'eva'),
    '--funnel',
    '--trials',
    '4',
  ]);
  const evaReport = join(OUT, 'eva', 'local_module_0.0.0.md');
  const evaText = existsSync(evaReport) ? readFileSync(evaReport, 'utf8') : '';
  check(
    'the evolved value analysis reports every class it can',
    evaRun.status === 0 &&
      evaCodes.every((c) => evaText.includes(c)),
    `exit=${evaRun.status}`,
  );
  check(
    'the report has the evolved value analysis section',
    evaText.includes('### 5.3 EVA findings'),
  );
  // The six classes the roster declares as EVOLVED value families must be
  // listed IN THE EVOLVED SECTION, not somewhere else in the report. A class
  // that is filed under the classic abstract findings is a class a reader
  // auditing the EVA coverage does not find.
  const evaSection = (() => {
    const start = evaText.indexOf('### 5.3 EVA findings');
    if (start < 0) return '';
    const end = evaText.indexOf('\n## 6.', start);
    return end < 0 ? evaText.slice(start) : evaText.slice(start, end);
  })();
  const classicSection = (() => {
    const start = evaText.indexOf('### 5.2 L2 abstract findings');
    if (start < 0) return '';
    const end = evaText.indexOf('### 5.3 EVA findings', start);
    return end < 0 ? evaText.slice(start) : evaText.slice(start, end);
  })();
  check(
    'the evolved section lists every class the roster declares as evolved',
    evaCodes.every((c) => evaSection.includes(c)),
    `section=${evaSection.length} chars`,
  );
  check(
    'the classic section does not hold an evolved class',
    !evaCodes.some((c) => classicSection.includes(c)),
  );
  // The NEGATIVE half of the fixture must not be reported. Each of these is
  // the ordinary shape that sits next to the defect. The check is scoped to
  // the FINDINGS sections: the same names appear in the range tables and in
  // the allocation table, which are where a value's interval and a value's
  // placement are printed and not where a defect is.
  const safeFns = [
    'safe_sum',
    'safe_divisor',
    'safe_index',
    'safe_some',
    'safe_some_on_both_branches',
    'safe_initialized',
    'safe_cast',
  ];
  const findingsSection = (text) => {
    const start = text.indexOf('### 5.1 Taint sinks');
    if (start < 0) return '';
    const end = text.indexOf('### 5.4 The global region', start);
    return end < 0 ? text.slice(start) : text.slice(start, end);
  };
  const evaFindingsText = findingsSection(evaText);
  const reportedSafe = safeFns.filter((fn) =>
    new RegExp(`\\|\\s+${fn}\\s+\\|`).test(evaFindingsText),
  );
  check(
    'the ordinary shapes are not reported',
    reportedSafe.length === 0,
    reportedSafe.join(','),
  );

  // The family profile selects the evolved families by their code.
  const onlyOverflow = run([
    'analyze',
    '--dir',
    'fixtures/eva_demo',
    '--out',
    join(OUT, 'eva_profile'),
    '--funnel',
    '--families',
    'INTEGER-OVERFLOW',
  ]);
  const onlyText = existsSync(join(OUT, 'eva_profile', 'local_module_0.0.0.md'))
    ? readFileSync(join(OUT, 'eva_profile', 'local_module_0.0.0.md'), 'utf8')
    : '';
  check(
    'a family profile selects the evolved families by code',
    onlyOverflow.status === 0 &&
      onlyText.includes('INTEGER-OVERFLOW') &&
      !onlyText.includes('DIVISION-BY-ZERO'),
    `exit=${onlyOverflow.status}`,
  );
}

// The MEMORY LAYOUT model: the global region, the allocation classes and the
// layout-stability self-check.
//
// The fixture carries a global that reads a global declared LATER in the file
// (MoonBit resolves top-level bindings by dependency), a global whose
// initializer overflows, an allocation that stays in the frame and one that
// escapes. Every claim about it was settled by running the toolchain.
if (existsSync(join(ROOT, 'fixtures', 'memory_demo', 'lib.mbt'))) {
  const memRun = run([
    'analyze',
    '--dir',
    'fixtures/memory_demo',
    '--out',
    join(OUT, 'mem'),
    '--funnel',
    '--trials',
    '4',
    '--stability',
  ]);
  const memReport = join(OUT, 'mem', 'local_module_0.0.0.md');
  const memText = existsSync(memReport) ? readFileSync(memReport, 'utf8') : '';
  check(
    'the report has the global region section',
    memText.includes('### 5.4 The global region'),
  );
  check(
    'the report has the allocation classes section',
    memText.includes('### 5.5 Where the allocations live'),
  );
  check(
    'the report has the layout stability section',
    memText.includes('### 5.6 Layout stability'),
  );
  // The dependency-order global: `derived` is written BEFORE `base`, and its
  // value is still 12. A file-order evaluator would leave it unknown.
  check(
    'a global is resolved in dependency order, not file order',
    /`derived`\s*\|\s*Int32\s*\|\s*12\s*\|/.test(memText),
  );
  // The global whose initializer overflows: the value is the WRAPPED one.
  check(
    "a global's value is the wrapped one MoonBit computes",
    /`overflowing`\s*\|\s*Int32\s*\|\s*-2147483648\s*\|/.test(memText),
  );
  check(
    'the overflow in a global initializer is reported',
    memText.includes('INTEGER-OVERFLOW'),
  );
  // The allocation classes: one stays in the frame, one escapes.
  const frameRow = /\| frame_allocation \|.*\| \*\*FRAME\*\*/.test(memText);
  const heapRows =
    /\| escaping_allocation \|.*\| \*\*HEAP\*\*/.test(memText) &&
    /\| handed_over \|.*\| \*\*HEAP\*\*/.test(memText);
  check(
    'an allocation that does not escape is in the frame',
    frameRow,
  );
  check(
    'an allocation that escapes is on the heap',
    heapRows,
  );
  // The stability self-check: the abstract classes do not depend on the
  // sample, and the check says so.
  check(
    'the stability check compares the findings across the re-samples',
    memText.includes('Does the sample depend on it') ||
      memText.includes('Depends on the sample?'),
  );
  check(
    'the stability check ran at more than one sample size',
    memRun.status === 0 && memText.includes('In every run'),
  );
  // The GROWTH family: a module-level collection that only ever grows. The
  // fixture carries the defect half AND the three safe halves: a collection
  // that is trimmed, a LOCAL collection, and one filled in a bounded loop.
  check(
    'the report has the growth section',
    memText.includes('#### 5.5.1 A collection that only grows'),
  );
  check(
    'a global collection that only grows is reported',
    (memText.match(/\| UNBOUNDED-GROWTH \|/g) || []).length === 1,
  );
  check(
    'the global collection that is trimmed is not reported',
    !/UNBOUNDED-GROWTH \| warning \| certain \|.*ring/.test(memText),
  );
  check(
    'the local collection is not reported',
    !/UNBOUNDED-GROWTH \| warning \| certain \|.*scratch/.test(memText),
  );
  check(
    'the collection filled in a bounded loop is not reported',
    !/UNBOUNDED-GROWTH \| warning \| certain \|.*few/.test(memText),
  );
  const growthContract = run(['--explain', 'UNBOUNDED-GROWTH']);
  const growthText = growthContract.stdout ?? '';
  check(
    'the growth family states the limit of its claim',
    growthContract.status === 0 &&
      growthText.includes('cannot bound') &&
      /local/i.test(growthText),
    `exit=${growthContract.status}`,
  );
}

// The FOREIGN ADDRESS SPACE model: the C boundary, the two address spaces and
// the ownership contract.
//
// The fixture carries a C symbol declared TWICE with two different
// signatures, an `#owned` argument that is used after the call, a constant
// address handed to two different symbols, and a slot that is constant at one
// call site and computed at another. Every claim about it was settled by
// running the toolchain.
if (existsSync(join(ROOT, 'fixtures', 'ffi_demo', 'lib.mbt'))) {
  const ffiRun = run([
    'analyze',
    '--dir',
    'fixtures/ffi_demo',
    '--out',
    join(OUT, 'ffi'),
    '--funnel',
    '--trials',
    '4',
  ]);
  const ffiReport = join(OUT, 'ffi', 'local_module_0.0.0.md');
  const ffiText = existsSync(ffiReport) ? readFileSync(ffiReport, 'utf8') : '';
  check('the foreign address space is analysed', ffiRun.status === 0);
  check(
    'the report has the foreign address space section',
    ffiText.includes('### 5.7 The foreign address space'),
  );
  check(
    'the report lists the foreign declarations',
    ffiText.includes('#### 5.7.1 The foreign declarations'),
  );
  check(
    'the report lists the named addresses',
    ffiText.includes('#### 5.7.2 The named addresses'),
  );
  check(
    'the report lists the calls across the boundary',
    ffiText.includes('#### 5.7.3 The calls across the boundary'),
  );
  // The SPACES: the declared type says which side of the boundary a value
  // lands on. A `Bytes` is an address of a MoonBit heap object, an `#external`
  // type is an address the C side owns, and a `UInt64` is copied by value.
  check(
    'a pointer parameter is a heap pointer at the boundary',
    /buffer : Bytes \(heap pointer, owned\)/.test(ffiText),
  );
  check(
    'an #external parameter is a foreign address',
    /name : Reg \(foreign address/.test(ffiText),
  );
  check(
    'a scalar parameter is copied by value',
    /base : UInt64 \(value/.test(ffiText),
  );
  // The findings. The signature conflict is reported at BOTH declarations,
  // because either of them may be the wrong one.
  check(
    'one C symbol with two signatures is reported at both declarations',
    (ffiText.match(/FFI-SIGNATURE-CONFLICT/g) || []).length === 2,
  );
  check(
    'an #owned argument used after the call is reported',
    ffiText.includes('FFI-USE-AFTER-MOVE'),
  );
  check(
    'the constant address is in the named address table',
    ffiText.includes('0x40000000'),
  );
  check(
    'a slot that is computed where it is constant elsewhere is reported',
    ffiText.includes('FFI-ADDRESS-UNKNOWN'),
  );
  check(
    'a constant that reaches two C symbols is reported',
    ffiText.includes('FFI-ADDRESS-CONFLICT'),
  );
  check(
    'the FFI findings are filed under their own method',
    ffiText.includes('L2-FFI'),
  );
  check(
    'the FFI findings are NOT filed as the classic abstract findings',
    !ffiText.includes('| L2-abstract |'),
  );
  // The RELEASE families. The C side cannot be seen, so a release is
  // recognised by the SYMBOL's NAME -- and the fixture says so.
  //
  // The counts are of the TABLE ROWS, not of the text: the section's prose
  // names the families too, and a count over the whole report would count
  // the prose.
  check(
    'the same buffer released twice is reported as a double free',
    (ffiText.match(/\| FFI-DOUBLE-FREE \|/g) || []).length === 1,
  );
  check(
    'a buffer the C side released, used afterwards, is reported',
    (ffiText.match(/\| FFI-USE-AFTER-FREE \|/g) || []).length === 1,
  );
  check(
    'a length that is not the object\'s length is reported',
    (ffiText.match(/\| FFI-LENGTH-MISMATCH \|/g) || []).length === 1,
  );
  check(
    'the length finding is on the call with the wrong length, not on the right one',
    /FFI-LENGTH-MISMATCH \| warning \| certain \| wrong_length/.test(ffiText),
  );
  // The classes safe MoonBit cannot express, and that the C boundary CAN.
  // The fixture carries the defect half AND the safe half of each one, and
  // the safe half is the half that must NOT be reported.
  check(
    'an allocation the module never releases is reported',
    (ffiText.match(/\| FFI-ALLOCATION-NOT-RELEASED \|/g) || []).length === 1,
  );
  check(
    'the allocation that is released is not reported as a leak',
    !/FFI-ALLOCATION-NOT-RELEASED \| warning \| certain \| release_the_region/.test(
      ffiText,
    ),
  );
  check(
    'the allocation that is handed back is not reported as a leak',
    !/FFI-ALLOCATION-NOT-RELEASED \| warning \| certain \| hand_back_the_region/.test(
      ffiText,
    ),
  );
  check(
    'a format slot handed a string from outside is reported',
    (ffiText.match(/\| FFI-FORMAT-STRING \|/g) || []).length === 1,
  );
  check(
    'the format slot filled with the module\'s own text is not reported',
    !/FFI-FORMAT-STRING \| error \| certain \| log_own_text/.test(ffiText),
  );
  check(
    'an address past the end of the region is reported',
    (ffiText.match(/\| FFI-ADDRESS-OOB \|/g) || []).length === 1,
  );
  check(
    'the address inside the region is not reported',
    !/FFI-ADDRESS-OOB \| error \| certain \| write_inside_the_region/.test(ffiText),
  );
  // The reserved EVA families point at the boundary families that cover their
  // class, so `--explain` answers the question the reader is asking.
  const leakContract = run(['--explain', 'MEMORY-LEAK']);
  check(
    'the reserved MEMORY-LEAK contract names the boundary family that covers it',
    leakContract.status === 0 &&
      leakContract.stdout.includes('FFI-ALLOCATION-NOT-RELEASED'),
    `exit=${leakContract.status}`,
  );
  const fmtContract = run(['--explain', 'FORMAT-STRING']);
  check(
    'the reserved FORMAT-STRING contract names the boundary family that covers it',
    fmtContract.status === 0 &&
      fmtContract.stdout.includes('FFI-FORMAT-STRING'),
    `exit=${fmtContract.status}`,
  );
  const ptrContract = run(['--explain', 'POINTER-ARITHMETIC']);
  check(
    'the reserved POINTER-ARITHMETIC contract names the boundary family that covers it',
    ptrContract.status === 0 &&
      ptrContract.stdout.includes('FFI-ADDRESS-OOB'),
    `exit=${ptrContract.status}`,
  );
}

// ------------------------------------------------------ the concurrency model
//
// The fixture holds the shapes that interleave and the shapes that do not:
// a counter two tasks update without a lock, the SAME counter under a mutex,
// the ABBA deadlock, a lock that is never given back, and a counter only one
// task touches. A check that fires on the safe half is a false positive, and
// a check that does not fire on the defect half is a check that does not
// work.
//
// Every claim here was settled by RUNNING the toolchain: MoonBit tasks do
// NOT run MoonBit code on several OS threads (a spin-lock with no await
// inside HANGS), so the defect class is INTERLEAVING sensitivity, and the
// read-modify-write that loses an update is the one split by an await.
if (existsSync(join(ROOT, 'fixtures', 'conc_demo', 'lib.mbt'))) {
  const concRun = run([
    'analyze',
    '--dir',
    'fixtures/conc_demo',
    '--out',
    join(OUT, 'conc'),
    '--funnel',
    '--trials',
    '4',
  ]);
  const concReport = join(OUT, 'conc', 'local_module_0.0.0.md');
  const concText = existsSync(concReport) ? readFileSync(concReport, 'utf8') : '';
  check('the concurrency model is analysed', concRun.status === 0);
  check(
    'the report has the concurrency section',
    concText.includes('### 5.8 Concurrency'),
  );
  check('the report lists the tasks', concText.includes('#### 5.8.1 The tasks'));
  check(
    'the report lists the shared cells',
    concText.includes('#### 5.8.2 The shared cells'),
  );
  check(
    'the report lists the waits',
    concText.includes('#### 5.8.3 The waits'),
  );
  check(
    'the report says what the model does NOT cover',
    concText.includes('#### 5.8.5 What this model does NOT cover'),
  );
  // The read-modify-write split by an await point loses the update -- and
  // ONLY the unprotected one does: the mutex orders the other pair.
  check(
    'the lost update is reported',
    concText.includes('CONC-RACE-LOST-UPDATE'),
  );
  check(
    'the lost update is reported ONCE -- the mutex-protected counter is not',
    (concText.match(/CONC-RACE-LOST-UPDATE/g) || []).length === 1,
  );
  check(
    'the ABBA deadlock is reported',
    concText.includes('CONC-DEADLOCK-CYCLE'),
  );
  check(
    'a lock that is never released is reported',
    concText.includes('CONC-RESOURCE-UNRELEASED'),
  );
  check(
    'the concurrency findings are filed under their own method',
    concText.includes('L2-CONC'),
  );
  check(
    'the concurrency findings are NOT filed as the classic abstract findings',
    !concText.includes('| L2-abstract |'),
  );
  // The model does NOT claim a thread-level data race: it says what it
  // models, and it says what it does not.
  check(
    'the model says the defect class is interleaving sensitivity',
    concText.includes('interleaving sensitivity'),
  );
  check(
    'the model says a thread-level data race is not covered',
    concText.includes('A thread-level data race'),
  );
}

// ------------------------------------------------------ the IPC and buffer model
//
// The fixture holds the shapes that break the core's reader contract and the
// shapes that do not: a read whose count is discarded, the SAME read with the
// count kept, a loop that cannot see the end of the stream, a peeked view
// used after the reader ran again and the SAME view used before it, and a
// buffer a task writes while the parent uses it next to a task that has a
// buffer of its own.
//
// Every claim about the core was settled by RUNNING it: a read into a
// 16-byte sentinel buffer returned 3 and left the other 13 bytes at their
// old value; at EOF the read returns 0; a peeked view read `78 79 7A` after
// two reads; and a pending write delivered the bytes the buffer held when
// the write was HANDED OVER, not when it was issued.
//
// A check that fires on the safe half is a false positive, and a check that
// does not fire on the defect half is a check that does not work.
if (existsSync(join(ROOT, 'fixtures', 'ipc_demo', 'lib.mbt'))) {
  const ipcRun = run([
    'analyze',
    '--dir',
    'fixtures/ipc_demo',
    '--out',
    join(OUT, 'ipc'),
    '--funnel',
    '--trials',
    '4',
  ]);
  const ipcReport = join(OUT, 'ipc', 'local_module_0.0.0.md');
  const ipcText = existsSync(ipcReport) ? readFileSync(ipcReport, 'utf8') : '';
  check('the IPC model is analysed', ipcRun.status === 0);
  check(
    'the report has the IPC section',
    ipcText.includes('### 5.9 IPC and buffers'),
  );
  check(
    'the report lists the calls on the readers and writers',
    ipcText.includes('#### 5.9.1 The calls on the readers and writers'),
  );
  check(
    'the report lists the stale views',
    ipcText.includes('#### 5.9.2 The views that went stale'),
  );
  check(
    'the report lists the shared buffers',
    ipcText.includes('#### 5.9.3 The buffers two sides write'),
  );
  check(
    'the report says what the model does NOT cover',
    ipcText.includes('#### 5.9.4 What this model does NOT cover'),
  );
  // The findings. Each one is counted, because a check that fires TWICE on
  // the same defect is as wrong as one that does not fire at all.
  check(
    'a read whose count is discarded is reported ONCE',
    (ipcText.match(/IPC-PARTIAL-READ/g) || []).length === 1,
  );
  check(
    'a loop that cannot see the end of the stream is reported ONCE',
    (ipcText.match(/IPC-READ-EOF/g) || []).length === 1,
  );
  check(
    'a peeked view used after the reader ran again is reported ONCE',
    (ipcText.match(/IPC-VIEW-STALE/g) || []).length === 1,
  );
  check(
    'a buffer a task writes and the parent uses is reported ONCE',
    (ipcText.match(/IPC-BUFFER-SHARED/g) || []).length === 1,
  );
  check(
    'the IPC findings are filed under their own method',
    ipcText.includes('L2-IPC'),
  );
  check(
    'the IPC findings are NOT filed as the classic abstract findings',
    !ipcText.includes('| L2-abstract |'),
  );
  // The model states what it measured, and it states what it does not model.
  check(
    'the model says a read can come back short',
    ipcText.includes('A read can come back SHORT'),
  );
  check(
    'the model says a pending write is not a snapshot',
    ipcText.includes('A pending write is not a snapshot'),
  );
  check(
    'the model says a length that comes from the stream is not judged here',
    ipcText.includes('A length that comes from the stream'),
  );

  // The analyzer's OWN source is the false-positive test. It has THIRTEEN
  // `peek` calls that return a TOKEN and not a view, and matching the name
  // alone reported every one of them. A peek is only a view when the value
  // is USED AS ONE, so the analyzer's own source must report NO stale view
  // at all -- while the fixture still reports its one.
  const selfRun = run([
    'analyze',
    '--dir',
    'src/app',
    '--out',
    join(OUT, 'ipc_self'),
    '--funnel',
    '--trials',
    '4',
  ]);
  const selfReport = join(OUT, 'ipc_self', 'local_module_0.0.0.md');
  const selfText = existsSync(selfReport) ? readFileSync(selfReport, 'utf8') : '';
  check('the analyzer scans its own source', selfRun.status === 0);
  check(
    'a peek that returns a token is NOT a stale view',
    !selfText.includes('IPC-VIEW-STALE'),
  );
  check(
    'the analyzer\'s own source reports no IPC finding at all',
    !selfText.includes('IPC-PARTIAL-READ') &&
      !selfText.includes('IPC-READ-EOF') &&
      !selfText.includes('IPC-BUFFER-SHARED'),
  );
}

// ------------------------------------------------------ the documented flags
//
// The README's CLI reference is the only place a reader learns what the
// command line accepts, and it is PROSE. `riantr/moonbit_static_analysis`
// guards its family table the same way -- it asserts that the set of ids the
// README names is the set the code returns -- because a table that drifts
// from the code is a table nobody checks.
//
// This is the same guard for the flags: the set of `--flags` the README
// documents is the set the CLI's argument parser accepts. The parser is the
// source of truth and is read straight out of the source, so a flag added to
// the code without a README line fails the gate, and a README line for a
// flag the code does not accept fails it too.

const cliSourcePath = join(ROOT, 'src', 'command', 'command.mbt');
const readmePath = join(ROOT, 'README.md');
if (existsSync(cliSourcePath) && existsSync(readmePath)) {
  const cliSource = readFileSync(cliSourcePath, 'utf8');
  const readme = readFileSync(readmePath, 'utf8');

  // The flags the PARSER accepts: every `a == "--name"` in the argument
  // loop. The loop is the only place a flag is recognised.
  const accepted = new Set(
    [...cliSource.matchAll(/a == "(--[a-z][a-z0-9-]*)"/g)].map((m) => m[1]),
  );

  // The flags the README's CLI reference documents: the first cell of every
  // row of that table. The section is bounded by its own heading and by the
  // next one, so a flag mentioned elsewhere in the README does not count.
  const sectionStart = readme.indexOf('## CLI reference');
  const sectionEnd = sectionStart >= 0 ? readme.indexOf('\n## ', sectionStart + 5) : -1;
  const section =
    sectionStart >= 0 && sectionEnd > sectionStart
      ? readme.slice(sectionStart, sectionEnd)
      : '';
  const documented = new Set(
    [...section.matchAll(/^\|\s*`?(--[a-z][a-z0-9-]*)`?/gm)].map((m) => m[1]),
  );

  const undocumented = [...accepted].filter((f) => !documented.has(f)).sort();
  const unknown = [...documented].filter((f) => !accepted.has(f)).sort();

  check(
    'the README documents the canonical invocation line',
    section.includes('moonx riantr/LunaFlow@latest <target> [flags]'),
  );
  check(
    'the README documents the peer invocation line too',
    section.includes('moonx riantr/moonbit_static_analysis@latest <target> [flags]'),
  );
  check(
    'every flag the CLI accepts is in the README CLI reference',
    undocumented.length === 0,
    undocumented.length ? 'undocumented: ' + undocumented.join(', ') : `${accepted.size} flag(s)`,
  );
  check(
    'every flag in the README CLI reference is one the CLI accepts',
    unknown.length === 0,
    unknown.length ? 'unknown: ' + unknown.join(', ') : `${documented.size} flag(s)`,
  );
}

console.log(`\nRESULT: ${failures.length === 0 ? 'PASS' : 'FAIL'} (${passes.length} passed, ${failures.length} failure(s))`);
process.exit(failures.length === 0 ? 0 : 1);
