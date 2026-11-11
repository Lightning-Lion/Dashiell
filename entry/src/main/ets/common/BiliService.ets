import { getBiliSessionEpoch, isCurrentBiliSessionEpoch, assertBiliSessionEpoch } from './BiliSession';
import { BiliMediaDecoder } from './bili/BiliMediaDecoder';
import { BiliMediaMapping } from './bili/BiliMediaMapping';
import { BiliSearchResponse, BiliCidResponse, BiliNavResponse } from './bili/schema/BiliModels.generated';
import { BiliFavoriteMapping } from './bili/BiliFavoriteMapping';
import { BiliResponseDecoder } from './bili/BiliResponseDecoder';
import { JsonDecodeError } from './jsonschema/JsonDecode';
import { BusinessError } from '@kit.BasicServicesKit';
import { FavoriteFoldersResponse, FavoriteContentsResponse, FavoriteFolderResponse, FavoriteResponse } from './BiliFavoriteModels';
import http from '@ohos.net.http';
import { BiliHotSearchItem, parseBiliHotSearch } from './BiliHotSearch';
import { BiliHomeFeedApiResponse } from './bili/BiliMediaModels';
import {
  BiliAddToFavoriteApiResponse,
  BiliFolderListAllApiResponse,
  BiliMidApiResponse
} from '../pages/BiliVideoDetailPage/AddToFavoritePage';
import { BiliHasCoinBeenInsertedApiResponse } from '../pages/BiliVideoDetailPage/BiliCoinView';
import { BiliHasFavoriteApiResponse } from '../pages/BiliVideoDetailPage/BiliFavoriteView';
import { BiliInsertCoinApiResponse } from '../pages/BiliVideoDetailPage/BiliInsertCoinPage';
import {
  BiliDislikeApiResponse,
  BiliHasLikeApiResponse,
  BiliLikeApiResponse
} from '../pages/BiliVideoDetailPage/BiliLikeView';
import { LogEvents } from '../utils/log/LogEvents.generated';
import {
  BiliHistoryApiResponse,
  BiliHistoryCursor,
  BiliHistoryItem,
  BiliHistoryItemHistory,
  BiliHistoryTab,
  BiliHistoryListResponse
} from './BiliHistoryModels';
import { BiliVideoDetailApiResponse } from '../pages/BiliVideoDetailPage/BiliVideoDetailPage';
import { BiliVideoPlaybackApiResponse } from '../pages/BiliVideoPlayer/BiliVideoPlayerPage';
import { PersonalizedSettingsPersist } from '../pages/Settings/PersonalizedSettingsPage';
import { getUPsVideos, GetUPsVideosResponseDataListVlistItem } from './Wbi';

@ObservedV2
export class GetHomeFeedError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ObservedV2
export class RequestSearchError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ObservedV2
export class LikeError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ObservedV2
export class CoinError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ObservedV2
export class FavoriteError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ObservedV2
export class CurrentUserInfoError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

export interface BiliCurrentUserStatData {
  following?: number;
  follower?: number;
  dynamic_count?: number;
}

export interface BiliCurrentUserStatResponse {
  code: number;
  message?: string;
  ttl?: number;
  data?: BiliCurrentUserStatData;
}

export interface BiliCurrentUserCardSummary {
  following?: number;
  follower?: number;
}

export interface BiliCurrentUserCardData {
  card?: BiliCurrentUserCardSummary;
  following?: boolean;
  follower?: number;
}

export interface BiliCurrentUserCardResponse {
  code: number;
  message?: string;
  ttl?: number;
  data?: BiliCurrentUserCardData;
}

export interface BiliCurrentUserCoinData {
  money?: number;
}

export interface BiliCurrentUserCoinResponse {
  code: number;
  message?: string;
  ttl?: number;
  data?: BiliCurrentUserCoinData;
}

export interface BiliFollowingItem {
  mid: number;
  uname?: string;
  face?: string;
  sign?: string;
}

export interface BiliFollowingListData {
  list?: BiliFollowingItem[];
  total?: number;
}

export interface BiliFollowingListResponse {
  code: number;
  message?: string;
  ttl?: number;
  data?: BiliFollowingListData;
}

