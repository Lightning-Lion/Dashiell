import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const ts = require(process.env.TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
export const projectRoot = path.resolve(import.meta.dirname, '../..');
const etsRoot = path.join(projectRoot, 'entry/src/main/ets');

// Test adapter only: actual production methods run, platform I/O is injectable.
// Does not claim ArkUI/runtime validation; the SDK build and emulator are separate gates.
export function arktsLoader(platforms = {}) {
  const cache = new Map();
  function load(file) {
    const absolute = path.resolve(etsRoot, file);
    if (!absolute.startsWith(etsRoot + path.sep)) throw new Error('Source outside ArkTS root');
    if (cache.has(absolute)) return cache.get(absolute).exports;
    const module = {exports: {}}; cache.set(absolute, module);
    const source = fs.readFileSync(absolute, 'utf8')
      .replace(/@ObservedV2\s*/g, '').replace(/@(?:Trace|Computed|Local)\s*/g, '');
    const {outputText} = ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}});
    const localRequire = name => {
      if (Object.hasOwn(platforms, name)) return platforms[name];
      if (!name.startsWith('.')) throw new Error('Unmocked platform module: ' + name);
      return load(path.relative(etsRoot, path.resolve(path.dirname(absolute), name + '.ets')));
    };
    vm.runInNewContext(outputText, {module, exports: module.exports, require: localRequire,
      console: {info(){},warn(){},debug(){},error(){}}, setTimeout,clearTimeout}, {filename:absolute});
    return module.exports;
  }
  return load;
}
