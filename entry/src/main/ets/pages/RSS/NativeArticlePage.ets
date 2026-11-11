/**
 * Native article reader replacing the old ArkWeb + cloud reader-mode pipeline.
 *
 * Three entry modes:
 * - Feed: the RSS description already carries the full article HTML (3DM / IT之家 / 知乎日报).
 * - ArticlePage: a linked 3DM / IT之家 article URL; the server-rendered content container is
 *   fetched and parsed (these two sites only — everything else falls back to ArticleLinkPage).
 * - ZhihuQuestion: Zhihu hot-list links; a hidden ArkWeb passes the JS challenge and reports
 *   the page's structured initialData JSON, which is then rendered natively here.
 *
 * Images render from PixelMaps loaded by RemoteImage (browser UA + Referer, bounded decode
 * size) and open in a fullscreen viewer. The viewer intentionally does not use a
 * geometryTransition shared element: dismissing it with ModalTransition.NONE used to leave
 * the large image stranded over the article page.
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { ArcScrollBar, LengthMetrics } from '@kit.ArkUI';
import {
  Article, ArticleBlock, BlockKind, EmbedType, InlineRun, RunKind, TableCell, TableRow
} from '../../common/rss/ArticleModel';
import {
  FeedSourceKind, feedSourceTopGradient, feedSourceAccent
} from '../../common/rss/FeedSources';
import {
  LinkDestination, linkDestination, isITHomeArticleURL
} from '../../common/rss/FeedLinks';
import {
  parseArticlePage, parseGenericFeedArticle, parseZhihuDailyArticle
} from '../../common/rss/FeedParsers';
import {
  ZHIHU_DIAG_HOOK_JS, ZHIHU_POLL_JS, ZhihuDiag, ZhihuDiagBudget, ZhihuDiagDecoder,
  ZhihuPartDecoder, ZhihuArticleAssembler, ZhihuProgressRow
} from '../../common/rss/ZhihuHot';
import { SerialTaskTimer } from '../../common/SerialTaskTimer';
import { RemoteImage } from '../../common/rss/RemoteImage';
import {
  IMAGE_ZOOM, IMAGE_ZOOM_STAGE_HEIGHT_VP, IMAGE_ZOOM_STAGE_WIDTH_VP, ImageZoomRect
} from '../../common/ImageZoomTransition';
import { ImageViewerPushData } from './ImageViewerPage';
import { BilibiliServiceWithoutLogin } from '../../common/BiliService';
import { VideoPlayingPagePushData } from '../BiliVideoPlayer/BiliVideoPlayerPage';
import { ReadRequestScope, ReadRequestCancelled } from '../../common/ReadRequestScope';
import { DeviceMgr } from '../../common/AlwaysOn';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { WebLoadProgressRing } from '../../components/WebLoadProgressRing';
import { ErrorPrompt } from '../../components/ErrorPages';
import { UUID } from '../../common/UUID';
import { watchHeightVp, watchWidthVp } from '../../common/ScreenSize';
import { logTag } from '../../common/printLog';
import { ArticleLinkPagePushData } from './ArticleLinkPage';
import { DarkTheme } from '../../common/Theme';
import { JsonDecodeError } from '../../common/jsonschema/JsonDecode';
import { LogEvents } from '../../utils/log/LogEvents.generated';

/** 只记录解码元数据,不带页面原始 JSON。part/diag 两条链路共用。 */
function logZhihuDecodeFailure(error: JsonDecodeError, operation: string): void {
  const issue = error.issues.length > 0 ? error.issues[0] : undefined;
  LogEvents.zhihuDecodeFailed({
    operation: operation,
    schema: error.schema,
    issueCount: error.issues.length,
    code: issue === undefined ? '' : issue.code,
    path: issue === undefined ? '' : issue.pathText(),
    expected: issue === undefined ? '' : issue.expected,
    actualType: issue === undefined ? '' : issue.actualType,
  });
}

const BROWSER_UA = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/120.0 Mobile Safari/537.36';
/** Content images decode at this pixel width; ~180vp on the 466px watch screen. */
const IMAGE_MAX_WIDTH_PX = 360;
const ZHIHU_POLL_INTERVAL_MS = 1500;
/** Outer budget for the whole flow; the JS challenge alone has taken ~47s on this device. */
const ZHIHU_DEADLINE_MS = 75000;
/** A document that ended this long ago and still yielded nothing is empty, not slow. */
const ZHIHU_EMPTY_PAGE_MS = 10000;
/** No new part for this long and the page is done. */
const ZHIHU_SETTLE_MS = 5000;
/** Before the document has ended a page can pause between parts, so give it longer. */
const ZHIHU_SETTLE_PRE_PAGEEND_MS = 12000;
/** Per-part progress log cadence. */
const ZHIHU_PROGRESS_LOG_MS = 4000;
/** A poll taking this long is why the poll counter crawls: the render process is the wall. */
const ZHIHU_SLOW_POLL_MS = 3000;
/** Rejected poll calls are logged this often, then every Nth, so a stalling page stays readable. */
const ZHIHU_POLL_FAILURE_LOG_COUNT = 3;
const ZHIHU_POLL_FAILURE_LOG_EVERY = 10;

/** "+1.2s", relative to the loader's mount. */
function zhihuSeconds(ms: number): string {
  return '+' + (ms / 1000).toFixed(1) + 's';
}

/** Left-aligns log columns without relying on String.prototype.padEnd. */
function zhihuPad(text: string, width: number): string {
  let padded = text;
  while (padded.length < width) { padded = padded + ' '; }
  return padded;
}

export enum ArticleMode {
  Feed = 'feed',
  ArticlePage = 'articlePage',
  ZhihuQuestion = 'zhihuQuestion'
}

export interface NativeArticlePagePushData {
  mode: ArticleMode
  sourceKind: FeedSourceKind
  title: string
  url: string
  contentHTML: string
  enclosureURL: string
  pubDate: string
}

@Builder
export function NativeArticlePageBuilder(_name: string, param: Object) {
  NativeArticlePage({
    mode: (param as NativeArticlePagePushData).mode,
    sourceKind: (param as NativeArticlePagePushData).sourceKind,
    title: (param as NativeArticlePagePushData).title,
    url: (param as NativeArticlePagePushData).url,
    contentHTML: (param as NativeArticlePagePushData).contentHTML,
    enclosureURL: (param as NativeArticlePagePushData).enclosureURL,
    pubDate: (param as NativeArticlePagePushData).pubDate
  })
}

@ComponentV2
export struct NativeArticlePage {
  @Param @Require mode: ArticleMode
  @Param @Require sourceKind: FeedSourceKind
  @Param @Require title: string
  @Param @Require url: string
  @Param @Require contentHTML: string
  @Param @Require enclosureURL: string
  @Param @Require pubDate: string

