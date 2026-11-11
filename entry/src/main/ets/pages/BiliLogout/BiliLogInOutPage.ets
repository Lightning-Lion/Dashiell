import { getBiliSessionEpoch, isCurrentBiliSessionEpoch, invalidateBiliSession } from '../../common/BiliSession';
import { clearBiliCookies } from '../../common/BiliCookies';
import { BiliBusinessError } from '../../common/bili/BiliBusinessError';
import { JsonDecodeError } from '../../common/jsonschema/JsonDecode';
import { UUID } from '../../common/UUID';
import { focusWatchList } from '../../common/WatchListFocus';
import { DarkTheme } from '../../common/Theme';
import { BiliLoginState, biliLoginState } from '../../common/BiliSession';
import { BilibiliService } from "../../common/BiliService"
import { setCurrentBiliService, clearCurrentBiliService } from "../../common/BiliServiceRegistry"
import { BiliGetCookieViewStandard, CookieStringPack } from "../BiliLogin/BiliGetCookieView"
import { webview } from "@kit.ArkWeb";
import { ErrorPrompt, ErrorPromptData } from "../../components/ErrorPages";
import { AlertDialog, ArcScrollBar, CustomContentDialog, LengthMetrics } from '@kit.ArkUI'
import { logTag } from "../../common/printLog";
import { AppDatabase } from "../../common/storage/AppDatabase";
import { StorageKeys, StorageNamespaces } from "../../common/storage/StorageKeys";
import { NewlyDoneLoginModel } from "../BiliLogin/BiliLoginWebView";
import { pushBiliLoginRequired } from "../BiliLogin/BiliLoginRequiredPage";

export interface BiliLogInOutPagePushData {
  openRecommendPage: () => void
  // 从功能页的登录中间页进来：登录成功并按返回后回到调用方，而不是清空导航栈回推荐页。
  returnToCaller?: boolean
}

@Builder
export function BiliLogInOutPageBuilder(name: string, param: Object) {
  BiliLogInOutPage({
    openRecommendPage: (param as BiliLogInOutPagePushData).openRecommendPage,
    returnToCaller: (param as BiliLogInOutPagePushData).returnToCaller ?? false
  })
}

class ClearCookiesForDomainError extends Error {
  errorCode: string
  errorMessage: string

  constructor(errorCode: string, errorMessage: string) {
    super(errorMessage)
    this.errorCode = errorCode
    this.errorMessage = errorMessage
  }
}

@ObservedV2
class BiliLogInOutPageViewModel {
  /**
   * 清理指定域名下的所有 Cookie.
   *
   * @param domain 要清理 Cookie 的域名（例如：".bilibili.com"）.
   * @returns Promise<void>  成功时 resolve, 失败时 reject.
   * @throws BusinessError 如果 WebviewController 未初始化或发生其他错误。
   */
  static async clearCookiesForDomain(domain: string) {
    console.debug(`Attempting to clear cookies for domain: ${domain}`);
    try {
      if (!domain) {
        throw new Error("Domain cannot be empty.");
      }
      // 从API版本11开始可以使用 clearAllCookies
      await clearBiliCookies();
      console.debug(`Successfully cleared Bilibili cookies.`);
    } catch (error) {
      console.debug(`Failed to clear cookies for domain ${domain}:`, error);
      // 处理错误
      throw new ClearCookiesForDomainError("404-1", "退出登录失败")
    }
  }
}

@Entry
@ComponentV2
export struct BiliLogInOutPage {
  @Param @Require openRecommendPage: () => void
  @Param returnToCaller: boolean = false
  private profileFocusId: string = UUID();
  @Local
  cookieStringPack: CookieStringPack = new CookieStringPack()
  @Local
  private biliService: BilibiliService | null = null
  @Local
  private pageInfos: NavPathStack | null = null
  @Local
  private error0Pack: Error0Pack = new Error0Pack()
  @Local
  private newlyDoneLoginModel:NewlyDoneLoginModel = new NewlyDoneLoginModel()
  @Local
  private loggedInAtLeastOnceStore: LoggedInAtLeastOnceStore = new LoggedInAtLeastOnceStore()

