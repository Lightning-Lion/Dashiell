import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { webview } from '@kit.ArkWeb';
import { DevFlags } from '../dev/DevFlags';
import { DouyinCookieExport, ExportedCookie } from './DouyinCookieExport';
import { LogEvents } from '../../utils/log/LogEvents.generated';

/**
 * 调试用 Want 导入抖音 Cookie。
 *
 * 只在 debug 构建生效；release 构建收到同一 action 也只记日志、不写任何 Cookie。
 * 输入只接受 Want 的 `--ps cookie "..."`，解析后直接写入 WebCookieManager；
 * 不再写 `douyin-cookie.txt` / `douyin-web-cookies.json`，也不再从文件读取。
 * Want 和结果文件都不打印/不记录 Cookie 值。
 *
 * 命令示例见 docs/debug-config.md。
 */

export const DOUYIN_COOKIE_IMPORT_ACTION: string =
  'com.dalton.dashiell.debug.IMPORT_DOUYIN_COOKIES';
export const DOUYIN_COOKIE_IMPORT_COOKIE_KEY: string = 'cookie';
export const DOUYIN_COOKIE_IMPORT_REMOVE_KEY: string = 'remove';
export const DOUYIN_COOKIE_IMPORT_INSPECT_KEY: string = 'inspect';
export const DOUYIN_COOKIE_IMPORT_RESULT_FILE: string = 'douyin-cookie-import-result.json';

const LEGACY_NATIVE_COOKIE_FILE: string = 'douyin-cookie.txt';
const LEGACY_WEB_COOKIE_FILE: string = 'douyin-web-cookies.json';
// 抖音单个 Cookie 值 < 4 KB；16 KB 足够容纳一条完整的 Cookie 请求头。
const MAX_RAW_COOKIE_CHARS: number = 16384;
const PERSIST_SECONDS: number = 31536000;

export interface CookieDomainCount {
  domain: string;
  count: number;
}

export interface CookieImportResult {
  ok: boolean;
  reason: string;
  origin: string;
  source: string;
  format: string;
  parsed: number;
  outOfScope: number;
  invalid: number;
  kept: number;
  domains: CookieDomainCount[];
  nativeChars: number;
  webViewAttempted: number;
  webViewErrors: number;
  webViewPresent: number;
  webViewSaved: boolean;
  removed: number;
  loginMarkers: string[];
  cookieNames: string[];
  legacyFilesRemoved: number;
  timestamp: string;
}

export class DouyinCookieDebugImport {
  static isImportAction(action: string | undefined): boolean {
    return action === DOUYIN_COOKIE_IMPORT_ACTION;
  }

  /**
   * EntryAbility 的 onCreate/onNewWant 调用入口。同步解析 Want 并写入 WebCookieManager；
   * 不再落 Cookie 文件。失败不抛出，结果写到私有 result 文件供 hdc 回收。
   */
  static handle(context: common.Context, action: string | undefined,
    parameters: Record<string, Object> | undefined, origin: string): void {
    if (!DouyinCookieDebugImport.isImportAction(action)) { return; }
    let result: CookieImportResult = DouyinCookieDebugImport.emptyResult(origin);
    try {
      if (!DevFlags.isDebugBuild) {
        result.reason = 'release-build';
      } else {
        result = DouyinCookieDebugImport.run(context, parameters, origin);
      }
    } catch (_) {
      result = DouyinCookieDebugImport.fail(origin, 'exception');
    }
    DouyinCookieDebugImport.writeResult(context, result);
    DouyinCookieDebugImport.log(result);
  }

  private static run(context: common.Context, parameters: Record<string, Object> | undefined,
    origin: string): CookieImportResult {
    const remove = DouyinCookieDebugImport.stringParam(parameters, DOUYIN_COOKIE_IMPORT_REMOVE_KEY);
    if (remove !== undefined) {
      return DouyinCookieDebugImport.removeWebCookies(remove, origin);
    }
    const inspect = DouyinCookieDebugImport.stringParam(parameters, DOUYIN_COOKIE_IMPORT_INSPECT_KEY);
    if (inspect !== undefined) {
      return DouyinCookieDebugImport.inspectWebCookies(origin);
    }
    const raw = DouyinCookieDebugImport.stringParam(parameters, DOUYIN_COOKIE_IMPORT_COOKIE_KEY);
    if (raw !== undefined) {
      if (raw.length === 0) { return DouyinCookieDebugImport.fail(origin, 'want-cookie-empty'); }
      if (raw.length > MAX_RAW_COOKIE_CHARS) {
        return DouyinCookieDebugImport.fail(origin, 'want-cookie-too-large');
      }
      return DouyinCookieDebugImport.importText(context, raw, '(want-cookie)', origin);
    }
    return DouyinCookieDebugImport.fail(origin, 'no-input');
  }

