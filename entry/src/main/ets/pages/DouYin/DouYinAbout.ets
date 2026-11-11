import { ArcList, ArcListItem, ComponentContent, LengthMetrics } from "@kit.ArkUI"

@Builder
export function DouYinAboutPageBuilder(name: string, param: Object) {
  DouYinAboutPage()
}

@Builder
function ArcListTitleView() {
  Text("法律声明")
    .fontSize("24fp")
    .fontWeight(FontWeight.Bold)
    .padding({
      top:LengthMetrics.fp(22),
      bottom:LengthMetrics.fp(13)
    })
}

@ComponentV2
export struct DouYinAboutPage {
  @Local
  private listRowBackgroundColor: string = "#262626"
  @Local
  pageInfos: NavPathStack | null = null
  @Local
  private titleView: ComponentContent<Object> = new ComponentContent(this.getUIContext(), wrapBuilder(ArcListTitleView));
  build() {
    NavDestination() {
      Stack() {
        ArcList({ initialIndex: 0,header:this.titleView }) {
          ArcListItem() {
            Button({ type: ButtonType.ROUNDED_RECTANGLE }) {
              Column() {
                Text("本代码与北京抖音科技有限公司及其任何关联公司或子公司均无任何关联，未经其授权、维护、赞助或认可。这是一款独立的非官方软件。使用本软件需自行承担风险。")
                  .textAlign(TextAlign.Start)
                  .enableHapticFeedback(true)
                  .copyOption(CopyOptions.None)
                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                  .draggable(true)
                  .fontSize("12fp")
              }
              .padding({
                top:LengthMetrics.vp(8),
                bottom:LengthMetrics.vp(8),
                start:LengthMetrics.vp(5),
                end:LengthMetrics.vp(5)
              })
            }
            .width("76%")
            .focusable(true)
            .focusOnTouch(true)
            .backgroundColor(this.listRowBackgroundColor)
          }.align(Alignment.Center)
        }
        .chainAnimation(true)
        .space(LengthMetrics.vp(5))
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .align(Alignment.Center)
      .width("100%")
      .height("100%")
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}