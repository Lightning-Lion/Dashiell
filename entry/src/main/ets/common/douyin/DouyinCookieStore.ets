import { webview } from '@kit.ArkWeb';

/**
 * 抖音 Cookie 的唯一运行时来源是 WebView 的 WebCookieManager。
 *
 * 调试/QA 的显式 Want 导入会先把 Cookie 写入 WebCookieManager；
 * 这里不再读取应用私有文件，也不再有源码级开发 Cookie 覆盖。Never log cookies.
 */
export class DouyinCookieStore {
  // 登录后才会下发，匿名访客只有 ttwid / odin_tt / __ac_nonce 这类标记。
  private static readonly loginMarkerNames: string[] = ['passport_assist_user', 'sessionid',
    'sessionid_ss', 'sid_tt'];

  /**
   * 这份 Cookie 是否带登录标记。只判存在性，值非空才算。
   * 传给它的字符串决定「来源」语义：登录页给 WebCookieManager 的，精选页给 read() 的。
   */
  static hasLoginMarker(cookie: string): boolean {
    if (cookie.length === 0) { return false; }
    for (const part of cookie.split(';')) {
      const trimmed = part.trim();
      const equals = trimmed.indexOf('=');
      if (equals <= 0) { continue; }
      const name = trimmed.substring(0, equals).trim();
      const value = trimmed.substring(equals + 1).trim();
      if (value.length > 0 && DouyinCookieStore.loginMarkerNames.includes(name)) { return true; }
    }
    return false;
  }

  /** 读 WebView Cookie 并判定登录态。读不到即未登录，不抛错。 */
  static async isLoggedIn(): Promise<boolean> {
    try {
      return DouyinCookieStore.hasLoginMarker(await DouyinCookieStore.read());
    } catch (_) {
      return false;
    }
  }

  /** 只读 WebView 的 www.douyin.com Cookie；没有就抛错。 */
  static async read(): Promise<string> {
    const value = (await webview.WebCookieManager.fetchCookie('https://www.douyin.com/')).trim();
    if (value.length === 0) {
      throw new Error('请先登录抖音或通过 Want 导入 Cookie');
    }
    return value;
  }

  /** 只清 WebView Cookie；导入过的 Cookie 也在同一个 Cookie store 里。 */
  static async clear(): Promise<void> {
    const origins: string[] = ['https://www.douyin.com/', 'https://douyin.com/',
      'https://live.douyin.com/', 'https://m.douyin.com/', 'https://passport.douyin.com/'];
    for (const origin of origins) {
      const cookie = await webview.WebCookieManager.fetchCookie(origin);
      const names: Set<string> = new Set(['sessionid', 'sessionid_ss', 'sid_tt', 'sid_guard',
        'passport_assist_user', 'uid_tt', 'uid_tt_ss']);
      for (const part of cookie.split(';')) {
        const equals = part.indexOf('=');
        const name = equals > 0 ? part.substring(0, equals).trim() : '';
        if (/^[A-Za-z0-9_.-]+$/.test(name)) { names.add(name); }
      }
      for (const name of names) {
        const expired = `${name}=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly`;
        await webview.WebCookieManager.configCookie(origin, expired, false, true);
        await webview.WebCookieManager.configCookie(origin, expired + '; Domain=.douyin.com', false, true);
      }
    }
    await webview.WebCookieManager.saveCookieAsync();
  }

}
