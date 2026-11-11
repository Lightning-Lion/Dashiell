import { DarkTheme } from '../../common/Theme'

@ComponentV2
export struct AboutSubpageHeader {
  @Param @Require title: string
  @Param subtitle: string = '腕上 RSS'

  build() {
    Column({ space: '3vp' }) {
      Text(this.title)
        .fontSize('21fp')
        .fontWeight(FontWeight.Bold)
        .fontColor(DarkTheme.textPrimary)
        .maxLines(1)
      Text(this.subtitle)
        .fontSize('10fp')
        .fontColor(DarkTheme.textSecondary)
        .maxLines(1)
    }
    .width('100%')
    .height('76vp')
    .padding({ top: '18vp', bottom: '9vp' })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
