import { QrCodeView } from '../../components/QrCodeView'
import { DarkTheme } from '../../common/Theme'
import { AboutSubpageHeader } from './AboutSubpageHeader'

@Builder
export function BeianQrPageBuilder(name: string, param: Object) {
  BeianQrPage()
}

@Entry
@ComponentV2
struct BeianQrPage {
  build() {
    NavDestination() {
      Column() {
        AboutSubpageHeader({ title: '备案信息', subtitle: '浙ICP备00000000号-1A' })
        Column({ space: '7vp' }) {
          QrCodeView({
            image: $r('app.media.beian_qr'),
            qrSize: 92
          })
          Text('扫码访问备案查询')
            .fontSize('11fp')
            .fontColor(DarkTheme.textSecondary)
          Text('beian.miit.gov.cn')
            .fontSize('9fp')
            .fontColor('#77777D')
        }
        .width('82%')
        .padding({ top: '11vp', bottom: '11vp' })
        .backgroundColor('#D9262628')
        .border({ width: '0.5vp', color: '#3A3A3D' })
        .borderRadius('18vp')
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
