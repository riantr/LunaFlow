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
  // The NEGATIVE half of the fixture must not be reported. Each of these is
  // the ordinary shape that sits next to the defect. The check is scoped to
  // the FINDINGS sections: the same names appear in the range tables, which
  // is where a value's interval is printed and not where a defect is.
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
    const start = text.indexOf('### 5.2 L2 abstract findings');
    if (start < 0) return '';
    const end = text.indexOf('\n## 6.', start);
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

console.log(`\nRESULT: ${failures.length === 0 ? 'PASS' : 'FAIL'} (${passes.length} passed, ${failures.length} failure(s))`);
process.exit(failures.length === 0 ? 0 : 1);
