import { BiliPlaybackQueue, PlaybackPart } from '../../common/bili/BiliPlaybackQueue';
import { UUID } from "../../common/UUID";
import { BiliVideoPlayerMenu } from "./BiliVideoPlayerMenu";
import { logTag } from "../../common/printLog";
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { ErrorPrompt } from "../../components/ErrorPages";
import { DarkTheme } from "../../common/Theme";
import { audio, AVVolumePanel } from "@kit.AudioKit";
import { LengthMetrics, RectShape } from "@kit.ArkUI";
import { CapsuleVolumeBar } from "../../components/CapsuleVolumeBar";

@ObservedV2
export class BiliVideoPlayerViewModel {
  @Trace
  pageID: string = UUID()
  @Trace
  objectFitMode: ImageFit = ImageFit.Contain

  @Computed
  get fullScreen(): boolean {
    if (this.objectFitMode == ImageFit.Cover) {
      return true
    } else {
      return false
    }
  }

  @Trace
  showControls: boolean = true
  @Trace
  isError: boolean = false
  @Trace
  loaded: boolean = false
  @Trace
  controller: VideoController = new VideoController();
  @Trace
  resumePlayback: boolean = true
  @Trace
  playing: boolean = false
  @Trace
  seekData: PlayerSeekSliderViewData = new PlayerSeekSliderViewData(this)
  @Trace
  showFloatBar: boolean = false
  @Trace
  showMenu: boolean = false
  @Trace
  digitalCrownVolumeMod:BiliVideoPlayerDigitalCrownViewModel = new BiliVideoPlayerDigitalCrownViewModel()
  @Trace
  pushVolumeControlPagePack: PushVolumeControlPagePack

  private queue: BiliPlaybackQueue = new BiliPlaybackQueue();
  @Trace currentVideoURL: string = '';
  @Trace sourceRevision: number = 0;
  private seeking: boolean = false;

  configurePlayback(parts: PlaybackPart[], resumeAt: number = 0): void {
    this.triggerSeekDoneByUpdate();
    this.queue.configure(parts);
    if (resumeAt > 0 && this.queue.duration > 0) { this.queue.seek(resumeAt); }
    this.seekData.currentPlayingTime = this.queue.position;
    this.seekData.duration = this.queue.duration > 0 ? this.queue.duration : null;
    this.resumePlayback = true;
    this.switchSource();
  }

  suspendPlayback(): void {
    this.triggerSeekDoneByUpdate();
    // Invalidate events from the old native Video even when resuming the same URL.
    this.sourceRevision++;
    this.loaded = false;
    this.playing = false;
  }

  private switchSource(): void {
    this.loaded = false;
    this.isError = false;
    this.playing = false;
    this.currentVideoURL = this.queue.url;
    // Recreate even if two different segments happen to use the same address.
    this.sourceRevision++;
  }

  onFinish(): void {
    this.triggerSeekDoneByUpdate();
    if (this.queue.next()) {
      this.seekData.currentPlayingTime = this.queue.position;
      this.resumePlayback = true;
      this.switchSource();
    } else {
      this.seekData.currentPlayingTime = this.queue.position;
      this.playing = false;
      this.resumePlayback = false;
    }
  }

  retryPlayback(): void {
    this.triggerSeekDoneByUpdate();
    this.queue.retry();
    this.resumePlayback = true;
    this.switchSource();
  }

  readonly component: CustomComponent

  constructor(pushVolumeControlPagePack: PushVolumeControlPagePack, component: CustomComponent) {
    this.pushVolumeControlPagePack = pushVolumeControlPagePack
    this.component = component
  }

  @Monitor("seekData.pendingSeekRequest")
  onNewSeekRequest() {
    (async () => {
      if (this.seekData.pendingSeekRequest !== null) {
        let request = this.seekData.pendingSeekRequest
        console.debug("🚩收到了一次SeekRequest，到：" + JSON.stringify(request))
        // 记录开始时间
        const startTime = Date.now();
        try {
          // 如果用户在上一个seek请求还没完成的时候触发了下一个seek请求，则会直接resolve这个await
          await this.asyncSeekTo(request.targetTime)
        } catch (error) {
          console.debug("🚩有一次setCurrentTime出错了，错误消息：" + error.message ?? JSON.stringify(error, null, 2))
        }
        // 计算耗时
        const endTime = Date.now();
        const executionTime = endTime - startTime;

        console.debug(`🚩seek操作耗时: ${executionTime}ms`);
        if (this.seekData.pendingSeekRequest !== null) {
          if (this.seekData.pendingSeekRequest.id === request.id) {
            console.debug("🚩完成了一个seek请求，想到时间点：" + request.targetTime)
            // 允许slider的progress继续随着播放更新
            this.seekData.pendingSeekRequest = null
          } else {
            // 处理已经被覆盖的Request这种情形
            // 下一个新的seek请求已经进行着了
            console.debug("🚩下一个新的seek请求已经进行着了")
          }
        } else {
          console.debug("🚩不应该出现这个情况，是谁把this.seekData.pendingSeekRequest偷偷设为null的？！")
        }
      }
    })()
  }

