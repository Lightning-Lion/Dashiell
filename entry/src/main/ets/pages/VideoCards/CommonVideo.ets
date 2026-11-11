import { BiliImageDownsizer } from "../../common/BiliImageDownSizer";
import { BilibiliService, BilibiliServiceWithoutLogin } from "../../common/BiliService";
import { DarkTheme } from "../../common/Theme";
import { VideoItem } from "../BiliHome/BiliHomeL2";
import { BiliVideoDetailPagePushData } from "../BiliVideoDetailPage/BiliVideoDetailPage";
import { VideoPlayingPagePushData } from "../BiliVideoPlayer/BiliVideoPlayerPage";

// 视频卡片组件
@ComponentV2
export struct BaseVideoCard {
  @Param @Require item: VideoItem;
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack

  build() {
    Button({ stateEffect: true }) {
      Column() {
        Stack({ alignContent: Alignment.BottomEnd }) {
          VideoCoverWithTransition({ imageSrc: this.getSmallCoverURL })

          if (this.item.watchedSeconds !== undefined && this.item.watchedSeconds > 0) {
            Text(this.item.watchFinished === true ? '已看完' : `已看 ${this.formatDuration(this.item.watchedSeconds)}`)
              .fontSize(12)
              .backgroundColor('#0009')
              .fontColor('#fff')
              .padding(2)
              .borderRadius(4)
              .margin(4)
              .align(Alignment.BottomStart)
          }

          if (this.item.duration) {
            Text(typeof this.item.duration === 'string' ? this.item.duration : this.formatDuration(this.item.duration))
              .fontSize(12)
              .backgroundColor('#0009')
              .fontColor('#fff')
              .padding(2)
              .borderRadius(4)
              .margin(4)
          }
        }

        Text(this.item.title)
          .fontColor(DarkTheme.textPrimary)
          .textAlign(TextAlign.Start)
          .fontSize(14)
          .fontWeight(500)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })

        Row() {
          if (this.item.owner?.name) {
            Text(this.item.owner.name)
              .fontSize(12)
              .fontColor(DarkTheme.textSecondary)
          }

          if (this.item.stat?.view) {
            Blank()
            Text(`${this.formatNumber(this.item.stat.view)}播放`)
              .fontSize(12)
              .fontColor(DarkTheme.textSecondary)
          }
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(DarkTheme.cardBackground)
      .borderRadius(8)
      .shadow({
        radius: 5,
        color: '#00000050',
        offsetX: 0,
        offsetY: 2
      })
    }.onClick(async () => {
      console.debug(`🚩点击了列表项：${this.item.bvid}, cid: ${this.item.cid}`)
      if (this.biliService instanceof BilibiliService) {
        const data: BiliVideoDetailPagePushData = {
          bvid: this.item.bvid,
          biliService: this.biliService,
          resumeAt: this.item.watchFinished === true ? 0 : (this.item.watchedSeconds ?? 0)
        }
        this.pageInfos.pushPathByName("BiliVideoDetailPage", data)
        return
      }
      const data: VideoPlayingPagePushData = {
        videoID: {
          bvid: this.item.bvid,
          cid: this.item.cid
        },
        biliService: this.biliService
      }
      this.pageInfos.pushPathByName("BiliVideoPlayerPage", data)
    }).clickEffect({ level: ClickEffectLevel.LIGHT })
  }

  @Computed
  get getSmallCoverURL() { // 正确用法
    const originCoverURL = this.item.pic
    if (originCoverURL === undefined) {
      return ""
    }
    const originalUrl = originCoverURL;
    const transformedUrl =
      BiliImageDownsizer.transformBilibiliImageUrl(originalUrl, 384, 216); // 经过真人检查，宽高比与原始封面（16/9）是一致的
    return transformedUrl
  }

  // 辅助函数：格式化视频时长
  formatDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const remainingSeconds = total % 60;
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    if (hours > 0) {
      return `${hours}:${pad(minutes)}:${pad(remainingSeconds)}`;
    }
    return `${minutes}:${pad(remainingSeconds)}`;
  }

  // 辅助函数：格式化数字
  formatNumber(num: number): string {
    //（只用"万"或"亿"单位，不显示.0）
    if (num >= 100000000) {
      const value = num / 100000000;
      const formatted = value.toFixed(1);
      return formatted.endsWith('.0') ? formatted.slice(0, -2) + '亿' : formatted + '亿';
    } else if (num >= 10000) {
      const value = num / 10000;
      const formatted = value.toFixed(1);
      return formatted.endsWith('.0') ? formatted.slice(0, -2) + '万' : formatted + '万';
    }
    return num.toString();
  }
}

@ComponentV2
struct VideoCoverWithTransition {
  @Param @Require imageSrc: string
  @Local imageOpacity: number = 0.0
  @Local imageFailed: boolean = false

  @Monitor('imageSrc')
  resetImage(): void {
    this.imageFailed = false;
    this.imageOpacity = 0;
  }

  build() {
    if (this.imageSrc.length === 0 || this.imageFailed) {
      Stack() {
        Text('暂无封面').fontSize(12).fontColor(DarkTheme.textSecondary)
      }.width('100%').aspectRatio(16.0 / 9.0).backgroundColor(DarkTheme.background).borderRadius(8)
    } else {
    Image(this.imageSrc)
      .borderRadius(8)
      .objectFit(ImageFit.Cover)
      .onError(() => { this.imageFailed = true; })
      .opacity(this.imageOpacity)
      .onComplete(() => {
        this.getUIContext().animateTo({
          curve: Curve.EaseOut,
          duration: 300
        }, () => {
          this.imageOpacity = 1
        })
      })
      .width('100%')
      .aspectRatio(16.0 / 9.0)
    }
  }
}

