import { DouyinListSource, DouyinRequestBuilder } from '../../common/douyin/DouyinRequestBuilder';
import { logTag } from '../../common/printLog';
import { webview } from '@kit.ArkWeb';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { DouyinNativeFeed } from './DouyinNativeFeed';
import { common } from '@kit.AbilityKit';
import { DouVideoPlayer } from './DouYinCardList';
import { DouYinCardListModel } from './DouYinCardListModel';
import { DouYinAvaliabilityCheck } from './AvaliabilityCheckView';
import { DouYinLoginGateModel, DouYinLoginGateState, DouYinLoginRequiredView } from './DouYinLoginGate';
import { DarkTheme } from '../../common/Theme';
import { DevFlags } from '../../common/dev/DevFlags';
import { DouyinWebSign } from '../../common/douyin/DouyinWebSign';
import { DouyinCookieStore } from '../../common/douyin/DouyinCookieStore';
import { SerialTaskTimer } from '../../common/SerialTaskTimer';
import { DeviceMgr } from '../../common/AlwaysOn';
import { SettingsButton } from '../../common/SettingsButton';
import { ColorMetrics } from '@kit.ArkUI';
import { DouYinPlayerSession } from './DouYinPlayerSession';
import { closeDouYinLayer, DouYinLoopMode, DouYinMenuLayer } from './DouYinPlayerUi';
import { DouYinPlaybackPrefs } from '../../common/douyin/DouYinPlaybackPrefs';

// 自动加载更多的限流间隔：用户连续滑到底也不至于连着发请求
const AUTO_LOAD_MIN_INTERVAL_MS = 1500


@Builder
export function DouYinJingxuanPageBuilder(name: string, param: Object) {
  DouYinJingxuanPage()
}


@Builder
export function DouyinCollectedPageBuilder(name: string, param: Object) {
  DouYinJingxuanPage({ source: 'collected' })
}


@Builder
export function DouyinLikedPageBuilder(name: string, param: Object) {
  DouYinJingxuanPage({ source: 'liked' })
}

// 不采用服务器中转方案：短期能缓解压力，但随用户量增长服务器成本不可持续。
// 以本地方案为主，服务器方案只做最基础的定时刷新预置视频。
@ComponentV2
export struct DouYinJingxuanPage {
  @Param source: DouyinListSource = 'recommended';
  @Local
  pageInfos: NavPathStack | null = null
  @Local private playbackActive: boolean = true;
  // 整个播放器共用的会话：AVPlayer、音量、内外页 UI 状态。
  @Local private session: DouYinPlayerSession = new DouYinPlayerSession();
  // 推荐接口需要登录 Cookie，未登录时用这道门挡住播放器
  @Local private gate: DouYinLoginGateModel = new DouYinLoginGateModel()

  aboutToAppear(): void {
    this.loadPlaybackPrefs()
  }

  aboutToDisappear(): void {
    this.session.release()
  }

  private loadPlaybackPrefs(): void {
    (async () => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mode = await DouYinPlaybackPrefs.loadLoopMode(context)
      this.session.onLoopModeChanged = (value: DouYinLoopMode): void => {
        DouYinPlaybackPrefs.saveLoopMode(context, value === DouYinLoopMode.Sequence ? 'sequence' : 'single')
      }
      this.session.setLoopMode(mode === 'sequence' ? DouYinLoopMode.Sequence : DouYinLoopMode.Single)
    })()
  }

  private checkLogin(): void {
    this.gate.check()
  }

  build() {
    NavDestination() {
      DouYinAvaliabilityCheck({
        requireNetwork:true,
        pageInfos: this.pageInfos,
        content:() => {
          this.buildDouYinJingxuanPageInner({
            pageInfos:this.pageInfos,
            playbackActive:this.playbackActive,
            gate:this.gate,
            source:this.source,
            session:this.session
          })
        }
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
      this.checkLogin()
    })
    .onShown(() => {
      this.playbackActive = true;
      // 用户可能刚从登录页返回，重新判定一次
      this.checkLogin()
    })
    .onHidden(() => { this.playbackActive = false; })
    .onWillDisappear(() => {
      this.playbackActive = false;
    })
    .onBackPressed(() => {
      // 先逐层关内页菜单，再退出内页，最后才交给系统返回。
      if (this.session.ui.layer !== DouYinMenuLayer.None) {
        this.session.setLayer(closeDouYinLayer(this.session.ui.layer))
        return true
      }
      if (this.session.ui.immersive) {
        // 全屏时先退全屏，再退内页；避免用户误以为返回失效。
        if (this.session.ui.fullscreen) {
          this.session.setFullscreen(false)
          return true
        }
        this.session.requestImmersive(false)
        return true
      }
      return false
    })
  }
  // 定义为组件内的@Builder，因为如果定义成全局的@Builder，会因为：https://developer.huawei.com/consumer/cn/forum/topic/0203170527095268768
  // 崩溃
  // 注意：全局 @Builder 里误读 this 会取到 undefined，所以保持组件内定义
  @Builder
  private buildDouYinJingxuanPageInner(param:BuildDouYinJingxuanPageInner) {
    DouYinRSSDetailView({
      pageInfos:param.pageInfos,
      playbackActive:param.playbackActive,
      gate:param.gate,
      source:param.source,
      session:param.session
    })
  }
}

