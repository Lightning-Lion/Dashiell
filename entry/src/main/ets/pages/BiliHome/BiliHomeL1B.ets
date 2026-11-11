import { BilibiliService, BilibiliServiceWithoutLogin } from "../../common/BiliService"
import { logTag } from "../../common/printLog"
import { CookieStringPack } from "../BiliLogin/BiliGetCookieView"
import { BilibiliHomeFeedView } from "./BiliHomeL2"
import { DarkTheme } from "../../common/Theme"

@Builder
export function BiliHomeFeedWithoutLoginPageBuilder(name: string, param: Object) {
  BiliHomeFeedWithoutLogin()
}

@Entry
@ComponentV2
export struct BiliHomeFeedWithoutLogin {
  @Local
  cookieStringPack: CookieStringPack = new CookieStringPack()
  @Local biliService:BilibiliServiceWithoutLogin = new BilibiliServiceWithoutLogin()
  pageInfos: NavPathStack | null = null
  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.pageInfos === null) {
            Text("404-7")
          } else if (this.biliService === null) {
            Text("404-8")
          } else {
            BilibiliHomeFeedView({
              biliService:this.biliService,
              pageInfos:this.pageInfos
            })
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
  }
}
