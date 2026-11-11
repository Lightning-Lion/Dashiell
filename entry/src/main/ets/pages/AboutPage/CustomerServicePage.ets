@Builder
export function CustomerServicePageBuilder(name: string, param: Object) {
  CustomerServicePage()
}

@Entry
@ComponentV2
struct CustomerServicePage {
  pageInfos: NavPathStack | null = null

  build() {
    NavDestination() {
      Stack({ alignContent:Alignment.Center }) {
        // EdgeEffect.Spring出界后的背景色匹配二维码图片的背景色
        Column() {}.width("100%").height("100%").backgroundColor("#F3F2F7")
        Scroll() {
          Image($r("app.media.customer_service_qq_group_qr"))
            .width("100%")
            // 表冠可聚焦
            .onClick(() => {})
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
        .height('100%')
        .width('100%')
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}