  // Only one pending seek owns the waiters. Cross-part seeks are applied after prepare.
  private seekResolve: (() => void) | null = null;
  private seekTimeout: number | null = null;

  async asyncSeekTo(targetTime: number): Promise<void> {
    this.triggerSeekDoneByUpdate();
    const seek = this.queue.seek(targetTime);
    this.seekData.currentPlayingTime = this.queue.position;
    this.seeking = true;
    return new Promise<void>((resolve, reject) => {
      this.seekResolve = resolve;
      this.seekTimeout = setTimeout(() => this.triggerSeekDoneByUpdate(), 10000);
      try {
        if (seek.changedPart) {
          this.switchSource();
        } else if (this.loaded) {
          this.controller.setCurrentTime(seek.localTime, SeekMode.Accurate);
        }
        // When not prepared, onDuration applies the queue's requested local position.
      } catch (error) {
        if (this.seekTimeout !== null) { clearTimeout(this.seekTimeout); }
        this.seekTimeout = null;
        this.seekResolve = null;
        this.seeking = false;
        reject(error);
      }
    });
  }

  /**
   * Called when seeking is complete to resolve the pending promise
   */
  triggerSeekDoneByUpdate(): void {
    this.seeking = false;
    // Clear the timeout since we no longer need it
    if (this.seekTimeout !== null) {
      clearTimeout(this.seekTimeout);
      this.seekTimeout = null;
    }

    // If there's a pending seek operation, resolve it
    if (this.seekResolve) {
      this.seekResolve();
      this.seekResolve = null;
    }
  }

  onStart() {
    console.debug("🚩标记了playing为true")
    this.playing = true
  }

  onPause() {
    console.debug("🚩标记了playing为false")
    this.playing = false
  }

  onError() {
    this.triggerSeekDoneByUpdate();
    if (this.queue.fallback()) {
      this.switchSource();
    } else {
      this.loaded = true;
      this.playing = false;
      this.isError = true;
    }
  }

  onDuration(duration: number) {
    this.queue.prepared(duration);
    this.loaded = true;
    this.seekData.duration = this.queue.duration > 0 ? this.queue.duration : null;
    const local = this.queue.localTime;
    if (local > 0) {
      this.seeking = true;
      if (this.seekTimeout === null) {
        this.seekTimeout = setTimeout(() => this.triggerSeekDoneByUpdate(), 5000);
      }
      this.controller.setCurrentTime(local, SeekMode.Accurate);
    } else {
      this.triggerSeekDoneByUpdate();
    }
  }

  onUpdate(playbackInfo: PlaybackInfo) {
    // Ignore pre-seek progress events; they must not replace the requested resume point.
    if (this.seeking) {
      if (Math.abs(playbackInfo.time - this.queue.localTime) > 1) { return; }
      this.triggerSeekDoneByUpdate();
    }
    this.queue.update(playbackInfo.time);
    this.seekData.currentPlayingTime = this.queue.position;
  }

  playOrPause() {
    if (this.queue.completed) {
      this.queue.restart();
      this.seekData.currentPlayingTime = 0;
      this.resumePlayback = true;
      this.switchSource();
    } else if (this.playing) {
      this.resumePlayback = false;
      this.controller.pause();
    } else {
      this.resumePlayback = true;
      this.controller.start();
    }
  }

