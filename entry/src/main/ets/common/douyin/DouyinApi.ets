import http from '@ohos.net.http';
import { logTag } from '../printLog';
import { DouyinWebSign } from './DouyinWebSign';
import { DouyinRequestBuilder, DouyinRequestSpec, SignatureMode as RequestSignatureMode } from './DouyinRequestBuilder';
import { LogEvents } from '../../utils/log/LogEvents.generated';
export type SignatureMode = RequestSignatureMode;

/** Read-only API. No favorite/like mutations are performed by the application. */
export class DouyinApi {
  async request(cookie: string, feed: boolean, awemeId: string = '',
    mode: SignatureMode = 'valid', cursor: string = ''): Promise<http.HttpResponse> {
    return this.send(cookie, feed ? DouyinRequestBuilder.feed(cursor, mode) : DouyinRequestBuilder.detail(awemeId, mode));
  }

  async selfProfile(cookie: string): Promise<http.HttpResponse> {
    return this.send(cookie, DouyinRequestBuilder.selfProfile());
  }

  async library(cookie: string, source: 'collected' | 'liked', cursor: string = '', secUid: string = ''): Promise<http.HttpResponse> {
    return this.send(cookie, DouyinRequestBuilder.library(source, cursor, secUid));
  }

  private async send(cookie: string, spec: DouyinRequestSpec): Promise<http.HttpResponse> {
    DouyinRequestBuilder.validateCookie(cookie);
    const prepared = DouyinRequestBuilder.authenticate(spec, cookie);
    const headers = DouyinRequestBuilder.headers(cookie, prepared.method, prepared.signatureHeaders);
    // 诊断日志:只报路径/方法/长度/布尔,绝不输出 cookie、uifid、签名值或 query 正文。
    const protectedPath = DouyinWebSign.isProtected(spec.path);
    const signed = prepared.signatureHeaders['x-secsdk-web-signature'] !== undefined;
    console.debug(logTag, 'DOUYIN_NATIVE http ' + prepared.method + ' path=' + spec.path +
      ' protected=' + protectedPath + ' signed=' + signed + ' ' + DouyinWebSign.identitySummary(cookie) +
      ' queryLen=' + prepared.query.length + ' bodyLen=' + prepared.body.length +
      ' headerCount=' + Object.keys(headers).length);
    if (protectedPath && !signed) {
      console.warn(logTag, 'DOUYIN_NATIVE http UNSIGNED-ON-PROTECTED path=' + spec.path +
        ' —— 受保护端点却没挂上网页签名(十有八九是 cookie 缺 uifid)，服务端会回 403');
    }
    const options: http.HttpRequestOptions = {
      method: prepared.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: headers, expectDataType: http.HttpDataType.STRING,
      usingProtocol: http.HttpProtocol.HTTP1_1, usingCache: false,
      connectTimeout: 15000, readTimeout: 30000, maxRedirects: 0
    };
    if (prepared.body.length > 0) { options.extraData = prepared.body; }
    const client = http.createHttp();
    const started: number = Date.now();
    try {
      const response = await client.request('https://www.douyin.com' + prepared.path + '?' + prepared.query, options);
      LogEvents.douyinRequestDone({
        path: spec.path,
        method: prepared.method,
        status: response.responseCode,
        elapsedMs: Date.now() - started,
      });
      return response;
    } catch (error) {
      LogEvents.douyinRequestFailed({ path: spec.path, method: prepared.method }, error as Object);
      throw error as Error;
    } finally { client.destroy(); }
  }
}
