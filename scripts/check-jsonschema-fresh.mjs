#!/usr/bin/env node
// Fast, Node-only freshness check for Schema -> generated ArkTS.
//
// The Rust generator still owns the full `--check` (schema + generator code).
// This script only compares the schema source SHA-256 with the hash baked into
// each generated file, so a build/CI step can fail in milliseconds without Cargo.
//
//   node scripts/check-jsonschema-fresh.mjs
//
// Exit 1: generated files are missing, stale, or do not carry a Schema SHA-256.
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const manifestPath = path.join(root, 'schemas/generation.json');
const entries = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const problems = [];

function sha256(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

for (const entry of entries) {
  const schemaPath = path.join(root, entry.schema);
  const outDir = path.join(root, entry.out);
  const source = fs.readFileSync(schemaPath, 'utf8');
  const schema = JSON.parse(source);
  const expected = sha256(source);
  const files = [
    `${schema.name}Models.generated.ets`,
    `${schema.name}Decoders.generated.ets`,
  ];
  for (const file of files) {
    const target = path.join(outDir, file);
    if (!fs.existsSync(target)) {
      problems.push(`${path.relative(root, target)}: missing`);
      continue;
    }
    const text = fs.readFileSync(target, 'utf8');
    const match = /^\/\/ Schema SHA-256: ([0-9a-f]{64})$/m.exec(text);
    if (match === null) {
      problems.push(`${path.relative(root, target)}: no Schema SHA-256 header`);
    } else if (match[1] !== expected) {
      problems.push(`${path.relative(root, target)}: stale (${match[1].slice(0, 12)} != ${expected.slice(0, 12)})`);
    }
  }
}

if (problems.length > 0) {
  console.error('check-jsonschema-fresh: FAIL');
  for (const problem of problems) {
    console.error(`- ${problem}`);
  }
  console.error('run: node scripts/generate-jsonschema.mjs');
  process.exitCode = 1;
} else {
  console.log(`check-jsonschema-fresh: PASS (${entries.length} schemas)`);
}
