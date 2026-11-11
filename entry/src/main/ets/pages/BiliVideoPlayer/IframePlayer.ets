import { webview } from "@kit.ArkWeb";
import { DeviceMgr } from "../../common/AlwaysOn";
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { ErrorPrompt } from "../../components/ErrorPages";
import { watchWidthFp } from "../../common/ScreenSize";
import { DarkTheme } from "../../common/Theme";

export interface IframePlayerPushData {
  bvid: string
}

@Builder
export function IframePlayerBuilder(_name: string, param: Object) {
  IframePlayer({
    bvid: (param as IframePlayerPushData).bvid
  })
}

@ComponentV2
export struct IframePlayer {
  @Param @Require bvid: string
  @Local
  private pageInfos: NavPathStack | null = null
  @Local
  private controller: webview.WebviewController = new webview.WebviewController();
  @Local
  private errorMessage: string | null = null
  @Local
  private isShowBackMenu: boolean = false

  build() {
    NavDestination() {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          TimeoutLoadingView()
          Web({
            src: "https://player.bilibili.com/player.html?isOutside=true&bvid=" + encodeURIComponent(this.bvid) +
              "&p=1",
            controller: this.controller
          })
            .darkMode(WebDarkMode.On)
            .backgroundColor(Color.Transparent)
            .userAgent("Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile HuaweiBrowser/5.1.4.305")
            .fileAccess(true)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onErrorReceive((event) => {
              if (event.request.isMainFrame()) {
                this.errorMessage = event.error.getErrorInfo()
              }
            })
            .onGestureRecognizerJudgeBegin(this.gestureInterceptCallback, true)
            .bindMenu(!!this.isShowBackMenu, this.swipeCloseMenu(), {
              title: "是否返回？", hapticFeedbackMode: HapticFeedbackMode.ENABLED, aboutToDisappear: () => {
                this.isShowBackMenu = false
              }
            })
          if (this.errorMessage !== null) {
            ErrorPrompt({
              errorCode: null,
              errorMessage: this.errorMessage,
              showCloseButton: true,
              showRetryButton: false,
              onClose: () => {
                if (this.pageInfos !== null) {
                  this.pageInfos.removeByName("IframePlayer")
                } else {
                  this.getUIContext().getPromptAction().showToast({ message: "无法关闭视频，请将手表关机，然后再开机" })
                }
              }
            }).transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
          }
        }
      }
      .height('100%')
      .width('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn("videoPlayback", true)
    })
    .onDisAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn("videoPlayback", false)
    })
  }

  private gestureInterceptCallback: GestureRecognizerJudgeBeginCallback =
    (event: BaseGestureEvent, current: GestureRecognizer, _others: Array<GestureRecognizer>): GestureJudgeResult => {
      if (current.getType() !== GestureControl.GestureType.PAN_GESTURE) {
        return GestureJudgeResult.CONTINUE;
      }
      let fingerInfo = event.fingerList[0];
      let panEvent = event as PanGestureEvent;
      //这里panEvent.offsetX是手势的位移，fingerInfo.displayX是手势起点距离屏幕左边的x坐标（这里都可以改，改成距离组件最左边的x坐标也行）
      if ((panEvent.offsetX > 0) && (fingerInfo.displayX < (watchWidthFp / 2))) {
        // return GestureJudgeResult.REJECT;
        this.isShowBackMenu = true
      }
      return GestureJudgeResult.CONTINUE;
    };

  private swipeCloseMenu(): MenuElement[] {
    return [
      {
        value: "是",
        action: () => {
          if (this.pageInfos !== null) {
            this.pageInfos.removeByName("IframePlayer")
          } else {
            this.getUIContext().getPromptAction().showToast({ message: "无法关闭视频，请将手表关机，然后再开机" })
          }
        }
      },
      {
        value: "否",
        action: () => {
          this.isShowBackMenu = false
        }
      }
    ]
  }
}

@ComponentV2
struct TimeoutLoadingView {
  @Local
  private isTimeout: boolean = false

  build() {
    Column() {
      if (this.isTimeout) {
        ErrorPrompt({
          errorCode: null,
          errorMessage: "视频加载超时",
          showCloseButton: false,
          showRetryButton: false
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      } else {
        // Loading indicator
        AnimatedProgressView({ color: DarkTheme.biliPink })
          .width(50)
          .height(50)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    .onAppear(() => {
      setTimeout(() => {
        this.isTimeout = true
      }, 10 * 1000)
    })
  }
}
