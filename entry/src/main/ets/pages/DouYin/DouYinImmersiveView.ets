import { DouYinPlayerSession } from './DouYinPlayerSession';
import { DouYinLoopMode, DouYinMenuLayer } from './DouYinPlayerUi';
import { VideoSlotController } from './DouYinVideoSurface';
import { CapsuleVolumeBar } from '../../components/CapsuleVolumeBar';
import { UUID } from '../../common/UUID';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DevFlags } from '../../common/dev/DevFlags';
import { watchHeightVp, watchWidthVp } from '../../common/ScreenSize';
import {
  DouYinFanMenu,
  DouYinFullMenu,
  DouYinInfoPanel,
  DouYinSeekPanel,
  DouYinVolumePanel
} from './DouYinImmersiveMenu';

/**
 * 内页：独立组件，不持有 AVPlayer，只画菜单/手势，并通过 session 控制播放。
 * 视频节点由外层播放器迁移到这里的 NodeContainer 槽位。
 */
@ComponentV2
export struct DouYinImmersiveView {
  @Param @Require session: DouYinPlayerSession;
  @Param index: number = 0;
  @Param total: number = 0;
  @Param @Require onInnerSlotReady: (slot: VideoSlotController) => void;
  @Param @Require onInnerSlotGone: () => void;
  @Param @Require onExitPlayback: () => void;

  @Local private slot: VideoSlotController = new VideoSlotController();
  @Local private focused: boolean = false;
  @Local private seekFocusId: string = 'douyin-seek-' + UUID();

  private readonly crownId: string = 'douyin-immersive-crown-' + UUID();
  private lastX: number = 0;
  private lastY: number = 0;

  aboutToAppear(): void {
    this.session.volume.ensureReady();
    this.session.onFullscreenChanged = (on: boolean): void => {
      this.applyBackGesture(!on);
    };
    this.applyBackGesture(!this.session.ui.fullscreen);
    this.session.onLayerChanged = (layer: DouYinMenuLayer): void => {
      if (layer !== DouYinMenuLayer.Seek) {
        this.refocusCrown();
      }
    };
    setTimeout(() => {
      this.refocusCrown();
    }, 30);
  }

  aboutToDisappear(): void {
    this.session.onLayerChanged = null;
    this.session.onFullscreenChanged = null;
    this.applyBackGesture(true);
  }

