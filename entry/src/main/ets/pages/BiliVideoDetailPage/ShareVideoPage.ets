import { QrCodePanel } from "../../components/QrCodePanel";

export interface ShareVideoPagePushData {
  bvid:string
}


@Builder
export function ShareVideoPageBuilder(name: string, param: Object) {
  ShareVideoPage({
    bvid:(param as ShareVideoPagePushData).bvid,
  })
}

@Entry
@ComponentV2
struct ShareVideoPage {
  @Param @Require bvid:string
  @Local fullURL: string = 'https://www.bilibili.com/video/'+this.bvid;
  pageInfos: NavPathStack | null = null

  build() {
    NavDestination() {
      QrCodePanel({
        title: "分享视频",
        content: this.fullURL,
        hint: "手机扫码观看视频",
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}