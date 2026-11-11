import { QrCodeView } from '../../components/QrCodeView'
import { DarkTheme } from '../../common/Theme'
import { AboutSubpageHeader } from './AboutSubpageHeader'

@Builder
export function PrivacyPolicyPageBuilder(name: string, param: Object) {
  PrivacyPolicyPage()
}

@Entry
@ComponentV2
struct PrivacyPolicyPage {
  build() {
    NavDestination() {
      Column() {
        AboutSubpageHeader({ title: '隐私政策', subtitle: '腕上 RSS · 隐私保护' })
        Column({ space: '8vp' }) {
          QrCodeView({
            image: $r('app.media.privacy_policy_qr'),
            qrSize: 98
          })
          Text('使用手机扫码查看完整政策')
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