  showBottomBarOrHide() {
    if (this.showFloatBar === true) {
      this.component.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
        this.showFloatBar = false
      })
    } else {
      this.component.getUIContext().animateTo({ duration: 150, curve: Curve.Smooth }, () => {
        this.showFloatBar = true
      })
    }
  }

  showSlider() {
    this.component.getUIContext().animateTo({ duration: 150, curve: Curve.Smooth }, () => {
      this.seekData.seekSliderVisible = true
    })
  }

  showSliderOrHide() {
    if (this.seekData.seekSliderVisible === true) {
      this.component.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
        this.seekData.seekSliderVisible = false
      })
    } else {
      this.component.getUIContext().animateTo({ duration: 150, curve: Curve.Smooth }, () => {
        this.seekData.seekSliderVisible = true
      })
    }
  }

  clickSliderCloseButton() {
    this.component.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      this.seekData.seekSliderVisible = false
    })
  }

  clickFloatBarMenuButton() {
    console.debug("🚩触发clickFloatBarMenuButton")
    this.component.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, () => {
      this.showMenu = true
    })
  }

  clickMenuPlaybackBarButton() {
    this.component.getUIContext().animateTo({
      duration: 300, curve: Curve.Smooth, onFinish: () => {
        // 关闭菜单了，显示进度条
        this.showSlider()
      }
    }, () => {
      this.showMenu = false
    })
  }

  clickMenuFullscreenButton() {
    this.component.getUIContext().animateTo({
      duration: 300, curve: Curve.Smooth, onFinish: () => {
        // 关闭菜单了，切换全屏
        this.component.getUIContext().animateTo({
          duration: 300,
          curve: Curve.Smooth,
        }, () => {
          this.fillOrFit()
        })
      }
    }, () => {
      this.showMenu = false
    })

  }

  clickMenuVolumeControlButton() {
    this.component.getUIContext().animateTo({
      duration: 300, curve: Curve.Smooth, onFinish: () => {
        // 关闭菜单了，打开音量面板
        this.pushVolumeControlPagePack.triggerID = UUID()
      }
    }, () => {
      this.showMenu = false
    })

  }

  clickMenuCloseButton() {
    this.component.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      this.showMenu = false
    })

  }

  fillOrFit() {
    if (this.objectFitMode == ImageFit.Cover) {
      // to fit
      this.objectFitMode = ImageFit.Contain
    } else {
      // to fill
      this.objectFitMode = ImageFit.Cover
    }
  }
}

@ObservedV2
export class BiliVideoPlayerDigitalCrownViewModel {
  @Trace
  focusComponentID:string = "7151a9bf-c52d-45d5-a2fd-6de46f4f0c94"
  defaultFocus(pageID:string,uiContext:UIContext) {
    try {
      uiContext.getFocusController().requestFocus(pageID + this.focusComponentID)
    } catch (error) {
      console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
    }
  }
  @Trace
  currentVolume:number = 0 // 0-15
  @Trace
  currentVolumeReady:boolean = false

  // 返回的是0-15
  async getCurrentVolume(): Promise<number> {
    const groupId: number = audio.DEFAULT_VOLUME_GROUP_ID;
    const audioManager = audio.getAudioManager();
    const audioVolumeManager: audio.AudioVolumeManager = audioManager.getVolumeManager();
    const audioVolumeGroupManager: audio.AudioVolumeGroupManager = await audioVolumeManager.getVolumeGroupManager(groupId)
    const volume = await audioVolumeGroupManager.getVolume(audio.AudioVolumeType.MEDIA);
    return volume
  }
  @Trace
  showCurrentVolumeBar:boolean = false
  @Trace
  disappearDelay:number | null = null
  async handleDigtialCrown(event: CrownEvent) {
    if (event.action === CrownAction.BEGIN) {
      try {
        this.currentVolume = await this.getCurrentVolume()
      } catch (error) {
        console.debug(logTag,"获取当前音量出错了")
        this.currentVolume = 50
      }
      this.currentVolumeReady = true
      // 显示音量悬浮窗
      if (this.disappearDelay !== null) {
        clearTimeout(this.disappearDelay)
      }
      this.showCurrentVolumeBar = true
    }
    if (this.currentVolumeReady) {
      // 表冠往上转是-的，为了调节音量更符合直觉，这里取-
      // 表冠原始灵敏度过高，这里用 0.02 缩放角度，避免轻微转动就直接打到最大或最小音量
      const scaleRatio = 0.02
      const elips = event.degree
      const volumeChange = (-elips) * scaleRatio
      // 钳制到0-15
      const newVolumeUnbound = this.currentVolume + volumeChange
      const newVolume = Math.min(Math.max(0,newVolumeUnbound),15)
      this.currentVolume = newVolume
    } else {
      // 直接抛弃这些事件，因为实际上这个await不会等太久，丢失几帧的表冠运动不要紧
    }
    // 隐藏音量悬浮窗
    if (event.action === CrownAction.END) {
      // 因为表冠一停止旋转就会报结束，导致音量bar反反复复出现消失（闪烁），这里设置一个延时，表冠停止旋转后继续显示1秒
      this.disappearDelay = setTimeout(() => {
        this.showCurrentVolumeBar = false
      },1000)
    }
  }
}