export class BilibiliServiceWithoutLogin {
  // https://github.com/pskdje/bilibili-API-collect/blob/main/docs/search/hot.md
  static async getHotSearch(): Promise<BiliHotSearchItem[]> {
    const request = http.createHttp();
    try {
      const response = await request.request(
        'https://api.bilibili.com/x/web-interface/wbi/search/square?limit=20&platform=web',
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://www.bilibili.com/'
          },
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 5000,
          readTimeout: 8000
        }
      );
      if (response.responseCode !== 200) {
        throw new Error(`热搜榜请求失败（HTTP ${response.responseCode}）`);
      }
      return parseBiliHotSearch(BiliResponseDecoder.responseText(response.result));
    } finally {
      request.destroy();
    }
  }

  protected httpRequestDestroyed: boolean = false
  private activeRequests: Set<http.HttpRequest> = new Set();

  protected async requestHTTP(address: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    if (this.httpRequestDestroyed) { throw new Error('请求已取消，请重新进入页面'); }
    // Independent handles allow search, details and recommendations to run concurrently.
    // No idle handle survives a network change; always release on success and failure.
    const started: number = Date.now();
    const endpoint: string = BilibiliServiceWithoutLogin.endpointOf(address);
    const method: string = BilibiliServiceWithoutLogin.methodOf(options);
    const request = http.createHttp();
    this.activeRequests.add(request);
    try {
      const response = await request.request(address, options);
      LogEvents.biliRequestDone({
        endpoint: endpoint,
        method: method,
        status: response.responseCode,
        elapsedMs: Date.now() - started,
      });
      return response;
    } catch (error) {
      LogEvents.biliRequestFailed({ endpoint: endpoint, method: method }, error as Object);
      throw error as Error;
    } finally {
      if (this.activeRequests.delete(request)) { request.destroy(); }
    }
  }

  private static endpointOf(address: string): string {
    const scheme: number = address.indexOf('://');
    const start: number = scheme >= 0 ? address.indexOf('/', scheme + 3) : 0;
    if (start < 0) {
      return address;
    }
    const query: number = address.indexOf('?', start);
    return query >= 0 ? address.substring(start, query) : address.substring(start);
  }

  private static methodOf(options: http.HttpRequestOptions): string {
    return options.method === http.RequestMethod.POST ? 'POST' : 'GET';
  }

  protected static logDecodeFailure(error: JsonDecodeError, operation: string): void {
    const issue = error.issues.length > 0 ? error.issues[0] : undefined;
    LogEvents.biliDecodeFailed({
      operation: operation,
      schema: error.schema,
      issueCount: error.issues.length,
      code: issue === undefined ? '' : issue.code,
      path: issue === undefined ? '' : issue.pathText(),
      expected: issue === undefined ? '' : issue.expected,
      actualType: issue === undefined ? '' : issue.actualType,
    });
  }
  protected ua: string =
    "Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile HuaweiBrowser/5.1.4.305"

  // 获取首页推荐
  async getHomeFeed(queryParams: string): Promise<BiliHomeFeedApiResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new GetHomeFeedError(`获取首页推荐失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?${queryParams}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/?spm_id_from=333.1245.0.0',
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9'
        },
        connectTimeout: 5000,
        readTimeout: 10000
      }
    );

    if (response.responseCode === 200) {
      const data = BiliMediaMapping.home(BiliMediaDecoder.parseHome(BiliResponseDecoder.responseText(response.result)));
      return data
    } else {
      throw new GetHomeFeedError(`🚩获取首页推荐请求HTTP错误: ${response.responseCode}`)
    }
  }

  async requestSearch(queryParams: string): Promise<BiliSearchResponse> {

    if (this.httpRequestDestroyed === true) {
      throw new Error(`获取视频播放链接失败：http.HttpRequest已destroy。`)
    }

    try {
      // 这个CookieString只是为了能正常搜索，不起到个性化推荐作用。
      const defaultCookieString: string = 'SESSDATA='
      const response = await this.requestHTTP(
        `https://api.bilibili.com/x/web-interface/search/type?${queryParams}`,
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': this.ua,
            'Referer': 'https://www.bilibili.com/',
            'Cookie': defaultCookieString
          },
          connectTimeout: 5000,
          readTimeout: 10000
        }
      )
      if (response.responseCode === 200) {
        return BiliMediaDecoder.parseSearch(BiliResponseDecoder.responseText(response.result));
      } else {
        throw new RequestSearchError(`[RequestSearchError] 搜索请求失败，responseCode：${response.responseCode}`)
      }
    } catch (e) {
      if (e instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(e, 'search');
        throw e;
      }
      console.warn("搜索请求失败")
      throw new RequestSearchError(`[RequestSearchError.catch] ${e.message} ${e.code}`)
    }
  }

  async requestVideoDetail(bvid: string): Promise<BiliCidResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new Error(`获取视频播放链接失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/wbi/view?bvid=${bvid}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': 'SESSDATA='
        }
      }
    )
    if (response.responseCode !== 200) { throw new Error('分P查询失败（HTTP ' + response.responseCode + '）'); }
    return BiliMediaDecoder.parseCid(BiliResponseDecoder.responseText(response.result), bvid);
  }


  async getVideoPlayUrl(bvid: string, cid: string): Promise<BiliVideoPlaybackApiResponse> {
    try {
      const url =
        `https://api.bilibili.com/x/player/playurl?bvid=${encodeURIComponent(bvid)}&cid=${encodeURIComponent(cid)}&platform=html5&otype=json&qn=16&type=mp4&html5=1&web_location=333.400`
      if (this.httpRequestDestroyed === true) {
        throw new Error(`获取视频播放链接失败：http.HttpRequest已destroy。`)
      }
      const response = await this.requestHTTP(
        url,
        {
          method: http.RequestMethod.GET,
          header: {
            'Content-Type': 'application/json'
          },
          readTimeout: 10000,
          connectTimeout: 10000
        }
      );
      if (response.responseCode === 200) {
        console.debug("🚩response.responseCode：", response.responseCode);
        const responseData = BiliMediaDecoder.parsePlayback(BiliResponseDecoder.responseText(response.result));
        return responseData;
      } else {
        console.debug(`🚩Network error: ${response.responseCode}`)
        throw new Error(`Network error: ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(error, 'playurl');
        throw error;
      }
      throw new Error('🚩Failed to fetch video play url');
    }
  }

  // Format view count to readable format
  static formatViewCount(count: number): string {
    if (count >= 100000000) {
      return (count / 100000000).toFixed(1) + 'y'; // 亿
    } else if (count >= 10000) {
      return (count / 10000).toFixed(1) + 'w'; // 万
    }
    return count.toString();
  }

  // Format timestamp to date
  static formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp * 1000);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate()
      .toString()
      .padStart(2, '0')}`;
  }

  // Format video duration
  // Format video duration
  static formatDuration(seconds: number): string {
    if (!seconds) {
      return '0:00';
    }

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainingSeconds = seconds % 60;

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
    }

    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  // Format timestamp to date
  static formatPublishDate(timestamp: number): string {
    if (!timestamp) {
      return '';
    }

    const now = new Date();
    const publishDate = new Date(timestamp * 1000);
    const diffTime = Math.abs(now.getTime() - publishDate.getTime());
    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays < 1) {
      const diffHours = Math.floor(diffTime / (1000 * 60 * 60));
      if (diffHours < 1) {
        const diffMinutes = Math.floor(diffTime / (1000 * 60));
        return diffMinutes + ' minutes ago';
      }
      return diffHours + ' hours ago';
    } else if (diffDays < 7) {
      return diffDays + ' days ago';
    } else if (diffDays < 30) {
      return Math.floor(diffDays / 7) + ' weeks ago';
    } else {
      return publishDate.getFullYear() + '-' +
      (publishDate.getMonth() + 1).toString().padStart(2, '0') + '-' +
      publishDate.getDate().toString().padStart(2, '0');
    }
  }

  isReleased(): boolean { return this.httpRequestDestroyed; }

  forkForRequests(): BilibiliServiceWithoutLogin {
    return new BilibiliServiceWithoutLogin();
  }

  cancelPendingRequests(): void {
    this.activeRequests.forEach((request: http.HttpRequest) => request.destroy());
    this.activeRequests.clear();
  }

  releaseHttp(): void {
    this.httpRequestDestroyed = true;
    this.cancelPendingRequests();
  }
}

