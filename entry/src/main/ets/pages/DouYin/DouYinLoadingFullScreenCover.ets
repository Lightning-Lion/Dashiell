import { AnimatedProgressView } from '../../components/AnimatedProgressView'
import { DarkTheme } from '../../common/Theme'

@Builder
export function DouYinLoadingFullScreenCoverBuilder(name: string, param: Object) {
  DouYinLoadingFullScreenCover()
}

@ComponentV2
struct DouYinLoadingFullScreenCover {
  @Local
  pageInfos: NavPathStack | null = null
  build() {
    NavDestination() {
      Column() {
        Blank()
        AnimatedProgressView({ color: DarkTheme.accents.douyin })
          .width("50vp")
          .height("50vp")
        Blank()
        Text("视频加载中")
          .fontColor(DarkTheme.accents.douyin)
        Blank()
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")
      .height("100%")
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}