@ObservedV2
export class PushVolumeControlPagePack {
  @Trace
  triggerID: string = UUID()
}


@ComponentV2
export struct BiliVideoPlayerView {
  @Param @Require pushVolumeControlPagePack: PushVolumeControlPagePack
  @Param @Require vm: BiliVideoPlayerViewModel
  @Param onReload: (() => void) | undefined = undefined

  aboutToAppear(): void {
    this.vm.loaded = false;
  }

  aboutToDisappear(): void {
    this.vm.suspendPlayback();
    if (this.vm.digitalCrownVolumeMod.disappearDelay !== null) {
      clearTimeout(this.vm.digitalCrownVolumeMod.disappearDelay);
      this.vm.digitalCrownVolumeMod.disappearDelay = null;
    }
    this.vm.controller.pause();
    this.vm.playing = false;
    this.vm.loaded = false;
  }

  build() {
    Stack() {
      AVVolumePanel({
        volumeLevel: this.vm.digitalCrownVolumeMod.currentVolume,
      })
      Column() {
        ForEach([this.vm.sourceRevision], (revision: number) => {
        Video({
          src: this.vm.currentVideoURL,
          controller: this.vm.controller
        })
          .id(this.vm.pageID + this.vm.digitalCrownVolumeMod.focusComponentID)
          .focusable(true)
          // 因为我不是页面一打开就在的元素，只是.defaultFocus(true)没效果
          .onAppear(() => {
            this.vm.digitalCrownVolumeMod.defaultFocus(this.vm.pageID,this.getUIContext())
          })
          .focusOnTouch(true)
          .onDigitalCrown(async (event) => {
            await this.vm.digitalCrownVolumeMod.handleDigtialCrown(event)
          })
          .muted(false) //设置是否静音
          .controls(false) //设置是否显示默认控制条
          .autoPlay(this.vm.resumePlayback) // 保留用户暂停状态，隐藏时释放视频组件
          .loop(false) // 分段完成后交给队列接续，不能循环第一段
          .objectFit(this.vm.objectFitMode) //设置视频适配模式
          .onStart(() => {
            if (revision !== this.vm.sourceRevision) { return; }
            console.debug("🚩onStart")
            this.vm.onStart()
          })
          .onPause(() => {
            if (revision !== this.vm.sourceRevision) { return; }
            console.debug("🚩onPause")
            this.vm.onPause()
          })
          .onUpdate((playbackInfo) => {
            if (revision !== this.vm.sourceRevision) { return; }
            this.vm.onUpdate(playbackInfo)
          })
          .onError(() => {
            if (revision !== this.vm.sourceRevision) { return; }
            console.debug("🚩onError")
            this.vm.onError()
          })
          .onPrepared((event) => {
            if (revision !== this.vm.sourceRevision) { return; }
            console.debug("🚩onPrepared")
            console.debug("🚩event", JSON.stringify(event))
            this.vm.onDuration(event.duration)
          })
          .onFinish(() => {
            if (revision === this.vm.sourceRevision) { this.vm.onFinish(); }
          })
          .onSeeking(() => {
            if (revision !== this.vm.sourceRevision) { return; }
            console.debug("🚩onSeeking")
          })
          .onSeeked(() => {
            if (revision !== this.vm.sourceRevision) { return; }
            this.vm.triggerSeekDoneByUpdate()
          })
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2, fingers: 1 })
                .onAction(() => {
                  console.debug('🚩Double tap gesture detected')
                  this.getUIContext().animateTo({
                    duration: 300,
                    curve: Curve.Smooth,
                  }, () => {
                    this.vm.fillOrFit()
                  })
                }),
              TapGesture({ count: 1, fingers: 1 })
                .onAction(() => {
                  console.debug("🚩检测到单击")
                  this.vm.showBottomBarOrHide()
                })
            )
          )
        }, (revision: number) => String(revision))
      }
      if (this.vm.digitalCrownVolumeMod.showCurrentVolumeBar) {
        Column() {
          Blank()
          Blank()
          // 进场（blur-in）由 CapsuleVolumeBar 自己做；退场淡出交给外层 Column 的 transition。
          CapsuleVolumeBar({
            progress: this.vm.digitalCrownVolumeMod.currentVolume * (100 / 15),
            icon: $r("app.media.bili_player_volume_floating_bar_icon")
          })
          Blank()
        }
        .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,TransitionEffect.OPACITY.animation({ duration:233,curve:Curve.Smooth })))
        .width("100%")
        .height("100%")
      }
      if (this.vm.seekData.seekSliderVisible) {
        PlayerSeekSliderView({
          vm: this.vm.seekData, clickClose: () => {
            this.vm.clickSliderCloseButton()
          }
        })
      }
      // 不要在显示进度条的时候显示我，进度条有自己的关闭按钮
      if ((this.vm.showFloatBar) && (!this.vm.seekData.seekSliderVisible)) {
        BottomFloatBar({
          playing: this.vm.playing,
          tapButton0: () => {
            this.vm.playOrPause()
          }, tapButton1: () => {
            this.vm.clickFloatBarMenuButton()
          }
        })
      }
      if (!this.vm.loaded) {
        // Loading indicator
        AnimatedProgressView({ color: DarkTheme.biliPink })
          .width(50)
          .height(50)
          .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
            TransitionEffect.OPACITY.animation({ duration: 300 })))
      }
      if (this.vm.showMenu === true) {
        BiliVideoPlayerMenu({
          fullscreen: this.vm.fullScreen,
          click0: () => {
            this.vm.clickMenuPlaybackBarButton()
          },
          click1: () => {
            this.vm.clickMenuFullscreenButton()
          },
          click2: () => {
            this.vm.clickMenuVolumeControlButton()
          },
          clickClose: () => {
            this.vm.clickMenuCloseButton()
          }
        })
          .transition(TransitionEffect.OPACITY)
      }
      if (this.vm.isError) {
        ErrorPrompt({
          errorMessage: "当前视频分段播放失败，可能是网络、地址过期或格式不支持，请重试",
          showRetryButton: true,
          onRetry: () => {
            if (this.onReload !== undefined) { this.onReload(); }
            else { this.vm.retryPlayback(); }
          },
          showCloseButton: false,
        })
      }
    }
  }
}


