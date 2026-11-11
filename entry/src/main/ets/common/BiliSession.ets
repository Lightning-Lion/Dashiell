import { readBiliCookieCandidates } from './BiliCookies';
import { BiliResponseDecoder } from './bili/BiliResponseDecoder';
import { LogEvents } from '../utils/log/LogEvents.generated';
import http from '@ohos.net.http';

@ObservedV2
export class BiliLoginState {
  @Trace loggedIn: boolean = false;
}

export const biliLoginState: BiliLoginState = new BiliLoginState();

let sessionEpoch: number = 0;
export class BiliSessionSuperseded extends Error {
  constructor() { super('登录状态已更新，请重试'); }
}
export function getBiliSessionEpoch(): number { return sessionEpoch; }
export function isCurrentBiliSessionEpoch(epoch: number): boolean { return epoch === sessionEpoch; }
export function assertBiliSessionEpoch(epoch: number): void {
  if (!isCurrentBiliSessionEpoch(epoch)) { throw new BiliSessionSuperseded(); }
}
export function invalidateBiliSession(): void {
  sessionEpoch++;
  biliLoginState.loggedIn = false;
}
export function acceptInteractiveBiliLogin(): void {
  sessionEpoch++;
  biliLoginState.loggedIn = true;
}

interface SessionResponse {
  code: number;
  message?: string;
  data?: SessionData;
}

interface SessionData {
  isLogin: boolean;
}

// Network failures must not be mistaken for an expired session.
export function isValidBiliSession(response: SessionResponse): boolean {
  return BiliResponseDecoder.validateSession(response);
}

export async function checkBiliSession(cookie: string, publishState: boolean = true, expectedEpoch?: number): Promise<boolean> {
  const epoch = expectedEpoch ?? getBiliSessionEpoch();
  assertBiliSessionEpoch(epoch);
  if (!/(^|;\s*)SESSDATA=[^;]+/.test(cookie)) {
    if (publishState) { biliLoginState.loggedIn = false; }
    return false;
  }
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.bilibili.com/x/web-interface/nav', {
      method: http.RequestMethod.GET,
      header: { 'Cookie': cookie, 'Referer': 'https://www.bilibili.com/' },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    assertBiliSessionEpoch(epoch);
    if (response.responseCode !== 200) {
      throw new Error(`验证登录状态失败（HTTP ${response.responseCode}）`);
    }
    assertBiliSessionEpoch(epoch);
    const valid = BiliResponseDecoder.parseSession(BiliResponseDecoder.responseText(response.result));
    if (publishState) { biliLoginState.loggedIn = valid; }
    return valid;
  } finally {
    request.destroy();
  }
}

/** Verify actual cookie candidates, rather than forcing a second login for a different web subdomain. */
export async function restoreBiliSessionCookie(preferredURL?: string, expectedEpoch?: number): Promise<string | undefined> {
  const epoch = expectedEpoch ?? getBiliSessionEpoch();
  assertBiliSessionEpoch(epoch);
  const candidates = await readBiliCookieCandidates(preferredURL);
  assertBiliSessionEpoch(epoch);
  for (const cookie of candidates) {
    // One expired host-scope cookie cannot log out another still-unverified scope.
    // Publish only the aggregate result; any network exception preserves prior state.
    if (await checkBiliSession(cookie, false, epoch)) {
      assertBiliSessionEpoch(epoch);
      biliLoginState.loggedIn = true;
      LogEvents.biliSessionRestored();
      return cookie;
    }
  }
  assertBiliSessionEpoch(epoch);
  biliLoginState.loggedIn = false;
  LogEvents.biliSessionExpired();
  return undefined;
}
