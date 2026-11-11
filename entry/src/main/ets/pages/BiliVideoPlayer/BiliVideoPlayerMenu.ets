@ComponentV2
export struct BiliVideoPlayerMenu {
  @Param @Require fullscreen: boolean
  @Param @Require click0: () => void
  @Param @Require click1: () => void
  @Param @Require click2: () => void
  @Param @Require clickClose: () => void

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row({ space: "17fp" }) {
          IconButton({
            icon0: $r("app.media.bili_player_playback_progress_icon"),
            text0: "调进度",
            onClickAction: () => {
              this.click0()
            }
          })
          IconButton({
            showVersion1: this.fullscreen,
            icon0: $r("app.media.bili_player_expend_icon"),
            icon1: $r("app.media.bili_player_minimize_icon"),
            text0: "全屏",
            text1: "缩小",
            onClickAction: () => {
              this.click1()
            }
          })
          IconButton({
            icon0: $r("app.media.bili_player_volume_control_icon"),
            text0: "调音量",
            onClickAction: () => {
              this.click2()
            }
          })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")
      .height("100%")
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)

      Button({ type: ButtonType.Circle }) {
        Image($r("app.media.bili_player_menu_icon"))
          .objectFit(ImageFit.Cover)
          .width("38fp")
          .height("38fp")
      }
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .margin({ bottom: "20fp" })
      .onClick(() => {
        this.clickClose()
      })
    }.hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
struct IconButton {
  @Param @Require icon0: Resource
  @Param icon1: Resource | null = null
  @Param showVersion1: boolean = false
  @Param @Require text0: string
  @Param text1: string | null = null
  @Param @Require onClickAction: () => void

  build() {
    Column({ space: "9fp" }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Column() {
          if (this.showVersion1) {
            Image(this.icon1)
              .transition(TransitionEffect.scale({ x: 0, y: 0 }))
          } else {
            Image(this.icon0)
              .transition(TransitionEffect.scale({ x: 0, y: 0 }))
          }
        }
        .width("33fp")
        .height("33fp")
      }
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK)
      .borderRadius("25fp")
      .width("50fp")
      .height("50fp")
      .onClick(() => {
        this.onClickAction()
      })

      Column() {
        if (this.showVersion1) {
          Text(this.text1)
            .fontSize("13fp")
            .transition(TransitionEffect.OPACITY)
        } else {
          Text(this.text0)
            .fontSize("13fp")
            .transition(TransitionEffect.OPACITY)
        }
      }
    }
  }
}