export class BilibiliService extends BilibiliServiceWithoutLogin {
  private authenticationEpoch: number = getBiliSessionEpoch();

  isSessionCurrent(): boolean { return isCurrentBiliSessionEpoch(this.authenticationEpoch); }

  protected async requestHTTP(address: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    assertBiliSessionEpoch(this.authenticationEpoch);
    const response = await super.requestHTTP(address, options);
    assertBiliSessionEpoch(this.authenticationEpoch);
    return response;
  }

  // Default cookie storage
  private cookieString: string
  private harmonyPCUA: string =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.196 Safari/537.36"
  private personalizedEnabled: Promise<boolean> | undefined = undefined

  constructor(cookie: string) {
    super()
    this.cookieString = cookie
  }

  forkForRequests(): BilibiliService {
    const scoped = new BilibiliService(this.cookieString);
    // Forking an old page after logout must not re-authorize its old Cookie.
    scoped.authenticationEpoch = this.authenticationEpoch;
    return scoped;
  }

  private getPersonalizedEnabled(): Promise<boolean> {
    if (this.personalizedEnabled === undefined) {
      this.personalizedEnabled = (async () => {
        const settings = await PersonalizedSettingsPersist.asyncInit(getContext())
        return settings.isEnablePersonalized()
      })()
    }
    return this.personalizedEnabled
  }

