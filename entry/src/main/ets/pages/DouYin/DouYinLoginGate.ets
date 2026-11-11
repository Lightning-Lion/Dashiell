import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ColorMetrics,
  LengthMetrics
} from '@kit.ArkUI';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { DarkTheme } from '../../common/Theme';
import { DouyinCookieStore } from '../../common/douyin/DouyinCookieStore';
import { DouYinLoginPagePushData } from './DouYinLoginPage';

// 推荐接口必须有登录 Cookie 才能返回可播的视频，所以精选页先过这道门。
// 判定只看 Cookie 里的登录标记，不额外发请求（见 DouyinCookieStore.isLoggedIn）。

export enum DouYinLoginGateState {
  Checking = 0,
  LoggedOut = 1,
  LoggedIn = 2
}

@ObservedV2
export class DouYinLoginGateModel {
  @Trace
  state: DouYinLoginGateState = DouYinLoginGateState.Checking
  private generation: number = 0;

  /**
   * 检查登录态。页面在 onReady 与 onShown 各调一次：前者是首次进入，
   * 后者覆盖「去登录页又返回」。每次重新显示都复查 Cookie，避免退出登录后继续显示个人列表。
   */
  check(): void {
    this.state = DouYinLoginGateState.Checking;
    this.generation++;
    const generation = this.generation;
    (async () => {
      const loggedIn = await DouyinCookieStore.isLoggedIn();
      // 页面离开后的旧检查不能覆盖重进后的状态
      if (generation === this.generation) {
        this.state = loggedIn ? DouYinLoginGateState.LoggedIn : DouYinLoginGateState.LoggedOut;
      }
    })();
  }
}

// 未登录时盖住整个精选页：检查中显示进度，未登录显示提示与入口。
@ComponentV2
export struct DouYinLoginRequiredView {
  @Param contentName: string = '推荐视频'
  @Param afterLoginPage: string = 'DouYinJingxuanPage'
  @Param @Require state: DouYinLoginGateState
  @Param @Require pageInfos: NavPathStack | null

  private goToLogin(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
      return
    }
    const pushData: DouYinLoginPagePushData = { openJingxuanAfterLogin: true, afterLoginPage: this.afterLoginPage }
    this.pageInfos.pushPathByName("DouYinLoginPage", pushData)
  }

  build() {
    Column() {
      if (this.state === DouYinLoginGateState.Checking) {
        Column({ space: "15vp" }) {
          AnimatedProgressView({ color: DarkTheme.accents.douyin })
            .width("50vp")
            .height("50vp")
          Text("正在检查登录状态")
            .fontSize("17fp")
            .fontWeight(FontWeight.Bold)
            .fontColor(DarkTheme.accents.douyin)
        }
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      } else {
        Blank()
        Column({ space: "8vp" }) {
          Image($r('app.media.dou_menu_login'))
            .width("48vp")
            .height("48vp")
            .opacity(0.92)
          Text('登录抖音')
            .fontSize("20fp")
            .fontWeight(FontWeight.Bold)
            .fontColor(DarkTheme.textPrimary)
          Text('登录后即可查看' + this.contentName)
            .fontSize("13fp")
            .fontColor(DarkTheme.textSecondary)
            .textAlign(TextAlign.Center)
            .lineBreakStrategy(LineBreakStrategy.GREEDY)
            .width("86%")
        }
        .width("100%")
        .alignItems(HorizontalAlign.Center)
        // 视觉重心略高于几何中心；也给底部 ArcButton 留出呼吸。
        .margin({ bottom: "24vp" })
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        Blank()
        ArcButton({
          options: new ArcButtonOptions({
            label: "去登录",
            position: ArcButtonPosition.BOTTOM_EDGE,
            styleMode: ArcButtonStyleMode.CUSTOM,
            backgroundColor: ColorMetrics.rgba(254, 44, 85),
            fontColor: ColorMetrics.rgba(255, 255, 255),
            fontSize: LengthMetrics.fp(18),
            shadowEnabled: true,
            shadowColor: ColorMetrics.rgba(254, 44, 85, 0.45),
            onClick: () => {
              this.goToLogin()
            }
          })
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    // 抖音系页面统一的顶部渐变；未登录态不再是一块纯灰底。
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
  }
}
