/**
 * 抖音调试 Cookie 导出解析（纯逻辑，无平台依赖）。
 *
 * 支持三种输入：
 * 1. 按域分组的 TSV：一行域名，随后若干行 `name<TAB>value`；
 * 2. 单行 Cookie 请求头：`name=value; name2=value2`（域按 www.douyin.com 处理）；
 * 3. JSON 数组或 `{ "cookies": [...] }`，元素含 domain/name/value。
 *
 * 这里绝不打印任何 value。域外 Cookie 在解析阶段丢弃，只保留抖音及其静态资源域。
 */

import { DecodeContext, JsonNode } from '../jsonschema/JsonDecode';

export interface ExportedCookie {
  domain: string;
  name: string;
  value: string;
}

export interface ParsedCookieExport {
  cookies: ExportedCookie[];
  outOfScope: number;
  invalid: number;
  format: string;
  error: string;
}

const BOM: string = '\uFEFF';
const MAX_NAME_LENGTH: number = 1024;
const MAX_VALUE_LENGTH: number = 65536;
const MAX_NATIVE_NAME_LENGTH: number = 128;
const MAX_NATIVE_VALUE_LENGTH: number = 4096;
const MAX_NATIVE_HEADER_BYTES: number = 8192;

const LOGIN_MARKER_NAMES: string[] = ['passport_assist_user', 'sessionid', 'sessionid_ss', 'sid_tt'];

/** 真正参与登录态判定的 Cookie；只用于报告名称，不暴露值。 */
const AUTH_COOKIE_NAMES: string[] = ['passport_assist_user', 'sessionid', 'sessionid_ss', 'sid_tt',
  'sid_guard', 'uid_tt', 'uid_tt_ss', 'sso_uid_tt', 'sso_uid_tt_ss', 'toutiao_sso_user',
  'toutiao_sso_user_ss', 'd_ticket', 'passport_csrf_token', 'passport_csrf_token_default',
  'ttwid', 'odin_tt', 'mstoken', 'uifid', 's_v_web_id', '__ac_nonce', '__ac_signature',
  'csrf_session_id'];