  // Each request owns its HTTP handle, so child pages cannot interrupt one another.
  private async requestFavorite(path: string, body?: string): Promise<string> {
    const started = Date.now();
    const endpoint = path.split("?")[0];
    console.info(`[FavoriteHTTP] start ${endpoint}`);
    try {
      const response = await this.requestHTTP(`https://api.bilibili.com${path}`, {
        method: body === undefined ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          'Cookie': this.cookieString,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        extraData: body === undefined ? '' : `${body}&csrf=${encodeURIComponent(this.extractCsrf(this.cookieString))}`,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      console.info(`[FavoriteHTTP] response ${endpoint} http=${response.responseCode} elapsed=${Date.now() - started}ms`);
      if (response.responseCode !== 200) {
        throw new Error(`收藏夹请求失败（HTTP ${response.responseCode}）`);
      }
      const text = BiliResponseDecoder.responseText(response.result);
      const result = BiliResponseDecoder.parseEnvelope(text);
      console.info(`[FavoriteHTTP] result ${endpoint} code=${result.code}`);
      if (result.code !== 0) {
        throw new Error(result.code === -101 ? '登录已失效，请重新登录' :
          `${result.message || '收藏夹请求失败'}（${result.code}）`);
      }
      return text;
    } catch (error) {
      if (error instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(error, 'favorite');
        throw error;
      }
      const failure = error as BusinessError;
      console.warn(`[FavoriteHTTP] failed ${endpoint} code=${failure.code} elapsed=${Date.now() - started}ms`);
      if (failure.code === 2300028) {
        throw new Error('请求超时，请检查手表网络后重试');
      }
      throw new Error(failure.message);
    }
  }

  async getFavoriteFolders(): Promise<FavoriteFoldersResponse> {
    const user = await this.getMid('');
    const response = BiliResponseDecoder.parseFavoriteFolders(await this.requestFavorite(
      `/x/v3/fav/folder/created/list-all?up_mid=${user.data.mid}`));
    return BiliFavoriteMapping.folders(response);
  }

  async getFavoriteContents(id: number, page: number): Promise<FavoriteContentsResponse> {
    const response = BiliResponseDecoder.parseFavoriteContents(await this.requestFavorite(
      `/x/v3/fav/resource/list?media_id=${id}&pn=${page}&ps=20&order=mtime&type=0&platform=web`));
    return BiliFavoriteMapping.contents(response);
  }

  async getHistoryList(cursor?: BiliHistoryCursor): Promise<BiliHistoryListResponse> {
    const query: string[] = ['ps=20', 'type=archive'];
    if (cursor && cursor.max > 0) {
      query.push(`max=${encodeURIComponent(cursor.max.toString())}`);
    }
    if (cursor && cursor.viewAt > 0) {
      query.push(`view_at=${encodeURIComponent(cursor.viewAt.toString())}`);
    }
    if (cursor && cursor.business) {
      query.push(`business=${encodeURIComponent(cursor.business)}`);
    }
    const raw = BiliResponseDecoder.parseHistory(await this.requestFavorite(`/x/web-interface/history/cursor?${query.join('&')}`));
    const data = raw.data;
    return {
      code: raw.code,
      message: raw.message ?? '',
      ttl: raw.ttl ?? 0,
      data: data ? {
        cursor: data.cursor ? {
          max: Number(data.cursor.max ?? 0),
          viewAt: Number(data.cursor.view_at ?? 0),
          business: data.cursor.business ? String(data.cursor.business) : undefined
        } : undefined,
        tab: data.tab ? data.tab.map((item): BiliHistoryTab => ({
          type: item.type ?? '',
          name: item.name ?? ''
        })) : [],
        list: data.list ? data.list.map((item): BiliHistoryItem => ({
          title: item.title ?? '',
          long_title: item.long_title,
          cover: item.cover,
          uri: item.uri,
          history: item.history ? {
            oid: item.history.oid,
            epid: item.history.epid,
            bvid: item.history.bvid,
            page: item.history.page,
            cid: item.history.cid,
            part: item.history.part,
            business: item.history.business
          } as BiliHistoryItemHistory : undefined,
          videos: item.videos,
          author_name: item.author_name,
          author_face: item.author_face,
          author_mid: item.author_mid,
          view_at: item.view_at,
          progress: item.progress,
          badge: item.badge,
          show_title: item.show_title,
          duration: item.duration,
          is_finish: item.is_finish,
          is_fav: item.is_fav,
          kid: item.kid,
          tag_name: item.tag_name,
          live_status: item.live_status,
          business: item.business
        })) : []
      } : undefined
    };
  }

  async editFavoriteFolder(id: number, title: string, isPrivate: boolean): Promise<void> {
    // Preserve metadata that is not exposed by the watch editor.
    const response = BiliResponseDecoder.parseFavoriteFolder(await this.requestFavorite(`/x/v3/fav/folder/info?media_id=${id}`));
    await this.requestFavorite('/x/v3/fav/folder/edit',
      `media_id=${id}&title=${encodeURIComponent(title.trim())}&privacy=${isPrivate ? 1 : 0}` +
      `&intro=${encodeURIComponent(response.data.intro || '')}&cover=${encodeURIComponent(response.data.cover || '')}`);
  }

  // 获取首页推荐
  async getHomeFeed(queryParams: string): Promise<BiliHomeFeedApiResponse> {
    // 获取个性化推荐开关
    const enablePersonalized: boolean =
      await this.getPersonalizedEnabled()
    // 鸿蒙电脑UA
    if (this.httpRequestDestroyed === true) {
      throw new GetHomeFeedError(`获取首页推荐失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?${queryParams}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.harmonyPCUA,
          'Referer': 'https://www.bilibili.com/?spm_id_from=333.1245.0.0',
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': enablePersonalized ? this.cookieString : "",
        },
        connectTimeout: 5000,
        readTimeout: 10000
      }
    );

    if (response.responseCode === 200) {
      const data = BiliMediaMapping.home(BiliMediaDecoder.parseHome(BiliResponseDecoder.responseText(response.result)));
      return data
    } else {
      throw new GetHomeFeedError(`🚩获取首页推荐请求HTTP错误: ${response.responseCode}`)
    }
  }

  async requestSearch(queryParams: string): Promise<BiliSearchResponse> {

    // 获取个性化推荐开关
    const enablePersonalized: boolean =
      await this.getPersonalizedEnabled()
    if (this.httpRequestDestroyed === true) {
      throw new Error(`获取视频播放链接失败：http.HttpRequest已destroy。`)
    }

    try {

      // 这个CookieString只是为了能正常搜索，不起到个性化推荐作用。
      const defaultCookieString: string = 'SESSDATA='

      const response = await this.requestHTTP(
        `https://api.bilibili.com/x/web-interface/search/type?${queryParams}`,
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': this.ua,
            'Referer': 'https://www.bilibili.com/',
            // 如果登录了，传自己的Cookie，获得个性化推荐，如果没有登录，传defaultCookieString，确保能正常搜索（直接传空字符串会导致无法正常搜索）
            'Cookie': enablePersonalized ? this.cookieString : defaultCookieString,
          },
          connectTimeout: 5000,
          readTimeout: 10000
        }
      )
      if (response.responseCode === 200) {
        return BiliMediaDecoder.parseSearch(BiliResponseDecoder.responseText(response.result));
      } else {
        throw new RequestSearchError(`[RequestSearchError] 搜索请求失败，responseCode：${response.responseCode}`)
      }
    } catch (e) {
      if (e instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(e, 'search');
        throw e;
      }
      console.warn("搜索请求失败")
      throw new RequestSearchError(`[RequestSearchError.catch] ${e.message} ${e.code}`)
    }
  }