  private static importText(context: common.Context, text: string, source: string,
    origin: string): CookieImportResult {
    const parsed = DouyinCookieExport.parse(text);
    if (parsed.error.length > 0) { return DouyinCookieDebugImport.fail(origin, parsed.error); }
    if (parsed.cookies.length === 0) {
      return DouyinCookieDebugImport.fail(origin, 'no-in-scope-cookies');
    }

    const nativeHeader = DouyinCookieExport.buildNativeHeader(parsed.cookies);
    const markers = DouyinCookieExport.loginMarkers(parsed.cookies);
    const web = DouyinCookieDebugImport.syncWebView(parsed.cookies);

    let ok = false;
    let reason = '';
    if (web.attempted === 0) {
      reason = 'webview-no-cookie';
    } else if (web.errors > 0) {
      reason = 'webview-partial';
    } else if (!web.saved) {
      reason = 'webview-save-failed';
    } else if (web.present === 0) {
      reason = 'webview-verify-failed';
    } else {
      ok = true;
    }

    const legacyFilesRemoved = ok ? DouyinCookieDebugImport.cleanupLegacyCookieFiles(context) : 0;

    return {
      ok: ok,
      reason: reason,
      origin: origin,
      source: source,
      format: parsed.format,
      parsed: parsed.cookies.length + parsed.outOfScope + parsed.invalid,
      outOfScope: parsed.outOfScope,
      invalid: parsed.invalid,
      kept: parsed.cookies.length,
      domains: DouyinCookieDebugImport.domainCounts(parsed.cookies),
      nativeChars: nativeHeader.length,
      webViewAttempted: web.attempted,
      webViewErrors: web.errors,
      webViewPresent: web.present,
      webViewSaved: web.saved,
      removed: 0,
      loginMarkers: markers,
      cookieNames: [],
      legacyFilesRemoved: legacyFilesRemoved,
      timestamp: new Date().toISOString()
    };
  }

  /** Debug inspect: return Cookie names only, never values. Useful after force-stop/restart. */
  private static inspectWebCookies(origin: string): CookieImportResult {
    let names: string[] = [];
    try {
      const header = webview.WebCookieManager.fetchCookieSync('https://www.douyin.com/');
      names = DouyinCookieDebugImport.cookieNames(header);
    } catch (_) {
      return DouyinCookieDebugImport.fail(origin, 'inspect-failed');
    }
    const result = DouyinCookieDebugImport.emptyResult(origin);
    result.ok = names.length > 0;
    result.reason = names.length > 0 ? 'inspected' : 'inspect-empty';
    result.source = '(want-inspect)';
    result.format = 'inspect';
    result.cookieNames = names;
    result.loginMarkers = names.filter((name: string): boolean => DouyinCookieDebugImport.isLoginMarkerName(name));
    result.timestamp = new Date().toISOString();
    return result;
  }

  private static cookieNames(header: string): string[] {
    const names: string[] = [];
    for (const part of header.split(';')) {
      const equals = part.indexOf('=');
      if (equals <= 0) { continue; }
      const name = part.substring(0, equals).trim();
      if (name.length > 0 && !names.includes(name)) { names.push(name); }
    }
    return names;
  }

  private static isLoginMarkerName(name: string): boolean {
    return name === 'passport_assist_user' || name === 'sessionid' ||
      name === 'sessionid_ss' || name === 'sid_tt';
  }

  /** Debug cleanup: expire selected cookie names on the three scopes this importer owns. */
  private static removeWebCookies(raw: string, origin: string): CookieImportResult {
    const names: string[] = [];
    for (const part of raw.split(',')) {
      const name = part.trim();
      if (name.length === 0 || name.length > 256 || DouyinCookieExport.hasControl(name) ||
        name.indexOf(';') >= 0 || name.indexOf('=') >= 0) {
        continue;
      }
      if (!names.includes(name)) { names.push(name); }
    }
    if (names.length === 0) { return DouyinCookieDebugImport.fail(origin, 'remove-empty'); }

    const scopes: string[] = ['www.douyin.com', 'lf-zt.douyin.com', 'lf-rc1.yhgfb-cn-static.com'];
    let attempted = 0;
    let errors = 0;
    for (const domain of scopes) {
      for (const name of names) {
        const expired = name + '=; Path=/; Max-Age=0;' +
          ' Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly';
        try {
          webview.WebCookieManager.configCookieSync('https://' + domain + '/', expired, false, true);
          attempted++;
        } catch (_) {
          errors++;
        }
      }
    }
    let saved = false;
    try {
      webview.WebCookieManager.saveCookieSync();
      saved = true;
    } catch (_) { /* best effort */ }

    const result = DouyinCookieDebugImport.emptyResult(origin);
    result.ok = errors === 0 && saved;
    result.reason = errors === 0 ? (saved ? 'removed' : 'remove-save-failed') : 'remove-partial';
    result.source = '(want-remove)';
    result.webViewAttempted = attempted;
    result.webViewErrors = errors;
    result.webViewSaved = saved;
    result.removed = names.length;
    result.timestamp = new Date().toISOString();
    return result;
  }

