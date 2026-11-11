import { ABogus } from './ABogus';
import { DouyinWebSign } from './DouyinWebSign';

export type DouyinListSource = 'recommended' | 'collected' | 'liked';
export type SignatureMode = 'valid' | 'tampered' | 'missing';

/** Platform-free wire contract; the Node probe and ArkTS HTTP layer use this same implementation. */
export class DouyinRequestSpec {
  path: string;
  method: 'GET' | 'POST';
  query: string;
  body: string;
  signatureHeaders: Record<string, string> = {};
  constructor(path: string, method: 'GET' | 'POST', query: string, body: string = '') {
    this.path = path; this.method = method; this.query = query; this.body = body;
  }
}

export class DouyinRequestBuilder {
  static readonly USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36';

  private static baseParams(): Map<string, string> {
    const params = new Map<string, string>();
    params.set('device_platform', 'webapp');
    params.set('aid', '6383');
    params.set('channel', 'channel_pc_web');
    params.set('pc_client_type', '1');
    params.set('version_code', '290100');
    params.set('version_name', '29.1.0');
    params.set('cookie_enabled', 'true');
    params.set('screen_width', '680');
    params.set('screen_height', '907');
    params.set('browser_language', 'zh-CN');
    params.set('browser_platform', 'Win32');
    params.set('browser_name', 'Chrome');
    params.set('browser_version', '130.0.0.0');
    params.set('browser_online', 'true');
    params.set('engine_name', 'Blink');
    params.set('engine_version', '130.0.0.0');
    params.set('os_name', 'Windows');
    params.set('os_version', '10');
    params.set('cpu_core_num', '12');
    params.set('device_memory', '8');
    params.set('platform', 'PC');
    params.set('downlink', '10');
    params.set('effective_type', '4g');
    params.set('from_user_page', '1');
    params.set('locate_query', 'false');
    params.set('need_time_list', '1');
    params.set('pc_libra_divert', 'Windows');
    params.set('publish_video_strategy_type', '2');
    params.set('round_trip_time', '0');
    params.set('show_live_replay_strategy', '1');
    params.set('time_list_query', '0');
    params.set('whale_cut_token', '');
    params.set('update_version_code', '170400');
    return params;
  }

  private static personalParams(): Map<string, string> {
    const params = DouyinRequestBuilder.baseParams();
    // Current Douyin frontend's profile/favorite/listcollection contract (not post-list version).
    params.set('version_code', '170400');
    params.set('version_name', '17.4.0');
    params.set('support_h265', '0');
    params.set('support_dash', '0');
    for (const name of ['from_user_page', 'locate_query', 'need_time_list',
      'show_live_replay_strategy', 'time_list_query', 'whale_cut_token']) { params.delete(name); }
    return params;
  }

  static validateCookie(cookie: string): void {
    if (cookie.trim().length === 0 || /[\r\n]/.test(cookie)) {
      throw new Error('Cookie must be a nonempty single line');
    }
  }

