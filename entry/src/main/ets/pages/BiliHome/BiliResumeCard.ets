import { BiliHistoryItem } from '../../common/BiliHistoryModels';
import { BiliImageDownsizer } from '../../common/BiliImageDownSizer';
import { DarkTheme } from '../../common/Theme';

/**
 * 哔哩哔哩首页顶部的跨设备续播卡片。
 * 自带不透明卡片背景，只在列表顶部占位；布局与下方的 HomeFeedVideoCard 无关。
 */
@ComponentV2
export struct BiliResumeCard {
  @Param @Require item: BiliHistoryItem
  @Param @Require onClose: () => void
  @Param @Require onContinue: () => void

  @Computed
  get coverURL(): string {
    return BiliImageDownsizer.transformBilibiliImageUrl(this.item.cover ?? '', 200, 113)
  }

  private formatWatchDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const remain = total % 60
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`
    if (hours > 0) {
      return `${hours}:${pad(minutes)}:${pad(remain)}`
    }
    return `${minutes}:${pad(remain)}`
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('刚在其他设备上播放')
          .fontSize(13)
          .fontColor(DarkTheme.textSecondary)
        Blank()
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.bili_resume_card_close'))
            .width(24)
            .height(24)
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onClose()
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        Image(this.coverURL)
          .width(100)
          .height(56)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .backgroundColor(DarkTheme.background)

        Column() {
          Text(this.item.title || this.item.show_title || '未命名视频')
            .fontSize(13)
            .fontColor(DarkTheme.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${this.formatWatchDuration(this.item.progress ?? 0)} / ${this.formatWatchDuration(this.item.duration ?? 0)}`)
            .fontSize(11)
            .fontColor(DarkTheme.textSecondary)
            .width('100%')
        }
        .layoutWeight(1)
        .height(56)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Button('继续观看')
        .width('100%')
        .height(34)
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(DarkTheme.biliPink)
        .onClick(() => {
          this.onContinue()
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(DarkTheme.cardBackground)
    .borderRadius(10)
  }
}
