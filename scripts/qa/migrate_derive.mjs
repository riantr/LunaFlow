#!/usr/bin/env node
// One-shot migration: trailing `} derive(Eq)` -> `#derive(Eq)` before the type
// plus an explicit `pub extend T with Eq::{not_equal, equal}` declaration.
//
// Why: MoonBit deprecated the trailing derive syntax (warning 0027) and the
// implicit promotion of derived Eq methods to regular methods (warning 0079).
// Under `moon check --deny-warn` those become build failures.
//
// Usage: node scripts/qa/migrate_derive.mjs [--dry-run]
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';

const root = process.cwd();
const files = ['src/app/model.mbt', 'src/app/contract.mbt', 'src/app/lexer.mbt'];
const dryRun = process.argv.includes('--dry-run');

const DECL = /^(pub\(all\)\s+|pub\s+|priv\s+)?(enum|struct)\s+([A-Za-z_][A-Za-z0-9_]*)/;

function migrate(text, file) {
  const lines = text.split(/\r?\n/);
  const out = [];
  const changes = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!/^\}\s*derive\(Eq\)\s*$/.test(line)) {
      out.push(line);
      continue;
    }
    // find the owning declaration by walking back to the nearest header
    let declIdx = -1;
    let typeName = '';
    for (let j = out.length - 1; j >= 0; j -= 1) {
      const m = DECL.exec(out[j]);
      if (m) {
        declIdx = j;
        typeName = m[3];
        break;
      }
      if (/^\}\s*$/.test(out[j]) && j !== out.length - 1) break;
    }
    if (declIdx < 0 || typeName === '') {
      throw new Error(`${file}: could not find declaration for derive(Eq) at line ${i + 1}`);
    }
    out[declIdx] = '#derive(Eq)\n' + out[declIdx];
    out.push('}');
    out.push('');
    out.push('///|');
    out.push(`pub extend ${typeName} with Eq::{not_equal, equal}`);
    changes.push(`${typeName} @ line ${i + 1}`);
  }
  return { text: out.join('\n'), changes };
}

let total = 0;
for (const file of files) {
  const path = join(root, file);
  const original = readFileSync(path, 'utf8');
  const { text, changes } = migrate(original, file);
  if (changes.length === 0) {
    console.log(`SKIP ${file} (no trailing derive(Eq))`);
    continue;
  }
  if (text === original) {
    console.log(`NOOP ${file}`);
    continue;
  }
  console.log(`${dryRun ? 'DRY ' : 'WROTE'} ${file}: ${changes.join(', ')}`);
  total += changes.length;
  if (!dryRun) {
    const backup = join(root, '_build', 'qa', 'backup', file.replace(/[\\/]/g, '_'));
    mkdirSync(dirname(backup), { recursive: true });
    if (!existsSync(backup)) copyFileSync(path, backup);
    writeFileSync(path, text, 'utf8');
  }
}
console.log(`total migrated: ${total}`);
