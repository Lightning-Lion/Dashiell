import { LoginRequiredView, LoginRequiredVisual } from '../../components/LoginRequiredView';

// 与 DouYinLoginPagePushData 的字段保持一致；不直接 import 登录页模块，
// 让抖音中间页可以独立加载。
interface DouYinLoginPagePushData {
  openJingxuanAfterLogin: boolean
  afterLoginPage: string
}

export interface DouYinLoginRequiredParam {
  featureName: string
  accountName: string
  afterLoginPage: string
}

export function douyinLoginRequiredParam(featureName: string, afterLoginPage: string,
  accountName: string = '抖音'): DouYinLoginRequiredParam {
  return {
    featureName: featureName,
    accountName: accountName,
    afterLoginPage: afterLoginPage
  }
}

/**
 * 以导航栈为准去重，不在内存里记“已弹过”状态。
 * 返回 false 只表示导航栈还没准备好，调用方需要给出提示。
 */
export function pushDouYinLoginRequired(pageInfos: NavPathStack | null, featureName: string,
  afterLoginPage: string): boolean {
  if (pageInfos === null) {
    return false;
  }
  if (pageInfos.getIndexByName("DouYinLoginRequiredPage").length > 0) {
    return true;
  }
  pageInfos.pushPathByName("DouYinLoginRequiredPage",
    douyinLoginRequiredParam(featureName, afterLoginPage));
  return true;
}

@Builder
export function DouYinLoginRequiredPageBuilder(name: string, param: Object) {
  DouYinLoginRequiredPage({
    featureName: (param as DouYinLoginRequiredParam | undefined)?.featureName ?? '该',
    accountName: (param as DouYinLoginRequiredParam | undefined)?.accountName ?? '抖音',
    afterLoginPage: (param as DouYinLoginRequiredParam | undefined)?.afterLoginPage ?? 'DouYinJingxuanPage'
  })
}

/**
 * 抖音的登录中间页。登录成功后由 DouYinLoginPage 清栈并直接进入菜单 + 目标页，
 * 所以这里不需要像哔哩哔哩那样在 onShown 里自动 pop。
 */
@Entry
@ComponentV2
struct DouYinLoginRequiredPage {
  @Param featureName: string = '该'
  @Param accountName: string = '抖音'
  @Param afterLoginPage: string = 'DouYinJingxuanPage'
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
    const pushData: DouYinLoginPagePushData = {
      openJingxuanAfterLogin: true,
      afterLoginPage: this.afterLoginPage
    }
    this.pageInfos.pushPathByName("DouYinLoginPage", pushData)
  }

  build() {
    NavDestination() {
      LoginRequiredView({
        featureName: this.featureName,
        accountName: this.accountName,
        visual: LoginRequiredVisual.Douyin,
        onContinue: () => this.goToLogin(),
        onCancel: () => this.closePage()
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => {
      // 用户可能从登录页直接返回而没有完成登录；复位后「继续」才能再次进入登录页。
      this.waitingForLogin = false;
    })
  }
}