  /** Match the website transport: Argus reads UIFID from a request header, not just Cookie. */
  static headers(cookie: string, method: 'GET' | 'POST', signatureHeaders: Record<string, string> = {}): Record<string, string> {
    DouyinRequestBuilder.validateCookie(cookie);
    const headers: Record<string, string> = {
      'User-Agent': DouyinRequestBuilder.USER_AGENT,
      'Referer': 'https://www.douyin.com/', 'Cookie': cookie, 'Accept': 'application/json'
    };
    const uifid = DouyinWebSign.pickUifid(cookie);
    if (uifid !== undefined) { headers['uifid'] = uifid; }
    for (const name of ['uifid', 'x-secsdk-web-signature', 'x-secsdk-web-expire']) {
      const value = signatureHeaders[name];
      if (value !== undefined) {
        if (/[\r\n]/.test(value)) { throw new Error('Invalid signature header'); }
        headers[name] = value;
      }
    }
    if (method === 'POST') { headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'; }
    return headers;
  }

  /** Apply fresh webSign immediately before the native request; never replay cached signed URLs. */
  static authenticate(spec: DouyinRequestSpec, cookie: string,
    timestampSeconds: number = Math.floor(Date.now() / 1000)): DouyinRequestSpec {
    DouyinRequestBuilder.validateCookie(cookie);
    if (!DouyinWebSign.isProtected(spec.path)) { return spec; }
    const signed = DouyinWebSign.signSession(spec.query, cookie, timestampSeconds);
    if (signed === undefined) { return spec; } // No fabricated UIFID for incomplete/anonymous jars.
    const prepared = new DouyinRequestSpec(spec.path, spec.method, signed.query, spec.body);
    prepared.signatureHeaders = signed.headers();
    return prepared;
  }

  private static sign(params: Map<string, string>, mode: SignatureMode): string {
    params.set('msToken', '');
    if (mode === 'valid') { return new ABogus().signedQuery(params); }
    if (mode === 'tampered') {
      const signature = new ABogus().getValue(params);
      params.set('a_bogus', signature.split('').map((c: string): string =>
        c === '=' ? '=' : (c === 'A' ? 'B' : 'A')).join(''));
    }
    // Use identical form encoding for both the hash input and transmitted query.
    return ABogus.serialize(params);
  }

  private static cursor(value: string): string {
    const cursor = value.trim() || '0';
    if (!/^\d+$/.test(cursor)) { throw new Error('Invalid Douyin cursor'); }
    return cursor;
  }

  static feed(cursor: string = '', mode: SignatureMode = 'valid'): DouyinRequestSpec {
    const params = DouyinRequestBuilder.baseParams();
    params.set('count', '4');
    if (cursor.trim().length > 0) {
      params.set('cursor', DouyinRequestBuilder.cursor(cursor));
      params.set('max_cursor', DouyinRequestBuilder.cursor(cursor));
    }
    return new DouyinRequestSpec('/aweme/v2/web/module/feed/', 'POST', DouyinRequestBuilder.sign(params, mode));
  }

  static detail(id: string, mode: SignatureMode = 'valid'): DouyinRequestSpec {
    if (!/^\d+$/.test(id)) { throw new Error('A real aweme ID is required'); }
    const params = DouyinRequestBuilder.baseParams();
    params.set('aweme_id', id);
    return new DouyinRequestSpec('/aweme/v1/web/aweme/detail/', 'GET', DouyinRequestBuilder.sign(params, mode));
  }

  static selfProfile(): DouyinRequestSpec {
    const params = DouyinRequestBuilder.personalParams();
    params.set('source', 'channel_pc_web');
    params.set('personal_center_strategy', '1');
    return new DouyinRequestSpec('/aweme/v1/web/user/profile/self/', 'GET', DouyinRequestBuilder.sign(params, 'valid'));
  }

  static library(source: 'collected' | 'liked', cursor: string = '', secUid: string = ''): DouyinRequestSpec {
    const params = DouyinRequestBuilder.personalParams();
    const pageCursor = DouyinRequestBuilder.cursor(cursor);
    if (source === 'liked') {
      if (!/^[A-Za-z0-9_-]+$/.test(secUid)) { throw new Error('A sec_user_id is required for likes'); }
      params.set('sec_user_id', secUid);
      params.set('max_cursor', pageCursor);
      params.set('min_cursor', '0');
      params.set('whale_cut_token', '');
      params.set('cut_version', '1');
      params.set('count', '4');
      return new DouyinRequestSpec('/aweme/v1/web/aweme/favorite/', 'GET', DouyinRequestBuilder.sign(params, 'valid'));
    }
    const body = new Map<string, string>();
    body.set('cursor', pageCursor); body.set('count', '4');
    return new DouyinRequestSpec('/aweme/v1/web/aweme/listcollection/', 'POST',
      DouyinRequestBuilder.sign(params, 'valid'), ABogus.serialize(body));
  }
}
