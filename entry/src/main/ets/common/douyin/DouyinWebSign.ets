// Web-signature protocol adapted from Evil0ctal/Douyin_TikTok_Download_API (Apache-2.0).
// Reference revision: 4f0bed8483c35a980315d9c7b3a1d4a1119ad2b2, src/dtk/signing/native/websign.py.
// Changes: synchronous ArkTS, strict input guards, duplicate-preserving parser, immutable request output.
// License/notice: resources/rawfile/licenses/douyin-websign-{LICENSE,NOTICE}.txt.
import { MD5 } from './MD5';

export class DouyinQueryPair {
  name: string;
  value: string;
  constructor(name: string, value: string) { this.name = name; this.value = value; }
}

export class DouyinWebSignResult {
  query: string;
  signature: string;
  timestamp: string;
  uifid: string;
  constructor(query: string, signature: string, timestamp: string, uifid: string) {
    this.query = query; this.signature = signature; this.timestamp = timestamp; this.uifid = uifid;
  }
  headers(): Record<string, string> {
    return { 'uifid': this.uifid, 'x-secsdk-web-signature': this.signature, 'x-secsdk-web-expire': this.timestamp };
  }
}

/** The extra webSign layer; this is distinct from a_bogus and never mints a visitor identity. */
export class DouyinWebSign {
  static readonly SALT: string = 'A96D855A08C0A9707F8BEF0D9A527E4E';
  static readonly SIGNATURE_PARAM: string = 'x-secsdk-web-signature';
  private static readonly UIFID_NAMES: string[] = ['uifid', 'uifid_temp', 'uifidtemp', 'UIFID', 'UIFID_TEMP', 'UIFIDTEMP'];
  // Exact protected paths observed by the reference project's web SDK analysis.
  private static readonly PROTECTED_PATHS: string[] = [
    '/aweme/v1/web/aweme/detail/', '/aweme/v1/web/aweme/post/', '/aweme/v1/web/aweme/favorite/',
    '/aweme/v1/web/aweme/listcollection/', '/aweme/v1/web/mix/aweme/', '/aweme/v1/web/tab/feed/',
    '/aweme/v1/web/mix/list/', '/aweme/v1/web/music/aweme/', '/aweme/v1/web/music/list/',
    '/aweme/v1/web/mix/detail/', '/aweme/v1/web/mix/listcollection/', '/aweme/v1/web/music/detail/',
    '/aweme/v1/web/collects/list/', '/aweme/v1/web/collects/video/list/'
  ];

  static isProtected(path: string): boolean {
    const normalized = (path.startsWith('/') ? '' : '/') + path + (path.endsWith('/') ? '' : '/');
    return DouyinWebSign.PROTECTED_PATHS.includes(normalized);
  }

  static cookieValue(cookie: string, name: string): string | undefined {
    for (const part of cookie.split(';')) {
      const equals = part.indexOf('=');
      if (equals > 0 && part.substring(0, equals).trim() === name) {
        return part.substring(equals + 1).trim() || undefined;
      }
    }
    return undefined;
  }

  static pickUifid(cookie: string): string | undefined {
    for (const name of DouyinWebSign.UIFID_NAMES) {
      const value = DouyinWebSign.cookieValue(cookie, name);
      if (value !== undefined) { return value; }
    }
    return undefined;
  }

  /**
   * 诊断用:只报关键身份 cookie 的「是否存在」(1/0),绝不返回任何取值。
   * 受保护端点(favorite/listcollection/detail)缺 uifid 时 authenticate 会静默不签名,
   * 服务端随后回 403 Uifid Not Found——过去这被误报成「登录失效」,这里把它显形。
   */
  static identitySummary(cookie: string): string {
    const present = (name: string): string => DouyinWebSign.cookieValue(cookie, name) !== undefined ? '1' : '0';
    return 'uifid=' + (DouyinWebSign.pickUifid(cookie) !== undefined ? '1' : '0') +
      ' s_v_web_id=' + present('s_v_web_id') + ' sessionid=' + present('sessionid') +
      ' sid_tt=' + present('sid_tt') + ' passport_assist_user=' + present('passport_assist_user');
  }