@ComponentV2
struct BottomFloatBar {
  @Param @Require playing: boolean
  @Param @Require tapButton0: () => void
  @Param @Require tapButton1: () => void

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: "20fp" }) {
        Button({ type: ButtonType.Circle }) {
          if (this.playing === true) {
            Image($r("app.media.bili_player_pause_icon"))
              .objectFit(ImageFit.Cover)
              .width("38fp")
              .height("38fp")
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0, y: 0 }))
                .animation({ duration: 300, curve: Curve.Smooth }))

          } else {
            Image($r("app.media.bili_player_play_icon"))
              .objectFit(ImageFit.Cover)
              .width("38fp")
              .height("38fp")
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0, y: 0 }))
                .animation({ duration: 300, curve: Curve.Smooth }))
          }
        }
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onClick(() => {
          this.tapButton0()
        })

        Button({ type: ButtonType.Circle }) {
          Image($r("app.media.bili_player_menu_icon"))
            .objectFit(ImageFit.Cover)
            .width("38fp")
            .height("38fp")
        }
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onClick(() => {
          this.tapButton1()
        })
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: "20fp" })
    }
    .width("100%")
    .height("100%")
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({
      x: 0,
      y: 0,
      // 视觉效果：按钮沿着自己的bottom边放大出来
      // 这个200vp是按钮放大动画anchor的Y，截图测量，按钮底边的y就是200vp
      centerY: 200
    })))
    .hitTestBehavior(HitTestMode.None)
  }
}

interface currentAndTotal {
  curent: string;
  total: string;
}

interface SeekRequest {
  id: string;
  targetTime: number
}

@ObservedV2
class PlayerSeekSliderViewData {
  @Trace
  currentPlayingTime: number | null = null
  @Trace
  duration: number | null = null
  @Trace
  seekSliderVisible: boolean = false
  @Trace
  sliderTime: number | null = null

  @Computed
  get sliderProgress(): number {
    if ((this.sliderTime !== null) && (this.duration !== null)) {
      return this.sliderTime / this.duration
    } else {
      return 0
    }
  }

  // 更新我这个值，外面会知道应该seek了
  @Trace
  pendingSeekRequest: SeekRequest | null = null
  private readonly model: BiliVideoPlayerViewModel

  constructor(model: BiliVideoPlayerViewModel) {
    this.model = model
  }

