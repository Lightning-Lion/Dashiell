#!/usr/bin/env node
// Lexical regression guard for direct JSON.parse calls (not a full alias/taint analysis).
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const base = path.join(root, 'entry/src/main/ets');
const runtime = 'entry/src/main/ets/common/jsonschema/JsonDecode.ets';
const files = [];
function walk(dir) {
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, item.name);
    if (item.isDirectory()) walk(file);
    else if (item.name.endsWith('.ets')) files.push(file);
  }
}
walk(base);
const unexpected = [];
let runtimeCalls = 0;
for (const file of files) {
  const relative = path.relative(root, file);
  const source = fs.readFileSync(file, 'utf8');
  const lines = source.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) continue;
    if (/\bJSON\s*(?:\.\s*parse|\[\s*['"]parse['"]\s*\])\s*\(/.test(line)) {
      if (relative === runtime) runtimeCalls++;
      else unexpected.push({ file: relative, line: i + 1, source: line.trim() });
    }
  }
}
fs.mkdirSync(path.join(root, 'docs/jsonschema'), { recursive: true });
fs.writeFileSync(path.join(root, 'docs/jsonschema/remaining-json-sites.json'), JSON.stringify(unexpected, null, 2) + '\n');
if (unexpected.length !== 0 || runtimeCalls !== 1) {
  console.error(JSON.stringify({ unexpected, runtimeCalls }, null, 2));
  process.exitCode = 1;
} else {
  console.log('PASS: direct production JSON.parse is confined to the one shared runtime boundary.');
}