  private closed: boolean = false;
  @Local private sessionState: BiliLoginState = biliLoginState;
  @Monitor('sessionState.loggedIn')
  private sessionChanged(): void {
    if (!this.closed && !this.sessionState.loggedIn && this.cookieStringPack.cookieString !== undefined) {
      this.cookieStringPack.cookieString = undefined;
      this.biliService = null;
    }
  }
  @Monitor("cookieStringPack.cookieString")
  onStrChange(monitor: IMonitor) {
    if (this.closed) { return; }
    monitor.dirty.forEach((path: string) => {

      const newValue: string | undefined = monitor.value(path)?.now as string | undefined
      // cookieStringPack.cookieString有值了
      if (newValue !== undefined && isCurrentBiliSessionEpoch(this.cookieStringPack.sessionEpoch)) {
        // 可以创建BilibiliService对象了
        this.biliService = new BilibiliService(newValue)
        setCurrentBiliService(this.biliService)
        biliLoginState.loggedIn = true
        this.loggedInAtLeastOnceStore.onSuccessfullyLoggedIn()
      }
    })
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 如果已经获取到cookie字符串，则显示
          if (this.cookieStringPack.cookieString !== undefined) {
            Column() {
              biliLogoutView({
                listFocusId: this.profileFocusId,
                error0Pack: this.error0Pack,
                biliService: this.biliService,
                pageInfos: this.pageInfos,
                openRecommendPage: () => this.openRecommendPage()
              })
            }
            // 渐显入场
            .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
          } else {
            // Cookie获取视图，用户会先在这里完成登录
            BiliGetCookieViewStandard({ cookieStringPack: this.cookieStringPack,newlyDoneLoginModel:this.newlyDoneLoginModel })
              .width('100%')
              .height('100%')
              // 渐隐离场
              .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
                TransitionEffect.OPACITY.animation({ duration: 300 })))
          }
        }
        .width('100%')
        .height('100%')

        if (this.error0Pack.error0 !== null) {
          ErrorPrompt({
            errorCode: this.error0Pack.error0.errorCode,
            errorMessage: this.error0Pack.error0.errorMessage,
            showCloseButton: false,
            showRetryButton: false
          })
            .transition(TransitionEffect.OPACITY.animation({}))
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层的半透明卡片正好让它透出来
    .linearGradient({ colors: DarkTheme.pageTopGradients.mine })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => focusWatchList(this.getUIContext(), this.profileFocusId))
    .onWillDisappear(() => {
      this.closed = true;
      // The registry, not this page, owns the shared authenticated service.
      this.biliService = null
    })
    .onBackPressed(() => {
      if (!this.returnToCaller && this.newlyDoneLoginModel.newlyDoneLogin === true) {
        // 如果用户是刚刚完成登录的，在返回的时候需要强制重新进入一下，这样会使用BilibiliService而不是BilibiliServiceWithoutLogin
        if (this.pageInfos !== null) {
          this.pageInfos.clear(true)
          // 用户已登录，放心进已登录的哔哩哔哩主页
          this.pageInfos.pushPathByName("BiliHomeFeedPageWithLogin", undefined)
          // 导航已接管
          return true
        } else {
          // 默认逻辑
          return false
        }
      } else {
        // 默认逻辑
        return false
      }
    })
  }

  @Builder
  cookieStringDebugView() {
    if (this.cookieStringPack.cookieString !== undefined) {
      Scroll() {
        Column() {
          Text('获取到的Cookie:')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 10 })

          Text(this.cookieStringPack.cookieString || '空')
            .fontSize(14)
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding(10)
            .borderRadius(5)
        }
        .padding(20)
        .width('100%')
      }
    } else {
      Text("404-6")
    }
  }
}

@ObservedV2
class Error0Pack {
  @Trace
  error0: ErrorPromptData | null = null
}

@ComponentV2
struct biliLogoutView {
  @Param @Require listFocusId: string;
  @Param @Require error0Pack: Error0Pack
  @Param @Require biliService: BilibiliService | null
  @Param @Require pageInfos: NavPathStack | null = null
  @Param @Require openRecommendPage: () => void
  @Local private loggedInAtLeastOnceStore: LoggedInAtLeastOnceStore = new LoggedInAtLeastOnceStore()
  @Local private scroller: Scroller = new Scroller()
  @Local private avatarUrl: string = ""
  @Local private uname: string = ""
  @Local private money: number = -1
  @Local private bCoin: number = -1
  @Local private currentLevel: number = 0
  @Local private currentExp: number = 0
  @Local private followingCount: number = -1
  @Local private followerCount: number = -1
  @Local private dynamicCount: number = -1
  @Local private statError: string = ''
  @Local private session: BiliLoginState = biliLoginState
  @Local private profileReady: boolean = false
  @Local private profileError: string = ""
  @Local private loggingOut: boolean = false

