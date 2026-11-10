#!/usr/bin/env node
// Verify the PUBLISHED module from a clean consumer.
//
// The check that matters for a release is not "the publish step succeeded"
// but "a consumer can install the published version and call it". This
// script does that in a scratch directory: `moon add` resolves the registry
// coordinate, and the consumer calls the published library API.
//
// It is NOT part of the CI gate, and it cannot be: the gate checks the
// commit, and this checks what the registry serves for it. A release can
// have a green gate and still publish something a consumer cannot use, and
// the only thing that catches that is installing it.
//
// The manifest is written with node because both PowerShell's
// `Set-Content -Encoding UTF8` and the editor's `write` tool put a byte
// order mark in front of the file on this machine, and the MoonBit manifest
// lexer rejects it with "Lexing error at 0..3".
//
// Usage: node scripts/qa/verify_published.mjs [version]

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const version = process.argv[2];
if (!version) {
  console.error('usage: node scripts/qa/verify_published.mjs <version>');
  process.exit(2);
}

const root = process.cwd();
const dir = resolve(root, '_build', 'qa', 'published_check');

rmSync(dir, { recursive: true, force: true });
mkdirSync(join(dir, 'src'), { recursive: true });

writeFileSync(
  join(dir, 'moon.mod'),
  'name = "test/lunaflow_published_check"\n\nversion = "0.0.0"\n',
  'utf8',
);
writeFileSync(
  join(dir, 'src', 'moon.pkg'),
  'pkgtype(kind: "executable")\n\nimport {\n  "riantr/LunaFlow/src/app" @lf,\n}\n',
  'utf8',
);
writeFileSync(
  join(dir, 'src', 'main.mbt'),
  `///|
/// The library API of the PUBLISHED module, called from a consumer that only
/// knows \`moon add riantr/LunaFlow\`.
fn main {
  let f = @lf.parse_file(
    "t.mbt",
    "///|\\npub fn add1(x : Int32) -> Int32 {\\n  x + 1\\n}\\n",
  )
  println("functions\\t" + f.funcs.length().to_string())
  println("statements\\t" + f.parsed_stmts.to_string())
}
`,
  'utf8',
);

let failures = 0;
function check(name, ok, detail = '') {
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

// The coordinate is PINNED on purpose. A bare `moon add riantr/LunaFlow`
// resolves to the newest published version, so asking for an older release
// with it would silently test the newest one instead -- which is how this
// script managed to report "0.1.1 is not pinned" while testing 0.1.2.
const add = spawnSync('moon', ['add', `riantr/LunaFlow@${version}`], {
  cwd: dir,
  encoding: 'utf8',
  timeout: 300000,
  maxBuffer: 16 * 1024 * 1024,
});
check('moon add succeeds', add.status === 0, `exit=${add.status}`);

const manifest = readFileSync(join(dir, 'moon.mod'), 'utf8');
check(
  `the published version ${version} is pinned`,
  manifest.includes(`"riantr/LunaFlow@${version}"`),
  manifest.match(/"riantr\/LunaFlow@[\d.]+"/)?.[0] ?? 'no import',
);

const run = spawnSync('moon', ['run', 'src', '--target', 'native'], {
  cwd: dir,
  encoding: 'utf8',
  timeout: 300000,
  maxBuffer: 16 * 1024 * 1024,
});
check('the consumer builds and runs', run.status === 0, `exit=${run.status}`);
check(
  'the published library API answers',
  (run.stdout ?? '').includes('functions\t1'),
  (run.stdout ?? '').trim().split('\n').slice(-2).join(' | '),
);

console.log(`\nRESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
