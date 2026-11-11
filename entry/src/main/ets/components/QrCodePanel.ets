import { LengthMetrics } from "@kit.ArkUI";
import { QrCodeView } from "./QrCodeView";

/**
 * 统一的「标题 + 二维码 + 提示文字」展示面板。
 * 沿用隐私政策页那套居中排版，供分享视频、隐私政策等页面复用。
 * 二维码内容二选一：传 image 用现成图片，否则传 content 由系统生成。
 * 顶部标题、底部提示文字均为必填：每页都要保持「上有标题、下有说明」的布局。
 */
@ComponentV2
export struct QrCodePanel {
  // 顶部标题，必填
  @Param @Require title: string
  // 二维码图片资源，给了就优先用图片
  @Param image: Resource | null = null
  // 二维码内容，没给 image 时用它生成
  @Param content: string = ''
  // 底部提示文字，必填
  @Param @Require hint: string

  build() {
    Column({
      space: "0vp"
    }) {
      Text(this.title)
        .fontColor($r("app.color.TextPrimaryColorInBlackBackground"))
        .fontSize("18fp")
        .fontWeight(FontWeight.Bold)
        .margin({
          top: LengthMetrics.vp(37)
        })
      QrCodeView({ image: this.image, content: this.content })
        .margin({
          top: LengthMetrics.vp(13)
        })
      Text(this.hint)
        .fontColor($r("app.color.TextSecondaryColorInBlackBackground"))
        .fontSize("13fp")
        .margin({
          top: LengthMetrics.vp(8)
        })
      Blank()
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .width('100%')
  }
}