class BuildDouYinJingxuanPageInner {
  public source: DouyinListSource = 'recommended';
  public playbackActive: boolean = true;
  public pageInfos: NavPathStack | null = null
  public gate: DouYinLoginGateModel = new DouYinLoginGateModel()
  public session: DouYinPlayerSession = new DouYinPlayerSession()
}


@ComponentV2
struct DouYinRSSDetailView {
  @Param source: DouyinListSource = 'recommended';
  @Computed private get sourceName(): string {
    return this.source === 'collected' ? '我的收藏' : this.source === 'liked' ? '我的喜欢' : '精选';
  }
  @Param playbackActive: boolean = true;
  @Param @Require pageInfos: NavPathStack | null
  @Param @Require gate: DouYinLoginGateModel
  @Param @Require session: DouYinPlayerSession
  @Local private nativeFeed: DouyinNativeFeed = new DouyinNativeFeed()

  private loadNative(): void {
    this.nativeFeed.load(this.videoListMod);
  }

  private refreshCurrentLink(): void {
    this.nativeFeed.refresh(this.videoListMod, this.session.currentAwemeID).then(() => {
      if (this.nativeFeed.refreshError.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: this.nativeFeed.refreshError });
      }
    });
  }

  private leavePlayback(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: '页面栈尚未挂载' });
      return;
    }
    if (this.pageInfos.popToName('DouYinMenu') === -1) {
      this.pageInfos.pop();
    }
  }

  // 停在同一条上只加载一次，避免反复停下就反复请求
  private lastAutoLoadIndex: number = -1
  private lastAutoLoadMs: number = 0

  /**
   * 滑到最后一条时自动加载更多。限流 + 同一条去重；
   * 请求本身在 DouyinNativeFeed 里还会挡掉「正在加载 / 没有下一页」。
   * 失败了不自动重试（否则停在这一条上会一直发请求），交给底部提示里的重试按钮。
   */
  private autoLoadMore(index: number): void {
    if (index === this.lastAutoLoadIndex) { return }
    if (this.nativeFeed.loading || !this.nativeFeed.hasMore || this.nativeFeed.error.length > 0) { return }
    const now = Date.now()
    if (now - this.lastAutoLoadMs < AUTO_LOAD_MIN_INTERVAL_MS) { return }
    this.lastAutoLoadMs = now
    this.lastAutoLoadIndex = index
    this.loadNative()
  }

  // 用户明确点了重试，绕过上面的去重与限流
  private retryLoadMore(): void {
    this.lastAutoLoadIndex = -1
    this.lastAutoLoadMs = 0
    this.loadNative()
  }

  // 进页按需铸造 uifid 的状态：true 时先展示 PC-UA 的铸造 WebView，铸成再发原生列表请求。
  @Local private uifidMinting: boolean = false

  // 收藏/喜欢是受保护端点，必须有基于 uifid 的网页签名；推荐流不需要。
  private isProtectedSource(): boolean {
    return this.source === 'collected' || this.source === 'liked';
  }

  private mintUrl(): string {
    const base = 'https://www.douyin.com/user/self?enter_from=discover&enter_method=personal_panel&from_tab_name=main&showTab=';
    return base + (this.source === 'liked' ? 'like' : 'favorite_collection');
  }

  /**
   * 按需铸造：受保护来源先查共享 cookie 是否已有 uifid，命中就直连发原生请求；
   * 缺失则切到 PC-UA 的 WebView 去加载 user/self 页铸造 uifid，铸成后再回来发请求。
   */
  private ensureUifidThenLoad(): void {
    if (!this.isProtectedSource()) { this.loadNative(); return; }
    DouyinCookieStore.read().then((cookie: string): void => {
      if (DouyinWebSign.pickUifid(cookie) !== undefined) {
        console.info(logTag, 'DOUYIN_NATIVE uifid precheck hit source=' + this.source);
        this.loadNative();
      } else {
        console.info(logTag, 'DOUYIN_NATIVE uifid precheck miss → 按需铸造 source=' + this.source);
        this.uifidMinting = true;
      }
    }).catch((error: Error): void => {
      console.warn(logTag, 'DOUYIN_NATIVE uifid precheck read-failed → 尝试铸造 message=' + error.message);
      this.uifidMinting = true;
    });
  }

  private onUifidMinted(): void {
    console.info(logTag, 'DOUYIN_NATIVE uifid minted → 发起列表请求 source=' + this.source);
    this.uifidMinting = false;
    this.loadNative();
  }

  @Local
  videoListMod:DouYinCardListModel = new DouYinCardListModel()

  build() {
    // 未登录时不建立播放器：加载请求在这里的 onAppear 才发出
    if (this.gate.state !== DouYinLoginGateState.LoggedIn) {
      DouYinLoginRequiredView({
        state: this.gate.state,
        pageInfos: this.pageInfos,
        contentName: this.sourceName,
        afterLoginPage: this.source === 'collected' ? 'DouyinCollectedPage' :
          this.source === 'liked' ? 'DouyinLikedPage' : 'DouYinJingxuanPage'
      })
    } else {
      Stack({ alignContent:Alignment.Center }) {
        if (this.uifidMinting) {
          DouyinUifidMintView({ targetUrl: this.mintUrl(), onReady: () => this.onUifidMinted(), pageInfos: this.pageInfos })
        }
        if (!this.uifidMinting) {
        if (this.videoListMod.cardList === null) {
          // 整屏 Column：内容在 ArcButton 上方居中，避免设置网络的贴底按钮盖住错误文案和重试。
          // 背景用抖音页自己的渐变，不再是纯黑底；错误态也有品牌色。
          Column() {
            Blank()
            Column({ space: 10 }) {
              Text(this.nativeFeed.loading ? '正在加载' + this.sourceName + '…' : this.nativeFeed.error ||
                (this.nativeFeed.loaded ? this.sourceName + '暂无可播放的视频' : '准备加载' + this.sourceName))
                .fontColor('#FFF5F6').fontSize(16).textAlign(TextAlign.Center)
              if (!this.nativeFeed.loading && (!this.nativeFeed.loaded || this.nativeFeed.hasMore)) {
                // 重试是次级动作：文字按钮，不抢贴底「设置网络」的主操作。
                Button('重试', { type: ButtonType.Normal })
                  .height('28vp')
                  .fontSize('13fp')
                  .fontColor('#D9A7B2')
                  .backgroundColor(Color.Transparent)
                  .onClick(() => this.loadNative())
              }
            }.width('75%')
            Blank()
            // 原生列表首屏失败时，给一个贴底的「设置网络」入口；用压暗一档的抖音玫红，
            // 和上面的渐变同一色相，但不像 #FE2C55 那么刺眼。
            if (!this.nativeFeed.loading && this.nativeFeed.error.length > 0) {
              SettingsButton({
                arcBackgroundColor: ColorMetrics.rgba(201, 79, 104),
                arcFontColor: ColorMetrics.rgba(255, 255, 255),
                arcShadowColor: ColorMetrics.rgba(201, 79, 104, 0.4)
              })
            }
          }
          .width('100%')
          .height('100%')
          .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
        }
        if (this.videoListMod.cardList !== null) {
          DouVideoPlayer({
            cards:this.videoListMod.cardList,
            session:this.session,
            playbackActive:this.playbackActive,
            onReachEnd:(index: number) => this.autoLoadMore(index),
            loadingMore:this.nativeFeed.loading,
            loadMoreError:this.nativeFeed.error,
            onRetryLoadMore:() => this.retryLoadMore(),
            onExitPlayback:() => this.leavePlayback()
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        }
        // 调试面板：条目数、手动加载/刷新链接。用户不需要，用 DevFlags.douyinDevUI 控制（见 docs/debug-config.md）
        if (DevFlags.douyinDevUI && this.videoListMod.cardList !== null) {
          Column() {
            Row({ space: 8 }) {
              Text('原生 ' + this.videoListMod.cardList.length).fontSize(12).fontColor(Color.White)
              Button(this.nativeFeed.loading ? '加载中' : '更多').fontSize(12).height(28)
                .enabled(!this.nativeFeed.loading && this.nativeFeed.hasMore).onClick(() => this.loadNative())
              Button('刷新链接').fontSize(12).height(28).enabled(!this.nativeFeed.loading)
                .onClick(() => this.refreshCurrentLink())
            }.margin({ top: 34 })
            if (this.nativeFeed.error.length > 0) {
              Text(this.nativeFeed.error).fontSize(12).fontColor(Color.White).width('70%')
            }
          }.height('100%').width('100%').hitTestBehavior(HitTestMode.Transparent)
        }
        }
      }
      .onAppear(() => {
        this.nativeFeed.configure(this.source, this.videoListMod);
        this.nativeFeed.activate();
        if (this.videoListMod.cardList === null) { this.ensureUifidThenLoad(); }
      })
      .onDisAppear(() => this.nativeFeed.dispose(this.videoListMod))
    }
  }
}


// 按需铸造 uifid 的 WebView 层：幕后用一个 opacity 0 的 PC-UA WebView 打开抖音个人主页，
// 只为触发服务端 Set-Cookie 下发 UIFID_TEMP；前台是标准加载态（转圈 + 文案，抖音配色/顶部渐变），
// 把幕后 Web 完全遮住。调试信息（秒数等）只进日志；等待超过 15s 才在加载态下方露出
// 「小感叹号圆圈 + 了解详情」入口，点开是独立说明页；30s 仍拿不到 uifid 则整屏切到失败页（重试/返回）。
@ComponentV2
struct DouyinUifidMintView {
  @Param @Require targetUrl: string
  @Param @Require onReady: () => void
  @Param @Require pageInfos: NavPathStack | null
  @Local private controller: webview.WebviewController = new webview.WebviewController()
  @Local private showHelp: boolean = false
  @Local private failed: boolean = false
  private poller: SerialTaskTimer = new SerialTaskTimer()
  private startedAt: number = Date.now()

  aboutToAppear(): void {
    console.info(logTag, 'DOUYIN_NATIVE uifid-mint begin url=' + this.targetUrl)
    DeviceMgr.Ins().requestKeepScreenOn('douYinLoadingWebPage', true, 'uifidMint')
    this.startPolling()
  }

  aboutToDisappear(): void {
    this.poller.stop()
    DeviceMgr.Ins().requestKeepScreenOn('douYinLoadingWebPage', false, 'uifidMint')
  }

  private startPolling(): void {
    this.startedAt = Date.now()
    this.poller.start(async (current: () => boolean): Promise<void> => {
      const cookie = await webview.WebCookieManager.fetchCookie('https://www.douyin.com/')
      if (!current()) { return; }
      if (DouyinWebSign.pickUifid(cookie) !== undefined) {
        console.info(logTag, 'DOUYIN_NATIVE uifid-mint ok elapsed=' + (Date.now() - this.startedAt) + 'ms')
        this.poller.stop()
        this.onReady()
        return;
      }
      const waited = Math.floor((Date.now() - this.startedAt) / 1000)
      // 秒数只进日志，绝不上屏
      console.debug(logTag, 'DOUYIN_NATIVE uifid-mint waiting waited=' + waited + 's')
      if (waited >= 15) { this.showHelp = true; }
      if (waited >= 30) {
        console.warn(logTag, 'DOUYIN_NATIVE uifid-mint timeout waited=' + waited + 's')
        this.poller.stop()
        this.failed = true
        return;
      }
    }, 1000)
  }

  private retry(): void {
    console.info(logTag, 'DOUYIN_NATIVE uifid-mint retry')
    this.failed = false
    this.showHelp = false
    try { this.controller.loadUrl(this.targetUrl); } catch (error) { /* 控制器可能尚未 attach */ }
    this.startPolling()
  }

  private openExplainer(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: 'NavPathStack未挂载' })
      return
    }
    this.pageInfos.pushPathByName('DouyinUifidMintExplainer', null)
  }

  private goBack(): void {
    if (this.pageInfos !== null) { this.pageInfos.pop() }
  }

  build() {
    Stack() {
      // 幕后 Web：opacity 0，只为让服务端把 UIFID_TEMP 写进共享 cookie jar；视觉由前台加载层完全遮住
      Web({ src: this.targetUrl, controller: this.controller })
        .backgroundColor(Color.Transparent)
        .userAgent(DouyinRequestBuilder.USER_AGENT)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .fileAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .width('100%')
        .height('100%')
        .opacity(0)
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          // 只看主框架；-3 是导航被取消，不是断网。
          if (event.request.isMainFrame() && event.error.getErrorCode() !== -3) {
            console.warn(logTag, 'DOUYIN_NATIVE uifid-mint mainframe-error code=' + event.error.getErrorCode() +
              ' info=' + event.error.getErrorInfo())
          }
        })

      if (this.failed) {
        this.buildFailedLayer()
      } else {
        this.buildLoadingLayer()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildLoadingLayer() {
    Column({ space: '30px' }) {
      AnimatedProgressView({ color: DarkTheme.accents.douyin })
        .width(50)
        .height(50)
      Text('加载中')
        .fontColor(DarkTheme.accents.douyin)
        .fontWeight(FontWeight.Bold)
      // 只有等待超过 15s 才出现：小感叹号圆圈 + 了解详情，点开独立说明页
      if (this.showHelp) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize('15vp')
            .fontColor(['#E6A23C'])
          Text('了解详情')
            .fontSize('13fp')
            .fontColor(DarkTheme.textSecondary)
        }
        .padding({ top: 6, bottom: 2 })
        .onClick(() => { this.openExplainer(); })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    // 抖音顶部渐变承载美观，同时完全遮住幕后不可见的 Web
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
  }

  @Builder
  private buildFailedLayer() {
    Column() {
      Blank()
      Image($r('app.media.dou_videos_provider_loading_errror_icon'))
        .width('40%')
        .height('40%')
        .objectFit(ImageFit.Contain)
      Text('加载失败')
        .fontSize('17fp')
        .fontWeight(FontWeight.Bold)
        .fontColor(DarkTheme.textPrimary)
      Blank()
      Text('暂时没拿到抖音的登录凭证，请检查网络后重试')
        .fontSize('13fp')
        .fontColor(DarkTheme.textSecondary)
        .textAlign(TextAlign.Center)
        .width('85%')
      Blank()
      Row({ space: 12 }) {
        Button('重试')
          .height('34vp')
          .backgroundColor(DarkTheme.accents.douyin)
          .fontColor(Color.White)
          .onClick(() => { this.retry(); })
        Button('返回')
          .height('34vp')
          .backgroundColor(DarkTheme.textFieldBackground)
          .fontColor(Color.White)
          .onClick(() => { this.goBack(); })
      }
      Blank()
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
  }
}

// uifid 铸造说明页：等待超过 15s 时点「了解详情」进入，用大白话解释这一步在干嘛。
@Builder
export function DouyinUifidMintExplainerBuilder(name: string, param: Object) {
  DouyinUifidMintExplainer()
}

@ComponentV2
struct DouyinUifidMintExplainer {
  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('正在准备登录凭证')
          .fontSize('17fp')
          .fontWeight(FontWeight.Bold)
          .fontColor(DarkTheme.textPrimary)
        Text('为了读取你的抖音收藏和喜欢，需要先让抖音确认这台设备的访客身份（uifid）。' +
          '这一步会在后台打开一次抖音个人主页，由服务器把凭证写进登录 Cookie，通常几秒就完成。')
          .fontSize('13fp')
          .fontColor(DarkTheme.textSecondary)
          .textAlign(TextAlign.Start)
          .width('100%')
        Text('期间无需操作，也不要退出本页；如果长时间未完成，会自动提示失败，可返回重试。')
          .fontSize('12fp')
          .fontColor(DarkTheme.textSecondary)
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(DarkTheme.navDestDefaultBackground)
  }
}

