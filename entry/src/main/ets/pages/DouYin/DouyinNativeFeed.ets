import http from '@ohos.net.http';
import { DouyinApi } from '../../common/douyin/DouyinApi';
import { DouyinCookieStore } from '../../common/douyin/DouyinCookieStore';
import { DouYinCardListModel } from './DouYinCardListModel';
import { DouyinResponseDecoder } from '../../common/douyin/DouyinResponseDecoder';
import { DouyinFeedMapping } from '../../common/douyin/DouyinFeedMapping';
import { JsonDecodeError, DecodeIssue } from '../../common/jsonschema/JsonDecode';
import { DouyinListSource } from '../../common/douyin/DouyinRequestBuilder';
import { DouyinPagination } from '../../common/douyin/DouyinPagination';
import { logTag } from '../../common/printLog';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogEvents } from '../../utils/log/LogEvents.generated';

class DouyinAuthorizationError extends Error {
  status: number;
  // reason 为服务端 'Blocked by ArgusSecurityPlugin <reason>' 里的那段原因(如 Signature Not Found / Uifid Not Found);
  // 非安全插件拦截时为空串,代表真正的登录态失效。
  reason: string;
  constructor(message: string, status: number, reason: string = '') {
    super(message);
    this.status = status;
    this.reason = reason;
  }
}

// 非 200 / 非字符串响应:把状态码与结果长度一并带上抛出。
// 此前这里抛的是光秃秃的 'Invalid Douyin HTTP response',catch 里再被吞成一句 REQUEST_OR_PLAYBACK_FAILURE。
// 注意:只携带元数据,绝不携带响应正文或 Cookie。
class DouyinHttpError extends Error {
  status: number;
  resultLength: number;
  isStringResult: boolean;
  constructor(status: number, resultLength: number, isStringResult: boolean) {
    super('Invalid Douyin HTTP response');
    this.status = status;
    this.resultLength = resultLength;
    this.isStringResult = isStringResult;
  }
}

// 把任意 error 展开成可读片段。非 JsonDecodeError 的分支过去一律丢成一个固定字符串,
// 现在把 code / name / message / 状态码 / 结果长度全找回来。
function describeError(error: Error): string {
  if (error instanceof JsonDecodeError) {
    const head = error.issues.slice(0, 3).map((issue: DecodeIssue): string =>
      issue.code + '@' + issue.pathText()).join(', ');
    return 'JsonDecode schema=' + error.schema + ' issues=' + error.issues.length + ' head=[' + head + ']';
  }
  if (error instanceof DouyinAuthorizationError) {
    return 'AUTH status=' + error.status + (error.reason.length > 0 ? ' block=' + JSON.stringify(error.reason) : '') +
      ' message=' + error.message;
  }
  if (error instanceof DouyinHttpError) {
    return 'HTTP status=' + error.status + ' resultLen=' + error.resultLength + ' stringResult=' + error.isStringResult;
  }
  const biz = error as BusinessError;
  return 'code=' + biz.code + ' name=' + error.name + ' message=' + error.message;
}

/** 只记录解码元数据,不带原始响应/字段值。列表与详情共用,保证事件仍只有一个调用点。 */
function logDecodeFailure(error: JsonDecodeError, operation: string): void {
  const issue = error.issues.length > 0 ? error.issues[0] : undefined;
  LogEvents.douyinDecodeFailed({
    operation: operation,
    schema: error.schema,
    issueCount: error.issues.length,
    code: issue === undefined ? '' : issue.code,
    path: issue === undefined ? '' : issue.pathText(),
    expected: issue === undefined ? '' : issue.expected,
    actualType: issue === undefined ? '' : issue.actualType,
  });
}

@ObservedV2
export class DouyinNativeFeed {
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace refreshError: string = '';
  @Trace hasMore: boolean = true;
  @Trace loaded: boolean = false;
  private source: DouyinListSource = 'recommended';
  private cursor: string = '';
  private disposed: boolean = false;
  private generation: number = 0;
  private api: DouyinApi = new DouyinApi();
  private sessionCookie: string = '';
  private secUid: string = '';

