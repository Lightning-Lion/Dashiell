import { PlaybackLifecycle, playbackLifecycle } from '../../common/PlaybackLifecycle';
import { BiliBusinessError } from '../../common/bili/BiliBusinessError';
import { JsonDecodeError } from '../../common/jsonschema/JsonDecode';
import { DeviceMgr } from '../../common/AlwaysOn';
import { BilibiliService, BilibiliServiceWithoutLogin } from '../../common/BiliService';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { DarkTheme } from '../../common/Theme';
import { BiliVideoPlayerView, PushVolumeControlPagePack } from './BiliVideoPlayerView';
import { BiliVideoPlayerViewModel } from './BiliVideoPlayerView'

// Validated projection; unused API metadata is not asserted to be a specific shape.
import { BiliPlaybackResponse as BiliVideoPlaybackApiResponse } from '../../common/bili/schema/BiliModels.generated';
import { BiliMediaMapping } from '../../common/bili/BiliMediaMapping';
export { BiliVideoPlaybackApiResponse };

// Video info data structure
interface DurationInterface {
  milliseconds: number;
  formatted: string;
}

interface VideoInfo {
  qualityDescription: string;
  format: string;
  duration: DurationInterface;
  url: string;
  backupUrl: string | undefined;
}

export interface VideoPlayingPagePushData {
  videoID: PlaybackURLVideoID
  biliService: BilibiliService | BilibiliServiceWithoutLogin
  // 从历史/续播入口带入的观看进度（秒）；缺省从头播放。
  resumeAt?: number
}

interface PlaybackURLVideoID {
  bvid: string
  cid?: string
}

@Builder
export function BiliVideoPlayerPageBuilder(name: string, param: Object) {
  BiliVideoPlayerPage({
    videoID: (param as VideoPlayingPagePushData).videoID,
    biliService: (param as VideoPlayingPagePushData).biliService,
    resumeAt: (param as VideoPlayingPagePushData).resumeAt ?? 0
  })
}

@Entry
@ComponentV2
export struct BiliVideoPlayerPage {
  @Local private lifecycle: PlaybackLifecycle = playbackLifecycle;
  @Local private pageVisible: boolean = true;
  @Param @Require videoID: PlaybackURLVideoID
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param resumeAt: number = 0
  @Local videoInfo: VideoInfo | undefined = undefined;
  @Local errorMessage: string = '';
  @Local showError: boolean = false;
  @Local private fetching: boolean = false;
  @Local pushVolumeControlPagePack: PushVolumeControlPagePack = new PushVolumeControlPagePack()
  @Local private playerViewModel: BiliVideoPlayerViewModel =
    new BiliVideoPlayerViewModel(this.pushVolumeControlPagePack, this)
  pageInfos: NavPathStack | null = null

  @Monitor("pushVolumeControlPagePack.triggerID")
  receivePushRequest() {
    if (this.pageInfos !== null) {
      this.pageInfos.pushPathByName("VolumeControlPage", undefined)
    } else {
      this.getUIContext().getPromptAction().showToast({
        message: "音量条加载失败"
      })
    }
  }

  aboutToAppear(): void {
    this.fetchVideoInfo()
  }

  build() {
    NavDestination() {
      Column() {
        // Error message
        if (this.showError) {
          Text(this.errorMessage)
            .fontSize(16)
            .fontColor(Color.Red)
            .margin({ bottom: 20 })
            .width('90%')
            .textAlign(TextAlign.Center)
          Button('重试')
            .enabled(!this.fetching)
            .onClick(() => this.fetchVideoInfo())
        } else {
          // Video info display
          if (this.videoInfo) {
            // this.debugVideoInfo()
            Column() {
              this.videoPlayer()
            }
            .transition(TransitionEffect.asymmetric(TransitionEffect.OPACITY.animation({ duration: 300 }),
              TransitionEffect.IDENTITY))

            // 渐显
          } else {
            // Loading indicator
            AnimatedProgressView({ color: DarkTheme.biliPink })
              .width(50)
              .height(50)
              // 渐隐
              .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
                TransitionEffect.OPACITY.animation({ duration: 300 })))
          }
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .height('100%')
      .backgroundColor('#121212')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => {
      this.onShown()
    })
    .onHidden(() => {
      this.onHidden()
    })
    .onBackPressed(() => {
      // 业务逻辑：修复播放视频多功能界面右滑后，直接退出播放界面的问题
      if (this.playerViewModel.showMenu) {
        this.playerViewModel.clickMenuCloseButton()
        return true
      }
      // 调整进度页面
      if (this.playerViewModel.seekData.seekSliderVisible) {
        this.playerViewModel.clickSliderCloseButton()
        return true
      }
      return false
    })
  }

  @Monitor('lifecycle.foreground', 'pageVisible', 'playerViewModel.playing', 'playerViewModel.loaded',
    'playerViewModel.isError', 'playerViewModel.resumePlayback', 'fetching', 'showError', 'videoInfo')
  private updateScreenRequirement(): void {
    const busy = this.fetching || (this.videoInfo !== undefined &&
      !this.playerViewModel.isError && (!this.playerViewModel.loaded || (this.playerViewModel.playing && this.playerViewModel.resumePlayback)));
    DeviceMgr.Ins().requestKeepScreenOn('videoPlayback',
      this.pageVisible && this.lifecycle.foreground && !this.showError && busy, this.playerViewModel.pageID);
  }

