import { LengthMetrics, window } from "@kit.ArkUI";
import { logTag } from "../../common/printLog";
import { AppDatabase } from "../../common/storage/AppDatabase";
import { StorageKeys, StorageNamespaces } from "../../common/storage/StorageKeys";
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { UUID } from "../../common/UUID";
import { common } from "@kit.AbilityKit";
import { HomePageRSSList } from "../RSS/HomePageRSSList";
import { DarkTheme } from "../../common/Theme";
import { RSSHeroTransition } from "../../common/RSSHeroTransition";

@ComponentV2
export struct LandingPageL1 {
  @Param @Require pageInfos: NavPathStack
  // 首页条目点进去的转场状态，由 NavigationStack 持有并画在最上层
  @Param @Require hero: RSSHeroTransition
  @Local
  private store: LandingPageStore = new LandingPageStore()
  @Local
  private showLandingPage: boolean | null = null
  @Local
  private agreeAndDisagreeModel: AgreeAndDisagreeModel = new AgreeAndDisagreeModel()

  @Monitor("agreeAndDisagreeModel.agreeToken")
  private onAgree() {
    // 先切换，再存储
    this.store.onAgree()
    this.showLandingPage = false
  }

  @Monitor("agreeAndDisagreeModel.disagreeToken")
  private onDisagree() {
    (async () => {
      // 先存储状态，再退出App
      await this.store.onDisagree()
      await this.minimizeMainWindow()
      await this.exitApp()
    })()
  }

  build() {
    Column() {
      if (this.showLandingPage !== null) {
        if (this.showLandingPage) {
          LandingPageL0({ agreeAndDisagreeModel: this.agreeAndDisagreeModel, pageInfos: this.pageInfos })
            .width("100%")
            .height("100%")
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        } else {
          HomePageRSSList({ pageInfos: this.pageInfos, hero: this.hero })
        }
      } else {
        Column({ space: "30px" }) {
          AnimatedProgressView({ color: DarkTheme.accents.brand })
            .width(50)
            .height(50)
          Text("启动中")
            .fontColor(DarkTheme.accents.brand)
            .fontWeight(FontWeight.Bold)
        }
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
        .backgroundColor(Color.Black)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        .onAppear(async () => {
          const isPrivacyPolicyAgreed: boolean = await this.store.isPrivacyPolicyAgreed()
          this.showLandingPage = !isPrivacyPolicyAgreed
        })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }

  private async minimizeMainWindow() {
    try {
      // 获取当前应用的WindowStage对象
      const mainWindow = await window.getLastWindow(getContext())
      // 最小化主窗口
      await mainWindow.minimize();

      console.debug(logTag, '成功最小化主窗口');
    } catch (error) {
      console.debug(logTag, `最小化主窗口失败: ${error.message}`);
    }
  }

  private async exitApp() {
    const context = getContext(this) as common.UIAbilityContext
    await context.terminateSelf()
  }
}

// 上层监听值的变换，而不是让下层持有上层的闭包
@ObservedV2
class AgreeAndDisagreeModel {
  @Trace
  agreeToken: string = UUID()
  @Trace
  disagreeToken: string = UUID()
}

class LandingPageStore {
  async isPrivacyPolicyAgreed(): Promise<boolean> {
    try {
      const db = await AppDatabase.open(getContext())
      return await db.values.getBoolean(StorageKeys.PRIVACY_POLICY_AGREED, false)
    } catch (error) {
      console.debug(logTag, '读取隐私政策状态失败: ' + LandingPageStore.describe(error))
      return false
    }
  }

  onAgree(): void {
    (async () => {
      try {
        await this.save(true)
      } catch (error) {
        console.debug(logTag, '保存隐私政策同意状态失败: ' + LandingPageStore.describe(error))
      }
    })()
  }

  async onDisagree(): Promise<void> {
    try {
      await this.save(false)
    } catch (error) {
      console.debug(logTag, '保存隐私政策拒绝状态失败: ' + LandingPageStore.describe(error))
    }
  }

  private async save(isAgree: boolean): Promise<void> {
    const db = await AppDatabase.open(getContext())
    await db.values.setBoolean(StorageKeys.PRIVACY_POLICY_AGREED, StorageNamespaces.SETTING, isAgree)
  }

  private static describe(error: Object): string {
    const message = (error as Error).message
    return message === undefined ? 'unknown' : message
  }
}


@ComponentV2
export struct LandingPageL0 {
  @Param @Require agreeAndDisagreeModel: AgreeAndDisagreeModel
  @Param @Require pageInfos: NavPathStack
  @Local
  private textSize: string = "15fp"

  build() {
    Column({ space: "4fp" }) {
      Row({ space: "0fp" }) {
        Text("欢迎使用腕上RSS，本服务需要联网，并请在使用前仔细阅读")
          .textAlign(TextAlign.Start)
          .fontSize(this.textSize)
        Blank()
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")

      // 超链接
      Button({ type: ButtonType.ROUNDED_RECTANGLE, role: ButtonRole.NORMAL, buttonStyle: ButtonStyleMode.NORMAL }) {
        Row({ space: "0fp" }) {
          Text("《腕上RSS隐私政策》")
            .textAlign(TextAlign.Start)
            .fontSize(this.textSize)
            .fontColor($r("app.color.landing_page_agree_link_text_color"))
          Blank()
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width("100%")
      }
      .stateEffect(true)
      .backgroundColor(Color.Transparent)
      .width("100%")
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.pageInfos.pushPathByName("PrivacyPolicyPage", undefined)
      })

      Row({ space: "0fp" }) {
        Text("同意该政策后，我们方可提供服务，是否同意？")
          .textAlign(TextAlign.Start)
          .fontSize(this.textSize)
        Blank()
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")

      ButtonRow({ agreeAndDisagreeModel: this.agreeAndDisagreeModel })
        .padding({
          top: LengthMetrics.fp(2)
        })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({
      top: LengthMetrics.fp(43),
      start: LengthMetrics.fp(33),
      end: LengthMetrics.fp(33),
      bottom: LengthMetrics.fp(43)
    })
    .width("100%")
    .height("100%")
  }
}

@ComponentV2
struct ButtonRow {
  @Param @Require agreeAndDisagreeModel: AgreeAndDisagreeModel
  @Local
  private buttonHeight: number = 35

  @Computed
  get buttonRadius(): number {
    return this.buttonHeight / 2
  }

  build() {
    Row({ space: "0fp" }) {
      Button({
        type: ButtonType.Normal,
        role: ButtonRole.NORMAL,
        buttonStyle: ButtonStyleMode.NORMAL,
        stateEffect: true
      }) {
        Text("不同意")
          .fontColor($r("app.color.landing_page_cancel_button_text_color"))
      }
      .backgroundColor($r("app.color.landing_page_cancel_button_background_color"))
      .height(this.buttonHeight + "fp")
      .borderRadius({
        topLeft: this.buttonRadius + "fp",
        bottomLeft: this.buttonRadius + "fp"
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.agreeAndDisagreeModel.disagreeToken = UUID()
      })
      .layoutWeight(1)

      Button({
        type: ButtonType.Normal,
        role: ButtonRole.NORMAL,
        buttonStyle: ButtonStyleMode.NORMAL,
        stateEffect: true
      }) {
        Text("同意")
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .backgroundColor($r("app.color.landing_page_agree_button_background_color"))
      .height(this.buttonHeight + "fp")
      .borderRadius({
        topRight: this.buttonRadius + "fp",
        bottomRight: this.buttonRadius + "fp"
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.agreeAndDisagreeModel.agreeToken = UUID()
      })
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("88%")
  }
}