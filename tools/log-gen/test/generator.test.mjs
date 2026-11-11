import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { maskSource, scanCalls, positionAt } from '../scanner.mjs';
import { detectScope } from '../scope.mjs';
import { validateCatalog } from '../schema.mjs';
import { render } from '../emit.mjs';
import { generate } from '../cli.mjs';

test('maskSource keeps offsets and newlines while hiding comments and strings', () => {
  const source = [
    'const a = 1; // LogEvents.commented({})',
    'const b = "LogEvents.string({})";',
    'const c = `LogEvents.template({})`;',
    'const d = /* LogEvents.block({}) */ LogEvents.real({});',
  ].join('\n');
  const masked = maskSource(source);
  assert.equal(masked.length, source.length);
  assert.equal(masked.split('\n').length, source.split('\n').length);
  assert.equal(masked.includes('LogEvents.commented'), false);
  assert.equal(masked.includes('LogEvents.string'), false);
  assert.equal(masked.includes('LogEvents.template'), false);
  assert.equal(masked.includes('LogEvents.block'), false);
  assert.equal(masked.includes('LogEvents.real'), true);
});

test('positionAt is one-based for line and column', () => {
  const text = 'aa\nbbb\nc';
  assert.deepEqual(positionAt(text, 0), { line: 1, column: 1 });
  assert.deepEqual(positionAt(text, 3), { line: 2, column: 1 });
  assert.deepEqual(positionAt(text, 7), { line: 3, column: 1 });
});

test('scanCalls ignores property access and reports unknown events', () => {
  const source = [
    'foo.LogEvents.notMine({});',
    'LogEvents.known({});',
    'LogEvents.missing({});',
  ].join('\n');
  const result = scanCalls(maskSource(source), 'entry/src/main/ets/demo.ets', ['known']);
  assert.equal(result.calls.length, 1);
  assert.equal(result.calls[0].event, 'known');
  assert.equal(result.calls[0].line, 2);
  assert.equal(result.calls[0].column, 1);
  assert.equal(result.unknown.length, 1);
  assert.equal(result.unknown[0].event, 'missing');
});

test('detectScope finds struct/class methods, including multi-line signatures and nested callbacks', () => {
  const source = [
    '@ComponentV2',
    'struct Demo {',
    '  @Local value: number = 0;',
    '',
    '  aboutToAppear(): void {',
    '    if (this.value > 0) {',
    '      LogEvents.a({});',
    '    }',
    '  }',
    '',
    '  private async load(',
    '    id: string,',
    '    cb: (x: number) => void,',
    '  ): Promise<void> {',
    '    await foo(() => {',
    '      LogEvents.b({});',
    '    });',
    '  }',
    '}',
  ].join('\n');
  const masked = maskSource(source);
  const a = masked.indexOf('LogEvents.a');
  const b = masked.indexOf('LogEvents.b');
  assert.deepEqual(detectScope(masked, a), { className: 'Demo', methodName: 'aboutToAppear' });
  assert.deepEqual(detectScope(masked, b), { className: 'Demo', methodName: 'load' });
});

test('schema rejects incomplete or ambiguous catalogs', () => {
  const base = {
    schemaVersion: 1,
    events: [{
      name: 'demo', tag: 'Demo', level: 'INFO', zh: '演示', en: 'demo',
      fields: [{ name: 'value', type: 'number' }],
    }],
  };
  assert.doesNotThrow(() => validateCatalog(structuredClone(base)));
  const noEn = structuredClone(base);
  noEn.events[0].en = '';
  assert.throws(() => validateCatalog(noEn), /en must be a non-empty string/);
  const dup = structuredClone(base);
  dup.events.push(structuredClone(dup.events[0]));
  assert.throws(() => validateCatalog(dup), /duplicated/);
  const badType = structuredClone(base);
  badType.events[0].fields[0].type = 'date';
  assert.throws(() => validateCatalog(badType), /type must be one of/);
  const badField = structuredClone(base);
  badField.events[0].fields[0].name = 'error';
  assert.throws(() => validateCatalog(badField), /reserved/);
});

test('render is deterministic and bakes the exact site', () => {
  const catalog = {
    schemaVersion: 1,
    events: [{
      name: 'demoEvent', tag: 'Demo', level: 'INFO', zh: '演示', en: 'demo',
      error: true, class: '', method: '',
      fields: [{ name: 'value', type: 'number', required: true, zh: '值', en: 'value' }],
    }],
  };
  const sites = {
    demoEvent: {
      file: 'entry/src/main/ets/pages/Demo.ets', line: 12, column: 7,
      className: 'Demo', methodName: 'run',
    },
  };
  const text = render(catalog, sites, '{"schemaVersion":1}');
  assert.equal(text, render(catalog, sites, '{"schemaVersion":1}'));
  assert.match(text, /private static readonly SITE_DEMO_EVENT: LogSite = new LogSite\(/);
  assert.match(text, /"entry\/src\/main\/ets\/pages\/Demo\.ets",\n    12,\n    7,/);
  assert.match(text, /"Demo",\n    "run",/);
  assert.match(text, /L\("演示", "demo"\)/);
  assert.match(text, /static demoEvent\(fields: DemoEventFields, error\?: Object\): void/);
  assert.match(text, /F\("value", fields\.value\)/);
});

test('generate enforces exactly one call site per event', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dashiell-log-gen-'));
  try {
    const events = path.join(dir, 'events.json');
    const src = path.join(dir, 'src');
    fs.mkdirSync(path.join(src, 'pages'), { recursive: true });
    fs.writeFileSync(events, JSON.stringify({
      schemaVersion: 1,
      events: [{
        name: 'demoEvent', tag: 'Demo', level: 'INFO', zh: '演示', en: 'demo',
        fields: [{ name: 'value', type: 'number' }],
      }],
    }));
    const file = path.join(src, 'pages', 'Demo.ets');
    fs.writeFileSync(file, [
      'class Demo {',
      '  run(): void {',
      '    LogEvents.demoEvent({ value: 1 });',
      '  }',
      '}',
    ].join('\n'));
    const good = generate({ events, src, out: path.join(dir, 'out.ets') });
    assert.equal(good.sites.demoEvent.line, 3);
    assert.equal(good.sites.demoEvent.className, 'Demo');
    assert.equal(good.sites.demoEvent.methodName, 'run');

    fs.writeFileSync(file, [
      'class Demo {',
      '  run(): void {',
      '    LogEvents.demoEvent({ value: 1 });',
      '    LogEvents.demoEvent({ value: 2 });',
      '  }',
      '}',
    ].join('\n'));
    assert.throws(() => generate({ events, src, out: path.join(dir, 'out.ets') }),
      /exactly one call site/);

    fs.writeFileSync(file, 'class Demo { run(): void {} }');
    assert.throws(() => generate({ events, src, out: path.join(dir, 'out.ets') }),
      /no LogEvents\.demoEvent/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
