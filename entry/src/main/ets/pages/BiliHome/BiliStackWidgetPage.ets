import { readBiliCookieCandidates } from '../../common/BiliCookies';
import { BiliLoginState, biliLoginState, restoreBiliSessionCookie, getBiliSessionEpoch, assertBiliSessionEpoch } from '../../common/BiliSession';
import { BiliLogInOutPagePushData, LoggedInAtLeastOnceStore } from "../BiliLogout/BiliLogInOutPage";
import { BilibiliService } from "../../common/BiliService";
import { getCurrentBiliService, resolveAuthenticatedBiliService, setCurrentBiliService } from "../../common/BiliServiceRegistry";
import { webview } from '@kit.ArkWeb';
import { CardInfo, StackWidgetPage, StackWidgetPageScrollController } from "../../components/StackWidgetPage";
import { pushBiliLoginRequired } from "../BiliLogin/BiliLoginRequiredPage";

enum BiliMenuPendingEntry {
  None = 0,
  Favorites = 1,
  History = 2
}

export interface BiliStackWidgetPushData {
  service: BilibiliService
  loggedIn: boolean
}

@Builder
export function BiliStackWidgetPageBuilder() {
  BiliStackWidgetPage()
}

@ComponentV2
export struct BiliStackWidgetPage {
  @Local
  private session: BiliLoginState = biliLoginState
  @Local private isLoggedIn: boolean = biliLoginState.loggedIn
  private loginHistory: LoggedInAtLeastOnceStore = new LoggedInAtLeastOnceStore()
  @Local private param: BilibiliService | undefined = undefined
  @Local private scrollMod:StackWidgetPageScrollController = new StackWidgetPageScrollController()
  private pageStack: NavPathStack | null = null
  // 从登录中间页返回后要接着打开的功能；取消登录时在 onNavShown 里清空。
  private pendingEntry: BiliMenuPendingEntry = BiliMenuPendingEntry.None

  private disposed: boolean = false;
  private restoring: boolean = false;
  aboutToDisappear(): void { this.disposed = true; }

  // 用户可能从搜索等功能的登录中间页完成登录后返回菜单；这里同步卡片标题和后续入口，
  // 避免菜单仍显示“登录”，或在已登录时又把收藏/历史送去登录页。
  @Monitor('session.loggedIn')
  private sessionChanged(): void {
    this.isLoggedIn = this.session.loggedIn;
    if (this.session.loggedIn && this.param === undefined) {
      this.param = getCurrentBiliService() ?? undefined;
    }
  }

  aboutToAppear(): void {
    this.restoreLoginState();
  }

  private async restoreLoginState(): Promise<void> {
    if (this.disposed || this.restoring) { return; }
    this.restoring = true;
    const epoch = getBiliSessionEpoch();
    try {
      // Use the same persisted login marker as the Bilibili entry route. This
      // prevents a cold start from showing the stale in-memory default false.
      const loggedInBefore = await this.loginHistory.isLoggedInAtLeastOnce();
      if (this.disposed) { return; }
      assertBiliSessionEpoch(epoch);
      if (loggedInBefore) { this.isLoggedIn = true; }
      webview.WebviewController.initializeWebEngine();
      // Login redirects through m.bilibili.com, while older sessions may be
      // scoped to www.bilibili.com. Read both cookie scopes on cold start.
      const cookies = await readBiliCookieCandidates();
      if (this.disposed) { return; }
      assertBiliSessionEpoch(epoch);
      const cookie = cookies[0] ?? '';
      // Restore the menu state immediately from the persisted session cookie.
      // Waiting for the network check here made a valid logged-in user see
      // “登录” briefly (or permanently when the check timed out).
      const hasSessionCookie = /(^|;\s*)SESSDATA=[^;]+/.test(cookie || '');
      if (!hasSessionCookie) {
        this.isLoggedIn = false;
        biliLoginState.loggedIn = false;
        return;
      }
      this.isLoggedIn = true;
      biliLoginState.loggedIn = true;
      setCurrentBiliService(new BilibiliService(cookie));
      const verifiedCookie = await restoreBiliSessionCookie(undefined, epoch);
      if (this.disposed) { return; }
      assertBiliSessionEpoch(epoch);
      if (verifiedCookie === undefined) {
        this.isLoggedIn = false;
        biliLoginState.loggedIn = false;
      } else if (verifiedCookie !== cookie) {
        setCurrentBiliService(new BilibiliService(verifiedCookie));
      }
    } catch (error) {
      if (!this.disposed) { console.warn('Bili menu session refresh did not complete'); }
    } finally { this.restoring = false; }
  }

