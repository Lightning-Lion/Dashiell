import { hasBiliSessionCookie } from '../../common/BiliCookies';
import { checkBiliSession, biliLoginState, restoreBiliSessionCookie, getBiliSessionEpoch, assertBiliSessionEpoch, BiliSessionSuperseded } from '../../common/BiliSession';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { webview } from '@kit.ArkWeb';
import { ErrorPrompt } from '../../components/ErrorPages';
import { bilibiliWebView, BiliLoginWebViewPage, BiliIsLoggedInData, NewlyDoneLoginModel } from './BiliLoginWebView';
import { DarkTheme } from '../../common/Theme';

/**
 * Cookie字符串的包装类，用于在组件间传递cookie信息
 */
@ObservedV2
export class CookieStringPack {
  sessionEpoch: number = -1;
  @Trace
  cookieString: string | undefined = undefined
}

/**
 * Cookie获取状态枚举
 */
enum CookieStatus {
  LOADING,
  SUCCESS,
  ERROR
}

/**
 * BiliGetCookieView的ViewModel
 */
@ObservedV2
class BiliGetCookieViewModel {
  @Trace
  isLoggedInPack: BiliIsLoggedInData = new BiliIsLoggedInData(false)
  @Trace
  cookieStringPack: CookieStringPack
  private domain: string = 'https://www.bilibili.com/';
  @Trace checking: boolean = true;
  @Trace needsLogin: boolean = false;
  private disposed: boolean = false;

  dispose(): void {
    this.disposed = true;
  }

  async restoreSession(): Promise<void> {
    if (this.disposed) { return; }
    const epoch = getBiliSessionEpoch();
    this.checking = true;
    this.needsLogin = false;
    this.showErrorPrompt = false;
    try {
      webview.WebviewController.initializeWebEngine();
      const cookie = await restoreBiliSessionCookie(undefined, epoch);
      assertBiliSessionEpoch(epoch);
      const valid = cookie !== undefined;
      if (this.disposed) { return; }
      if (valid) {
        // restoreSession 与登录后取 Cookie 走同一状态路径，避免已登录用户再次进入登录页。
        biliLoginState.loggedIn = true;
        this.cookieStringPack.sessionEpoch = epoch;
        this.cookieStringPack.cookieString = cookie;
      } else {
        this.needsLogin = true;
      }
    } catch (error) {
      if (!this.disposed) {
        this.errorMessage = error instanceof BiliSessionSuperseded ? '登录状态已更新，请重试' : '检查登录状态失败，请检查网络后重试';
        this.showErrorPrompt = true;
      }
    } finally {
      if (!this.disposed) { this.checking = false; }
    }
  }

  @Monitor("isLoggedInPack.isLoggedIn")
  fetchCookieStringAfterDoneLogin(monitor: IMonitor) {
    if (this.isLoggedInPack.isLoggedIn === true) {
      console.debug("🚩观察到用户已完成登录")
      // 页面获取Cookie
      this.getCookiesForDomain(this.domain);
    }
  }

  status: CookieStatus = CookieStatus.LOADING
  @Trace errorMessage: string = ''
  @Trace errorCode: string = ''
  @Trace showErrorPrompt: boolean = false

  constructor(cookieStringPack: CookieStringPack) {
    this.cookieStringPack = cookieStringPack
  }

  /**
   * 获取指定域名的Cookie字符串
   *
   * @param domain 要获取Cookie的域名（例如：".bilibili.com"）
   * @returns Promise<void> 成功时resolve，失败时reject
   */
  async getCookiesForDomain(domain: string): Promise<void> {
    const epoch = getBiliSessionEpoch();
    this.status = CookieStatus.LOADING;
    this.showErrorPrompt = false;

    try {
      if (!domain) {
        throw new Error("Domain cannot be empty.");
      }

      // 使用WebCookieManager获取所有cookie
      const cookieManager = webview.WebCookieManager;
      const cookieString = this.isLoggedInPack.verifiedCookie ?? await cookieManager.fetchCookie(domain);
      if (this.disposed) { return; }
      assertBiliSessionEpoch(epoch);
      if (this.isLoggedInPack.verifiedCookie !== undefined) { assertBiliSessionEpoch(this.isLoggedInPack.verifiedEpoch); }
      if (!hasBiliSessionCookie(cookieString)) { throw new Error('登录凭据为空，请重试'); }
      if (this.isLoggedInPack.verifiedCookie === undefined) {
        if (!await checkBiliSession(cookieString, false, epoch)) { throw new Error('登录尚未完成，请重试'); }
        await cookieManager.saveCookieAsync();
      }
      if (this.disposed) { return; }
      assertBiliSessionEpoch(epoch);
      biliLoginState.loggedIn = true;
      this.cookieStringPack.sessionEpoch = epoch;
      this.cookieStringPack.cookieString = cookieString;
      this.status = CookieStatus.SUCCESS;
    } catch (error) {
      if (this.disposed) { return; }
      this.status = CookieStatus.ERROR;

      // 处理错误
      this.errorMessage = "Cookie获取失败";
      this.errorCode = "404-2";
      this.showErrorPrompt = true;
    }
  }

  /**
   * 关闭错误提示
   */
  closeErrorPrompt(): void {
    this.showErrorPrompt = false;
  }
}

/**
 * BiliGetCookieView组件
 * 用于获取Bilibili网站的Cookie并传递给外部
 */

@ComponentV2
export struct BiliGetCookieViewStandard {
  @Param @Require
  cookieStringPack: CookieStringPack
  @Param @Require newlyDoneLoginModel:NewlyDoneLoginModel
  @Local
  vm: BiliGetCookieViewModel = new BiliGetCookieViewModel(this.cookieStringPack)

  aboutToAppear(): void {
    this.vm.restoreSession();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.vm.checking) {
        Column({ space: 16 }) {
          AnimatedProgressView({ color: DarkTheme.biliPink }).width(50).height(50)
          Text("正在检查登录状态").fontColor(DarkTheme.biliPink)
        }
      } else if (this.vm.needsLogin) {
        Column() {
          BiliLoginWebViewPage({
            isLoggedInPack: this.vm.isLoggedInPack,
            webViewInitData: bilibiliWebView,
            newlyDoneLoginModel:this.newlyDoneLoginModel
          })
        }
        .width('100%')
        .height('100%')

      }

      // 错误提示弹窗
      if (this.vm.showErrorPrompt) {
        ErrorPrompt({
          errorMessage: this.vm.errorMessage,
          errorCode: this.vm.errorCode,
          showRetryButton: true,
          showCloseButton: false,
          onRetry: () => {
            if (this.vm.needsLogin) {
              this.vm.getCookiesForDomain("https://www.bilibili.com/");
            } else {
              this.vm.restoreSession();
            }
          },
          onClose: () => {
            this.vm.closeErrorPrompt();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