  private onShown() {
    this.pageVisible = true;
    this.updateScreenRequirement();
  }

  private onHidden() {
    this.pageVisible = false;
    this.updateScreenRequirement();
  }

  @Builder
  videoPlayer() {
    if (this.videoInfo && this.pageVisible && this.lifecycle.foreground) {
      BiliVideoPlayerView({
        pushVolumeControlPagePack: this.pushVolumeControlPagePack,
        vm: this.playerViewModel,
        onReload: (): void => { this.fetchVideoInfo(); }
      })
    } else {
      Blank()
    }
  }

  @Builder
  debugVideoInfo() {
    if (this.videoInfo) {
      Scroll() {
        Column() {
          Text('Video Information')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 10, bottom: 20 })

          // Video details in a card
          Column() {
            Row() {
              Text('Quality: ')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width('40%')

              Text(this.videoInfo.qualityDescription)
                .fontSize(16)
                .fontColor(Color.White)
                .width('60%')
            }
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              Text('Format: ')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width('40%')

              Text(this.videoInfo.format)
                .fontSize(16)
                .fontColor(Color.White)
                .width('60%')
            }
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              Text('Duration: ')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width('40%')

              Text(this.videoInfo.duration.formatted)
                .fontSize(16)
                .fontColor(Color.White)
                .width('60%')
            }
            .width('100%')
            .margin({ bottom: 10 })

            // URL info
            Text('Video URL: ')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width('100%')
              .margin({ bottom: 5 })

            Text(this.videoInfo.url)
              .fontSize(14)
              .fontColor(Color.White)
              .width('100%')
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .maxLines(3)
              .margin({ bottom: 10 })

          }
          .width('90%')
          .padding(15)
          .backgroundColor('#1F1F1F')
          .borderRadius(10)
        }
        .width('100%')
        .margin({ top: '80px', bottom: '150px' })
      }
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    } else {
      Text("404-2")
    }
  }

  fetchVideoInfo(): void {
    if (this.fetching) { return; }
    if (this.videoID === undefined) {
      this.errorMessage = '缺少视频编号，请返回后重新打开视频';
      this.showError = true;
      return;
    }

    // 重试/重新拉流时沿用本页当前进度；首次进入才使用入口带入的续播点。
    let resumeAt = this.resumeAt;
    const played = this.playerViewModel.seekData.currentPlayingTime;
    const resumedFromCurrent = played !== null && played > 0;
    if (played !== null && played > 0) {
      resumeAt = played;
    }
    console.info(`[BiliVideoPlayer] resumeAt=${resumeAt} ` +
      `source=${resumedFromCurrent ? 'current' : 'incoming'} bvid=${this.videoID.bvid}`);
    this.fetching = true;
    this.errorMessage = '';
    this.showError = false;
    this.videoInfo = undefined;

    (async () => {
      try {
        if (!this.videoID.cid) {
          console.debug(`🚩cid为空，正在尝试请求第一P的CID...`)
          const response = await this.biliService.requestVideoDetail(this.videoID.bvid)
          if (response && response.data && response.data.cid) {
            this.videoID.cid = String(response.data.cid)
            console.debug(`🚩cid为空，尝试请求第1P的CID请求成功！当前cid:`, this.videoID.cid)
          } else {
            console.debug(`🚩cid为空，CID请求失败！`)
            this.errorMessage = "查找视频分P失败，请重试"
            this.showError = true;
            return
          }
        }
        const response: BiliVideoPlaybackApiResponse =
          await this.biliService.getVideoPlayUrl(this.videoID.bvid, this.videoID.cid as string)

        // Extract video info
        const info = this.extractVideoInfo(response);
        this.playerViewModel.configurePlayback(BiliMediaMapping.playbackParts(response), resumeAt);
        this.videoInfo = info;
      } catch (parseErr) {
        if (parseErr instanceof BiliBusinessError) {
          this.errorMessage = parseErr.code === -101 ? '登录已失效，请重新登录后播放' :
            `平台暂未提供播放地址（错误码 ${parseErr.code}），请稍后重试或切换视频`;
        } else if (parseErr instanceof JsonDecodeError) {
          this.errorMessage = '返回的视频数据不完整或没有可用播放地址，请重试或切换视频';
        } else {
          this.errorMessage = '视频地址请求未成功，请检查网络后重试';
        }
        this.showError = true;
      } finally {
        this.fetching = false;
      }
    })()
  }

  extractVideoInfo(response: BiliVideoPlaybackApiResponse): VideoInfo {
    const data = response.data;
    const selection = BiliMediaMapping.playback(response);
    if (!selection.url) { throw new Error('视频播放地址不可用'); }
    // Calculate formatted duration
    const totalSeconds = Math.floor(data.timelength / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const formattedDuration = `${minutes}:${seconds.toString().padStart(2, '0')}`;


    const finalResult: VideoInfo = {
      qualityDescription: data.support_formats?.[0]?.display_desc ?? '当前画质',
      format: data.format, // Usually "mp4"
      duration: {
        milliseconds: data.timelength,
        formatted: formattedDuration
      },
      url: selection.url,
      backupUrl: selection.backupUrl
    };

    console.debug("🚩D");

    return finalResult
  }

  aboutToDisappear() {
    this.pageVisible = false;
    DeviceMgr.Ins().requestKeepScreenOn('videoPlayback', false, this.playerViewModel.pageID);
  }
}