  @Computed
  private get cardData() {
    const list: Array<CardInfo> = [
      {
        title: '推荐',
        svgIcon: $r("app.media.BilibiliRecommend"),
        gradientColors: [['#00B4DB', 0], ['#0083B0', 1]],
        onClick:(pageInfos: NavPathStack) => { this.click0(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: this.isLoggedIn ? "我的" : "登录",
        svgIcon: $r("app.media.BilibiliPersonal"),
        gradientColors: [['#F953C6', 0], ['#B91D73', 1]],
        onClick:(pageInfos: NavPathStack) => { this.click1(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: '搜索',
        svgIcon: $r("app.media.BiliSearch"),
        gradientColors: [['#969696', 0], ['#555555', 1]],
        onClick:(pageInfos: NavPathStack) => { this.click2(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: '收藏',
        svgIcon: $r("app.media.bili_video_detail_page_has_favorite"),
        gradientColors: [['#F7971E', 0], ['#FFD200', 1]],
        iconColor: Color.White,
        onClick:(pageInfos: NavPathStack) => { this.click3(pageInfos) }
      },
      {
        title: '历史',
        svgIcon: $r("app.media.bili_video_detail_page_watch_count"),
        gradientColors: [['#43CEA2', 0], ['#185A9D', 1]],
        onClick:(pageInfos: NavPathStack) => { this.click4(pageInfos) }
      },
      {
        title: '联系我们',
        svgIcon: $r("app.media.stack_contact_us_icon"),
        gradientColors: [['#2A0BD0', 0], ['#7744FF', 1]],
        onClick:(pageInfos: NavPathStack) => { this.click5(pageInfos) } // 在实际点击的时候才调用我的的函数
      }
    ]
    return list
  }

  build() {
    StackWidgetPage({
      cardData:this.cardData,
      onNavReady:(context: NavDestinationContext) => {
        // Navigation parameters can be materialized as plain objects and lose
        // BilibiliService methods. Reuse the live process instance instead.
        this.pageStack = context.pathStack;
        const liveService = getCurrentBiliService();
        const routeParam = context.pathInfo.param as BiliStackWidgetPushData | undefined;
        this.param = liveService || routeParam?.service;
        // Reaching this menu from the logged-in home already proves that a
        // live authenticated service exists. Do not wait for WebView cookie
        // restoration to update the first rendered card title.
        if (liveService !== null && this.session.loggedIn) {
          this.isLoggedIn = true;
          biliLoginState.loggedIn = true;
        }
        this.restoreLoginState();

      },
      onNavShown: () => this.resumePendingEntry(),
      scrollMod:this.scrollMod
    })
  }

  private click0(pageInfos: NavPathStack) {
    (async () => {
      console.debug("🚩点击了0")
      const isLoggedInAtLeastOnce: boolean = this.session.loggedIn
      if (isLoggedInAtLeastOnce) {
        if (pageInfos.getIndexByName("BiliHomeFeedPageWithLogin").length !== 0) {
          // 上一页就是推荐视频（已登录）的列表
          pageInfos.removeByName("BiliStackWidgetPage")
        } else {
          pageInfos.pushPathByName("BiliHomeFeedPageWithLogin", undefined)
        }
      } else {
        if (pageInfos.getIndexByName("BiliHomeFeedPageWithoutLogin").length !== 0) {
          // 上一页就是推荐视频（未登录）的列表
          pageInfos.removeByName("BiliStackWidgetPage")
        } else {
          pageInfos.pushPathByName("BiliHomeFeedPageWithoutLogin", undefined)
        }
      }
    })()
  }

  private click1(pageInfos: NavPathStack) {
    console.debug("🚩点击了1")
    const pushData: BiliLogInOutPagePushData = {
      openRecommendPage: (): void => {
        this.scrollMod.scrollToTop()
        this.click0(pageInfos)
      }
    }
    pageInfos.pushPathByName("BiliLogInOutPage", pushData)
  }

  private click2(pageInfos: NavPathStack) {
    console.debug("🚩点击了2")
    pageInfos.pushPathByName("BiliSearch", this.param)
  }

  private click3(pageInfos: NavPathStack) {
    console.debug("🚩点击了收藏")
    const service = resolveAuthenticatedBiliService(this.param);
    if (service !== null) {
      pageInfos.pushPathByName("BiliFavoritesPage", service)
      return;
    }
    this.pendingEntry = BiliMenuPendingEntry.Favorites;
    if (!pushBiliLoginRequired(pageInfos, '收藏')) {
      this.pendingEntry = BiliMenuPendingEntry.None;
      this.getUIContext().getPromptAction().showToast({ message: "无法打开页面\n错误信息：导航堆栈未准备就绪" })
    }
  }

  private click4(pageInfos: NavPathStack) {
    console.debug("🚩点击了历史")
    const service = resolveAuthenticatedBiliService(this.param);
    if (service !== null) {
      pageInfos.pushPathByName("BiliHistoryPage", service)
      return;
    }
    this.pendingEntry = BiliMenuPendingEntry.History;
    if (!pushBiliLoginRequired(pageInfos, '历史')) {
      this.pendingEntry = BiliMenuPendingEntry.None;
      this.getUIContext().getPromptAction().showToast({ message: "无法打开页面\n错误信息：导航堆栈未准备就绪" })
    }
  }

  private resumePendingEntry(): void {
    const entry = this.pendingEntry;
    this.pendingEntry = BiliMenuPendingEntry.None;
    if (entry === BiliMenuPendingEntry.None || this.pageStack === null) { return; }
    // 从登录页返回后以进程内当前登录服务为准，不依赖可能滞后的 isLoggedIn 字段。
    const service = resolveAuthenticatedBiliService(this.param);
    if (service === null) { return; }
    if (entry === BiliMenuPendingEntry.Favorites) {
      this.pageStack.pushPathByName("BiliFavoritesPage", service)
    } else if (entry === BiliMenuPendingEntry.History) {
      this.pageStack.pushPathByName("BiliHistoryPage", service)
    }
  }

  private click5(pageInfos: NavPathStack) {
    console.debug("🚩点击了3")
    pageInfos.pushPathByName("CustomerServicePage", undefined)
  }
}