  private static syncWebView(cookies: ExportedCookie[]): WebSyncResult {
    let attempted = 0;
    let errors = 0;
    for (const cookie of cookies) {
      if (!DouyinCookieExport.validForWebView(cookie)) { continue; }
      const setCookie = cookie.name + '=' + cookie.value + '; Path=/; Secure; HttpOnly; Max-Age=' +
        PERSIST_SECONDS;
      try {
        webview.WebCookieManager.configCookieSync('https://' + cookie.domain + '/', setCookie, false, true);
        attempted++;
      } catch (_) {
        errors++;
      }
    }
    let saved = false;
    try {
      webview.WebCookieManager.saveCookieSync();
      saved = true;
    } catch (_) { /* save failure is reported to the caller */ }

    let present = 0;
    for (const domain of DouyinCookieExport.domains(cookies)) {
      let header = '';
      try {
        header = webview.WebCookieManager.fetchCookieSync('https://' + domain + '/');
      } catch (_) {
        continue;
      }
      const names: string[] = [];
      for (const part of header.split(';')) {
        const equals = part.indexOf('=');
        if (equals > 0) {
          const name = part.substring(0, equals).trim();
          if (!names.includes(name)) { names.push(name); }
        }
      }
      for (const cookie of cookies) {
        if (cookie.domain === domain && names.includes(cookie.name)) { present++; }
      }
    }
    return { attempted: attempted, errors: errors, present: present, saved: saved };
  }

  private static domainCounts(cookies: ExportedCookie[]): CookieDomainCount[] {
    const result: CookieDomainCount[] = [];
    const counts = DouyinCookieExport.countByDomain(cookies);
    for (const domain of DouyinCookieExport.domains(cookies)) {
      result.push({ domain: domain, count: counts.get(domain) ?? 0 });
    }
    return result;
  }

  private static stringParam(parameters: Record<string, Object> | undefined, key: string): string | undefined {
    if (parameters === undefined) { return undefined; }
    const value = parameters[key];
    return typeof value === 'string' ? value as string : undefined;
  }

  private static appFilesDir(context: common.Context): string {
    try {
      return context.getApplicationContext().filesDir;
    } catch (_) {
      return context.filesDir;
    }
  }

  /** Only cleanup: old debug builds wrote these files; the new runtime never reads them. */
  private static cleanupLegacyCookieFiles(context: common.Context): number {
    const canonicalDir = DouyinCookieDebugImport.appFilesDir(context);
    let legacyDir = canonicalDir;
    try {
      legacyDir = context.filesDir;
    } catch (_) { /* keep canonical */ }
    const dirs: string[] = canonicalDir === legacyDir ? [canonicalDir] : [canonicalDir, legacyDir];
    const names: string[] = [LEGACY_NATIVE_COOKIE_FILE, LEGACY_WEB_COOKIE_FILE];
    let removed = 0;
    for (const dir of dirs) {
      for (const name of names) {
        const path = dir + '/' + name;
        try {
          if (fs.accessSync(path)) {
            fs.unlinkSync(path);
            removed++;
          }
        } catch (_) { /* best effort; stale files are ignored by the runtime */ }
      }
    }
    return removed;
  }

  private static writeAtomic(path: string, text: string): void {
    const temporary = path + '.tmp';
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    try {
      fs.renameSync(temporary, path);
    } catch (_) {
      if (fs.accessSync(path)) { fs.unlinkSync(path); }
      fs.renameSync(temporary, path);
    }
  }

  private static writeResult(context: common.Context, result: CookieImportResult): void {
    try {
      const path = DouyinCookieDebugImport.appFilesDir(context) + '/' + DOUYIN_COOKIE_IMPORT_RESULT_FILE;
      DouyinCookieDebugImport.writeAtomic(path, JSON.stringify(result));
    } catch (_) { /* Diagnostics must never crash the ability launch. */ }
  }

  private static emptyResult(origin: string): CookieImportResult {
    return {
      ok: false,
      reason: '',
      origin: origin,
      source: '',
      format: '',
      parsed: 0,
      outOfScope: 0,
      invalid: 0,
      kept: 0,
      domains: [],
      nativeChars: 0,
      webViewAttempted: 0,
      webViewErrors: 0,
      webViewPresent: 0,
      webViewSaved: false,
      removed: 0,
      loginMarkers: [],
      cookieNames: [],
      legacyFilesRemoved: 0,
      timestamp: new Date().toISOString()
    };
  }

  private static fail(origin: string, reason: string): CookieImportResult {
    const result = DouyinCookieDebugImport.emptyResult(origin);
    result.reason = reason;
    return result;
  }

  private static log(result: CookieImportResult): void {
    // 只记计数/域名数量/是否成功;不记 Cookie 值、域名明细或文件内容。
    LogEvents.cookieImportDone({
      ok: result.ok,
      reason: result.reason.length > 0 ? result.reason : '-',
      kept: result.kept,
      saved: result.webViewSaved,
      domains: result.domains.length,
    });
  }
}

interface WebSyncResult {
  attempted: number;
  errors: number;
  present: number;
  saved: boolean;
}
