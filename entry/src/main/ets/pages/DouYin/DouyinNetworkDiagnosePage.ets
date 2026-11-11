import { LengthMetrics } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { WifiManager } from '../../common/WiFiManager';
import { DarkTheme } from '../../common/Theme';

// 网络诊断页：把闸门各项检测的状态和原始数据都列出来，方便用户对照或截图反馈。
// 通过 NavPathStack push 进入，数据源是应用级单例 WifiManager（@ObservedV2 + @Trace，实时刷新）。
//
// 实测记录（原 DouYinWebViewDev 探针页留下的结论，那个页已删）：在鸿蒙电脑的系统浏览器里
// 观察抖音精选，点开一个视频会产生 https://www.douyin.com/aweme/v2/web/module/feed/ 与
// https://www-hj.douyin.com/aweme/v1/web/hot/search/list/ 两个请求，其它操作未观察到同样的请求，
// 所以可以当作「点击视频」的标记物；网页自身没有加载提示，需要前端自己弹一个。
@Builder
export function DouyinNetworkDiagnosePageBuilder(name: string, param: Object) {
  DouyinNetworkDiagnosePage()
}

@ComponentV2
export struct DouyinNetworkDiagnosePage {
  @Local private wifiManager: WifiManager = WifiManager.getInstance();
  @Local private pageInfos: NavPathStack | null = null;

  private fmtTime(ms: number): string {
    if (ms <= 0) {
      return '未探测';
    }
    const d = new Date(ms);
    const p = (n: number): string => n < 10 ? '0' + n : '' + n;
    return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  }

  @Builder
  private infoRow(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize('11fp')
        .fontColor(DarkTheme.textSecondary)
      Text(value)
        .fontSize('13fp')
        .fontColor(DarkTheme.textPrimary)
        .copyOption(CopyOptions.LocalDevice)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        // 标题 + 重新检测
        Row() {
          Text('网络诊断')
            .fontSize('17fp')
            .fontWeight(FontWeight.Bold)
            .fontColor(DarkTheme.textPrimary)
          Blank()
          Button('重新检测')
            .fontSize('12fp')
            .height('28vp')
            .backgroundColor(DarkTheme.prominentButton)
            .fontColor(Color.White)
            .onClick(() => {
              this.wifiManager.probe();
            })
        }
        .width('100%')
        .padding({
          start: LengthMetrics.vp(16),
          end: LengthMetrics.vp(16),
          top: LengthMetrics.vp(14),
          bottom: LengthMetrics.vp(8)
        })

        Scroll() {
          Column({ space: 10 }) {
            this.infoRow('闸门判定',
              this.wifiManager.wifiOr5GFirst ? '通过（有可用网络）' : '拦截（未检测到默认网络）')
            this.infoRow('系统 API 版本', `${deviceInfo.sdkApiVersion}（鸿蒙6需 ≥ 20）`)
            this.infoRow('默认网络 netId', `${this.wifiManager.defaultNetId}`)
            this.infoRow('默认网络类型', this.wifiManager.defaultNetBearers)
            this.infoRow('全部网络', this.wifiManager.allNetsSummary)
            this.infoRow('最近探测时间', this.fmtTime(this.wifiManager.lastProbeMs))
            this.infoRow('探测错误',
              this.wifiManager.lastProbeError.length === 0 ? '无' : this.wifiManager.lastProbeError)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)

        Text('提示：长按任意条目可复制原始数据，便于反馈')
          .fontSize('10fp')
          .fontColor(DarkTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: LengthMetrics.vp(10) })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(DarkTheme.navDestDefaultBackground)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
  }
}