  async getHomeFeedHuawei(pn: number): Promise<GetUPsVideosResponseDataListVlistItem[]> {
    const mid: string = "102999485"
    const referer: string = "https://space.bilibili.com/" + mid + "/upload/video"
    const result = await getUPsVideos(mid, pn.toString(), this.cookieString, this.harmonyPCUA, referer)
    return result
  }

  // Get video details
  async getVideoDetails(bvid: string): Promise<BiliVideoDetailApiResponse> {
    try {
      const url =
        `https://api.bilibili.com/x/web-interface/wbi/view/detail?platform=web&bvid=${encodeURIComponent(bvid)}&need_operation_card=1&web_rm_repeat=1&need_elec=1&out_referer=&page_no=1&p=1&web_location=1446382&gaia_source=main_web&from_spmid=&spmid=333.788.0.0&from_trackid=`;
      if (this.httpRequestDestroyed === true) {
        throw new Error(`获取视频详情失败：http.HttpRequest已destroy。`)
      }
      const response = await this.requestHTTP(
        url,
        {
          method: http.RequestMethod.GET,
          header: {
            'Content-Type': 'application/json',
            'Cookie': this.cookieString
          },
          readTimeout: 10000,
          connectTimeout: 10000
        }
      );
      console.debug("🚩请求到了内容")
      if (response.responseCode === 200) {
        console.debug("🚩response.responseCode：", response.responseCode);
        const responseData = BiliMediaDecoder.parseDetail(BiliResponseDecoder.responseText(response.result), bvid);
        return responseData;
      } else {
        console.debug(`🚩Network error: ${response.responseCode}`)
        throw new Error(`Network error: ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(error, 'detail');
        throw error;
      }
      throw new Error('🚩Failed to fetch video details');
    }
  }

  // Get playing url
  async getVideoPlayUrl(bvid: string, cid: string): Promise<BiliVideoPlaybackApiResponse> {
    try {
      const url =
        `https://api.bilibili.com/x/player/playurl?bvid=${encodeURIComponent(bvid)}&cid=${encodeURIComponent(cid)}&platform=html5&otype=json&qn=16&type=mp4&html5=1&web_location=333.400`
      if (this.httpRequestDestroyed === true) {
        throw new Error(`获取视频播放链接失败：http.HttpRequest已destroy。`)
      }
      const response = await this.requestHTTP(
        url,
        {
          method: http.RequestMethod.GET,
          header: {
            'Content-Type': 'application/json',
            'Cookie': this.cookieString
          },
          readTimeout: 10000,
          connectTimeout: 10000
        }
      );
      if (response.responseCode === 200) {
        console.debug("🚩response.responseCode：", response.responseCode);
        const responseData = BiliMediaDecoder.parsePlayback(BiliResponseDecoder.responseText(response.result));
        return responseData;
      } else {
        console.debug(`🚩Network error: ${response.responseCode}`)
        throw new Error(`Network error: ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof JsonDecodeError) {
        BilibiliServiceWithoutLogin.logDecodeFailure(error, 'playurl');
        throw error;
      }
      throw new Error('🚩Failed to fetch video play url');
    }
  }

  async hasLike(bvid: string): Promise<BiliHasLikeApiResponse> {
    // 发起请求
    if (this.httpRequestDestroyed === true) {
      throw new LikeError(`查询点赞状态失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/archive/has/like?bvid=${encodeURIComponent(bvid)}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': `https://www.bilibili.com/video/${bvid}/?spm_id_from=333.1387.homepage.video_card.click`,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': this.cookieString,
        }
      }
    );

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseLikeStateResponse(BiliResponseDecoder.responseText(response.result));
      const mapped: BiliHasLikeApiResponse = { code: data.code, message: data.message ?? '', ttl: data.ttl ?? 0, data: data.data };
      return mapped;
    } else {
      throw new LikeError(`🚩查询点赞状态请求HTTP错误: ${response.responseCode}`)
    }
  }

  async like(bvid: string): Promise<BiliLikeApiResponse> {
    // 发起请求
    if (this.httpRequestDestroyed === true) {
      throw new LikeError(`点赞失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/archive/like`,
      {
        method: http.RequestMethod.POST,
        header: {
          'User-Agent': this.ua,
          'Referer': `https://www.bilibili.com/video/${bvid}/?spm_id_from=333.1387.homepage.video_card.click`,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': this.cookieString,
          "Content-Type": "application/x-www-form-urlencoded"
        },
        extraData: `bvid=${encodeURIComponent(bvid)}&like=1&csrf=${this.extractCsrf(this.cookieString)}`
      }
    );

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseActionResponse(BiliResponseDecoder.responseText(response.result));
      const mapped: BiliLikeApiResponse = { code: data.code, message: data.message ?? '', ttl: data.ttl ?? 0 };
      return mapped;
    } else {
      throw new LikeError(`🚩点赞请求HTTP错误: ${response.responseCode}`)
    }
  }

  async disLike(bvid: string): Promise<BiliDislikeApiResponse> {
    // 发起请求
    if (this.httpRequestDestroyed === true) {
      throw new LikeError(`点赞失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/archive/like`,
      {
        method: http.RequestMethod.POST,
        header: {
          'User-Agent': this.ua,
          'Referer': `https://www.bilibili.com/video/${bvid}/?spm_id_from=333.1387.homepage.video_card.click`,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': this.cookieString,
          "Content-Type": "application/x-www-form-urlencoded"
        },
        extraData: `bvid=${encodeURIComponent(bvid)}&like=2&csrf=${this.extractCsrf(this.cookieString)}`
      }
    );

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseActionResponse(BiliResponseDecoder.responseText(response.result));
      const mapped: BiliDislikeApiResponse = { code: data.code, message: data.message ?? '', ttl: data.ttl ?? 0 };
      return mapped;
    } else {
      throw new LikeError(`🚩取消点赞请求HTTP错误: ${response.responseCode}`)
    }
  }

  async hasCoinInserted(bvid: string): Promise<BiliHasCoinBeenInsertedApiResponse> {
    // 发起请求
    if (this.httpRequestDestroyed === true) {
      throw new CoinError(`查询投币状态失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/archive/coins?bvid=${encodeURIComponent(bvid)}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': `https://www.bilibili.com/video/${bvid}/?spm_id_from=333.1387.homepage.video_card.click`,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': this.cookieString,
        }
      }
    );

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseCoinStateResponse(BiliResponseDecoder.responseText(response.result));
      const mapped: BiliHasCoinBeenInsertedApiResponse = { code: data.code, message: data.message ?? '', ttl: data.ttl ?? 0, data: { multiply: data.data.multiply } };
      return mapped;
    } else {
      throw new CoinError(`🚩查询投币状态HTTP错误: ${response.responseCode}`)
    }
  }

  async insertCoin(bvid: string, multiply: number): Promise<BiliInsertCoinApiResponse> {
    // 发起请求
    if (this.httpRequestDestroyed === true) {
      throw new CoinError(`投币失败：http.HttpRequest已destroy。`)
    }
    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/coin/add`,
      {
        method: http.RequestMethod.POST,
        header: {
          'User-Agent': this.ua,
          'Referer': `https://www.bilibili.com/video/${bvid}/?spm_id_from=333.1387.homepage.video_card.click`,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': this.cookieString,
          "Content-Type": "application/x-www-form-urlencoded"
        },
        // 固定不勾选“同时点赞内容”：本应用不维护点赞状态，避免产生无法回显的写操作
        extraData: `bvid=${encodeURIComponent(bvid)}&select_like=0&multiply=${multiply}&csrf=${this.extractCsrf(this.cookieString)}`
      }
    );

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseInsertCoinResponse(BiliResponseDecoder.responseText(response.result));
      const mapped: BiliInsertCoinApiResponse = { code: data.code, message: data.message ?? '', ttl: data.ttl ?? 0, data: { like: data.data.like } };
      return mapped;
    } else {
      throw new CoinError(`🚩投币请求HTTP错误: ${response.responseCode}`)
    }
  }

  async hasFavorite(avid: number, bvid: string): Promise<BiliHasFavoriteApiResponse> {
    const response = BiliResponseDecoder.parseFavoriteState(await this.requestFavorite(
      `/x/v2/fav/video/favoured?aid=${avid}`));
    const mapped: BiliHasFavoriteApiResponse = { code: response.code, message: response.message ?? '', ttl: response.ttl ?? 0, data: { favoured: response.data.favoured } };
    return mapped;
  }

  async getFolderListAll(mid: string, avidForIsInFavorite: number,
    bvidForReferer: string): Promise<BiliFolderListAllApiResponse> {
    const response = BiliResponseDecoder.parseFavoriteFolders(await this.requestFavorite(
      `/x/v3/fav/folder/created/list-all?type=2&rid=${avidForIsInFavorite}&up_mid=${encodeURIComponent(mid)}`));
    return BiliFavoriteMapping.folders(response);
  }

  async addToFavorite(avid: number, add_media_ids: Array<number>, del_media_ids: Array<number>,
    bvidForReferer: string): Promise<BiliAddToFavoriteApiResponse> {
    const response = BiliResponseDecoder.parseEnvelope(await this.requestFavorite('/x/v3/fav/resource/deal',
      `rid=${avid}&type=2&add_media_ids=${encodeURIComponent(add_media_ids.join(','))}` +
      `&del_media_ids=${encodeURIComponent(del_media_ids.join(','))}`));
    return { code: response.code, message: response.message ?? '' };
  }

  async getMid(bvidForReferer: string): Promise<BiliMidApiResponse> {
    const result = BiliResponseDecoder.parseMid(await this.requestFavorite('/x/web-interface/nav'));
    if (result.data.mid <= 0) { throw new FavoriteError('请先登录哔哩哔哩'); }
    const mapped: BiliMidApiResponse = { code: result.code, message: result.message ?? '', data: { mid: result.data.mid } };
    return mapped;
  }


  /**
   * Extracts the bili_jct value from a cookie string
   * @param cookieStr The cookie string to extract bili_jct from
   * @returns The bili_jct value
   * @throws Error if bili_jct is not found in the cookie string
   */
  extractCsrf(cookieStr: string): string {
    // Create a regular expression to match bili_jct=<value>
    const biliJctRegex = /bili_jct=([^;]+)/;

    // Try to match the regex in the cookie string
    const match = cookieStr.match(biliJctRegex);

    // If no match was found, throw an error
    if (!match) {
      throw new Error('bili_jct not found in cookie string');
    }
    // The captured value (the part after bili_jct=)
    const biliJct = match[1];
    const csrf = biliJct
    return csrf;
  }

  async getCurrentUserInfo(): Promise<BiliNavResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new CurrentUserInfoError(`获取当前用户信息失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/nav`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': this.cookieString
        }
      }
    )

    if (response.responseCode === 200) {
      const data = BiliMediaDecoder.parseNav(BiliResponseDecoder.responseText(response.result));
      return data
    } else {
      throw new CurrentUserInfoError(`🚩获取当前用户信息时HTTP错误: ${response.responseCode}`)
    }
  }

  async getCurrentUserStat(): Promise<BiliCurrentUserStatResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new CurrentUserInfoError(`获取当前用户状态失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/nav/stat`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': this.cookieString
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      }
    )

    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseUserStatResponse(BiliResponseDecoder.responseText(response.result));
      return data
    } else {
      throw new CurrentUserInfoError(`🚩获取当前用户状态时HTTP错误: ${response.responseCode}`)
    }
  }

  async getCurrentUserCard(mid: number): Promise<BiliCurrentUserCardResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new CurrentUserInfoError(`获取当前用户名片失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/web-interface/card?mid=${mid}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': this.cookieString
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      }
    )

    if (response.responseCode === 200) {
      return BiliResponseDecoder.parseUserCardResponse(BiliResponseDecoder.responseText(response.result));
    }
    throw new CurrentUserInfoError(`🚩获取当前用户名片时HTTP错误: ${response.responseCode}`)
  }

  async getCurrentUserCoin(): Promise<BiliCurrentUserCoinResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new CurrentUserInfoError(`获取当前硬币数失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://account.bilibili.com/site/getCoin`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': this.cookieString
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      }
    )

    if (response.responseCode === 200) {
      return BiliResponseDecoder.parseUserCoinResponse(BiliResponseDecoder.responseText(response.result));
    }
    throw new CurrentUserInfoError(`🚩获取当前硬币数时HTTP错误: ${response.responseCode}`)
  }

  async getFollowingList(vmid: number, page: number, pageSize: number = 20): Promise<BiliFollowingListResponse> {
    if (this.httpRequestDestroyed === true) {
      throw new CurrentUserInfoError(`获取关注列表失败：http.HttpRequest已destroy。`)
    }

    const response = await this.requestHTTP(
      `https://api.bilibili.com/x/relation/followings?vmid=${vmid}&pn=${page}&ps=${pageSize}&order_type=`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': this.ua,
          'Referer': 'https://www.bilibili.com/',
          'Cookie': this.cookieString
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      }
    )

    if (response.responseCode === 200) {
      return BiliResponseDecoder.parseFollowingResponse(BiliResponseDecoder.responseText(response.result));
    }
    throw new CurrentUserInfoError(`获取关注列表时HTTP错误: ${response.responseCode}`)
  }

  // Format view count to readable format
  static formatViewCount(count: number): string {
    if (count >= 100000000) {
      return (count / 100000000).toFixed(1) + 'y'; // 亿
    } else if (count >= 10000) {
      return (count / 10000).toFixed(1) + 'w'; // 万
    }
    return count.toString();
  }

  // Format timestamp to date
  static formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp * 1000);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate()
      .toString()
      .padStart(2, '0')}`;
  }

  // Format video duration
  // Format video duration
  static formatDuration(seconds: number): string {
    if (!seconds) {
      return '0:00';
    }

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainingSeconds = seconds % 60;

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
    }

    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  // Format timestamp to date
  static formatPublishDate(timestamp: number): string {
    if (!timestamp) {
      return '';
    }

    const now = new Date();
    const publishDate = new Date(timestamp * 1000);
    const diffTime = Math.abs(now.getTime() - publishDate.getTime());
    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays < 1) {
      const diffHours = Math.floor(diffTime / (1000 * 60 * 60));
      if (diffHours < 1) {
        const diffMinutes = Math.floor(diffTime / (1000 * 60));
        return diffMinutes + ' minutes ago';
      }
      return diffHours + ' hours ago';
    } else if (diffDays < 7) {
      return diffDays + ' days ago';
    } else if (diffDays < 30) {
      return Math.floor(diffDays / 7) + ' weeks ago';
    } else {
      return publishDate.getFullYear() + '-' +
      (publishDate.getMonth() + 1).toString().padStart(2, '0') + '-' +
      publishDate.getDate().toString().padStart(2, '0');
    }
  }

  releaseHttp() {
    super.releaseHttp();
  }
}