  private disposed: boolean = false;
  private requestGeneration: number = 0;
  private requests: BilibiliService | undefined = undefined;
  private loadingProvider: BilibiliService | null = null;

  aboutToAppear(): void { this.loadProfile(); }
  aboutToDisappear(): void {
    this.disposed = true;
    this.requestGeneration++;
    this.requests?.releaseHttp();
    this.requests = undefined;
  }
  @Monitor('biliService')
  private serviceChanged(): void { this.loadProfile(); }

  private currentRequest(generation: number, epoch: number): boolean {
    return !this.disposed && generation === this.requestGeneration && isCurrentBiliSessionEpoch(epoch);
  }

  private async loadProfile(): Promise<void> {
    if (this.disposed || this.biliService === null) { return; }
    if (this.requests !== undefined && this.loadingProvider === this.biliService) { return; }
    this.loadingProvider = this.biliService;
    const generation = ++this.requestGeneration;
    const epoch = getBiliSessionEpoch();
    this.requests?.releaseHttp();
    const service = this.biliService.forkForRequests();
    this.requests = service;
    this.profileError = '';
    this.profileReady = false;
    this.statError = '';
    try {
      const currentUserInfo = await service.getCurrentUserInfo();
      if (!this.currentRequest(generation, epoch)) { return; }
      console.debug('Bili profile nav response', JSON.stringify({
        code: currentUserInfo?.code,
        isLogin: currentUserInfo?.data?.isLogin,
        hasMoney: typeof currentUserInfo?.data?.money === 'number',
        hasWallet: typeof currentUserInfo?.data?.wallet?.bcoin_balance === 'number'
      }))
      if (!currentUserInfo.data.isLogin) {
        this.profileError = '登录已失效，请重新登录';
        invalidateBiliSession();
        return;
      }
      // Authentication is published by the session verifier, not late profile responses.
      this.profileReady = true;
      if (typeof currentUserInfo.data.face === 'string') {
        this.avatarUrl = currentUserInfo.data.face
      }
      if (typeof currentUserInfo.data.uname === 'string') {
        this.uname = currentUserInfo.data.uname
      }
      if (typeof currentUserInfo.data.money === 'number') {
        this.money = currentUserInfo.data.money
      }
      if (typeof currentUserInfo.data.wallet?.bcoin_balance === 'number') {
        this.bCoin = currentUserInfo.data.wallet.bcoin_balance
      }
      if (currentUserInfo.data.level_info !== undefined && currentUserInfo.data.level_info !== null) {
        if (typeof currentUserInfo.data.level_info.current_level === 'number') {
          this.currentLevel = currentUserInfo.data.level_info.current_level
        }
        if (typeof currentUserInfo.data.level_info.current_exp === 'number') {
          this.currentExp = currentUserInfo.data.level_info.current_exp
        }
      }

      const currentUserCoin = await service.getCurrentUserCoin();
      if (!this.currentRequest(generation, epoch)) { return; }
      if (currentUserCoin.code === 0 && typeof currentUserCoin.data?.money === 'number') {
        this.money = currentUserCoin.data.money
      }

      const currentUserStat = await service.getCurrentUserStat();
      if (!this.currentRequest(generation, epoch)) { return; }
      console.debug('Bili profile nav/stat response', JSON.stringify({
        code: currentUserStat.code,
        hasData: currentUserStat.data !== undefined
      }))
      if (currentUserStat.code === 0 && currentUserStat.data) {
        this.followingCount = typeof currentUserStat.data.following === 'number' ? currentUserStat.data.following : -1
        this.followerCount = typeof currentUserStat.data.follower === 'number' ? currentUserStat.data.follower : -1
        this.dynamicCount = typeof currentUserStat.data.dynamic_count === 'number' ? currentUserStat.data.dynamic_count : -1
      } else {
        this.statError = `统计接口返回异常（${currentUserStat.code}）`
      }

      if (currentUserInfo.data.mid && (this.followingCount < 0 || this.followerCount < 0 ||
        (this.followingCount === 0 && this.followerCount === 0))) {
        const currentUserCard = await service.getCurrentUserCard(currentUserInfo.data.mid);
        if (!this.currentRequest(generation, epoch)) { return; }
        const card = currentUserCard.data?.card
        if (currentUserCard.code === 0 && card) {
          if (this.followingCount < 0 || (this.followingCount === 0 && typeof card.following === 'number' && card.following > 0)) {
            this.followingCount = typeof card.following === 'number' ? card.following : this.followingCount
          }
          if (this.followerCount < 0 || (this.followerCount === 0 && typeof card.follower === 'number' && card.follower > 0)) {
            this.followerCount = typeof card.follower === 'number' ? card.follower : this.followerCount
          }
        }
      }
      if (this.followingCount < 0 || this.followerCount < 0 || this.dynamicCount < 0) {
        this.statError = this.statError || '统计数据暂不可用'
      }
    } catch (error) {
      if (!this.currentRequest(generation, epoch)) { return; }
      if (error instanceof BiliBusinessError && error.code === -101) {
        this.profileError = '登录已失效，请重新登录';
        invalidateBiliSession();
      } else {
        this.profileError = '账号信息加载失败，请重试';
      }
      if (error instanceof JsonDecodeError) { console.warn(error.message); }
    } finally {
      service.releaseHttp();
      if (this.requests === service) { this.requests = undefined; }
    }
  }

