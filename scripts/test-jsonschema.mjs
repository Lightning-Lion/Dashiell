#!/usr/bin/env node
import { expansionFixtures } from './jsonschema-expansion-fixtures.mjs';
// Execute the actual ArkTS decoder/test sources on Node after TS erasure.
// This complements, NEVER substitutes for, devecocli SDK compilation and Hypium device tests.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
const root = path.resolve(import.meta.dirname, '..');
const update = process.argv.includes('--update-fixtures');
execFileSync(process.execPath, [path.join(root, 'scripts/check-jsonschema-fresh.mjs')], { cwd: root, stdio: 'inherit' });
execFileSync(process.execPath, [path.join(root, 'scripts/audit-json-boundaries.mjs')], { cwd: root, stdio: 'inherit' });
execFileSync(process.execPath, [path.join(root, 'scripts/generate-jsonschema.mjs'), '--check'], { cwd: root, stdio: 'inherit' });
const expansionCount = expansionFixtures(root, update);
const require = createRequire(import.meta.url);
const ts = require(process.env.TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dashiell-jsonschema-'));
const sources = [
  'entry/src/main/ets/common/jsonschema/JsonDecode.ets',
  'entry/src/main/ets/common/douyin/DouyinResponseDecoder.ets',
  'entry/src/main/ets/common/douyin/DouyinFeedMapping.ets',
  'entry/src/main/ets/common/bili/BiliResponseDecoder.ets',
  'entry/src/main/ets/common/bili/BiliFavoriteMapping.ets',
  'entry/src/main/ets/common/bili/BiliBusinessError.ets',
  'entry/src/main/ets/common/bili/BiliMediaDecoder.ets',
  'entry/src/main/ets/common/bili/BiliMediaMapping.ets',
  'entry/src/main/ets/common/bili/BiliMediaModels.ets',
  'entry/src/main/ets/common/bili/BiliPlaybackQueue.ets',
  'entry/src/main/ets/common/local/LocalDataDecoder.ets',
  'entry/src/main/ets/common/BiliHotSearch.ets',
  'entry/src/main/ets/common/BiliFavoriteModels.ets',
  'entry/src/main/ets/common/WebViewExtension.ets',
  'entry/src/main/ets/common/TypeValid.ets',
  'entry/src/test/JsonSchemaExpansionFixtures.generated.ets',
  'entry/src/test/JsonSchemaExpansion.test.ets',
];
for (const entry of JSON.parse(fs.readFileSync(path.join(root, 'schemas/generation.json'), 'utf8'))) {
  for (const file of fs.readdirSync(path.join(root, entry.out)).filter(f => f.endsWith('.ets'))) {
    sources.push(path.join(entry.out, file));
  }
}
try {
  let count = 0;
  const failures = [];
  const shim = {
    describe: (_name, body) => body(),
    it: (name, _flags, body) => { try { body(); count++; } catch (e) { failures.push(`${name}: ${e.stack}`); } },
    expect: actual => ({
      assertEqual: expected => assert.strictEqual(actual, expected),
      assertTrue: () => assert.strictEqual(actual, true),
      assertFalse: () => assert.strictEqual(actual, false),
    }),
  };
  const shimDir = path.join(tmp, 'node_modules/@ohos/hypium');
  fs.mkdirSync(shimDir, { recursive: true });
  fs.writeFileSync(path.join(shimDir, 'index.js'), 'module.exports = globalThis.__jsonSchemaHypium;');
  globalThis.__jsonSchemaHypium = shim;
  // Host harness only exercises decoders. LogEvents pulls Logger -> @kit.*, which
  // Node cannot resolve; stub every event as a no-op. Real logging is covered by
  // the Hvigor build and on-device log inspection (see docs/logging.md).
  const logDir = path.join(tmp, 'entry/src/main/ets/utils/log');
  fs.mkdirSync(logDir, { recursive: true });
  fs.writeFileSync(path.join(logDir, 'LogEvents.generated.js'),
    'const LogEvents = new Proxy({}, { get: () => () => {} });\nmodule.exports = { LogEvents };\n');
  for (const file of sources) {
    const output = path.join(tmp, file.replace(/\.ets$/, '.js'));
    fs.mkdirSync(path.dirname(output), { recursive: true });
    const transpiled = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true,
    });
    assert.equal(transpiled.diagnostics?.length ?? 0, 0, `Transpilation diagnostic: ${file}`);
    fs.writeFileSync(output, transpiled.outputText);
  }
  require(path.join(tmp, 'entry/src/test/JsonSchemaExpansion.test.js')).default();
  assert.equal(failures.length, 0, failures.join('\n\n'));
  const report = { runner: 'Node: actual ArkTS sources with type erasure', fixtureCount: expansionCount, tests: count, failed: failures.length };
  fs.mkdirSync(path.join(root, 'docs/jsonschema'), { recursive: true });
  fs.writeFileSync(path.join(root, 'docs/jsonschema/host-results.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`PASS: ${count} expansion tests (${expansionCount} fixtures); no decoder logic reimplemented in the host harness.`);
} finally {
  delete globalThis.__jsonSchemaHypium;
  fs.rmSync(tmp, { recursive: true, force: true });
}
