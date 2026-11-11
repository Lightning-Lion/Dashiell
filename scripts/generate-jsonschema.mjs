#!/usr/bin/env node
// Orchestration only. All schema parsing, descriptors and ArkTS emission live in Rust.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
for (const entry of JSON.parse(fs.readFileSync(path.join(root, 'schemas/generation.json'), 'utf8'))) {
  execFileSync(process.env.CARGO || 'cargo', ['run', '--locked', '--manifest-path', 'tools/json-gen/Cargo.toml', '--', '--schema', entry.schema, '--out', entry.out, '--runtime-import', entry.runtimeImport, ...(process.argv.includes('--check') ? ['--check'] : [])], { cwd: root, stdio: 'inherit' });
}
