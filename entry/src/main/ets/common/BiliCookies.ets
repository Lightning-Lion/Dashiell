import { webview } from '@kit.ArkWeb';

export function isBiliLoginReturnURL(address: string): boolean {
  // Exact trusted hosts only; query strings/trailing paths do not force another login.
  return /^https:\/\/(?:www|m)\.bilibili\.com(?:[/?#]|$)/i.test(address);
}

export function hasBiliSessionCookie(cookie: string): boolean {
  return /(^|;\s*)SESSDATA=[^;\s]+/.test(cookie);
}

/** Delete only Bilibili cookies, never Douyin or other embedded sites' sessions. */
export async function clearBiliCookies(): Promise<void> {
  const origins: string[] = ['https://www.bilibili.com/', 'https://m.bilibili.com/',
    'https://passport.bilibili.com/', 'https://api.bilibili.com/', 'https://bilibili.com/'];
  for (const origin of origins) {
    const cookie = await webview.WebCookieManager.fetchCookie(origin);
    const names: Set<string> = new Set(['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']);
    for (const part of cookie.split(';')) {
      const equals = part.indexOf('=');
      const name = equals > 0 ? part.substring(0, equals).trim() : '';
      if (/^[A-Za-z0-9_\-]+$/.test(name)) { names.add(name); }
    }
    for (const name of names) {
      const expired = `${name}=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly`;
      await webview.WebCookieManager.configCookie(origin, expired, false, true);
      await webview.WebCookieManager.configCookie(origin, expired + '; Domain=.bilibili.com', false, true);
    }
  }
  await webview.WebCookieManager.saveCookieAsync();
}

/** Shared by homepage, profile and login completion so cookie scope cannot change the UI's account state. */
export async function readBiliCookieCandidates(preferredURL?: string): Promise<string[]> {
  const origins: string[] = ['https://www.bilibili.com/', 'https://m.bilibili.com/', 'https://bilibili.com/'];
  if (preferredURL !== undefined && isBiliLoginReturnURL(preferredURL)) { origins.unshift(preferredURL); }
  const candidates: string[] = [];
  for (const origin of origins) {
    const cookie = await webview.WebCookieManager.fetchCookie(origin);
    if (hasBiliSessionCookie(cookie) && !candidates.includes(cookie)) { candidates.push(cookie); }
  }
  return candidates;
}
