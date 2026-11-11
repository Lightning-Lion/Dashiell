/**
 * Fallback web page for article links the native renderer cannot handle (external sites,
 * Zhihu story pages, non-Bilibili embeds...). ArkWeb stays here as an escape hatch only —
 * it is no longer part of the bundled feeds' reading path.
 */

import { webview, WebNetErrorList } from '@kit.ArkWeb';
import { DeviceMgr } from '../../common/AlwaysOn';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { ErrorPrompt } from '../../components/ErrorPages';
import { WebLoadProgressRing } from '../../components/WebLoadProgressRing';
import { h5ua } from '../../common/defaultUserAgent';
import { calculateSquareSideUnit, watchWidthVp } from '../../common/ScreenSize';
import { FeedSourceKind, feedSourceTopGradient, feedSourceAccent } from '../../common/rss/FeedSources';

/** 圆屏内接正方形的边长：「适应」模式下网页按这个尺寸排版，四个角不会被表盘切掉。 */
const FIT_SIDE_VP: number = watchWidthVp * calculateSquareSideUnit();
/** 圆屏边缘到能放按钮的地方还有一段距离，角上的按钮必须内缩这么多，否则会落在圆外。 */
const CORNER_INSET_VP: number = 32;
const CORNER_BUTTON_VP: number = 30;

/** 手表上没有客户端能接管 taobao://、openapp.jdmobile:// 这类协议。 */
function isUnsupportedScheme(url: string): boolean {
  const match = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(url.trim());
  if (match === null) { return false; }  // 相对地址交给 WebView 自己解析
  const scheme = match[1].toLowerCase();
  return scheme !== 'http' && scheme !== 'https' && scheme !== 'about' && scheme !== 'data' &&
    scheme !== 'blob' && scheme !== 'file' && scheme !== 'javascript';
}

export interface ArticleLinkPagePushData {
  url: string
  sourceKind: FeedSourceKind
}

@Builder
export function ArticleLinkPageBuilder(_name: string, param: Object) {
  ArticleLinkPage({
    url: (param as ArticleLinkPagePushData).url,
    sourceKind: (param as ArticleLinkPagePushData).sourceKind
  })
}

@ComponentV2
export struct ArticleLinkPage {
  @Param @Require url: string
  @Param @Require sourceKind: FeedSourceKind
  @Local
  private controller: webview.WebviewController = new webview.WebviewController()
  @Local
  private pageInfos: NavPathStack | null = null
  @Local
  private loading: boolean = true
  /** 当前主文档的加载进度 0-100，驱动表盘边缘的进度环。 */
  @Local
  private progress: number = 0
  @Local
  private errorMessage: string | null = null
  /** false = 铺满表盘（默认，四角可能被圆屏裁掉）；true = 内接正方形，保证整页可见。 */
  @Local
  private fitToScreen: boolean = false
  /** 切换全屏/适应时重建 Web：运行中直接改 Web 尺寸会让 ArkWeb 渲染面变黑。 */
  @Local
  private webGeneration: number = 0
  /** 当前页地址，重建后从这一页继续，而不是退回最初推送的链接。
   *  故意不做成 @Local：onPageEnd 改它时不能反过来触发 Web 重新加载。 */
  private currentURL: string = ''
  /** 同一个页面可能连续拉起多个 URL Scheme，去抖后只提示一次。 */
  private lastSchemeToastAt: number = 0

  private showUnsupportedSchemeToast(): void {
    const now = Date.now();
    if (now - this.lastSchemeToastAt < 2000) { return; }
    this.lastSchemeToastAt = now;
    this.getUIContext().getPromptAction().showToast({ message: '手表上没有可打开该链接的应用' });
  }

