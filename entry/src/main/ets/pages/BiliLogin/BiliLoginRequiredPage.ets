import { biliLoginState } from '../../common/BiliSession';
import { LoginRequiredView, LoginRequiredVisual } from '../../components/LoginRequiredView';

// 与 BiliLogInOutPagePushData 的字段保持一致；这里不直接 import 登录页模块，
// 避免只是看热搜榜时也把登录 WebView 相关代码加载进来。
interface BiliLoginPagePushData {
  openRecommendPage: () => void
  returnToCaller: boolean
}

/**
 * 中间页参数。功能名和账号名分开传，后续其它需要登录的功能也能复用这一页。
 * 例如 { featureName: '搜索', accountName: '哔哩哔哩' } 会显示
 * “搜索功能需登录哔哩哔哩账号后使用”。
 */
export interface BiliLoginRequiredParam {
  featureName: string
  accountName: string
}

export function biliLoginRequiredParam(featureName: string,
  accountName: string = '哔哩哔哩'): BiliLoginRequiredParam {
  return {
    featureName: featureName,
    accountName: accountName
  }
}

/**
 * 以导航栈为准去重，而不是记一个“已弹过”的布尔量：布尔量在右滑返回时
 * 可能来不及复位，导致第二次点入口没有任何反应；中间页出栈后，
 * getIndexByName 自然返回空，可以再次打开。
 *
 * 返回 false 只表示导航栈还没准备好，调用方需要给出提示。
 */
export function pushBiliLoginRequired(pageInfos: NavPathStack | null, featureName: string): boolean {
  if (pageInfos === null) {
    return false;
  }
  if (pageInfos.getIndexByName("BiliLoginRequiredPage").length > 0) {
    return true;
  }
  pageInfos.pushPathByName("BiliLoginRequiredPage", biliLoginRequiredParam(featureName));
  return true;
}

@Builder
export function BiliLoginRequiredPageBuilder(name: string, param: Object) {
  BiliLoginRequiredPage({
    featureName: (param as BiliLoginRequiredParam | undefined)?.featureName ?? '该',
    accountName: (param as BiliLoginRequiredParam | undefined)?.accountName ?? '哔哩哔哩'
  })
}

/**
 * 需要登录才能使用的功能，统一先插入这个中间页。
 * “继续”是画面主按钮（ArcButton，贴底）；“取消”是它上方的小号非强调按钮。
 */
@Entry
@ComponentV2
struct BiliLoginRequiredPage {
  @Param featureName: string = '该'
  @Param accountName: string = '哔哩哔哩'
  @Local private pageInfos: NavPathStack | null = null
  private waitingForLogin: boolean = false

  private closePage(): void {
    if (this.pageInfos !== null) {
      this.pageInfos.pop()
    }
  }

  private goToLogin(): void {
    if (this.waitingForLogin) { return; }
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({
        message: "无法打开页面，App导航堆栈状态异常，建议重启App。\n错误信息：导航堆栈未准备就绪。"
      })
      return
    }
    this.waitingForLogin = true
    // 登录成功后回到这里，由 onShown 自动出栈，回到发起登录的功能页。
    // returnToCaller 阻止登录页沿用“清空栈并回推荐页”的旧行为。
    const pushData: BiliLoginPagePushData = {
      openRecommendPage: () => {},
      returnToCaller: true
    }
    this.pageInfos.pushPathByName("BiliLogInOutPage", pushData)
  }

  build() {
    NavDestination() {
      LoginRequiredView({
        featureName: this.featureName,
        accountName: this.accountName,
        visual: LoginRequiredVisual.Bili,
        onContinue: () => this.goToLogin(),
        onCancel: () => this.closePage()
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => {
      if (!this.waitingForLogin) { return; }
      this.waitingForLogin = false;
      if (biliLoginState.loggedIn) {
        // 用户已经完成登录，中间页使命结束，直接回到发起登录的功能页。
        this.closePage()
      }
    })
  }
}