  configure(source: DouyinListSource, cards: DouYinCardListModel): void {
    if (source === this.source) { return; }
    this.generation++; this.loading = false; this.source = source;
    this.reset(cards);
  }

  private reset(cards: DouYinCardListModel): void {
    this.cursor = ''; this.hasMore = true; this.loaded = false; this.error = '';
    this.secUid = ''; this.refreshError = ''; cards.cardList = null;
  }

  activate(): void { this.disposed = false; }
  dispose(cards?: DouYinCardListModel): void {
    this.disposed = true; this.generation++; this.loading = false;
    this.sessionCookie = ''; this.secUid = ''; this.refreshError = '';
    if (cards !== undefined && this.source !== 'recommended') { this.reset(cards); }
  }
  private current(generation: number): boolean { return !this.disposed && generation === this.generation; }

  private responseText(response: http.HttpResponse): string {
    const isString = typeof response.result === 'string';
    if ((response.responseCode === 401 || response.responseCode === 403) && isString) {
      // 安全插件拦截体是一句固定短文本(如 'Blocked by ArgusSecurityPlugin Uifid Not Found'),非敏感数据。
      // 过去只特判 'Signature Not Found' 一种,导致 Uifid Not Found 等被误归为登录失效。这里识别整族并显形原因。
      const trimmed = (response.result as string).trim();
      const marker = 'Blocked by ArgusSecurityPlugin';
      if (trimmed.startsWith(marker)) {
        const reason = trimmed.substring(marker.length).trim() || 'Unknown';
        console.warn(logTag, 'DOUYIN_NATIVE security-block http=' + response.responseCode +
          ' reason=' + JSON.stringify(reason) + ' source=' + this.source);
        throw new DouyinAuthorizationError('Douyin security block: ' + reason, response.responseCode, reason);
      }
    }
    if (response.responseCode === 401 || response.responseCode === 403) {
      // 非安全插件的 401/403:保持原有语义(登录失效),但仍把可诊断的元数据打出来。
      console.warn(logTag, 'DOUYIN_NATIVE auth-fail http=' + response.responseCode + ' stringResult=' + isString +
        ' bodyLen=' + (isString ? (response.result as string).length : -1) + ' source=' + this.source);
      throw new DouyinAuthorizationError('Douyin authorization required', response.responseCode);
    }
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new DouyinHttpError(response.responseCode,
        typeof response.result === 'string' ? response.result.length : -1,
        typeof response.result === 'string');
    }
    return response.result;
  }

  async load(cards: DouYinCardListModel): Promise<void> {
    console.debug(logTag, 'DOUYIN_NATIVE list begin source=' + this.source + ' cursor=' + this.cursor +
      ' hasMore=' + this.hasMore + ' loaded=' + this.loaded + ' loading=' + this.loading +
      ' disposed=' + this.disposed + ' generation=' + this.generation);
    if (this.loading || !this.hasMore || this.disposed) {
      const reason = this.loading ? 'loading' : (!this.hasMore ? 'noMore' : 'disposed');
      console.debug(logTag, 'DOUYIN_NATIVE list skip reason=' + reason + ' generation=' + this.generation);
      return;
    }
    this.loading = true;
    const generation = this.generation;
    const startedAt = Date.now();
    this.error = '';
    try {
      console.debug(logTag, 'DOUYIN_NATIVE list cookie-read begin generation=' + generation);
      const cookieBegin = Date.now();
      const cookie = await DouyinCookieStore.read();
      // 绝不打印 cookie 内容,只打印长度。
      console.debug(logTag, 'DOUYIN_NATIVE list cookie-read ok len=' + cookie.length +
        ' elapsed=' + (Date.now() - cookieBegin) + 'ms generation=' + generation);
      if (!this.current(generation)) {
        console.warn(logTag, 'DOUYIN_NATIVE list abort stale-generation=' + generation + ' current=' + this.generation);
        return;
      }
      // Never append a second account's personal list into the first account's cards.
      if (this.sessionCookie.length > 0 && this.sessionCookie !== cookie) {
        console.warn(logTag, 'DOUYIN_NATIVE list reset cross-account generation=' + generation);
        this.reset(cards);
      }
      this.sessionCookie = cookie;
      if (this.source === 'liked' && this.secUid.length === 0) {
        console.debug(logTag, 'DOUYIN_NATIVE list secProfile begin generation=' + generation);
        const profileBegin = Date.now();
        const response = await this.api.selfProfile(cookie);
        if (!this.current(generation)) {
          console.warn(logTag, 'DOUYIN_NATIVE list abort stale-generation=' + generation + ' at=secProfile');
          return;
        }
        this.secUid = DouyinResponseDecoder.parseSelfProfile(this.responseText(response)).user.secUid;
        console.debug(logTag, 'DOUYIN_NATIVE list secProfile ok len=' + this.secUid.length +
          ' elapsed=' + (Date.now() - profileBegin) + 'ms generation=' + generation);
      }
      const oldCount = cards.cardList?.length ?? 0;
      console.debug(logTag, 'DOUYIN_NATIVE list append-begin oldCount=' + oldCount + ' generation=' + generation);
      // Duplicate-only and non-video pages must not strand the last visible row.
      // Keep each user-triggered load bounded; surface a retry rather than spin forever.
      for (let attempt = 0; attempt < 3; attempt++) {
        console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) + '/3 begin cursor=' + this.cursor +
          ' generation=' + generation);
        const requestBegin = Date.now();
        const response = this.source === 'recommended' ?
          await this.api.request(cookie, true, '', 'valid', this.cursor) :
          await this.api.library(cookie, this.source, this.cursor, this.secUid);
        console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) + ' http=' + response.responseCode +
          ' elapsed=' + (Date.now() - requestBegin) + 'ms cursor=' + this.cursor + ' generation=' + generation);
        if (!this.current(generation)) {
          console.warn(logTag, 'DOUYIN_NATIVE list abort stale-generation=' + generation +
            ' at=attempt' + (attempt + 1));
          return;
        }
        const data = DouyinResponseDecoder.parseFeed(this.responseText(response));
        console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) + ' decode items=' + data.items.length +
          ' generation=' + generation);
        const page = DouyinPagination.next(data, this.cursor, this.source);
        cards.appendVideoList(DouyinFeedMapping.feed(data));
        this.cursor = page.cursor; this.hasMore = page.hasMore; this.loaded = true;
        const added = (cards.cardList?.length ?? 0) - oldCount;
        console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) + ' page nextCursor=' + page.cursor +
          ' hasMore=' + page.hasMore + ' newTotal=' + (cards.cardList?.length ?? 0) + ' generation=' + generation);
        console.info('DOUYIN_NATIVE list source=' + this.source + ' http=200 received=' + data.items.length +
          ' added=' + added + ' hasMore=' + this.hasMore);
        if (added > 0 || !this.hasMore) {
          console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) + ' done added=' + added +
            ' totalElapsed=' + (Date.now() - startedAt) + 'ms generation=' + generation);
          return;
        }
        console.debug(logTag, 'DOUYIN_NATIVE list attempt=' + (attempt + 1) +
          ' added=0 continue generation=' + generation);
      }
      console.warn(logTag, 'DOUYIN_NATIVE list exhausted attempts=3 lastAdded=0 totalElapsed=' +
        (Date.now() - startedAt) + 'ms generation=' + generation);
      this.error = '本批没有新的视频，点击重试继续加载';
    } catch (error) {
      if (this.current(generation)) {
        console.warn(logTag, 'DOUYIN_NATIVE list FAILED ' + describeError(error as Error) + ' source=' + this.source +
          ' cursor=' + this.cursor + ' generation=' + generation + ' current=' + this.generation +
          ' elapsed=' + (Date.now() - startedAt) + 'ms');
        if (error instanceof DouyinAuthorizationError) {
          this.secUid = '';
          if (error.reason === 'Signature Not Found') {
            this.error = '网页签名未被接口接受，请重试；若持续失败需更新签名实现';
          } else if (error.reason === 'Uifid Not Found') {
            this.error = 'Cookie 缺少访客身份 uifid，请重新登录抖音以补齐后重试';
          } else if (error.reason.length > 0) {
            this.error = '抖音安全校验拦截（' + error.reason + '），请重试或重新登录';
          } else {
            this.error = '抖音登录已失效或请求被拒绝，请到“我的”重新登录';
          }
        } else if (error instanceof JsonDecodeError) {
          logDecodeFailure(error, 'list');
          this.error = error.issues.some((issue: DecodeIssue) => issue.code === 'LIMIT_EXCEEDED') ?
            '数据过大，已停止加载以保护内存，请重试' : '抖音返回数据异常，请重试；若持续失败请重新登录';
        } else { this.error = '加载失败，请检查网络和登录状态后重试'; }
      }
    } finally {
      console.debug(logTag, 'DOUYIN_NATIVE list end generation=' + generation +
        ' isCurrent=' + (generation === this.generation));
      if (generation === this.generation) { this.loading = false; }
    }
  }

  async refresh(cards: DouYinCardListModel, id: string | null): Promise<void> {
    console.debug(logTag, 'DOUYIN_NATIVE detail begin id=' + id + ' source=' + this.source +
      ' loading=' + this.loading + ' disposed=' + this.disposed + ' generation=' + this.generation);
    if (this.loading || !id || this.disposed) {
      const reason = this.loading ? 'loading' : (!id ? 'no-id' : 'disposed');
      console.debug(logTag, 'DOUYIN_NATIVE detail skip reason=' + reason + ' generation=' + this.generation);
      return;
    }
    this.loading = true;
    const generation = this.generation;
    const startedAt = Date.now();
    this.refreshError = '';
    try {
      const cookieBegin = Date.now();
      const cookie = await DouyinCookieStore.read();
      // 绝不打印 cookie 内容,只打印长度。
      console.debug(logTag, 'DOUYIN_NATIVE detail cookie-read ok len=' + cookie.length +
        ' elapsed=' + (Date.now() - cookieBegin) + 'ms generation=' + generation);
      if (!this.current(generation)) {
        console.warn(logTag, 'DOUYIN_NATIVE detail abort stale-generation=' + generation + ' current=' + this.generation);
        return;
      }
      const requestBegin = Date.now();
      const response = await this.api.request(cookie, false, id);
      console.debug(logTag, 'DOUYIN_NATIVE detail http=' + response.responseCode +
        ' elapsed=' + (Date.now() - requestBegin) + 'ms id=' + id + ' generation=' + generation);
      if (!this.current(generation)) {
        console.warn(logTag, 'DOUYIN_NATIVE detail abort stale-generation=' + generation + ' at=response');
        return;
      }
      const data = DouyinResponseDecoder.parseDetail(this.responseText(response), id);
      const item = DouyinFeedMapping.item(data.item);
      if (item === undefined) {
        console.warn(logTag, 'DOUYIN_NATIVE detail decode ok but not-video id=' + id + ' generation=' + generation);
        throw new Error('Detail is not video');
      }
      cards.refreshVideo(item);
      console.info('DOUYIN_NATIVE detail http=200 refreshed=true');
    } catch (error) {
      if (this.current(generation)) {
        if (error instanceof JsonDecodeError) { logDecodeFailure(error, 'detail'); }
        console.warn(logTag, 'DOUYIN_NATIVE detail FAILED ' + describeError(error as Error) + ' id=' + id +
          ' source=' + this.source + ' generation=' + generation + ' current=' + this.generation +
          ' elapsed=' + (Date.now() - startedAt) + 'ms');
        this.refreshError = '刷新播放链接失败，保留原链接';
      }
    } finally {
      console.debug(logTag, 'DOUYIN_NATIVE detail end generation=' + generation +
        ' isCurrent=' + (generation === this.generation));
      if (generation === this.generation) { this.loading = false; }
    }
  }
}
