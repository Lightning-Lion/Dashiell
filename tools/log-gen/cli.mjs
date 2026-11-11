#!/usr/bin/env node
// Log event generator (shared verbatim with the watch client repo).
//
//   node tools/log-gen/cli.mjs --write   # scan call sites, generate ArkTS
//   node tools/log-gen/cli.mjs --check   # fail if generated file is stale
//
// Inputs:
//   logging/events.json                  bilingual event catalog
//   entry/src/main/ets/**/*.ets          LogEvents.<name>( call sites
// Output:
//   entry/src/main/ets/utils/log/LogEvents.generated.ets

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { parseCatalog } from './schema.mjs';
import { maskSource, scanCalls } from './scanner.mjs';
import { detectScope } from './scope.mjs';
import { render } from './emit.mjs';

const ROOT = path.resolve(import.meta.dirname, '../..');
const DEFAULTS = {
  events: path.join(ROOT, 'logging/events.json'),
  src: path.join(ROOT, 'entry/src/main/ets'),
  out: path.join(ROOT, 'entry/src/main/ets/utils/log/LogEvents.generated.ets'),
};

export function generate(options = {}) {
  const eventsPath = options.events ?? DEFAULTS.events;
  const srcPath = options.src ?? DEFAULTS.src;
  const outPath = options.out ?? DEFAULTS.out;
  const appName = options.app ?? path.basename(ROOT);
  const catalogText = fs.readFileSync(eventsPath, 'utf8');
  const catalog = parseCatalog(catalogText);
  const eventNames = catalog.events.map((event) => event.name);
  const files = listEtsFiles(srcPath, outPath);
  const calls = [];
  const unknown = [];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const masked = maskSource(text);
    const result = scanCalls(masked, relative(file), eventNames);
    for (const call of result.calls) {
      const scope = detectScope(masked, call.offset);
      calls.push({ ...call, ...scope });
    }
    unknown.push(...result.unknown);
  }
  if (unknown.length > 0) {
    throw new Error(`unknown LogEvents call site(s):\n${unknown.map(formatSite).join('\n')}`);
  }
  const sites = {};
  const errors = [];
  for (const event of catalog.events) {
    const matches = calls.filter((call) => call.event === event.name);
    if (matches.length === 0) {
      errors.push(`${event.name}: no LogEvents.${event.name}(...) call site found`);
      continue;
    }
    if (matches.length > 1) {
      errors.push(
        `${event.name}: expected exactly one call site, found ${matches.length}:\n` +
        matches.map((call) => `  ${formatSite(call)}`).join('\n') +
        '\n  define a separate event per call site',
      );
      continue;
    }
    const call = matches[0];
    sites[event.name] = {
      file: call.file,
      line: call.line,
      column: call.column,
      className: event.class !== '' ? event.class : call.className,
      methodName: event.method !== '' ? event.method : call.methodName,
    };
  }
  if (errors.length > 0) {
    throw new Error(errors.join('\n'));
  }
  const output = render(catalog, sites, catalogText, appName);
  return { catalog, sites, calls, output, outPath };
}

export function writeOutput(result) {
  try {
    if (fs.readFileSync(result.outPath, 'utf8') === result.output) {
      return false;
    }
  } catch (e) {
    // missing file: write it
  }
  const dir = path.dirname(result.outPath);
  fs.mkdirSync(dir, { recursive: true });
  const temporary = `${result.outPath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, result.output, 'utf8');
  fs.renameSync(temporary, result.outPath);
  return true;
}

function listEtsFiles(dir, outPath) {
  const result = [];
  const walk = (current) => {
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name === 'build' || entry.name === 'oh_modules' || entry.name === 'node_modules' ||
        entry.name === '.git' || entry.name === '.hvigor') {
        continue;
      }
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name.endsWith('.ets') &&
        !entry.name.endsWith('.generated.ets') && path.resolve(full) !== path.resolve(outPath)) {
        result.push(full);
      }
    }
  };
  walk(dir);
  result.sort();
  return result;
}

function relative(file) {
  return path.relative(ROOT, file).split(path.sep).join('/');
}

function formatSite(site) {
  return `${site.file}:${site.line}:${site.column} (${site.event})`;
}

function usage() {
  console.log('log-gen');
  console.log('  node tools/log-gen/cli.mjs --write');
  console.log('  node tools/log-gen/cli.mjs --check');
  console.log('Options: --events PATH --src DIR --out FILE --app NAME');
}

export function main(argv = process.argv.slice(2)) {
  let check = false;
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--check') {
      check = true;
    } else if (arg === '--write') {
      check = false;
    } else if (arg === '--events' || arg === '--src' || arg === '--out') {
      const value = argv[++i];
      if (value === undefined) {
        throw new Error(`${arg} requires a path`);
      }
      options[arg.substring(2)] = path.resolve(ROOT, value);
    } else if (arg === '--app') {
      const value = argv[++i];
      if (value === undefined) {
        throw new Error('--app requires a name');
      }
      options.app = value;
    } else if (arg === '--help' || arg === '-h') {
      usage();
      return 0;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  const result = generate(options);
  if (check) {
    let existing = '';
    try {
      existing = fs.readFileSync(result.outPath, 'utf8');
    } catch (e) {
      throw new Error(`generated file missing: ${relative(result.outPath)}`);
    }
    if (existing !== result.output) {
      throw new Error(
        `stale generated file: ${relative(result.outPath)}\n` +
        'run: node tools/log-gen/cli.mjs --write',
      );
    }
    console.log(`log-gen: verified ${result.catalog.events.length} events -> ${relative(result.outPath)}`);
    return 0;
  }
  const changed = writeOutput(result);
  console.log(`log-gen: ${changed ? 'generated' : 'up-to-date'} ` +
    `${result.catalog.events.length} events, ${result.calls.length} call sites -> ` +
    relative(result.outPath));
  return 0;
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (e) {
    console.error(`log-gen: ${e.message}`);
    process.exitCode = 1;
  }
}
