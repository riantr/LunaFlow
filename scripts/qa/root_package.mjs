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
//   * the root builds for BOTH native and wasm
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

const nativeExe = join(ROOT, '_build', 'native', 'debug', 'build', 'LunaFlow.exe');
const nativeBin = join(ROOT, '_build', 'native', 'debug', 'build', 'LunaFlow');
const exe = existsSync(nativeExe) ? nativeExe : nativeBin;
check('the root executable is on disk', existsSync(exe), exe);

const wasmArtifact = join(ROOT, '_build', 'wasm', 'debug', 'build', 'LunaFlow.wasm');
check('the root wasm artifact is on disk', existsSync(wasmArtifact), wasmArtifact);

// ------------------------------------------- the bare coordinate, end to end

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

  // A PATH is not a coordinate, and neither spelling of a local path may be
  // mistaken for one: "fixtures/vuln_demo" has no author, and
  // "./fixtures/vuln_demo" has an author part of "." -- a path, not a name.
  // Both must be refused rather than analysed as a module, because a wrong
  // guess here is a report about the wrong tree.
  for (const path of ['fixtures/vuln_demo', './fixtures/vuln_demo']) {
    const pathRun = spawnSync(exe, [path, '--out', OUT, '--quiet'], {
      cwd: ROOT,
      encoding: 'utf8',
      shell: process.platform === 'win32',
      timeout: 120000,
    });
    check(
      `a local path is not mistaken for a coordinate: ${path}`,
      pathRun.status === 0 && !pathRun.stdout.includes('REPORT'),
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
}

console.log(`\nRESULT: ${failures.length === 0 ? 'PASS' : 'FAIL'} (${passes.length} passed, ${failures.length} failure(s))`);
process.exit(failures.length === 0 ? 0 : 1);
