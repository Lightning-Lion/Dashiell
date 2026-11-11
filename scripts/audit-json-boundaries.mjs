#!/usr/bin/env node
// Lexical regression guard for direct JSON.parse calls (not a full alias/taint analysis).
//
// 匹配只发生在「代码上下文」：字符串字面量与注释里的 JSON.parse 不算生产边界。
// 这一点是必需的——注入 ArkWeb 的浏览器脚本（如 ZhihuHot.ets 的 ZHIHU_EXTRACT_JS）
// 本身就是个多行模板字符串，它在页面里解析 #js-initialData，ArkTS 侧一行解析都没有。
// 已知简化：模板字符串里的 ${...} 插值也按字符串处理，所以插值中写 JSON.parse 会漏检；
// 真要防的是 ArkTS 语句里的裸解析，这条边界没有放松。
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const base = path.join(root, 'entry/src/main/ets');
const runtime = 'entry/src/main/ets/common/jsonschema/JsonDecode.ets';

// y（sticky）必须带：没有它 exec 会忽略 lastIndex 从文件头搜索，导致每个文件只报第一处。
const PARSE_AT = /JSON[ \t]*(?:\.[ \t]*parse|\[[ \t]*(['"])[ \t]*parse[ \t]*\1[ \t]*\])[ \t]*\(/y;

// 返回 source 里位于字符串与注释之外的 JSON.parse 所在行号（1 基）。
function findParseLines(source) {
  const hits = [];
  let state = 'code';   // code | line | block | single | double | template
  let line = 1;
  let i = 0;
  const n = source.length;
  while (i < n) {
    const c = source[i];
    if (c === '\n') {
      line += 1;
      // 单引号/双引号字符串不允许跨行：遇到换行就退出，避免一个漏配对把整文件吞掉。
      if (state === 'line' || state === 'single' || state === 'double') state = 'code';
      i += 1;
      continue;
    }
    if (state === 'line') { i += 1; continue; }
    if (state === 'block') {
      if (c === '*' && source[i + 1] === '/') { state = 'code'; i += 2; } else { i += 1; }
      continue;
    }
    if (state === 'single' || state === 'double' || state === 'template') {
      if (c === '\\') { i += 2; continue; }
      const closer = state === 'single' ? "'" : state === 'double' ? '"' : '`';
      if (c === closer) state = 'code';
      i += 1;
      continue;
    }
    // state === 'code'
    if (c === '/' && source[i + 1] === '/') { state = 'line'; i += 2; continue; }
    if (c === '/' && source[i + 1] === '*') { state = 'block'; i += 2; continue; }
    if (c === "'") { state = 'single'; i += 1; continue; }
    if (c === '"') { state = 'double'; i += 1; continue; }
    if (c === '`') { state = 'template'; i += 1; continue; }
    PARSE_AT.lastIndex = i;
    const m = PARSE_AT.exec(source);
    // 保留原来 \b 的语义：前一个字符是字母/数字/下划线时不算 JSON.parse（如 myJSON.parse）。
    const prev = i === 0 ? '' : source[i - 1];
    if (m && !/[A-Za-z0-9_]/.test(prev)) {
      hits.push(line);
      i += m[0].length;
      continue;
    }
    i += 1;
  }
  return hits;
}

function walk(dir, out) {
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, item.name);
    if (item.isDirectory()) walk(file, out);
    else if (item.name.endsWith('.ets')) out.push(file);
  }
  return out;
}

const unexpected = [];
let runtimeCalls = 0;
for (const file of walk(base, [])) {
  const relative = path.relative(root, file);
  const source = fs.readFileSync(file, 'utf8');
  for (const lineNumber of findParseLines(source)) {
    if (relative === runtime) runtimeCalls += 1;
    else unexpected.push({
      file: relative,
      line: lineNumber,
      source: source.split('\n')[lineNumber - 1].trim()
    });
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
