#!/usr/bin/env node
// Place the LunaFlow logo assets at the module root, following the sibling
// modules' convention: `LunaFlow.png` is the image the README shows (relative
// path, so the registry rewrites it to the asset URL) and `LunaFlow_Logo.png`
// is the 1024x1024 full-resolution file.
//
// The source is the 1024x1024 master; the README-sized variant is produced by
// an optional resampler when one is available on the machine.
//
// Usage: node scripts/qa/place_logo.mjs <source.png>
import { copyFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const source = process.argv[2];
if (!source || !existsSync(source)) {
  console.error(`missing source image: ${source}`);
  process.exit(2);
}

const logo = join(root, 'LunaFlow_Logo.png');
const shown = join(root, 'LunaFlow.png');
copyFileSync(source, logo);
console.log(`LunaFlow_Logo.png  ${statSync(logo).size} B  (full resolution)`);

// Try a resampler for the README-sized variant. None is required: if the
// machine has no resampler, the 1024x1024 master is used for both.
let resized = false;
for (const [cmd, args] of [
  ['magick', [source, '-resize', '438x438', shown]],
  ['convert', [source, '-resize', '438x438', shown]],
  ['ffmpeg', ['-y', '-i', source, '-vf', 'scale=438:438', shown]],
]) {
  const probe = spawnSync(cmd, ['-version'], { encoding: 'utf8' });
  if (probe.error || probe.status !== 0) continue;
  const r = spawnSync(cmd, args, { encoding: 'utf8' });
  if (r.status === 0 && existsSync(shown)) {
    resized = true;
    console.log(`LunaFlow.png       ${statSync(shown).size} B  (438x438, via ${cmd})`);
    break;
  }
}
if (!resized) {
  copyFileSync(source, shown);
  console.log(`LunaFlow.png       ${statSync(shown).size} B  (1024x1024 master, no resampler found)`);
}