  private formatCount(count: number): string {
    if (count < 0) {
      return '--'
    }
    if (count >= 100000000) {
      return `${(count / 100000000).toFixed(1)}亿`
    }
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}万`
    }
    return `${count}`
  }

  private formatBalance(balance: number): string {
    return balance < 0 ? '--' : `${balance}`
  }

  build() {
    Stack() {
      if (this.avatarUrl) {
        Image(this.avatarUrl)
          .width('100%').height('100%').objectFit(ImageFit.Cover)
          .blur(32).opacity(0.4).hitTestBehavior(HitTestMode.None)
      }
      Column().width('100%').height('100%')
        .backgroundColor('#80121212').hitTestBehavior(HitTestMode.None)
      Column() {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            Image(this.avatarUrl || $r('app.media.layered_image')).width(60).height(60).borderRadius(30)
              .border({ width: 2, color: '#60FFFFFF' })
            Text(this.uname || '我的账号').fontSize(20).fontWeight(FontWeight.Bold).fontColor(DarkTheme.textPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`Lv${this.currentLevel} · ${this.currentExp} 经验`)
              .fontSize(12).fontColor(DarkTheme.biliPink)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 }).backgroundColor('#30FB7299').borderRadius(12)
            Row() {
              Column({ space: 3 }) {
                Text(this.formatCount(this.followingCount)).fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(DarkTheme.textPrimary)
                Text('关注').fontSize(11).fontColor(DarkTheme.textSecondary)
              }.layoutWeight(1).padding({ top: 4, bottom: 4 }).alignItems(HorizontalAlign.Center)
                .onClick(() => {
                  if (this.biliService && this.session.loggedIn) {
                    this.pageInfos?.pushPathByName('BiliFollowingPage', this.biliService)
                  } else {
                    pushBiliLoginRequired(this.pageInfos, '关注');
                  }
                })
              Column({ space: 3 }) {
                Text(this.formatCount(this.followerCount)).fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(DarkTheme.textPrimary)
                Text('粉丝').fontSize(11).fontColor(DarkTheme.textSecondary)
              }.layoutWeight(1).padding({ top: 4, bottom: 4 }).alignItems(HorizontalAlign.Center)
              Column({ space: 3 }) {
                Text(this.formatCount(this.dynamicCount)).fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(DarkTheme.textPrimary)
                Text('动态').fontSize(11).fontColor(DarkTheme.textSecondary)
              }.layoutWeight(1).padding({ top: 4, bottom: 4 }).alignItems(HorizontalAlign.Center)
            }.width('100%').padding({ top: 2, bottom: 2 })
            Row() {
            Column({ space: 5 }) {
              Text(this.formatBalance(this.money)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(DarkTheme.textPrimary)
              Text('硬币').fontSize(11).fontColor(DarkTheme.textSecondary)
            }.layoutWeight(1)
            Column({ space: 5 }) {
              Text(this.formatBalance(this.bCoin)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(DarkTheme.textPrimary)
              Text('B币').fontSize(11).fontColor(DarkTheme.textSecondary)
            }.layoutWeight(1)
            }.width('100%').padding(16).backgroundColor('#991E1E1E').borderRadius(16)

            if (this.statError) {
              Text(this.statError).fontSize(10).fontColor('#FFB347').width('100%').textAlign(TextAlign.Center)
            }

            if (this.profileError) {
              Text(this.profileError).fontColor(DarkTheme.textSecondary).fontSize(12)
              Button('重试').backgroundColor('#991E1E1E').fontColor(DarkTheme.primary)
                .onClick(() => this.loadProfile())
            }
            Button(this.loggingOut ? '正在退出...' : '退出登录').width('80%').height(40).fontSize(14)
              .enabled(!this.loggingOut)
              .backgroundColor('#601E1E1E').fontColor('#FF9299')
              .onClick(() => this.dialogControllerConfirm.open())
          }
          .width('100%').padding({ left: 28, right: 28, top: 30, bottom: 36 })
        }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
        .focusable(true).focusOnTouch(true).defaultFocus(true)
        .id(this.listFocusId)
        .onAppear(() => focusWatchList(this.getUIContext(), this.listFocusId))
      }
      .width('100%').height('100%')
    }
    // 不铺底色，让 NavDestination 的顶部渐变透上来
    .width('100%').height('100%').clip(true)
  }

  @Local
  private dialogControllerConfirm: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      contentBuilder: () => {
        this.dialogTitleView();
      },
      buttons: [
        {
          value: '退出登录',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          role: ButtonRole.ERROR,
          action:() => {
            if (this.disposed || this.loggingOut) { return; }
            (async () => {
              if (this.pageInfos !== null) {
              } else {
                this.getUIContext().getPromptAction().showToast({ message: '退出登录失败' });
                return
              }
              this.loggingOut = true;
              try {
                await BiliLogInOutPageViewModel.clearCookiesForDomain(".bilibili.com")
                invalidateBiliSession();
                clearCurrentBiliService();
                this.pageInfos.clear();
                this.pageInfos.pushPathByName("BiliHomeFeedPageWithoutLogin", undefined);
                this.getUIContext().getPromptAction().showToast({ message: '已退出登录' });
              } catch (anyError) {
                if (anyError instanceof ClearCookiesForDomainError) {
                  const clearCookiesForDomainError: ClearCookiesForDomainError = anyError
                  this.error0Pack.error0 = {
                    errorCode: clearCookiesForDomainError.errorCode,
                    errorMessage: clearCookiesForDomainError.errorMessage
                  }
                } else if (anyError instanceof Error) {
                  const error: Error = anyError
                  this.error0Pack.error0 = { errorCode: null, errorMessage: error.message }
                }
              } finally { this.loggingOut = false; }
            })()
          }
        },
        {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {

          }
        }
      ],
    }),
    width:"100%",
    height:"100%"
  });

  // 用自定义标题栏，这样标题可以居中显示，而不是吸在最上面
  @Builder
  private dialogTitleView(): void {
    Column() {
      // 文本尺寸和系统的弹窗标题是一致的
      Text("确认退出登录？")
        .fontSize("15fp")
        .fontWeight(FontWeight.Bold)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    // 把按钮推下去，而不是在屏幕中间
    .height("157vp")
  }
}

export class LoggedInAtLeastOnceStore {
  async isLoggedInAtLeastOnce(): Promise<boolean> {
    try {
      const db = await AppDatabase.open(getContext())
      return await db.values.getBoolean(StorageKeys.BILI_LOGGED_IN_AT_LEAST_ONCE, false)
    } catch (error) {
      console.debug(logTag, '读取登录过至少一次状态失败: ' + LoggedInAtLeastOnceStore.describe(error))
      return false
    }
  }

  onSuccessfullyLoggedIn(): void {
    (async () => {
      try {
        await this.save(true)
      } catch (error) {
        console.debug(logTag, '保存登录过至少一次状态失败: ' + LoggedInAtLeastOnceStore.describe(error))
      }
    })()
  }

  private async save(isLoggedIn: boolean): Promise<void> {
    const db = await AppDatabase.open(getContext())
    await db.values.setBoolean(StorageKeys.BILI_LOGGED_IN_AT_LEAST_ONCE,
      StorageNamespaces.SETTING, isLoggedIn)
  }

  private static describe(error: Object): string {
    const message = (error as Error).message
    return message === undefined ? 'unknown' : message
  }
}
