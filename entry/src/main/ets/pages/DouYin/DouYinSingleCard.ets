import { DouYinAwemeCard } from './DouYinJingxuanPage';
import { DouYinPlayerSession } from './DouYinPlayerSession';
import { VideoSlotController } from './DouYinVideoSurface';

/**
 * 外页的单个卡片：只负责一个视频槽位和简介。
 * 播放器/播放器会话是全局共享的，卡片本身不持有 AVPlayer。
 */
@ComponentV2
export struct DouCardItem {
  @Param @Require card: DouYinAwemeCard;
  @Param @Require session: DouYinPlayerSession;
  @Param @Require onRegisterSlot: (awemeID: string, slot: VideoSlotController) => void;
  @Param @Require onUnregisterSlot: (awemeID: string, slot: VideoSlotController) => void;
  @Param @Require onTap: () => void;

  @Local private slot: VideoSlotController = new VideoSlotController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      NodeContainer(this.slot)
        .width('100%')
        .height('100%')

      if (!this.session.ui.immersive) {
        Column() {
          Blank()
          Blank()
          Blank()
          Text(this.description())
            .maxLines(9)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize('13fp')
            .fontColor(Color.White)
            .width('80%')
            .padding({ bottom: '20vp' })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.onRegisterSlot(this.card.awemeID, this.slot);
    })
    .onDisAppear(() => {
      this.onUnregisterSlot(this.card.awemeID, this.slot);
    })
    .onClick(() => {
      this.onTap();
    })
  }

  private description(): string {
    const video = this.card.assumeVideo();
    return video === null ? '' : video.description;
  }
}
