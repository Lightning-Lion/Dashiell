import { QrCodeView } from '../../components/QrCodeView'
import { DarkTheme } from '../../common/Theme'
import { AboutSubpageHeader } from './AboutSubpageHeader'

@Builder
export function TermOfServicePageBuilder(name: string, param: Object) {
  TermOfServicePage()
}

@Entry
@ComponentV2
struct TermOfServicePage {
  build() {
    NavDestination() {
      Column() {
        AboutSubpageHeader({ title: '用户协议', subtitle: '腕上 RSS · 服务条款' })
        Column({ space: '8vp' }) {
          QrCodeView({
            image: $r('app.media.term_of_service_qr'),
            qrSize: 98
          })
          Text('使用手机扫码查看完整协议')
            .fontSize('11fp')
            .fontColor(DarkTheme.textSecondary)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
  }
}