  @Local
  private article: Article | null = null
  @Local
  private errorMessage: string | null = null
  @Local
  private pageInfos: NavPathStack | null = null
  // Incremented on retry so the Zhihu loader remounts with a fresh WebView.
  @Local
  private loadGeneration: number = 0
  // The Zhihu loader must outlive the first part: content renders over it, and it is only
  // torn down once polling stops, so parts that arrive later still reach the screen.
  @Local
  private zhihuLoaderActive: boolean = true
  // Web page load progress (0-100) as reported by the challenge page, drawn as the edge ring.
  @Local
  private zhihuProgress: number = 0

  private remoteImages: RemoteImage | null = null
  private requests: ReadRequestScope = new ReadRequestScope();
  private disposed: boolean = false;
  private fetching: boolean = false;

  aboutToAppear(): void {
    if (this.mode === ArticleMode.Feed) {
      this.buildFromFeed();
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.requests.cancel();
    if (this.remoteImages !== null) { this.remoteImages.cancel(); }
    DeviceMgr.Ins().requestKeepScreenOn('nativeArticle', false);
  }

  private ensureRemoteImages(): RemoteImage {
    if (this.remoteImages === null) {
      const context = this.getUIContext().getHostContext();
      this.remoteImages = new RemoteImage(context as common.UIAbilityContext);
    }
    return this.remoteImages;
  }

  private buildFromFeed(): void {
    try {
      if (this.sourceKind === FeedSourceKind.ZhihuDaily) {
        this.article = parseZhihuDailyArticle(this.title, this.url, this.contentHTML,
          this.enclosureURL.length > 0 ? this.enclosureURL : null);
      } else {
        this.article = parseGenericFeedArticle(this.sourceKind, this.title, this.contentHTML, this.url,
          this.pubDate.length > 0 ? this.pubDate : null);
      }
    } catch (_) {
      this.errorMessage = '文章解析失败，请稍后重试';
    }
  }

  private async fetchArticlePage(): Promise<void> {
    if (this.disposed || this.fetching) { return; }
    this.fetching = true;
    this.errorMessage = null;
    try {
      const response = await this.requests.get(this.url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': BROWSER_UA, 'Accept': 'text/html,application/xhtml+xml' },
        expectDataType: http.HttpDataType.STRING,
        usingCache: true,
        maxLimit: 2 * 1024 * 1024,
        connectTimeout: 5000,
        readTimeout: 10000
      });
      if (this.disposed) { return; }
      if (response.responseCode !== 200) {
        throw new Error('文章页暂不可用（HTTP ' + response.responseCode + '）');
      }
      if (typeof response.result !== 'string') { throw new Error('文章页数据格式异常'); }
      const article = parseArticlePage(this.sourceKind, response.result);
      article.sourceURL = this.url;
      this.article = article;
    } catch (error) {
      if (this.disposed || error instanceof ReadRequestCancelled) { return; }
      this.errorMessage = error instanceof Error ? error.message : '文章加载失败，请检查网络后重试';
    } finally {
      this.fetching = false;
    }
  }

  private retry(): void {
    this.errorMessage = null;
    this.article = null;
    this.loadGeneration++;
    this.zhihuLoaderActive = true;
    this.zhihuProgress = 0;
    if (this.mode === ArticleMode.Feed) {
      this.buildFromFeed();
    }
  }

