import { ComponentContent, LengthMetrics } from '@kit.ArkUI'
import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute } from '@kit.ArkUI'
import { watchSizePx } from '../../common/ScreenSize'
import { DarkTheme } from '../../common/Theme'

@Builder
export function AboutPageBuilder() {
  AboutPage()
}

@Entry
@ComponentV2
export struct AboutPage {
  @Local
  private watchSize: string = watchSizePx + 'px'
  @Local
  private pageInfos: NavPathStack | null = null
  @Local
  private titleView: ComponentContent<Object> =
    new ComponentContent(this.getUIContext(), wrapBuilder(AboutPageHeader))

  private openPage(name: string, errorCode: string): void {
    if (this.pageInfos !== null) {
      this.pageInfos.pushPathByName(name, undefined)
      return
    }
    this.getUIContext().getPromptAction().showToast({ message: errorCode })
  }

  build() {
    NavDestination() {
      Stack() {
        ArcList({ initialIndex: 0, header: this.titleView }) {
          ArcListItem() {
            AboutMenuEntry({
              label: '个性化设置',
              onTap: () => this.openPage('PersonalizedSettingsPage', '404-28')
            })
          }
          .align(Alignment.Center)

          ArcListItem() {
            AboutMenuEntry({
              label: '用户协议',
              onTap: () => this.openPage('TermOfServicePage', '404-14')
            })
          }
          .align(Alignment.Center)

          ArcListItem() {
            AboutMenuEntry({
              label: '隐私政策',
              onTap: () => this.openPage('PrivacyPolicyPage', '404-13')
            })
          }
          .align(Alignment.Center)

          ArcListItem() {
            AboutMenuEntry({
              label: '开源许可',
              onTap: () => this.openPage('AcknowledgmentsPage', '404-10')
            })
          }
          .align(Alignment.Center)

          ArcListItem() {
            AboutMenuEntry({
              label: '贡献者',
              onTap: () => this.openPage('ContributorsPage', '404-12')
            })
          }
          .align(Alignment.Center)

          ArcListItem() {
            Button({ type: ButtonType.ROUNDED_RECTANGLE, stateEffect: false }) {
              Column({ space: '3vp' }) {
                Text('备案信息')
                  .fontSize('11fp')
                  .fontColor(DarkTheme.textSecondary)
                Text('浙ICP备00000000号-1A')
                  .fontSize('10fp')
                  .fontColor('#77777D')
              }
              .alignItems(HorizontalAlign.Center)
            }
            .width('76%')
            .height('42vp')
            .backgroundColor(Color.Transparent)
            .focusable(true)
            .focusOnTouch(true)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.openPage('BeianQrPage', '404-11'))
          }
          .align(Alignment.Center)
        }
        .space(LengthMetrics.vp(6))
        .scrollBar(BarState.Off)
        .borderRadius(this.watchSize)
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .align(Alignment.Center)
      .width(this.watchSize)
      .height(this.watchSize)
      .borderRadius(this.watchSize)
    }
    .hideTitleBar(true)
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}

@ComponentV2
struct AboutMenuEntry {
  @Param @Require label: string
  @Param @Require onTap: () => void

  build() {
    Button({ type: ButtonType.Capsule }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.label)
          .width('100%')
          .fontSize('16fp')
          .fontWeight(FontWeight.Medium)
          .fontColor(DarkTheme.textPrimary)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        Row() {
          Image($r('app.media.chevron_right'))
            .width('13vp')
            .height('13vp')
            .fillColor('#77777D')
        }
          .width('100%')
          .padding({ right: '15vp' })
          .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height('100%')
    }
    .width('88%')
    .height('46vp')
    .backgroundColor('#D9262628')
    .border({ width: '0.5vp', color: '#3A3A3D' })
    .focusable(true)
    .focusOnTouch(true)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => this.onTap())
  }
}

@Builder
function AboutPageHeader() {
  Column({ space: '5vp' }) {
    Image($r('app.media.startIcon'))
      .width('34vp')
      .height('34vp')
      .borderRadius('50%')
      .objectFit(ImageFit.Contain)
    Text('关于腕上RSS')
      .fontSize('20fp')
      .fontWeight(FontWeight.Bold)
      .fontColor(DarkTheme.textPrimary)
    Text('版本 1.2.0')
      .fontSize('10fp')
      .fontColor(DarkTheme.textSecondary)
  }
  .width('100%')
  .height('102vp')
  .padding({ top: '13vp', bottom: '14vp' })
  .alignItems(HorizontalAlign.Center)
  .justifyContent(FlexAlign.Center)
}
