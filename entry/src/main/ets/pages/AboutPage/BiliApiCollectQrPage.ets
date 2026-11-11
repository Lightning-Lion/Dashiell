import { watchSizeFp, watchSizePx } from "../../common/ScreenSize";

@Builder
export function BiliApiCollectQrPageBuilder(name: string, param: Object) {
  BiliApiCollectQrPage()
}

@Builder
export function BiliApiLicenseQrPageBuilder(name: string, param: Object) {
  BiliApiLicenseQrPage()
}

@Entry
@ComponentV2
struct BiliApiCollectQrPage {
  @Local message: string = 'https://github.com/SocialSisterYi/bilibili-API-collect/';
  pageInfos: NavPathStack | null = null
  build() {
    NavDestination() {
      Column({space:13}) {
        Text(this.message)
          .margin({top:"18fp",left:"8fp",right:"8fp"})
        Image($r("app.media.bilibili_API_collect_qr"))
          .objectFit(ImageFit.Cover)
          .width(watchSizeFp*0.5)
          .height(watchSizeFp*0.5)
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



@ComponentV2
struct BiliApiLicenseQrPage {
  @Local message: string = 'https://github.com/SocialSisterYi/bilibili-API-collect/';
  pageInfos: NavPathStack | null = null
  build() {
    NavDestination() {
      Column({space:13}) {
        Text(this.message)
          .margin({top:"18fp",left:"8fp",right:"8fp"})
        Image($r("app.media.bilibili_API_collect_qr"))
          .objectFit(ImageFit.Cover)
          .width(watchSizeFp*0.5)
          .height(watchSizeFp*0.5)
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