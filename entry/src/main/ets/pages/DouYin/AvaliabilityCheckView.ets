import { deviceInfo } from '@kit.BasicServicesKit';
import { WifiManager } from '../../common/WiFiManager';
import { ColorMetrics, LengthMetrics } from '@kit.ArkUI';
import { SettingsButton } from '../../common/SettingsButton';

// 满足要求才显示其内的视图，否则显示我预设的提示页面。
@ComponentV2
export struct DouYinAvaliabilityCheck {
  @BuilderParam content: () => void
  // 默认强拦：无可用网络时挡住内容页，显示“暂未检测到默认网络”提示。
  @Param requireNetwork: boolean = true
  // 供拦截页 push“网络诊断”页使用；由调用方（精选/登录页）传入自己的 NavPathStack。
  @Param pageInfos: NavPathStack | null = null
  build() {
    Harmony6OnlyView({
      content:this.content,
      requireNetwork:this.requireNetwork,
      pageInfos:this.pageInfos
    })
  }
}

// 鸿蒙6是API20开始。
// https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-600
@ComponentV2
struct Harmony6OnlyView {
  @BuilderParam content: () => void
  @Param requireNetwork: boolean = true
  @Param pageInfos: NavPathStack | null = null
  @Local
  private harmonyOS6MinimalAPIVersion:number = 20
  build() {
    if (deviceInfo.sdkApiVersion >= this.harmonyOS6MinimalAPIVersion) {
      WiFiOnlyView({
        content:this.content,
        requireNetwork:this.requireNetwork,
        pageInfos:this.pageInfos
      })
    } else {
      ContentUnavailablePageByChromium()
    }
  }
}

@ComponentV2
struct WiFiOnlyView {
  @BuilderParam content: () => void
  @Param requireNetwork: boolean = true
  @Param pageInfos: NavPathStack | null = null
  @Local
  private wifiManager:WifiManager = WifiManager.getInstance()
  build() {
    Column() {
      // requireNetwork为true时强拦：无可用网络（wifiOr5GFirst为false）时不进页，直接展示提示页。
      // 网络状态异步初始化有约1秒窗口期，由 Delay1Second 的延时兜底，避免正常联网时闪现“无网络”。
      if (!this.requireNetwork || this.wifiManager.wifiOr5GFirst) {
        Column() {
          this.content()
        }
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
        .transition(TransitionEffect.OPACITY.animation({ duration:300,curve:Curve.Smooth }))
      } else {
        Delay1Second({
          pageInfos:this.pageInfos
        })
          .transition(TransitionEffect.OPACITY.animation({ duration:300,curve:Curve.Smooth }))
      }
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    .onAppear(() => {
      this.wifiManager.startListenNetChange();
    })
    // 切后台再回前台，监听也不会断开的
    // 不会出现用户去设置页面连了WiFi，从后台回来这里还是在叫他连WiFi
  }
}


// 因为鸿蒙6把ArkWeb升级到了M132，性能有了显著提升，老的鸿蒙5手表是M114内核的，打开网页卡死了，根本没法优化。
// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-component-overview
@ComponentV2
struct ContentUnavailablePageByChromium {
  build() {
    Column() {
      Text("【非官方】抖音RSS仅支持手表鸿蒙6系统使用")
        .padding({ start:LengthMetrics.vp(16.7),end:LengthMetrics.vp(16.7) })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 因为要需要大约1秒钟才能完成网络切换
// 这里只是兼容旧调用的提示，不将网络枚举结果当作 HTTP 可达性的证明。
@ComponentV2
struct Delay1Second {
  @Local
  private show:boolean = false
  @Param pageInfos: NavPathStack | null = null
  build() {
    Column() {
      if (this.show) {
        ContentUnavailablePageByWiFiOr5G({
          pageInfos:this.pageInfos
        })
          .transition(TransitionEffect.OPACITY.animation({ duration:300,curve:Curve.Smooth }))
      } else {
        // 会自然露出DarkTheme.navDestDefaultBackground
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onAppear(() => {
      setTimeout(() => {
        this.show = true
      },1000)
    })
    .width("100%")
    .height("100%")
  }
}

@ComponentV2
struct ContentUnavailablePageByWiFiOr5G {
  @Param pageInfos: NavPathStack | null = null

  private goDiagnose(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
      return
    }
    this.pageInfos.pushPathByName('DouyinNetworkDiagnosePage', null)
  }

  build() {
    Column() {
      Blank()
      Text("暂未检测到默认网络，请检查 Wi-Fi、蜂窝或手机共享网络")
        .padding({ start:LengthMetrics.vp(16.7),end:LengthMetrics.vp(16.7) })
      // 小感叹号圆圈图标 + “网络诊断”，点击 push 到诊断页展示检测状态与原始数据。
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize('15vp')
          .fontColor(['#E6A23C'])
        Text('网络诊断')
          .fontSize('13fp')
          .fontColor('#BBBBBB')
      }
      .padding({ top: 6, bottom: 2 })
      .onClick(() => {
        this.goDiagnose();
      })
      Blank()
      // 这一页的强调色是警告琥珀（图标 + 网络诊断），设置网络按钮跟着用琥珀，不抢抖音红。
      SettingsButton({
        arcBackgroundColor: ColorMetrics.rgba(230, 162, 60),
        arcFontColor: ColorMetrics.rgba(36, 23, 8),
        arcShadowColor: ColorMetrics.rgba(230, 162, 60, 0.4)
      })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}