  private toggleFitMode(): void {
    this.fitToScreen = !this.fitToScreen;
    // 运行中改 Web 的宽高会让 ArkWeb 的渲染面失效（真机验证过，整页变黑），
    // 所以换一个新的 WebView 按新尺寸重新排版；代价是当前滚动位置会回到页首。
    this.loading = true;
    this.progress = 0;
    this.errorMessage = null;
    this.controller = new webview.WebviewController();
    this.webGeneration++;
    this.getUIContext().getPromptAction().showToast({
      message: this.fitToScreen ? '适应屏幕：完整显示网页' : '全屏：网页铺满表盘'
    });
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        ForEach([this.webGeneration], (generation: number) => {
          Web({
            src: this.currentURL.length > 0 ? this.currentURL : this.url,
            controller: this.controller
          })
          .userAgent(h5ua)
          .darkMode(WebDarkMode.On)
          .backgroundColor(Color.Black)
          .domStorageAccess(true)
          .fileAccess(true)
          .javaScriptAccess(true)
          .multiWindowAccess(false)
          // 淘宝/京东这类页面会主动跳 taobao://、openapp.jdmobile:// 去拉起客户端。
          // 手表上没有对应 App，拦下来只提示一次，别让它把整页变成错误页。
          .onLoadIntercept((event) => {
            if (generation !== this.webGeneration) { return false; }
            if (isUnsupportedScheme(event.data.getRequestUrl())) {
              this.showUnsupportedSchemeToast();
              return true;
            }
            return false;
          })
          .onPageBegin(() => {
            if (generation !== this.webGeneration) { return; }
            // 页内跳转时进度会从 100 退回 0；立刻让环回来，而不是等第一次进度上报。
            this.progress = 0;
          })
          .onProgressChange((event) => {
            if (generation !== this.webGeneration) { return; }
            this.progress = event.newProgress;
            if (event.newProgress >= 80) {
              this.loading = false;
            }
          })
          .onPageEnd((event) => {
            if (generation !== this.webGeneration) { return; }
            // 不是所有页面都会把 onProgressChange 报到 100；页面结束就是这一圈走完的信号。
            this.currentURL = event.url;
            this.progress = 100;
            this.loading = false;
          })
          .onErrorReceive((event) => {
            if (generation !== this.webGeneration) { return; }
            // ERR_UNKNOWN_URL_SCHEME 是页面想拉起本地客户端，不是网页加载失败；
            // 静默吃掉，只给一个 toast，保留当前网页。
            if (event.error.getErrorCode() === WebNetErrorList.ERR_UNKNOWN_URL_SCHEME) {
              this.showUnsupportedSchemeToast();
              return;
            }
            if (event.request.isMainFrame()) {
              this.errorMessage = event.error.getErrorInfo();
            }
          })
          .width(this.fitToScreen ? FIT_SIDE_VP : '100%')
          .height(this.fitToScreen ? FIT_SIDE_VP : '100%')
        }, (generation: number) => String(generation))

        if (this.errorMessage === null && this.loading) {
          Column({ space: '15vp' }) {
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
          // 这一层压着下面正在加载的 WebView，底色必须不透明才挡得住；
          // 那就重绘该模块的顶部渐变——既挡得住，又和上一页的色相一致、跳转过去不跳色。
          .linearGradient({ colors: feedSourceTopGradient(this.sourceKind) })
          .onAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn('articleLinkWeb', true)
          })
          .onDisAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn('articleLinkWeb', false)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        }

        // 表盘边缘的进度环。加载遮罩在 80% 就揭幕，环却要走到 100% 才消失，
        // 所以它必须画在遮罩之上，否则揭幕那一刻进度会凭空断掉。
        if (this.errorMessage === null && this.progress < 100) {
          WebLoadProgressRing({
            progress: this.progress,
            color: feedSourceAccent(this.sourceKind)
          })
            .hitTestBehavior(HitTestMode.None)
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
        }

        if (this.errorMessage !== null) {
          ErrorPrompt({
            errorCode: null,
            errorMessage: this.errorMessage,
            showCloseButton: true,
            showRetryButton: true,
            onRetry: () => {
              this.errorMessage = null;
              this.loading = true;
              this.progress = 0;
              this.controller.loadUrl(this.currentURL.length > 0 ? this.currentURL : this.url);
            },
            onClose: () => {
              if (this.pageInfos !== null) {
                this.pageInfos.pop(true);
              }
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        }

        // WebView 会吃掉手表的边缘右滑返回手势，所以返回入口必须常驻：
        // 加载中、加载完成、以及错误页上都保留，用户在任何时刻都能退出去。
        // 圆屏左上角的可见区域从 ~(32,32)vp 才开始，放在 12,12 会被表盘圆角切掉。
        Button({
          type: ButtonType.Circle,
          role: ButtonRole.NORMAL,
          buttonStyle: ButtonStyleMode.NORMAL,
          stateEffect: true
        }) {
          Image($r('app.media.back_chevron'))
            .objectFit(ImageFit.Auto)
            .width('18fp')
            .height('18fp')
        }
        .width(CORNER_BUTTON_VP)
        .height(CORNER_BUTTON_VP)
        .position({ x: CORNER_INSET_VP, y: CORNER_INSET_VP })
        .zIndex(1)
        .backgroundColor('#99000000')
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          if (this.pageInfos !== null) {
            this.pageInfos.pop(true);
          }
        })

        // 右上角：全屏 / 适应切换。表盘是圆的，铺满时四角会被切掉；「适应」把网页
        // 收进圆的内接正方形，代价是左右留黑边，但整页都能看到。
        if (this.errorMessage === null) {
          Button({
            type: ButtonType.Circle,
            role: ButtonRole.NORMAL,
            buttonStyle: ButtonStyleMode.NORMAL,
            stateEffect: true
          }) {
            // 图标是「下一步动作」：当前全屏则显示收起，当前适应则显示展开。
            SymbolGlyph(this.fitToScreen
              ? $r('sys.symbol.arrow_up_left_and_arrow_down_right')
              : $r('sys.symbol.arrow_down_right_and_arrow_up_left'))
              .fontSize(18)
              .fontColor([Color.White])
          }
          .width(CORNER_BUTTON_VP)
          .height(CORNER_BUTTON_VP)
          .position({
            x: watchWidthVp - CORNER_INSET_VP - CORNER_BUTTON_VP,
            y: CORNER_INSET_VP
          })
          .zIndex(1)
          .backgroundColor('#99000000')
          .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.toggleFitMode();
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onDisAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn('articleLinkWeb', false)
    })
  }
}
