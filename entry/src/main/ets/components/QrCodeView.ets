import { watchSizeFp } from "../common/ScreenSize";

// 二维码四周的白边宽度与圆角。
// 表盘是圆形，贴边的方形二维码容易被圆切掉一个角，
// 而二维码图片自带的留白通常不够，所以这里统一再加一圈白边。
const QR_BORDER_WIDTH: Length = 6
const QR_BORDER_RADIUS: Length = 12

/**
 * 统一的二维码展示组件。两种用法二选一：
 * - 已有二维码图片：传 image（如 AboutPage 下的备案、隐私政策二维码）
 * - 只有链接：传 content，由系统生成二维码
 */
@ComponentV2
export struct QrCodeView {
  // 二维码图片资源，给了就优先用图片
  @Param image: Resource | null = null
  // 二维码内容，没给 image 时用它生成
  @Param content: string = ''
  // 边长，默认取屏幕宽度的一半
  // （不能叫 size：会和 CustomComponent 自带的 size 属性方法重名）
  @Param qrSize: number = watchSizeFp * 0.5

  build() {
    Column() {
      if (this.image !== null) {
        Image(this.image)
          .objectFit(ImageFit.Cover)
          .width(this.qrSize)
          .height(this.qrSize)
          .border({ width: QR_BORDER_WIDTH, color: Color.White })
          .borderRadius(QR_BORDER_RADIUS)
      } else {
        QRCode(this.content)
          .width(this.qrSize)
          .height(this.qrSize)
          .border({ width: QR_BORDER_WIDTH, color: Color.White })
          .borderRadius(QR_BORDER_RADIUS)
      }
    }
  }
}