  // Follow the reference's actual urllib.quote output, NOT URLSearchParams/form encoding:
  // spaces -> %20, * and ~ remain literal, ! ' ( ) are escaped, hex digits uppercase.
  static encode(value: string): string {
    return encodeURIComponent(value).replace(/[!'()]/g, (c: string): string =>
      '%' + c.charCodeAt(0).toString(16).toUpperCase());
  }

  static parseQuery(query: string): DouyinQueryPair[] {
    if (query.length > 65536 || query.startsWith('?')) { throw new Error('Invalid web-sign query'); }
    const pairs: DouyinQueryPair[] = [];
    for (const part of query.split('&')) {
      if (part.length === 0) { continue; }
      const index = part.indexOf('=');
      const key = index < 0 ? part : part.substring(0, index);
      const value = index < 0 ? '' : part.substring(index + 1);
      pairs.push(new DouyinQueryPair(decodeURIComponent(key.replace(/\+/g, ' ')), decodeURIComponent(value.replace(/\+/g, ' '))));
    }
    return pairs;
  }

  static serialize(pairs: DouyinQueryPair[]): string {
    return pairs.map((pair: DouyinQueryPair): string => DouyinWebSign.encode(pair.name) + '=' + DouyinWebSign.encode(pair.value)).join('&');
  }

  static signPairs(pairs: DouyinQueryPair[], uifid: string,
    timestampSeconds: number = Math.floor(Date.now() / 1000)): DouyinWebSignResult {
    if (uifid.length === 0 || /[\x00-\x1f\x7f]/.test(uifid)) { throw new Error('A valid visitor id is required'); }
    if (!Number.isSafeInteger(timestampSeconds) || timestampSeconds < 0) { throw new Error('Invalid web-sign timestamp'); }
    if (pairs.some((pair: DouyinQueryPair): boolean => pair.name === 'timestamp' || pair.name === DouyinWebSign.SIGNATURE_PARAM)) {
      throw new Error('Remove old web signature and timestamp before signing');
    }
    const covered: DouyinQueryPair[] = pairs.map((pair: DouyinQueryPair): DouyinQueryPair => new DouyinQueryPair(pair.name, pair.value));
    const visitors = covered.filter((pair: DouyinQueryPair): boolean => pair.name === 'uifid');
    if (visitors.length > 1 || (visitors.length === 1 && visitors[0].value !== uifid)) {
      throw new Error('Ambiguous visitor id in query');
    }
    if (visitors.length === 0) { covered.push(new DouyinQueryPair('uifid', uifid)); }
    const timestamp = String(timestampSeconds);
    covered.push(new DouyinQueryPair('timestamp', timestamp));
    const query = DouyinWebSign.serialize(covered);
    if (query.length > 65536) { throw new Error('Web-sign query exceeds budget'); }
    const signature = MD5.hex(uifid + '_' + timestamp + '_' + DouyinWebSign.SALT + '_' + query);
    return new DouyinWebSignResult(query + '&' + DouyinWebSign.SIGNATURE_PARAM + '=' + signature,
      signature, timestamp, uifid);
  }

  static signSession(query: string, cookie: string,
    timestampSeconds: number = Math.floor(Date.now() / 1000)): DouyinWebSignResult | undefined {
    if (/[\r\n]/.test(cookie)) { throw new Error('Invalid Cookie header'); }
    const uifid = DouyinWebSign.pickUifid(cookie);
    if (uifid === undefined) { return undefined; }
    const pairs = DouyinWebSign.parseQuery(query);
    const fp = DouyinWebSign.cookieValue(cookie, 's_v_web_id');
    if (fp !== undefined) {
      for (const name of ['verifyFp', 'fp']) {
        if (!pairs.some((pair: DouyinQueryPair): boolean => pair.name === name)) { pairs.push(new DouyinQueryPair(name, fp)); }
      }
    }
    return DouyinWebSign.signPairs(pairs, uifid, timestampSeconds);
  }
}