/** RFC 6265 cookie-name token；请求头里名字不合法的条目不能拼进 Cookie 头。 */
const HEADER_NAME_PATTERN: RegExp = new RegExp("^[!#$%&'*+\\-.^_`|~0-9A-Za-z]+$");
const DOMAIN_PATTERN: RegExp = new RegExp('^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

export class DouyinCookieExport {
  static readonly ALLOWED_ROOTS: string[] = ['douyin.com', 'yhgfb-cn-static.com'];

  /** 去空格、小写、去掉前导点；不是合法主机名时返回空串。 */
  static normalizeDomain(raw: string): string {
    const value = raw.trim().toLowerCase();
    if (value.length === 0 || value.length > 253) { return ''; }
    if (value.indexOf('/') >= 0 || value.indexOf(':') >= 0 || /\s/.test(value)) { return ''; }
    const host = value.startsWith('.') ? value.substring(1) : value;
    if (!DOMAIN_PATTERN.test(host)) { return ''; }
    return host;
  }

  static isAllowedDomain(domain: string): boolean {
    const host = DouyinCookieExport.normalizeDomain(domain);
    if (host.length === 0) { return false; }
    for (const root of DouyinCookieExport.ALLOWED_ROOTS) {
      if (host === root || host.endsWith('.' + root)) { return true; }
    }
    return false;
  }

  static isLoginMarker(name: string): boolean {
    return LOGIN_MARKER_NAMES.includes(name.trim());
  }

  /** 只返回命中的登录标记名称（去重），用于诊断，不含值。 */
  static loginMarkers(cookies: ExportedCookie[]): string[] {
    const found: string[] = [];
    for (const cookie of cookies) {
      if (cookie.domain !== 'www.douyin.com') { continue; }
      if (cookie.value.length === 0 || !DouyinCookieExport.isLoginMarker(cookie.name)) { continue; }
      if (!found.includes(cookie.name)) { found.push(cookie.name); }
    }
    return found;
  }

  static hasControl(value: string): boolean {
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code < 0x20 || code === 0x7f) { return true; }
    }
    return false;
  }

  static validForHeader(cookie: ExportedCookie): boolean {
    if (!HEADER_NAME_PATTERN.test(cookie.name)) { return false; }
    if (cookie.name.length === 0 || cookie.name.length > MAX_NATIVE_NAME_LENGTH) { return false; }
    if (cookie.value.length > MAX_NATIVE_VALUE_LENGTH) { return false; }
    if (cookie.value.indexOf(';') >= 0) { return false; }
    return !DouyinCookieExport.hasControl(cookie.name) && !DouyinCookieExport.hasControl(cookie.value);
  }

  /**
   * Set-Cookie 的 name 不能含 `=` 或 `;`；值不能含控制字符或分号，否则会把后半段当成属性。
   * 斜杠等 SDK 自定义名字先尝试交给 WebCookieManager，失败会计入结果而不是中断整批导入。
   */
  static validForWebView(cookie: ExportedCookie): boolean {
    if (cookie.name.length === 0 || cookie.name.length > 256) { return false; }
    if (cookie.name.indexOf('=') >= 0 || cookie.name.indexOf(';') >= 0) { return false; }
    if (cookie.value.length > MAX_NATIVE_VALUE_LENGTH) { return false; }
    if (cookie.value.indexOf(';') >= 0) { return false; }
    return !DouyinCookieExport.hasControl(cookie.name) && !DouyinCookieExport.hasControl(cookie.value);
  }

  static parse(text: string): ParsedCookieExport {
    let source = text;
    if (source.startsWith(BOM)) { source = source.substring(1); }
    if (source.trim().length === 0) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'empty', error: 'input-empty' };
    }
    if (source.length > 2 * 1024 * 1024) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'too-large', error: 'input-too-large' };
    }

    const first = source.trimStart();
    if (first.startsWith('[') || first.startsWith('{')) {
      return DouyinCookieExport.parseJson(source);
    }

    const lines = source.split(/\r?\n/);
    let firstLine = '';
    for (const line of lines) {
      if (line.trim().length > 0) { firstLine = line; break; }
    }
    if (firstLine.length === 0) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'empty', error: 'input-empty' };
    }
    if (firstLine.indexOf('\t') < 0 && firstLine.indexOf('=') < 0 &&
      DouyinCookieExport.normalizeDomain(firstLine).length > 0) {
      return DouyinCookieExport.parseGroupedTsv(lines);
    }
    return DouyinCookieExport.parseCookieHeader(source);
  }

  private static parseGroupedTsv(lines: string[]): ParsedCookieExport {
    const cookies: ExportedCookie[] = [];
    let outOfScope = 0;
    let invalid = 0;
    let domain = '';
    let inScope = false;
    for (const rawLine of lines) {
      const line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      if (line.trim().length === 0) { continue; }
      const tab = line.indexOf('\t');
      if (tab < 0) {
        const normalized = DouyinCookieExport.normalizeDomain(line);
        if (normalized.length === 0) {
          domain = '';
          inScope = false;
          invalid++;
          continue;
        }
        domain = normalized;
        inScope = DouyinCookieExport.isAllowedDomain(normalized);
        continue;
      }
      if (domain.length === 0 || !inScope) {
        if (domain.length > 0) { outOfScope++; }
        else { invalid++; }
        continue;
      }
      // Some browser exports append metadata columns after the value (domain length,
      // expiry, size, flags...). Cookie values cannot contain tabs, so the value is
      // exactly the second column; ignore the metadata instead of treating it as value.
      const columns = line.split('\t');
      const name = columns[0];
      const value = columns.length > 1 ? columns[1] : '';
      if (name.length === 0 || name.length > MAX_NAME_LENGTH || value.length > MAX_VALUE_LENGTH ||
        DouyinCookieExport.hasControl(name) || DouyinCookieExport.hasControl(value)) {
        invalid++;
        continue;
      }
      cookies.push({ domain: domain, name: name, value: value });
    }
    return { cookies: cookies, outOfScope: outOfScope, invalid: invalid, format: 'grouped-tsv', error: '' };
  }

  private static parseCookieHeader(source: string): ParsedCookieExport {
    const text = source.trim();
    if (text.indexOf('\n') >= 0 || text.indexOf('\r') >= 0) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'unsupported', error: 'multiline-header' };
    }
    if (text.length > MAX_VALUE_LENGTH * 4) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'too-large', error: 'header-too-large' };
    }
    const cookies: ExportedCookie[] = [];
    let invalid = 0;
    for (const part of text.split(';')) {
      const item = part.trim();
      if (item.length === 0) { continue; }
      const equals = item.indexOf('=');
      if (equals <= 0) {
        invalid++;
        continue;
      }
      const name = item.substring(0, equals).trim();
      const value = item.substring(equals + 1).trim();
      if (name.length === 0 || name.length > MAX_NAME_LENGTH || value.length > MAX_VALUE_LENGTH ||
        DouyinCookieExport.hasControl(name) || DouyinCookieExport.hasControl(value)) {
        invalid++;
        continue;
      }
      cookies.push({ domain: 'www.douyin.com', name: name, value: value });
    }
    if (cookies.length === 0) {
      return { cookies: [], outOfScope: 0, invalid: invalid, format: 'cookie-header', error: 'no-cookie-pairs' };
    }
    return { cookies: cookies, outOfScope: 0, invalid: invalid, format: 'cookie-header', error: '' };
  }

  private static parseJson(source: string): ParsedCookieExport {
    // 动态 JSON 访问只走 JsonNode 这一处共享边界；这里只做形状分流，绝不把解析结果直接
    // 断言成业务模型（与 *.generated.ets 里的 decoder 同一套约束）。
    const context = new DecodeContext('DouyinCookieExport');
    const node = JsonNode.parse(source, context);
    if (node === undefined) {
      return { cookies: [], outOfScope: 0, invalid: 0, format: 'json', error: 'json-parse' };
    }
    // items 先初始化为 node，保证所有存活路径都已赋值（ArkTS 不做可选链前的非空断言）。
    let items: JsonNode = node;
    if (node.kind() === 'object') {
      const envelope = node.field('cookies');
      if (envelope.kind() !== 'array') {
        return { cookies: [], outOfScope: 0, invalid: 0, format: 'json', error: 'json-shape' };
      }
      items = envelope;
    } else if (node.kind() !== 'array') {
      // 保持旧行为：非数组顶层被当作 envelope 读 .cookies，字符串/数字/布尔取到 undefined
      // 记 json-shape；而 JSON 'null' 读属性会抛 TypeError、被旧的 catch 归为 json-parse。
      return {
        cookies: [], outOfScope: 0, invalid: 0, format: 'json',
        error: node.kind() === 'null' ? 'json-parse' : 'json-shape'
      };
    }

    const cookies: ExportedCookie[] = [];
    let outOfScope = 0;
    let invalid = 0;
    for (let index = 0; index < items.length(); index++) {
      const item = items.element(index);
      const domainNode = item.field('domain');
      const nameNode = item.field('name');
      const valueNode = item.field('value');
      if (domainNode.kind() !== 'string' || nameNode.kind() !== 'string' || valueNode.kind() !== 'string') {
        invalid++;
        continue;
      }
      const name = nameNode.stringValue();
      const value = valueNode.stringValue();
      const domain = DouyinCookieExport.normalizeDomain(domainNode.stringValue());
      if (domain.length === 0 || name.length === 0 || name.length > MAX_NAME_LENGTH ||
        value.length > MAX_VALUE_LENGTH || DouyinCookieExport.hasControl(name) ||
        DouyinCookieExport.hasControl(value)) {
        invalid++;
        continue;
      }
      if (!DouyinCookieExport.isAllowedDomain(domain)) {
        outOfScope++;
        continue;
      }
      cookies.push({ domain: domain, name: name, value: value });
    }
    return { cookies: cookies, outOfScope: outOfScope, invalid: invalid, format: 'json', error: '' };
  }

  private static nativePriority(name: string): number {
    const lower = name.toLowerCase();
    if (AUTH_COOKIE_NAMES.includes(lower)) { return 0; }
    if (lower.startsWith('web_secsdk') || lower.startsWith('user_info')) { return 1; }
    return 2;
  }

  /**
   * 生成原生请求用的 Cookie 头：只取 www.douyin.com，过滤不能安全放进请求头的名字/值，
   * 大体积页面状态（>4 KiB）不进入请求头；完整数据仍在结构化 JSON 落盘文件里。
   */
  static buildNativeHeader(cookies: ExportedCookie[]): string {
    const chosen: ExportedCookie[] = [];
    for (const cookie of cookies) {
      if (cookie.domain !== 'www.douyin.com') { continue; }
      if (!DouyinCookieExport.validForHeader(cookie)) { continue; }
      chosen.push(cookie);
    }
    chosen.sort((left: ExportedCookie, right: ExportedCookie): number => {
      const byPriority = DouyinCookieExport.nativePriority(left.name) -
        DouyinCookieExport.nativePriority(right.name);
      if (byPriority !== 0) { return byPriority; }
      return 0;
    });

    const pairs: string[] = [];
    const seen: string[] = [];
    let bytes = 0;
    for (const cookie of chosen) {
      if (seen.includes(cookie.name)) { continue; }
      const pair = cookie.name + '=' + cookie.value;
      const extra = pairs.length === 0 ? pair.length : pair.length + 2;
      if (bytes + extra > MAX_NATIVE_HEADER_BYTES) { continue; }
      pairs.push(pair);
      seen.push(cookie.name);
      bytes += extra;
    }
    return pairs.join('; ');
  }

  static countByDomain(cookies: ExportedCookie[]): Map<string, number> {
    const counts: Map<string, number> = new Map<string, number>();
    for (const cookie of cookies) {
      counts.set(cookie.domain, (counts.get(cookie.domain) ?? 0) + 1);
    }
    return counts;
  }

  static domains(cookies: ExportedCookie[]): string[] {
    const result: string[] = [];
    for (const cookie of cookies) {
      if (!result.includes(cookie.domain)) { result.push(cookie.domain); }
    }
    return result;
  }
}