  build() {
    NavDestination() {
      Column() {
        // ZhihuQuestion heads the chain deliberately: its loader has to outlive the first
        // part, so a plain `article !== null` branch above it would unmount the WebView and
        // strand every part that had not arrived yet.
        if (this.mode === ArticleMode.ZhihuQuestion) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.zhihuLoaderActive) {
              // Keyed by generation so a retry remounts a fresh WebView instead of reusing
              // one stuck on a half-passed challenge page.
              ForEach([this.loadGeneration], (generation: number) => {
                ZhihuQuestionLoader({
                  questionURL: this.url,
                  generation: generation,
                  onUpdate: (article: Article): void => {
                    this.article = article;
                  },
                  onFailed: (message: string): void => {
                    this.errorMessage = message;
                  },
                  onProgress: (progress: number): void => {
                    this.zhihuProgress = progress;
                  },
                  onDone: (): void => {
                    this.zhihuLoaderActive = false;
                  }
                })
                  .width('100%')
                  .height('100%')
              }, (generation: number) => String(generation))
              // Opaque cover for the challenge WebView beneath it. An ArkWeb keeps running
              // while covered — that is how this one stays hidden — and the cover redraws the
              // same per-source gradient the NavDestination paints, so the transparent reader
              // content layered above shows no seam where the two meet.
              Column()
                .width('100%')
                .height('100%')
                .linearGradient({ colors: feedSourceTopGradient(this.sourceKind) })
            }
            if (this.article !== null) {
              ArticleContentView({
                article: this.article,
                remoteImages: this.ensureRemoteImages(),
                pageInfos: this.pageInfos,
                sourceKind: this.sourceKind
              })
                .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
            } else if (this.errorMessage !== null) {
              ErrorPrompt({
                errorCode: null,
                errorMessage: this.errorMessage,
                showCloseButton: false,
                showRetryButton: true,
                onRetry: () => {
                  this.retry();
                }
              })
                .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
            } else {
              // The ring hugs the screen edge, the spinner and the caption stay in the middle;
              // both are only up while nothing has been extracted yet.
              WebLoadProgressRing({ progress: this.zhihuProgress, color: feedSourceAccent(this.sourceKind) })
                .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
              LoadingOverlay({ sourceKind: this.sourceKind })
                .width('100%')
                .height('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
            }
          }
          .width('100%')
          .height('100%')
        } else if (this.article !== null) {
          ArticleContentView({
            article: this.article,
            remoteImages: this.ensureRemoteImages(),
            pageInfos: this.pageInfos,
            sourceKind: this.sourceKind
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        } else if (this.errorMessage !== null) {
          ErrorPrompt({
            errorCode: null,
            errorMessage: this.errorMessage,
            showCloseButton: false,
            showRetryButton: true,
            onRetry: () => {
              this.retry();
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        } else {
          Column({ space: '30px' }) {
            AnimatedProgressView({ color: feedSourceAccent(this.sourceKind) })
              .width(50)
              .height(50)
            Text('加载中')
              .fontColor(feedSourceAccent(this.sourceKind))
              .fontWeight(FontWeight.Bold)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
          // 不铺底色，让 NavDestination 上该模块的顶部渐变透出来
          .onAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn('nativeArticle', true);
            this.fetchArticlePage();
          })
          .onDisAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn('nativeArticle', false);
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不能铺不透明底色，否则会盖住它
    // 和列表页同一个源就同一个色相，读文章时颜色不会跳
    .linearGradient({ colors: feedSourceTopGradient(this.sourceKind) })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}

@ComponentV2
struct LoadingOverlay {
  @Param @Require sourceKind: FeedSourceKind

  build() {
    Column({ space: '15vp' }) {
      AnimatedProgressView({ color: feedSourceAccent(this.sourceKind) })
        .width(50)
        .height(50)
      Text('正在通过知乎安全校验')
        .fontColor(feedSourceAccent(this.sourceKind))
        .fontWeight(FontWeight.Bold)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .onAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn('nativeArticle', true)
    })
    .onDisAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn('nativeArticle', false)
    })
  }
}

@ObservedV2
class ZhihuBridgeHost {
  @Trace
  payload: string | null = null
  /**
   * Diagnostics go straight to the loader instead of through a @Trace field: the page repeats
   * the same failure on every poll, and `@Monitor` only fires on a *changed* value — the repeat
   * count is exactly the part worth logging. Nothing here feeds a render.
   */
  diagSink: (raw: string) => void = (_raw: string): void => {}

  onZhihuPayload(value: string): void {
    this.payload = value;
  }

  onZhihuDiag(value: string): void {
    this.diagSink(value);
  }
}

/**
 * Hidden ArkWeb that waits out Zhihu's JS challenge and extracts js-initialData.
 *
 * The page's parts become available at different times and in no fixed order, so this merges
 * each one as it lands and repaints. It only reports data through the bridge; rendering stays
 * native. The host keeps it mounted until `onDone`, so parts arriving after the first paint
 * still reach the screen.
 */
@ComponentV2
struct ZhihuQuestionLoader {
  @Param @Require questionURL: string
  @Param @Require generation: number
  @Param @Require onUpdate: (article: Article) => void
  @Param @Require onFailed: (message: string) => void
  @Param @Require onDone: () => void
  @Param @Require onProgress: (progress: number) => void

  @Local
  private controller: webview.WebviewController = new webview.WebviewController()
  @Local
  private bridge: ZhihuBridgeHost = new ZhihuBridgeHost()

  private poller: SerialTaskTimer = new SerialTaskTimer()
  private progressTimer: number = -1
  private assembler: ZhihuArticleAssembler = new ZhihuArticleAssembler()
  private mountAt: number = 0
  private lastChangeAt: number = 0
  private firstPaintAt: number = 0
  private pageBeginCount: number = 0
  private pageEndAt: number = 0
  private lastProgress: number = 0
  private pollCount: number = 0
  private pollFailures: number = 0
  private slowPolls: number = 0
  /** Mount time of the poll currently awaiting runJavaScript; 0 when none is in flight. */
  private pollInFlightSince: number = 0
  private diagBudget: ZhihuDiagBudget = new ZhihuDiagBudget()
  private lastDiagKind: string = ''
  private renderExits: number = 0
  private started: boolean = false
  private disposed: boolean = false
  private finished: boolean = false

  aboutToAppear(): void {
    this.mountAt = Date.now();
    this.bridge.diagSink = (raw: string): void => this.reportDiag(raw);
    // Poll from the mount, not from onPageEnd: the initialData script is readable as soon as
    // the document is parsed, while onPageEnd waits for every sub-resource — tens of seconds
    // on Zhihu. Polling a page that has nothing yet costs one early return.
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stopPolling();
  }

  /** Merge the arriving part; only parts that actually changed anything trigger a repaint. */
  @Monitor('bridge.payload')
  private onPayload(): void {
    if (this.disposed || this.finished) { return; }
    const payload = this.bridge.payload;
    if (payload === null || payload.length === 0) { return; }
    const decoded = ZhihuPartDecoder.tryParse(payload);
    if (!decoded.isSuccess()) {
      logZhihuDecodeFailure(decoded.getFailure(), 'part');
      return;
    }
    if (!this.assembler.apply(decoded.getOrThrow())) { return; }
    const now = Date.now();
    this.lastChangeAt = now;
    if (this.firstPaintAt === 0) { this.firstPaintAt = now; }
    this.onUpdate(this.assembler.snapshot(this.questionURL));
  }

  private startPolling(): void {
    if (this.disposed || this.finished || this.started) { return; }
    this.started = true;
    this.progressTimer = setInterval(() => {
      this.logProgress();
    }, ZHIHU_PROGRESS_LOG_MS);
    this.poller.start((current: () => boolean): Promise<void> => this.pollOnce(current),
      ZHIHU_POLL_INTERVAL_MS);
  }

  private async pollOnce(current: () => boolean): Promise<void> {
    if (this.disposed || this.finished || !current()) { return; }
    const now = Date.now();
    const elapsed = now - this.mountAt;
    if (this.assembler.hasContent()) {
      // Parts land independently, so silence is the real completion signal — and a document
      // that has not ended yet may still be pausing between them.
      const quietFor = this.pageEndAt > 0 ? ZHIHU_SETTLE_MS : ZHIHU_SETTLE_PRE_PAGEEND_MS;
      if (now - this.lastChangeAt >= quietFor || elapsed >= ZHIHU_DEADLINE_MS) {
        this.finish(elapsed >= ZHIHU_DEADLINE_MS ? 'deadline' : 'settled', '');
        return;
      }
    } else if ((this.pageEndAt > 0 && now - this.pageEndAt >= ZHIHU_EMPTY_PAGE_MS) ||
      elapsed >= ZHIHU_DEADLINE_MS) {
      this.finish('empty', '未能从知乎页面取出内容，请重试');
      return;
    }
    this.pollCount++;
    const startedAt = Date.now();
    this.pollInFlightSince = startedAt;
    try {
      await this.controller.runJavaScript(ZHIHU_POLL_JS);
    } catch (error) {
      // Not a page failure: 401/17100001 mean the controller is not attached yet, so the script
      // never ran at all. This used to be swallowed, which made a web that never attached look
      // exactly like a page that was merely slow.
      this.pollFailures++;
      if (this.pollFailures <= ZHIHU_POLL_FAILURE_LOG_COUNT ||
        this.pollFailures % ZHIHU_POLL_FAILURE_LOG_EVERY === 0) {
        const failure = error as BusinessError;
        console.warn(logTag, 'zhihu poll failed n=' + this.pollFailures + ' t=' +
          zhihuSeconds(elapsed) + ' code=' + failure.code + ' | ' + failure.message);
      }
      return;
    } finally {
      this.pollInFlightSince = 0;
    }
    const took = Date.now() - startedAt;
    if (took >= ZHIHU_SLOW_POLL_MS) {
      // The poll counter is the tell: SerialTaskTimer skips a tick while a call is in flight, so
      // a congested render process reads as "polls=2 in 44s" rather than as a failed poll.
      this.slowPolls++;
      console.warn(logTag, 'zhihu slow poll n=' + this.pollCount + ' t=' + zhihuSeconds(elapsed) +
        ' took=' + zhihuSeconds(took) + ' slow=' + this.slowPolls);
    }
  }

  /** Idempotent: a page error, an empty page and the deadline can all land here. */
  private finish(reason: string, failureMessage: string): void {
    if (this.finished) { return; }
    this.finished = true;
    this.stopPolling();
    const hasContent = this.assembler.hasContent();
    console.info(logTag, 'zhihu done t=' + zhihuSeconds(Date.now() - this.mountAt) +
      ' polls=' + this.pollCount + ' reason=' + reason + ' partial=' + (hasContent ? 'true' : 'false') +
      ' first-paint=' + (this.firstPaintAt > 0 ? zhihuSeconds(this.firstPaintAt - this.mountAt) : 'none') +
      ' pageEnd=' + (this.pageEndAt > 0 ? zhihuSeconds(this.pageEndAt - this.mountAt) : 'none') +
      ' begins=' + this.pageBeginCount +
      ' answers=' + this.assembler.answerCount() + ' blocks=' + this.assembler.blockCount() +
      this.diagSummary());
    // Whatever arrived is worth keeping; only a page that yielded nothing is a failure.
    if (!hasContent && failureMessage.length > 0) {
      this.onFailed(failureMessage);
    }
    this.onDone();
  }

  private stopPolling(): void {
    this.poller.stop();
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  /**
   * One log line per distinct in-page failure, carrying its repeat count — the page re-raises the
   * same failure on every poll, so a repeat is information rather than noise. What the budget
   * silences still moves the counters that the periodic summary prints.
   */
  private reportDiag(raw: string): void {
    const decoded = ZhihuDiagDecoder.tryParse(raw);
    if (!decoded.isSuccess()) { logZhihuDecodeFailure(decoded.getFailure(), 'diag'); }
    const diag: ZhihuDiag =
      decoded.isSuccess() ? decoded.getOrThrow() : ZhihuDiagDecoder.asMalformed(raw);
    this.lastDiagKind = diag.kind;
    const signature = ZhihuDiagBudget.signatureOf(diag);
    const accepted = this.diagBudget.accept(signature);
    const count = this.diagBudget.countOf(signature);
    if (!accepted) { return; }
    const where = diag.source.length > 0
      ? ' @' + ZhihuDiagBudget.truncate(diag.source, ZhihuDiagBudget.MAX_SOURCE_CHARS) + ':' + diag.line
      : '';
    const state = diag.readyState.length > 0 ? ' rs=' + diag.readyState : '';
    console.warn(logTag, 'zhihu js ' + diag.kind + ' t=' + zhihuSeconds(Date.now() - this.mountAt) +
      ' x' + count + ' | ' + ZhihuDiagBudget.truncate(diag.message, ZhihuDiagBudget.MAX_MESSAGE_CHARS) +
      where + state);
    // Only the first occurrence carries the stack; it does not change between repeats.
    if (diag.stack.length > 0 && count === 1) {
      console.warn(logTag, 'zhihu js stack | ' +
        ZhihuDiagBudget.truncate(diag.stack, ZhihuDiagBudget.MAX_STACK_CHARS));
    }
  }

  /** Diagnostic state for the periodic and final lines, so it survives even a silent failure. */
  private diagSummary(): string {
    const slow = this.slowPolls > 0 ? ' slow=' + this.slowPolls : '';
    const failed = this.pollFailures > 0 ? ' failed=' + this.pollFailures : '';
    // A poll that never returns reads as a frozen poll counter; this says so explicitly.
    let inflight = '';
    if (this.pollInFlightSince > 0) {
      inflight = ' inflight=' + zhihuSeconds(Date.now() - this.pollInFlightSince);
    }
    const total = this.diagBudget.total();
    if (total === 0) { return ' diag=0' + slow + failed + inflight; }
    return ' js=' + this.lastDiagKind + ' diag=' + this.diagBudget.distinct() + '/' + total +
      slow + failed + inflight;
  }

  /** One line per part per tick: parts arrive independently, so they are read independently. */
  private logProgress(): void {
    if (this.disposed || this.finished) { return; }
    const now = Date.now();
    // A poll stuck past the slow threshold only shows up while it is still in flight: the
    // completion-side warning cannot fire for a call that never completes.
    if (this.pollInFlightSince > 0 && now - this.pollInFlightSince >= ZHIHU_SLOW_POLL_MS) {
      console.warn(logTag, 'zhihu poll stuck t=' + zhihuSeconds(now - this.mountAt) +
        ' inflight=' + zhihuSeconds(now - this.pollInFlightSince) + ' poll=' + this.pollCount);
    }
    const prefix = 'zhihu t=' + zhihuSeconds(now - this.mountAt) + ' polls=' + this.pollCount;
    const rows: ZhihuProgressRow[] = this.assembler.progress();
    if (!this.assembler.hasContent()) {
      // No part yet: there is nothing per-part to report, only how far the page itself got.
      console.info(logTag, prefix + ' | waiting progress=' + this.lastProgress +
        ' begins=' + this.pageBeginCount + ' pageEnd=' +
        (this.pageEndAt > 0 ? zhihuSeconds(this.pageEndAt - this.mountAt) : 'none') + this.diagSummary());
      return;
    }
    for (const row of rows) {
      let detail = 'pending';
      if (row.ready) {
        const at = zhihuSeconds(row.at - this.mountAt);
        if (row.label === 'title' || row.label === 'meta') {
          detail = 'ready ' + at + ' len=' + row.blocks;
        } else if (row.label === 'detail') {
          detail = 'ready ' + at + ' blocks=' + row.blocks;
        } else {
          detail = 'header ' + at + (row.bodyReady
            ? ' body ' + zhihuSeconds(row.bodyAt - this.mountAt) + ' blocks=' + row.bodyBlocks
            : ' body:pending');
        }
      }
      console.info(logTag, prefix + ' | ' + zhihuPad(row.label + ':', 11) + detail);
    }
    console.info(logTag, prefix + ' | ' + zhihuPad('summary:', 11) +
      'partial parts=' + rows.length + ' answers=' + this.assembler.answerCount());
  }

  build() {
    Web({
      src: this.questionURL,
      controller: this.controller
    })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .javaScriptProxy({
        object: this.bridge,
        name: 'ZhihuBridge',
        methodList: ['onZhihuPayload', 'onZhihuDiag'],
        controller: this.controller
      })
      // Installed at document start so the page's own scripts cannot throw before the hook is in
      // place. The polled script carries the same hook and re-installs it when needed, which is
      // what covers a page that replaces window.onerror after us.
      .javaScriptOnDocumentStart([{ script: ZHIHU_DIAG_HOOK_JS, scriptRules: ['*'] }])
      // Both events are markers only; polling runs from the mount. The pair is what splits
      // "challenge time" from "extraction time" in the log.
      .onPageBegin(() => {
        this.pageBeginCount++;
        console.info(logTag, 'zhihu pageBegin n=' + this.pageBeginCount +
          ' t=' + zhihuSeconds(Date.now() - this.mountAt));
      })
      // The document's own progress, drawn as the edge ring. Nothing has been extracted for
      // most of the wait, so this is the only thing on screen that moves.
      .onProgressChange((event) => {
        this.lastProgress = event.newProgress;
        this.onProgress(event.newProgress);
      })
      .onPageEnd(() => {
        this.pageEndAt = Date.now();
        console.info(logTag, 'zhihu pageEnd t=' + zhihuSeconds(this.pageEndAt - this.mountAt) +
          ' begins=' + this.pageBeginCount + ' parts=' + this.assembler.answerCount());
      })
      .onErrorReceive((event) => {
        if (event.request.isMainFrame()) {
          console.warn(logTag, 'zhihu pageError ' + event.error.getErrorInfo());
          this.finish('page-error', '知乎页面加载失败：' + event.error.getErrorInfo());
        }
      })
      // A challenge page normally answers 200; a block or a rate limit answers 4xx/5xx, which is
      // the context the poll line needs to be read against.
      .onHttpErrorReceive((event) => {
        if (event.request.isMainFrame()) {
          console.warn(logTag, 'zhihu httpError code=' + event.response.getResponseCode() +
            ' t=' + zhihuSeconds(Date.now() - this.mountAt));
        }
      })
      // The other way this flow stalls with nothing thrown: the render process dies or wedges,
      // and the polls simply stop making progress.
      .onRenderExited((event) => {
        this.renderExits++;
        console.warn(logTag, 'zhihu renderExited n=' + this.renderExits +
          ' reason=' + String(event.renderExitReason) +
          ' t=' + zhihuSeconds(Date.now() - this.mountAt));
        if (this.disposed || this.finished) { return; }
        if (this.renderExits === 1) {
          // One free reload: on the emulator the render process occasionally fails its startup
          // handshake (channel connect timeout in the arkweb log) and is terminated before any
          // page script runs. Reloading beats waiting out the deadline, and the SDK documents
          // onRenderExited as the place to restore the page via the controller.
          this.poller.stop();
          this.started = false;
          try {
            this.controller.loadUrl(this.questionURL);
            console.warn(logTag, 'zhihu auto-reload after render exit t=' +
              zhihuSeconds(Date.now() - this.mountAt));
            this.startPolling();
          } catch (error) {
            // The controller may already be gone with the process; one attempt is all it gets.
            console.warn(logTag, 'zhihu reload failed t=' + zhihuSeconds(Date.now() - this.mountAt));
            this.finish('render-exit', '知乎页面渲染进程异常退出，请重试');
          }
          return;
        }
        // A second exit is a stable failure, not a flake; whatever arrived is worth keeping.
        this.finish('render-exit', this.assembler.hasContent() ? '' : '知乎页面渲染进程异常退出，请重试');
      })
      .onRenderProcessNotResponding(() => {
        console.warn(logTag, 'zhihu renderNotResponding t=' + zhihuSeconds(Date.now() - this.mountAt));
      })
      .onRenderProcessResponding(() => {
        console.info(logTag, 'zhihu renderResponding t=' + zhihuSeconds(Date.now() - this.mountAt));
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
  }
}

/**
 * 「整屏居中 + scaleToFit」的落点。
 *
 * 缩放是等比的：scale = min(可用宽 / 源宽, 可用高 / 源高)，一个维度先贴边、另一个留白；
 * 位移只负责把矩形中心挪到屏幕中心：x = (屏宽 - 目标宽) / 2，y = (屏高 - 目标高) / 2。
 * 用 transform 的说法就是「两中心之差 + 等比缩放」，这里直接对 rect 插值，避开 scale
 * 锚点与 translate/scale 叠加顺序的歧义（见 docs 里 RSS hero 转场踩过的坑）。
 *
 * 落点必须写成绝对矩形而不是「靠布局居中」：查看器里那张图也是按这个矩形摆的，
 * 两边共用 ImageZoomTransition.target，才对得上。
 */
function scaleToFitOnScreen(sourceWidth: number, sourceHeight: number): ImageZoomRect {
  const safeWidth = Math.max(1, sourceWidth);
  const safeHeight = Math.max(1, sourceHeight);
  const scale = Math.min(IMAGE_ZOOM_STAGE_WIDTH_VP / safeWidth,
    IMAGE_ZOOM_STAGE_HEIGHT_VP / safeHeight);
  const width = safeWidth * scale;
  const height = safeHeight * scale;
  return {
    x: (watchWidthVp - width) / 2,
    y: (watchHeightVp - height) / 2,
    width: width,
    height: height,
  };
}

/** Viewer state shared between in-page images and the fullscreen cover. */
class ImageRef {
  src: string = '';
  caption: string = '';
  /** onAreaChange 最后记录的窗口坐标（vp）：这张图此刻在屏幕上的位置。 */
  area: ImageZoomRect = { x: 0, y: 0, width: 0, height: 0 };
  /** 记录 area 那一刻的 Scroll 纵向偏移，用来把坐标投影到点击瞬间的视口。 */
  areaAtScrollY: number = 0;
  /** area 是否已由一次真实布局算出；图片还没上屏时是 false。 */
  areaValid: boolean = false;

  constructor(src: string, caption: string) {
    this.src = src;
    this.caption = caption;
  }
}

@ObservedV2
class ImageRefs {
  refs: ImageRef[] = [];
  /**
   * 由页面注入：Scroll 当前的纵向偏移（vp）。
   * onAreaChange 只在布局变化时回调，Scroll 滚动不会重发，所以点击瞬间要用
   * 「当前偏移 - 记录时的偏移」把记录下来的矩形投影回现在的视口。
   */
  scrollYProvider: () => number = (): number => 0;
  /**
   * 正在起飞的 ordinal。飞行层的第一帧和源图完全重合，之后源图必须让位，
   * 否则页面上会留一张不动的残影，看起来像图分成了两个。
   */
  @Trace flyingOrdinal: number = -1;

  next(src: string, caption: string): number {
    const ordinal = this.refs.length;
    this.refs.push(new ImageRef(src, caption));
    return ordinal;
  }
}

@ComponentV2
struct ArticleContentView {
  @Param @Require article: Article
  @Param @Require remoteImages: RemoteImage
  @Param @Require pageInfos: NavPathStack | null
  @Param @Require sourceKind: FeedSourceKind

  @Local
  private scroller: Scroller = new Scroller()
  @Local
  private pageID: string = UUID()

  private imageRefs: ImageRefs = new ImageRefs()
  /** 页面已销毁；交接流程的异步回调可能还没跑完，回调里不能再碰状态。 */
  private gone: boolean = false

  aboutToAppear(): void {
    // 滚动不会触发子组件的 onAreaChange，图片在屏幕上的位置要靠 Scroll 偏移差反推。
    this.imageRefs.scrollYProvider = (): number => this.scroller.currentOffset().yOffset;
  }

  aboutToDisappear(): void {
    this.gone = true
  }

  private handleLink(url: string): void {
    if (this.pageInfos === null) { return; }
    const destination = linkDestination(url);
    if (destination === LinkDestination.NativeArticlePage) {
      const pushData: NativeArticlePagePushData = {
        mode: ArticleMode.ArticlePage,
        sourceKind: isITHomeArticleURL(url) ? FeedSourceKind.ITHome : FeedSourceKind.ThreeDM,
        title: '',
        url: url,
        contentHTML: '',
        enclosureURL: '',
        pubDate: ''
      };
      this.pageInfos.pushPathByName('NativeArticlePage', pushData);
    } else if (destination === LinkDestination.ZhihuQuestion) {
      const pushData: NativeArticlePagePushData = {
        mode: ArticleMode.ZhihuQuestion,
        sourceKind: FeedSourceKind.ZhihuHot,
        title: '',
        url: url,
        contentHTML: '',
        enclosureURL: '',
        pubDate: ''
      };
      this.pageInfos.pushPathByName('NativeArticlePage', pushData);
    } else {
      const pushData: ArticleLinkPagePushData = { url: url, sourceKind: this.sourceKind };
      this.pageInfos.pushPathByName('ArticleLinkPage', pushData);
    }
  }

  private openBilibili(bvid: string): void {
    if (this.pageInfos === null) { return; }
    const pushData: VideoPlayingPagePushData = {
      videoID: { bvid: bvid, cid: '' },
      biliService: new BilibiliServiceWithoutLogin()
    };
    this.pageInfos.pushPathByName('BiliVideoPlayerPage', pushData);
  }

  /**
   * 点图片：量好两端几何交给 ImageZoomTransition，再 push 查看器。
   * 飞行层挂在 Navigation 外面（components/ImageZoomTransitionOverlay），这里不画图，
   * 只做三件事：把几何交出去、让正文里那张图让位、push 目标页。
   * 真正的起飞由交接对象在「目标页就绪」后统一发令——两边同时动才叠得上。
   */
  private openViewer(ordinal: number): void {
    if (IMAGE_ZOOM.active || this.pageInfos === null) { return; }
    const ref = this.imageRefs.refs[ordinal];
    // 起飞第一帧就要显示这张图，所以它必须已经解码完；没解出来就直连查看器，不硬飞。
    const pixelMap = ref === undefined ? null : this.remoteImages.peek(ref.src);
    if (ref === undefined || !ref.areaValid || pixelMap === null) {
      this.pushViewer(ordinal);
      return;
    }
    const target = scaleToFitOnScreen(ref.area.width, ref.area.height);
    console.info(logTag, 'imageZoom prepare ordinal=' + String(ordinal) +
      ' from=' + ref.area.x.toFixed(1) + ',' + ref.area.y.toFixed(1) + ' ' +
      ref.area.width.toFixed(1) + 'x' + ref.area.height.toFixed(1) +
      ' to=' + target.x.toFixed(1) + ',' + target.y.toFixed(1) + ' ' +
      target.width.toFixed(1) + 'x' + target.height.toFixed(1));
    IMAGE_ZOOM.begin({
      src: ref.src,
      caption: ref.caption,
      pixelMap: pixelMap,
      origin: ref.area,
      target: target
    });
    // 飞行层的第一帧和正文这张图完全重合，之后必须让它让位，否则原位留一张不动的残影
    this.imageRefs.flyingOrdinal = ordinal;
    this.pushViewer(ordinal);
    IMAGE_ZOOM.run().then((): void => {
      this.restoreSourceImage();
    }, (): void => {
      this.restoreSourceImage();
    });
  }

  private restoreSourceImage(): void {
    if (this.gone) { return; }
    // 复位后正文里的源图重新可见（从查看器返回时要看到它）
    this.imageRefs.flyingOrdinal = -1;
  }

  /** 把整篇文章的图片序列交给查看器，让它进去后能原地左右切换。 */
  private pushViewer(ordinal: number): void {
    const pageInfos = this.pageInfos;
    if (pageInfos === null) { return; }
    const srcs: string[] = [];
    const captions: string[] = [];
    for (const ref of this.imageRefs.refs) {
      srcs.push(ref.src);
      captions.push(ref.caption);
    }
    const pushData: ImageViewerPushData = { srcs: srcs, captions: captions, index: ordinal };
    pageInfos.pushPathByName('ImageViewerPage', pushData);
  }


  build() {
    Column() {
      Stack({ alignContent: Alignment.End }) {
        Scroll(this.scroller) {
          Column({ space: 8 }) {
            // Title block
            if (this.article.heroImage.length > 0) {
              ArticleImageView({
                src: this.article.heroImage,
                caption: '',
                remoteImages: this.remoteImages,
                imageRefs: this.imageRefs,
                fixedOrdinal: -1,
                avatar: false,
                maxDisplayVp: 150,
                maxDisplayHeightVp: 0,
                onOpenImage: (ordinal: number): void => {
                  console.info(logTag, 'imageViewer open ordinal=' + String(ordinal) +
                    ' total=' + String(this.imageRefs.refs.length));
                  this.openViewer(ordinal);
                }
              })
            }
            Text(this.article.title)
              .fontSize('15fp')
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Start)
              .width('100%')
            if (this.article.subtitle.length > 0) {
              Text(this.article.subtitle)
                .fontSize('10fp')
                .fontColor($r('app.color.font_color_secondary'))
                .textAlign(TextAlign.Start)
                .width('100%')
            }

            // Body blocks
            ForEach(this.article.blocks, (block: ArticleBlock) => {
              BlockView({
                block: block,
                remoteImages: this.remoteImages,
                imageRefs: this.imageRefs,
                onOpenImage: (ordinal: number): void => {
                  console.info(logTag, 'imageViewer open ordinal=' + String(ordinal) +
                    ' total=' + String(this.imageRefs.refs.length));
                  this.openViewer(ordinal);
                },
                onLink: (url: string): void => {
                  this.handleLink(url);
                },
                onEmbed: (bvid: string, embedURL: string): void => {
                  if (bvid.length > 0) {
                    this.openBilibili(bvid);
                  } else if (embedURL.length > 0) {
                    this.handleLink(embedURL);
                  }
                }
              })
            }, (block: ArticleBlock, index: number) => String(index) + ':' + block.kind)

            // Footer actions
            if (this.article.viewMoreURL.length > 0) {
              Text('查看知乎讨论')
                .fontSize('11fp')
                .fontColor('#8AB4F8')
                .decoration({ type: TextDecorationType.Underline, color: '#8AB4F8' })
                .onClick(() => {
                  this.handleLink(this.article.viewMoreURL);
                })
                .margin({ top: 6 })
            }
            if (this.article.sourceURL.length > 0) {
              Text('查看原文')
                .fontSize('11fp')
                .fontColor('#8AB4F8')
                .decoration({ type: TextDecorationType.Underline, color: '#8AB4F8' })
                .onClick(() => {
                  this.handleLink(this.article.sourceURL);
                })
                .margin({ top: 6 })
            }
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .padding({
            top: LengthMetrics.fp(56),
            bottom: LengthMetrics.fp(40),
            start: LengthMetrics.fp(16),
            end: LengthMetrics.fp(16)
          })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
        .onAppear(() => {
          try {
            this.getUIContext()
              .getFocusController()
              .requestFocus(this.pageID + 'c37abce5-6d3e-4b6a-8c9f-2a1b0f4e7d55')
          } catch (error) {
            console.debug(logTag, 'requestFocus failed: ' + String(error))
          }
        })
        .id(this.pageID + 'c37abce5-6d3e-4b6a-8c9f-2a1b0f4e7d55')

        ArcScrollBar({ scroller: this.scroller })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // 不铺底色，让 NavDestination 的顶部渐变透上来
  }
}

/** Renders one block; recurses into container children through nested BlockView instances. */
@ComponentV2
struct BlockView {
  @Param @Require block: ArticleBlock
  @Param @Require remoteImages: RemoteImage
  @Param @Require imageRefs: ImageRefs
  @Param @Require onOpenImage: (ordinal: number) => void
  @Param @Require onLink: (url: string) => void
  @Param @Require onEmbed: (bvid: string, embedURL: string) => void

  private headingSize(level: number): string {
    if (level <= 1) { return '15fp'; }
    if (level === 2) { return '14fp'; }
    return '13fp';
  }

  @Builder
  richText(block: ArticleBlock) {
    Text() {
      ForEach(block.runs, (run: InlineRun) => {
        Span(run.kind === RunKind.Break ? '\n' : run.text)
          .fontSize(block.kind === BlockKind.Heading ? this.headingSize(block.level) :
            (run.superscript || run.subscript ? '9fp' : '12fp'))
          .fontWeight(run.bold ? FontWeight.Bold :
            (block.kind === BlockKind.Heading ? FontWeight.Bold : FontWeight.Normal))
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(run.url.length > 0 ? '#8AB4F8' :
            (block.kind === BlockKind.Heading ? '#FFFFFF' : '#E0E0E0'))
          .decoration({
            type: run.url.length > 0 ? TextDecorationType.Underline : TextDecorationType.None,
            color: '#8AB4F8'
          })
          .onClick(() => {
            if (run.url.length > 0) { this.onLink(run.url); }
          })
      }, (run: InlineRun, index: number) => String(index) + ':' + run.kind + ':' + run.text.substring(0, 12))
    }
    .width('100%')
    .textAlign(TextAlign.Start)
    .lineHeight(18)
  }

  @Builder
  childrenView(block: ArticleBlock) {
    Column({ space: 4 }) {
      ForEach(block.children, (child: ArticleBlock) => {
        BlockView({
          block: child,
          remoteImages: this.remoteImages,
          imageRefs: this.imageRefs,
          onOpenImage: this.onOpenImage,
          onLink: this.onLink,
          onEmbed: this.onEmbed
        })
      }, (child: ArticleBlock, index: number) => String(index) + ':' + child.kind)
    }
    .width('100%')
  }

  @Builder
  quoteView(block: ArticleBlock) {
    Column({ space: 4 }) {
      ForEach(block.children, (child: ArticleBlock) => {
        BlockView({
          block: child,
          remoteImages: this.remoteImages,
          imageRefs: this.imageRefs,
          onOpenImage: this.onOpenImage,
          onLink: this.onLink,
          onEmbed: this.onEmbed
        })
      }, (child: ArticleBlock, index: number) => String(index) + ':' + child.kind)
    }
    .width('100%')
    .padding({
      start: LengthMetrics.fp(8),
      end: LengthMetrics.fp(4),
      top: LengthMetrics.fp(6),
      bottom: LengthMetrics.fp(6)
    })
    .border({ width: { left: 2 }, color: '#5A5A5E' })
    .backgroundColor('#1E1E1E')
    .borderRadius(6)
  }

  @Builder
  listView(block: ArticleBlock) {
    Column({ space: 4 }) {
      ForEach(block.children, (item: ArticleBlock, index: number) => {
        Row() {
          Text(block.ordered ? String(index + 1) + '. ' : '• ')
            .fontSize('12fp')
            .fontColor('#8AB4F8')
          BlockView({
            block: item,
            remoteImages: this.remoteImages,
            imageRefs: this.imageRefs,
            onOpenImage: this.onOpenImage,
            onLink: this.onLink,
            onEmbed: this.onEmbed
          })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (item: ArticleBlock, index: number) => String(index) + ':' + item.kind)
    }
    .width('100%')
  }

  @Builder
  tableView(block: ArticleBlock) {
    Column({ space: 6 }) {
      ForEach(block.rows, (row: TableRow, rowIndex: number) => {
        Column({ space: 2 }) {
          ForEach(row.cells, (cell: TableCell, cellIndex: number) => {
            Text(flattenCellText(cell))
              .fontSize('10fp')
              .fontWeight(row.header ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(row.header ? '#FFFFFF' : '#E0E0E0')
              .textAlign(TextAlign.Start)
              .width('100%')
          }, (cell: TableCell, cellIndex: number) => String(rowIndex) + ':' + String(cellIndex))
        }
        .width('100%')
        .padding(6)
        .backgroundColor('#1E1E1E')
        .borderRadius(6)
      }, (row: TableRow, rowIndex: number) => String(rowIndex))
    }
    .width('100%')
  }

  build() {
    if (this.block.kind === BlockKind.Paragraph || this.block.kind === BlockKind.Heading) {
      this.richText(this.block)
    } else if (this.block.kind === BlockKind.Image) {
      ArticleImageView({
        src: this.block.src,
        caption: this.block.caption,
        remoteImages: this.remoteImages,
        imageRefs: this.imageRefs,
        fixedOrdinal: -1,
        avatar: this.block.avatar,
        maxDisplayVp: 150,
        maxDisplayHeightVp: 0,
        onOpenImage: (ordinal: number): void => {
          this.onOpenImage(ordinal);
        }
      })
    } else if (this.block.kind === BlockKind.Quote) {
      this.quoteView(this.block)
    } else if (this.block.kind === BlockKind.ListItem) {
      this.childrenView(this.block)
    } else if (this.block.kind === BlockKind.List) {
      this.listView(this.block)
    } else if (this.block.kind === BlockKind.Table) {
      this.tableView(this.block)
    } else if (this.block.kind === BlockKind.Divider) {
      Divider()
        .strokeWidth(1)
        .color('#3A3A3C')
        .margin({ top: 4, bottom: 4 })
    } else if (this.block.kind === BlockKind.Embed) {
      Row({ space: 6 }) {
        Text('▶')
          .fontSize('14fp')
          .fontColor(DarkTheme.primary)
        Text(this.block.embedType === EmbedType.Bilibili && this.block.bvid.length > 0 ?
          '播放视频 ' + this.block.bvid : '查看嵌入内容')
          .fontSize('11fp')
          .fontColor('#FFFFFF')
      }
      .padding(8)
      .width('100%')
      .backgroundColor('#1E1E1E')
      .borderRadius(10)
      .onClick(() => {
        this.onEmbed(this.block.bvid, this.block.embedURL);
      })
    } else if (this.block.kind === BlockKind.AnswerHeader) {
      Row({ space: 8 }) {
        if (this.block.authorAvatar.length > 0) {
          // Fixed-size slot: ArticleImageView fills its parent, which must not be the row.
          Column() {
            ArticleImageView({
              src: this.block.authorAvatar,
              caption: '',
              remoteImages: this.remoteImages,
              imageRefs: this.imageRefs,
              fixedOrdinal: -1,
              avatar: true,
              maxDisplayVp: 22,
              maxDisplayHeightVp: 22,
              onOpenImage: (ordinal: number): void => {
              }
            })
          }
          .width(22)
          .height(22)
          .clip(true)
          .justifyContent(FlexAlign.Center)
        }
        Column({ space: 2 }) {
          Text(this.block.author)
            .fontSize('12fp')
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Start)
          if (this.block.votes.length > 0) {
            Text(this.block.votes)
              .fontSize('10fp')
              .fontColor($r('app.color.font_color_secondary'))
              .textAlign(TextAlign.Start)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 10, bottom: 2 })
    } else if (this.block.kind === BlockKind.Meta) {
      Text(this.block.metaText)
        .fontSize('10fp')
        .fontColor($r('app.color.font_color_secondary'))
        .textAlign(TextAlign.Start)
        .width('100%')
    }
  }
}

function flattenRuns(blocks: ArticleBlock[]): string {
  let text = '';
  for (const block of blocks) {
    for (const run of block.runs) {
      if (run.kind === RunKind.Text) { text += run.text; }
      else if (run.kind === RunKind.Break) { text += ' '; }
    }
    if (block.children.length > 0) { text += flattenRuns(block.children); }
  }
  return text;
}

function flattenCellText(cell: TableCell): string {
  return flattenRuns(cell.blocks);
}

/** Image with download state; registers itself in the shared viewer list on mount. */
@ComponentV2
struct ArticleImageView {
  @Param @Require src: string
  @Param @Require caption: string
  @Param @Require remoteImages: RemoteImage
  @Param @Require imageRefs: ImageRefs
  // >= 0 用调用方给的查看序号，-1 自动分配（正文图一律 -1）
  @Param @Require fixedOrdinal: number
  @Param @Require avatar: boolean
  @Param @Require maxDisplayVp: number
  // 0 表示不限制高度；正文图目前都传 0，只要横向封顶。
  @Param maxDisplayHeightVp: number = 0
  @Param @Require onOpenImage: (ordinal: number) => void

  @Local
  private pixelMap: image.PixelMap | null = null
  @Local
  private displayWidthVp: number = 0
  @Local
  private displayHeightVp: number = 0
  @Local
  private failed: boolean = false
  @Local
  private loaded: boolean = false
  @Local
  private imageOpacity: number = 0

  private ordinal: number = -1
  private disposed: boolean = false

  aboutToAppear(): void {
    if (!this.avatar) {
      this.ordinal = this.fixedOrdinal >= 0 ? this.fixedOrdinal : this.imageRefs.next(this.src, this.caption);
    }
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  /**
   * onAreaChange：记录「我此刻在屏幕上的矩形」，起飞动画拿它当起点。
   * globalPosition 是相对窗口的坐标，和起飞层（Scroll 的兄弟节点）同一套坐标系，
   * 不需要再叠加任何父容器的偏移。
   */
  private recordArea(area: Area): void {
    if (this.ordinal < 0) { return; }
    const ref = this.imageRefs.refs[this.ordinal];
    if (ref === undefined) { return; }
    // Area 的 Length 运行时就是 vp 数值，这里没有百分比尺寸。
    ref.area = {
      x: area.globalPosition.x as number,
      y: area.globalPosition.y as number,
      width: area.width as number,
      height: area.height as number,
    };
    ref.areaAtScrollY = this.imageRefs.scrollYProvider();
    ref.areaValid = ref.area.width > 0 && ref.area.height > 0;
  }

  /**
   * 点击瞬间把记录过的矩形投影到当前视口。Scroll 滚动只是挪内容偏移，不会重新布局
   * 子组件，所以 onAreaChange 不会重发；位置差只能靠 Scroll 偏移的变化量补回来。
   */
  private prepareFlySource(): void {
    if (this.ordinal < 0) { return; }
    const ref = this.imageRefs.refs[this.ordinal];
    if (ref === undefined || !ref.areaValid) { return; }
    const scrollY = this.imageRefs.scrollYProvider();
    const drifted = scrollY - ref.areaAtScrollY;
    if (drifted === 0) { return; }
    ref.area = {
      x: ref.area.x,
      y: ref.area.y - drifted,
      width: ref.area.width,
      height: ref.area.height,
    };
    ref.areaAtScrollY = scrollY;
  }

  private async load(): Promise<void> {
    if (this.src.length === 0) {
      console.warn(logTag, '文章图片加载失败：URL 为空' + (this.caption.length > 0 ?
        '，caption=' + this.caption : ''));
      this.failed = true;
      return;
    }
    const result = await this.remoteImages.load(this.src, this.avatar ? 48 : IMAGE_MAX_WIDTH_PX);
    if (this.disposed || !result.ok || result.pixelMap === null) {
      if (!this.disposed) {
        console.warn(logTag, '文章图片加载失败：url=' + this.src + '，原因=' +
          (result.reason.length > 0 ? result.reason : '未知') +
          (this.avatar ? '（头像）' : '') + (this.caption.length > 0 ?
            '，caption=' + this.caption : ''));
        this.failed = true;
      }
      return;
    }
    let widthVp = this.getUIContext().px2vp(result.width);
    let heightVp = this.getUIContext().px2vp(result.height);
    const cap = this.avatar ? 22 : this.maxDisplayVp;
    if (widthVp > cap) {
      heightVp = Math.max(1, heightVp * cap / widthVp);
      widthVp = cap;
    }
    const capHeight = this.avatar ? 0 : this.maxDisplayHeightVp;
    if (capHeight > 0 && heightVp > capHeight) {
      widthVp = Math.max(1, widthVp * capHeight / heightVp);
      heightVp = capHeight;
    }
    this.pixelMap = result.pixelMap;
    this.displayWidthVp = widthVp;
    this.displayHeightVp = heightVp;
    this.loaded = true;
    this.getUIContext().animateTo({
      duration: 300,
      curve: Curve.EaseOut
    }, () => {
      this.imageOpacity = 1;
    });
  }

  build() {
    Column({ space: 4 }) {
      if (this.loaded && this.pixelMap !== null) {
        if (this.avatar) {
          Image(this.pixelMap)
            .objectFit(ImageFit.Cover)
            .width(this.displayWidthVp)
            .height(this.displayHeightVp)
            .borderRadius(this.displayWidthVp / 2)
            .opacity(this.imageOpacity)
            .backgroundColor('#1E1E1E')
        } else {
          Image(this.pixelMap)
            .objectFit(ImageFit.Contain)
            .width(this.displayWidthVp)
            .height(this.displayHeightVp)
            .borderRadius(8)
            // 交接期间把源图藏起来：起飞层已经带着同一张图离开，原位留着就是残影。
            .opacity(this.imageRefs.flyingOrdinal === this.ordinal ? 0 : this.imageOpacity)
            .backgroundColor('#1E1E1E')
            // 正文图的真实屏幕矩形，交给 onAreaChange 记录，起飞时取它当起点
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.recordArea(newArea);
            })
            .onClick(() => {
              this.prepareFlySource();
              this.onOpenImage(this.ordinal);
            })
        }
      } else if (this.failed) {
        Text('图片加载失败')
          .fontSize('9fp')
          .fontColor($r('app.color.font_color_secondary'))
          .padding(10)
      } else {
        Column() {
          AnimatedProgressView()
            .width(20)
            .height(20)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height(60)
      }
      if (this.caption.length > 0) {
        Text(this.caption)
          .fontSize('9fp')
          .fontColor($r('app.color.font_color_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