@ObservedV2
export class DouYinVideoCard {
  // 简介，视频底下的字
  description:string
  // 如果不能起播，逐个往后替换
  @Trace videoURLList:Array<string>
  constructor(description:string,videoURLList:Array<string>) {
    this.description = description
    this.videoURLList = videoURLList
  }
}

@ObservedV2
class DouYinLiveStreamCard {
  awemeID:string
  hlsURL:string
  constructor(awemeID:string,hlsURL:string) {
    this.awemeID = awemeID
    this.hlsURL = hlsURL
  }
}

@ObservedV2
class DouYinPlogCard {
  awemeID:string
  picURLs:Array<string>
  // 简介，图集底下的字
  description:string
  constructor(awemeID:string,picURLs:Array<string>,description:string) {
    this.awemeID = awemeID
    this.picURLs = picURLs
    this.description = description
  }
}

// 视图各处共用的卡片
@ObservedV2
export class DouYinAwemeCard {
  type:string // 目前支持三种内容：视频、图集、直播
  awemeID:string
  videoInfo:DouYinVideoCard | null
  liveInfo:DouYinLiveStreamCard | null
  plogInfo:DouYinPlogCard | null
  constructor(awemeID:string,videoInfo:DouYinVideoCard) {
    this.type = "video"
    this.awemeID = awemeID
    this.videoInfo = videoInfo
    this.liveInfo = null
    this.plogInfo = null
  }
  assumeVideo():DouYinVideoCard | null {
    if (this.type === "video") {
      if (this.videoInfo !== null) {
        return this.videoInfo
      }
    }
    console.debug(logTag,"预期错误，不是视频")
    return null
  }
}
