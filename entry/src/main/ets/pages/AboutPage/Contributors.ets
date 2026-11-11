import { ComponentContent, LengthMetrics } from '@kit.ArkUI'
import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute } from '@kit.ArkUI'
import { DarkTheme } from '../../common/Theme'
import { AboutSubpageHeader } from './AboutSubpageHeader'

@Builder
export function ContributorsPageBuilder(name: string, param: Object) {
  ContributorsPage()
}

@Entry
@ComponentV2
export struct ContributorsPage {
  @Local
  private titleView: ComponentContent<Object> =
    new ComponentContent(this.getUIContext(), wrapBuilder(ContributorsHeader))

  build() {
    NavDestination() {
      ArcList({ initialIndex: 0, header: this.titleView }) {
        ArcListItem() {
          ContributorCard({
            name: '贡献者一',
            role: '前端开发',
            initial: '一',
            avatar: $r('app.media.contributor_6192edb6c6')
          })
        }
        .align(Alignment.Center)

        ArcListItem() {
          ContributorCard({
            name: '贡献者二',
            role: '前端开发',
            initial: '二',
            avatar: $r('app.media.contributor_854336c250')
          })
        }
        .align(Alignment.Center)

        ArcListItem() {
          ContributorCard({
            name: '贡献者三',
            role: '图标设计',
            initial: '三',
            avatar: $r('app.media.contributor_dc147c8f5d')
          })
        }
        .align(Alignment.Center)

      }
      .space(LengthMetrics.vp(7))
      .scrollBar(BarState.Off)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
    .hideTitleBar(true)
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
  }
}

@ComponentV2
struct ContributorCard {
  @Param @Require name: string
  @Param @Require role: string
  @Param @Require initial: string
  @Param avatar: Resource | null = null

  build() {
    Row({ space: '10vp' }) {
      if (this.avatar !== null) {
        Image(this.avatar)
          .width('30vp')
          .height('30vp')
          .borderRadius('15vp')
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.initial)
          .width('30vp')
          .height('30vp')
          .borderRadius('15vp')
          .backgroundColor('#33FF4C63')
          .fontSize('13fp')
          .fontWeight(FontWeight.Bold)
          .fontColor(DarkTheme.primary)
          .textAlign(TextAlign.Center)
      }

      Column({ space: '2vp' }) {
        Text(this.name)
          .fontSize('16fp')
          .fontWeight(FontWeight.Medium)
          .fontColor(DarkTheme.textPrimary)
        Text(this.role)
          .fontSize('10fp')
          .fontColor(DarkTheme.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('88%')
    .height('52vp')
    .padding({ left: '16vp', right: '16vp' })
    .backgroundColor('#D9262628')
    .border({ width: '0.5vp', color: '#3A3A3D' })
    .borderRadius('26vp')
    .alignItems(VerticalAlign.Center)
  }
}

@Builder
function ContributorsHeader() {
  AboutSubpageHeader({ title: '贡献者', subtitle: '感谢每一位项目参与者' })
}
