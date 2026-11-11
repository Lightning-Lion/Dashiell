import { watchSizeFp } from "../../common/ScreenSize";

export interface UPPagePushData {
  mid:string
}


@Builder
export function UPPageBuilder(name: string, param: Object) {
  UPPage({
    mid:(param as UPPagePushData).mid,
  })
}

// 这个偷懒先不做，未来更新里做UP主页
@Entry
@ComponentV2
struct UPPage {
  @Param @Require mid:string
  @Local fullURL: string = 'https://www.bilibili.com/video/'+this.mid;
  pageInfos: NavPathStack | null = null

  build() {
    NavDestination() {
      Column({ space: 22 }) {
        Text("手机扫码继续")
          .margin({ top: 22 })
        QRCode(this.fullURL)
          .width(watchSizeFp * 0.5)
          .height(watchSizeFp * 0.5)
          .border({ color:Color.White, width:"7fp" })
      }
      .justifyContent(FlexAlign.Center)
      .height('100%')
      .width('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}