  @Monitor("currentPlayingTime")
  onUpdate0() {
    if (this.seekSliderVisible === true) {
      // 更新显示状态
      if (this.pendingSeekRequest === null) {
        // 用户不正在滑动的时候，实时更新进度条的位置
        console.debug("🚩更新进度条时间")
        this.sliderTime = this.currentPlayingTime
      } else {
        console.debug("🚩避免打架")
        // 在滑动，不要和用户的操作打架
        // 我也不希望看到一松手，进度条就弹回当前的时间点了
      }
    } else {
      // 节约资源
    }
  }

  @Monitor("seekSliderVisible","pendingSeekRequest","duration","currentPlayingTime")
  updatePlaybackProgressDisplayText() {
    if (this.seekSliderVisible === true) {
      // 更新显示状态
      this.model.component.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
        if ((this.pendingSeekRequest !== null) && (this.duration !== null)) {
          // 用户在seek的时候，优先显示目标seek时间
          this.playbackProgressDisplayText =
            this.formatTimeProgressRow(this.pendingSeekRequest.targetTime, this.duration)
        } else if ((this.currentPlayingTime !== null) && (this.duration !== null)) {
          this.playbackProgressDisplayText = this.formatTimeProgressRow(this.currentPlayingTime, this.duration)
        } else {
          this.playbackProgressDisplayText = null;
        }
      })
    } else {
      // 节约资源
    }
  }

  @Trace
  playbackProgressDisplayText: currentAndTotal | null = null

  private formatTimeProgressRow(
    seconds: number,
    totalSeconds: number
  ): currentAndTotal {
    // 确保秒数为非负数
    seconds = Math.max(0, Math.floor(seconds));

    const total = totalSeconds

    // 格式化当前时间和总时间
    const formatTime = (secs: number): string => {
      const hours = Math.floor(secs / 3600);
      const minutes = Math.floor((secs % 3600) / 60);
      const remainingSeconds = secs % 60;

      if (hours > 0) {
        return `${hours.toString().padStart(2, '0')}:${minutes.toString()
          .padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
      } else {
        return `${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
      }
    };

    // 返回最终格式化的时间进度条字符串
    return {
      curent: `${formatTime(seconds)}`,
      total: `${formatTime(total)}`
    }
  }

  submitSeek(normalizedProgress: number) {
    if (this.duration === null) {
      console.debug("🚩由于this.duration === null，seek失败")
      return
    }
    const time = this.duration * normalizedProgress
    // 触发外界Monitor
    this.pendingSeekRequest = { id: UUID(), targetTime: time }
  }
}

@ComponentV2
struct PlayerSeekSliderView {
  @Param @Require vm: PlayerSeekSliderViewData
  @Param @Require clickClose: () => void

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: "20fp" }) {
          if (this.vm.playbackProgressDisplayText !== null) {
            Text(`${this.vm.playbackProgressDisplayText.curent}/${this.vm.playbackProgressDisplayText.total}`)
              .padding("10fp")
              // 避免白色背景的视频下看不清字
              .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
              .borderRadius("18fp")
              .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
          }
          Slider({
            min: 0,
            max: 1,
            step: 0.01,
            value: this.vm.sliderProgress,
            style: SliderStyle.OutSet,
            direction: Axis.Horizontal
          })
            .focusable(true)
            .defaultFocus(true)
            .focusOnTouch(true)
            .digitalCrownSensitivity(CrownSensitivity.MEDIUM)
            .enableHapticFeedback(true)
            .trackThickness('30vp')
            .selectedColor($r("app.color.brand_color"))
            .selectedBorderRadius(0)
            .height("40fp")
            .onChange((value) => {
              console.debug(logTag, '进度条value:' + value)
              // 提交完了以后，外界会通知已经seek成功了的
              this.vm.submitSeek(value)
            })
        }
      }
      .width("100%")
      .height("100%")

      Button({ type: ButtonType.Circle }) {
        Image($r("app.media.bili_player_menu_icon"))
          .objectFit(ImageFit.Cover)
          .width("38fp")
          .height("38fp")
      }
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .margin({ bottom: "20fp" })
      .onClick(() => {
        this.clickClose()
      })

    }
    .hitTestBehavior(HitTestMode.None)
    .width("100%")
    .height("100%")
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({
      x: 0,
      y: 0,
      // 视觉效果：slider沿着自己的bottom边放大出来
      // 这个160vp是slider放大动画anchor的Y，截图测量，slider底边的y就是160vp
      centerY: 160
    })))
  }
}