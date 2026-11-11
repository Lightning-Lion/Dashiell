import { isCurrentBiliSessionEpoch } from '../../common/BiliSession';
import { BilibiliService } from "../../common/BiliService"
import { setCurrentBiliService } from "../../common/BiliServiceRegistry"
import { logTag } from "../../common/printLog"
import { BiliGetCookieViewStandard, CookieStringPack } from "../BiliLogin/BiliGetCookieView"
import { NewlyDoneLoginModel } from "../BiliLogin/BiliLoginWebView"
import { BilibiliHomeFeedView } from "./BiliHomeL2"
import { DarkTheme } from "../../common/Theme"

@Builder
export function BiliHomeFeedPageWithLoginBuilder(name: string, param: Object) {
  BiliHomeFeedPage()
}

@Entry
@ComponentV2
export struct BiliHomeFeedPage {
  @Local
  cookieStringPack: CookieStringPack = new CookieStringPack()
  @Local biliService: BilibiliService | null = null
  pageInfos: NavPathStack | null = null
  @Local
  private newlyDoneLoginModel:NewlyDoneLoginModel = new NewlyDoneLoginModel()

  private disposed: boolean = false;
  aboutToDisappear(): void { this.disposed = true; }

  @Monitor("cookieStringPack.cookieString")
  onStrChange(monitor: IMonitor) {
    if (this.disposed) { return; }
    monitor.dirty.forEach((path: string) => {

      const newValue: string | undefined = monitor.value(path)?.now as string | undefined
      // cookieStringPack.cookieString有值了
      if (newValue !== undefined && isCurrentBiliSessionEpoch(this.cookieStringPack.sessionEpoch)) {
        // 可以创建BilibiliService对象了
        this.biliService = new BilibiliService(newValue)
        setCurrentBiliService(this.biliService)
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
              this.biliHomeFeedView()
            }

            // 不要渐显入场
            // 会造成闪一下（一个渐隐一个渐显，可不是闪一下吗？），体验不好
          } else {
            // Cookie获取视图，用户会先在这里完成登录
            BiliGetCookieViewStandard({ cookieStringPack: this.cookieStringPack,
              // 没什么意义，仅占位
              newlyDoneLoginModel:this.newlyDoneLoginModel })
              .width('100%')
              .height('100%')
              // 渐隐离场
              .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
                TransitionEffect.OPACITY.animation({ duration: 300 })))

          }
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .linearGradient({ colors: DarkTheme.pageTopGradients.biliHome })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    // onWillDisappear 也会在进入搜索、详情和播放器时触发，不能在这里销毁
    // 服务，否则返回首页后会复用一个已 destroy 的 HttpRequest，表现为掉登录/网络失败。
  }

  @Builder
  biliHomeFeedView() {
    if (this.pageInfos === null) {
      Text("404-7")
    } else if (this.biliService === null) {
      Text("404-8")
    } else {
      BilibiliHomeFeedView({
        biliService: this.biliService,
        pageInfos: this.pageInfos
      })
    }
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