  build() {
    Stack() {
      Stack() {
        NodeContainer(this.slot)
          .width('100%')
          .height('100%')
          .onAppear(() => {
            this.onInnerSlotReady(this.slot);
          })
          .onDisAppear(() => {
            this.onInnerSlotGone();
          })
      }
      .width('100%')
      .height('100%')
      .translate({ x: this.session.ui.dragX, y: this.session.ui.dragY })

      Column()
        .width('100%')
        .height('100%')
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
        // 画面上单击/上滑都不开菜单：扇形只由底部菜单钮展开，避免误触。
        .gesture(
          LongPressGesture({ repeat: false, fingers: 1, duration: 360 })
            .onAction(() => {
              this.handleLongPress(true);
            })
            .onActionEnd(() => {
              this.handleLongPress(false);
            })
            .onActionCancel(() => {
              this.handleLongPress(false);
            })
        )

      // 内页表冠焦点：整页唯一消费者，只调音量
      Column() {
        Button()
          .width(1)
          .height(1)
          .focusable(true)
          .onClick(() => {
            this.refocusCrown();
          })
      }
      .id(this.crownId)
      .width(1)
      .height(1)
      .opacity(0)
      .focusable(true)
      .defaultFocus(true)
      .onFocus(() => {
        this.focused = true;
        console.info('👑抖音表冠', 'inner crown panel focused');
      })
      .onBlur(() => {
        this.focused = false;
        console.warn('👑抖音表冠', 'inner crown panel blurred');
      })
      .onDigitalCrown((event: CrownEvent) => {
        event.stopPropagation();
        this.session.volume.handleCrown(event).catch((error: Error) => {
          console.debug('immersive crown failed: ' + error.message);
        });
      })

      if (this.session.volume.showBar) {
        Column() {
          Blank()
          Blank()
          // 进场（blur-in）由 CapsuleVolumeBar 自己做，这里只留退场淡出，避免两套进场叠加。
          CapsuleVolumeBar({
            progress: this.volumePercent(),
            icon: $r('app.media.dou_player_volume_floating_bar_icon')
          })
            .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
              TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.Smooth })))
          Blank()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.session.speed > 1) {
        Column() {
          Text('2.0x')
            .fontSize('12fp')
            .fontColor(Color.White)
            .padding({ left: '8vp', right: '8vp', top: '3vp', bottom: '3vp' })
            .backgroundColor('#99000000')
            .borderRadius('8vp')
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: '24vp' })
        .hitTestBehavior(HitTestMode.None)
      }

      // 菜单按钮和扇形展开由同一个组件持有：None 时只显示中心钮，
      // 点开后保持挂载，才能做「三点收成 X + 三个按钮从中心弹出」的连续动画。
      if (this.session.ui.layer === DouYinMenuLayer.None || this.session.ui.layer === DouYinMenuLayer.Fan) {
        DouYinFanMenu({
          expanded: this.session.ui.layer === DouYinMenuLayer.Fan,
          playing: this.session.playing,
          fullscreen: this.session.ui.fullscreen,
          onOpen: () => {
            this.session.setLayer(DouYinMenuLayer.Fan);
          },
          onTogglePlay: () => {
            this.session.playOrPause();
          },
          onToggleFullscreen: () => {
            this.session.setFullscreen(!this.session.ui.fullscreen);
            this.session.setLayer(DouYinMenuLayer.None);
          },
          onMore: () => {
            this.session.setLayer(DouYinMenuLayer.Full);
          },
          onClose: () => {
            this.session.setLayer(DouYinMenuLayer.None);
          }
        })
      } else if (this.session.ui.layer === DouYinMenuLayer.Full) {
        DouYinFullMenu({
          fullscreen: this.session.ui.fullscreen,
          loopMode: this.session.loopMode,
          volumePercent: this.volumePercent(),
          positionText: this.timeText(this.session.positionMs),
          onVolume: () => {
            this.session.setLayer(DouYinMenuLayer.Volume);
          },
          onSeek: () => {
            this.session.setLayer(DouYinMenuLayer.Seek);
          },
          onInfo: () => {
            this.session.setLayer(DouYinMenuLayer.Info);
          },
          onToggleLoop: () => {
            this.session.setLoopMode(this.session.loopMode === DouYinLoopMode.Single
              ? DouYinLoopMode.Sequence : DouYinLoopMode.Single);
          },
          // 留在完整菜单层：切全屏后按钮要翻成「缩小」，不像扇形那样一次性的动作完就收。
          onToggleFullscreen: () => {
            this.session.setFullscreen(!this.session.ui.fullscreen);
          },
          onExitPlayback: () => {
            this.onExitPlayback();
          },
          onClose: () => {
            this.session.setLayer(DouYinMenuLayer.Fan);
          }
        })
      } else if (this.session.ui.layer === DouYinMenuLayer.Volume) {
        DouYinVolumePanel({
          level: this.session.volume.level,
          maximum: this.session.volume.maximum,
          onLevel: (value: number) => {
            this.session.volume.setLevel(value);
          },
          onClose: () => {
            this.session.setLayer(DouYinMenuLayer.Full);
          }
        })
      } else if (this.session.ui.layer === DouYinMenuLayer.Seek) {
        DouYinSeekPanel({
          positionMs: this.session.positionMs,
          durationMs: this.session.durationMs,
          focusId: this.seekFocusId,
          onSeek: (ms: number) => {
            this.session.seekTo(ms);
          },
          onClose: () => {
            this.session.setLayer(DouYinMenuLayer.Full);
          }
        })
      } else if (this.session.ui.layer === DouYinMenuLayer.Info) {
        DouYinInfoPanel({
          description: this.session.currentDescription,
          onClose: () => {
            this.session.setLayer(DouYinMenuLayer.Full);
          }
        })
      }

      if (DevFlags.douyinDevUI) {
        Row({ space: '6vp' }) {
          Button('音量-').fontSize('10fp').height('24vp').onClick(() => {
            this.session.volume.setLevel(this.session.volume.level - 1);
          })
          Button('音量+').fontSize('10fp').height('24vp').onClick(() => {
            this.session.volume.setLevel(this.session.volume.level + 1);
          })
          Button('模拟表冠').fontSize('9fp').height('24vp').onClick(() => {
            const event: CrownEvent = {
              timestamp: Date.now() * 1000000,
              angularVelocity: 90,
              degree: -33,
              action: CrownAction.UPDATE,
              stopPropagation: (): void => {
              }
            };
            this.session.volume.handleCrown(event).catch((error: Error) => {
              console.debug('simulate crown failed: ' + error.message);
            });
          })
        }
        .position({ x: '8vp', y: '8vp' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
  }

  private handleLongPress(down: boolean): void {
    if (this.session.ui.fullscreen || this.session.ui.layer !== DouYinMenuLayer.None) {
      return;
    }
    this.session.setSpeed(down ? 2 : 1);
  }

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) { return; }
    // 只剩全屏拖画面这一种触摸用途；不开菜单，也就不需要在 Up 时判方向。
    if (!this.session.ui.fullscreen || this.session.ui.layer !== DouYinMenuLayer.None) { return; }
    const x = event.touches[0].x;
    const y = event.touches[0].y;
    if (event.type === TouchType.Down) {
      this.lastX = x;
      this.lastY = y;
    } else if (event.type === TouchType.Move) {
      const dx = x - this.lastX;
      const dy = y - this.lastY;
      this.lastX = x;
      this.lastY = y;
      this.applyDrag(dx, dy);
    }
  }

  private applyDrag(dx: number, dy: number): void {
    const videoW = this.session.videoW;
    const videoH = this.session.videoH;
    if (videoW <= 0 || videoH <= 0) { return; }
    const scale = Math.max(watchWidthVp / videoW, watchHeightVp / videoH);
    const maxX = Math.max(0, (videoW * scale - watchWidthVp) / 2);
    const maxY = Math.max(0, (videoH * scale - watchHeightVp) / 2);
    this.session.ui.dragX = this.clamp(this.session.ui.dragX + dx, -maxX, maxX);
    this.session.ui.dragY = this.clamp(this.session.ui.dragY + dy, -maxY, maxY);
  }

  /** 全屏拖拽时关掉系统侧滑返回，避免水平拖动把内页直接退掉。 */
  private applyBackGesture(enabled: boolean): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      win.setGestureBackEnabled(enabled).catch((error: Error) => {
        console.debug('setGestureBackEnabled failed: ' + error.message);
      });
    }).catch((error: Error) => {
      console.debug('getLastWindow failed: ' + error.message);
    });
  }

  private refocusCrown(): void {
    const request = (): void => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.crownId);
      } catch (error) {
        console.debug('immersive crown focus failed: ' + error.message);
      }
    };
    request();
    setTimeout(request, 100);
  }

  private volumePercent(): number {
    const max = this.session.volume.maximum > 0 ? this.session.volume.maximum : 15;
    return Math.max(0, Math.min(100, this.session.volume.level / max * 100));
  }

  private timeText(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }
}
