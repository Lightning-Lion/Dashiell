import { ListDataSource } from '../../common/ListDataSource';
import { PlaybackLifecycle, playbackLifecycle } from '../../common/PlaybackLifecycle';
import { logTag } from '../../common/printLog';
import { ArcScrollBar, curves } from '@kit.ArkUI';
import { watchHeightVp } from '../../common/ScreenSize';
import { DouYinAwemeCard } from './DouYinJingxuanPage';
import { DeviceMgr } from '../../common/AlwaysOn';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { DarkTheme } from '../../common/Theme';
import { DevFlags } from '../../common/dev/DevFlags';
import { DouYinPlayerSession } from './DouYinPlayerSession';
import { DouYinLoopMode, DouYinMenuLayer } from './DouYinPlayerUi';
import { DouYinCrownPager, CrownPagerUpdate } from './DouYinCrownPager';
import { Haptic } from '../../common/Haptic';
import { DouYinVideoSurfaceHost, VideoSlotController } from './DouYinVideoSurface';
import { DouCardItem } from './DouYinSingleCard';
import { DouYinImmersiveView } from './DouYinImmersiveView';

const crownLogTag = '👑抖音表冠';
export const DOUYIN_CROWN_PANEL_ID = 'douyinCrownDebugPanel';

/**
 * 抖音播放器：列表 + 外页推卡 + 内页宿主。
 * 整个播放器只有一个视频节点/一个 AVPlayer，节点在聚焦卡片和内页槽位之间迁移。
 */
@ComponentV2
export struct DouVideoPlayer {
  @Param @Require cards: Array<DouYinAwemeCard>;
  @Param @Require session: DouYinPlayerSession;
  @Param playbackActive: boolean = true;
  @Param @Require onReachEnd: (index: number) => void;
  @Param @Require loadingMore: boolean;
  @Param @Require loadMoreError: string;
  @Param @Require onRetryLoadMore: () => void;
  @Param @Require onExitPlayback: () => void;

  @Local private lifecycle: PlaybackLifecycle = playbackLifecycle;
  @Local private scroller: Scroller = new Scroller();
  @Local private currentFocusIndex: number = 0;
  @Local private host: DouYinVideoSurfaceHost = new DouYinVideoSurfaceHost();
  @Local private pager: DouYinCrownPager = new DouYinCrownPager();
  @Local private mountedSlot: VideoSlotController | null = null;
  @Local private animating: boolean = false;

  private slots: Record<string, VideoSlotController> = {};
  private innerSlot: VideoSlotController | null = null;
  private dataSource: ListDataSource<DouYinAwemeCard> = new ListDataSource<DouYinAwemeCard>();
  private mountRetryTimer: number | null = null;
  private mountRetryCount: number = 0;
  private exitRetryCount: number = 0;

  aboutToAppear(): void {
    this.host.build(this.getUIContext());
    this.host.onSurface = (surfaceId: string) => {
      this.session.bindSurface(surfaceId);
    };
    this.session.onCompleted = () => {
      this.onVideoCompleted();
    };
    this.session.onImmersiveRequest = (want: boolean) => {
      this.setImmersive(want);
    };
    this.session.onBusyChanged = () => {
      this.updateKeepScreenOn();
    };
    console.info(crownLogTag, 'player appear, cards=' + this.cards.length);
  }

  aboutToDisappear(): void {
    if (this.mountRetryTimer !== null) {
      clearTimeout(this.mountRetryTimer);
      this.mountRetryTimer = null;
    }
    this.session.onCompleted = null;
    this.session.onImmersiveRequest = null;
    this.session.onBusyChanged = null;
    if (this.mountedSlot !== null) {
      this.mountedSlot.attach(null);
    }
    this.mountedSlot = null;
    this.innerSlot = null;
    this.host.dispose();
  }

  @Monitor('playbackActive')
  private onPlaybackActiveChanged(): void {
    this.session.setActive(this.playbackActive && this.lifecycle.foreground);
    this.updateKeepScreenOn();
  }

  @Monitor('lifecycle.foreground')
  private onForegroundChanged(): void {
    this.session.setActive(this.playbackActive && this.lifecycle.foreground);
    this.updateKeepScreenOn();
  }

  private updateKeepScreenOn(): void {
    DeviceMgr.Ins().requestKeepScreenOn('douYinPlayback',
      this.playbackActive && this.lifecycle.foreground && (this.session.loading || this.session.playing),
      'douyinPlayer');
  }

  @Monitor('currentFocusIndex')
  private onFocusIndexChanged(): void {
    this.syncFocus();
  }

  @Monitor('cards')
  private updateCards(): void {
    const oldCount = this.dataSource.totalCount();
    let appendOnly = oldCount <= this.cards.length;
    for (let index = 0; appendOnly && index < oldCount; index++) {
      appendOnly = this.dataSource.getData(index) === this.cards[index];
    }
    if (appendOnly) {
      this.dataSource.append(this.cards.slice(oldCount));
    } else {
      this.dataSource.replace(this.cards);
    }
  }

  build() {
    Column() {
      if (this.cards.length !== 0) {
        Stack() {
          List({ scroller: this.scroller }) {
            LazyForEach(this.dataSource, (card: DouYinAwemeCard) => {
              ListItem() {
                DouCardItem({
                  card: card,
                  session: this.session,
                  onRegisterSlot: (awemeID: string, slot: VideoSlotController): void => {
                    this.registerSlot(awemeID, slot);
                  },
                  onUnregisterSlot: (awemeID: string, slot: VideoSlotController): void => {
                    this.unregisterSlot(awemeID, slot);
                  },
                  onTap: (): void => {
                    if (card.awemeID === this.focusedAwemeID()) {
                      this.session.requestImmersive(true);
                    }
                  }
                })
              }
              .height(watchHeightVp)
              .width('100%')
            }, (card: DouYinAwemeCard) => card.awemeID)
          }
          .focusable(false)
          .focusOnTouch(false)
          .tabIndex(-1)
          .cachedCount(1)
          .scrollSnapAlign(ScrollSnapAlign.START)
          .scrollBar(BarState.Off)
          .onScrollStart(() => {
            this.animating = true;
          })
          .onScrollStop(() => {
            this.onListStop();
          })
          .translate({
            y: this.session.ui.pushDirection * this.session.ui.pushProgress * 12
          })

          ArcScrollBar({ scroller: this.scroller })

          if (this.isAtLastCard() && (this.loadingMore || this.loadMoreError.length > 0)) {
            DouYinLoadMoreFooter({
              loading: this.loadingMore,
              error: this.loadMoreError,
              onRetry: this.onRetryLoadMore
            })
          }

          DouYinCrownDebugPanel({
            modeText: this.session.ui.immersive ? '内页/音量' : '外页/推卡',
            onCrown: (event: CrownEvent): void => {
              this.handleCrown(event);
            },
            onSimulate: (degree: number): void => {
              this.simulateCrown(degree);
            }
          })

          if (this.session.ui.immersive) {
            DouYinImmersiveView({
              session: this.session,
              index: this.currentFocusIndex,
              total: this.cards.length,
              onInnerSlotReady: (slot: VideoSlotController): void => {
                this.onInnerSlotReady(slot);
              },
              onInnerSlotGone: (): void => {
                this.onInnerSlotGone();
              },
              onExitPlayback: (): void => {
                this.onExitPlayback();
              }
            })
              .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.Smooth }))
          }

          if (this.session.loading) {
            AnimatedProgressView({ color: DarkTheme.accents.douyin })
              .width(50)
              .height(50)
          }

          if (this.session.errorMessage.length > 0) {
            Text(this.session.errorMessage)
              .fontSize('12fp')
              .fontColor(Color.White)
              .padding({ left: '10vp', right: '10vp', top: '5vp', bottom: '5vp' })
              .backgroundColor('#CC000000')
              .borderRadius('8vp')
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .onAppear(() => {
      this.updateCards();
      this.session.setActive(this.playbackActive && this.lifecycle.foreground);
      this.updateKeepScreenOn();
      this.syncFocus();
      this.mountFocused();
      this.refocusOuter();
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .width('100%')
    .height('100%')
  }

  private focusedAwemeID(): string {
    const card = this.cards[this.currentFocusIndex];
    return card === undefined ? '' : card.awemeID;
  }

  private isAtLastCard(): boolean {
    return this.currentFocusIndex >= this.cards.length - 1;
  }

  private syncFocus(): void {
    const card = this.cards[this.currentFocusIndex];
    if (card === undefined) { return; }
    const video = card.assumeVideo();
    if (video === null) { return; }
    // 同一张卡重进页面/重挂载时不要重置播放进度；换卡或上次失败才重新加载。
    if (this.session.currentAwemeID !== card.awemeID || this.session.errorMessage.length > 0) {
      this.session.play({
        awemeID: card.awemeID,
        urls: video.videoURLList,
        description: video.description
      });
    }
    if (!this.session.ui.immersive) {
      this.mountFocused();
    }
    if (this.isAtLastCard()) {
      this.onReachEnd(this.currentFocusIndex);
    }
  }

  private registerSlot(awemeID: string, slot: VideoSlotController): void {
    this.slots[awemeID] = slot;
    if (!this.session.ui.immersive && awemeID === this.focusedAwemeID()) {
      this.mountSlot(slot);
    }
  }

  private unregisterSlot(awemeID: string, slot: VideoSlotController): void {
    if (this.slots[awemeID] === slot) {
      const remaining: Record<string, VideoSlotController> = {};
      for (const key of Object.keys(this.slots)) {
        if (key !== awemeID) { remaining[key] = this.slots[key]; }
      }
      this.slots = remaining;
    }
    if (this.mountedSlot === slot) {
      this.mountedSlot = null;
    }
  }

  private mountFocused(): void {
    const card = this.cards[this.currentFocusIndex];
    if (card === undefined) { return; }
    const slot = this.slots[card.awemeID];
    if (slot === undefined) {
      if (this.mountRetryCount < 20) {
        this.mountRetryCount++;
        this.mountRetryTimer = setTimeout(() => {
          this.mountRetryTimer = null;
          this.mountFocused();
        }, 50);
      }
      return;
    }
    this.mountRetryCount = 0;
    this.mountSlot(slot);
  }

  private mountSlot(slot: VideoSlotController): void {
    if (this.mountedSlot === slot) { return; }
    const node = this.host.frame();
    if (node === null) { return; }
    const previous = this.mountedSlot;
    this.mountedSlot = null;
    if (previous !== null) {
      previous.attach(null);
    }
    slot.attach(node);
    this.mountedSlot = slot;
    console.info(crownLogTag, 'video node mounted to slot, immersive=' + this.session.ui.immersive);
  }

  private onInnerSlotReady(slot: VideoSlotController): void {
    this.innerSlot = slot;
    if (this.session.ui.immersive) {
      this.mountSlot(slot);
    }
  }

  private onInnerSlotGone(): void {
    if (this.innerSlot !== null && this.mountedSlot === this.innerSlot) {
      this.mountedSlot = null;
    }
    this.innerSlot = null;
  }

  private setImmersive(want: boolean): void {
    if (want) {
      if (this.session.ui.immersive) { return; }
      this.session.ui.immersive = true;
      console.info(crownLogTag, 'enter immersive, waiting inner slot');
      return;
    }
    if (!this.session.ui.immersive) { return; }
    const card = this.cards[this.currentFocusIndex];
    const slot = card === undefined ? undefined : this.slots[card.awemeID];
    if (slot === undefined) {
      if (this.exitRetryCount < 20) {
        this.exitRetryCount++;
        setTimeout(() => {
          this.setImmersive(false);
        }, 50);
      }
      return;
    }
    this.exitRetryCount = 0;
    this.mountSlot(slot);
    this.session.setLayer(DouYinMenuLayer.None);
    this.session.ui.fullscreen = false;
    this.session.ui.dragX = 0;
    this.session.ui.dragY = 0;
    this.session.ui.pushProgress = 0;
    this.session.ui.pushDirection = 0;
    this.session.setSpeed(1);
    this.session.setFullscreen(false);
    this.session.ui.immersive = false;
    setTimeout(() => {
      this.refocusOuter();
    }, 60);
  }

  private handleCrown(event: CrownEvent): void {
    event.stopPropagation();
    if (this.session.ui.immersive || this.session.ui.layer !== DouYinMenuLayer.None) {
      return;
    }
    if (event.action === CrownAction.BEGIN) {
      this.pager.begin();
    }
    this.applyCrown(event.degree);
    if (event.action === CrownAction.END) {
      this.pager.end();
      this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion() }, () => {
        this.session.ui.pushProgress = 0;
        this.session.ui.pushDirection = 0;
      });
    }
  }

  private applyCrown(degree: number): void {
    const update: CrownPagerUpdate = this.pager.update(degree, Date.now(), this.animating);
    this.session.ui.pushProgress = update.progress;
    this.session.ui.pushDirection = update.direction;
    if (update.tick) {
      Haptic.tick();
    }
    if (update.commit !== 0) {
      this.advance(update.commit);
    }
  }

  /** 仅开发探针：模拟一次表冠角度，不等真机表冠也能验证推卡。 */
  private simulateCrown(degree: number): void {
    console.info(crownLogTag, 'simulate crown degree=' + degree + ' immersive=' + this.session.ui.immersive);
    if (this.session.ui.immersive || this.session.ui.layer !== DouYinMenuLayer.None) { return; }
    this.applyCrown(degree);
  }

  private advance(direction: number): void {
    if (this.animating) { return; }
    const target = Math.max(0, Math.min(this.cards.length - 1, this.currentFocusIndex + direction));
    if (target === this.currentFocusIndex) {
      Haptic.edge();
      return;
    }
    this.animating = true;
    Haptic.commit();
    this.session.ui.pushProgress = 0;
    this.session.ui.pushDirection = 0;
    console.info(crownLogTag, `[推卡] ${this.currentFocusIndex} → ${target}`);
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: target * watchHeightVp,
      animation: { duration: 300, curve: Curve.Friction }
    });
  }

  private onListStop(): void {
    this.animating = false;
    const yOffset = this.scroller.currentOffset().yOffset;
    const page = Math.floor((yOffset + watchHeightVp / 2) / watchHeightVp);
    const next = Math.max(0, Math.min(this.cards.length - 1, page));
    if (next !== this.currentFocusIndex) {
      console.info(logTag, 'DOUYIN_LIST index=' + next);
      this.currentFocusIndex = next;
    }
  }

  private onVideoCompleted(): void {
    if (this.session.loopMode !== DouYinLoopMode.Sequence) { return; }
    if (this.isAtLastCard()) {
      this.onReachEnd(this.currentFocusIndex);
      return;
    }
    this.advance(1);
  }

  private refocusOuter(): void {
    const request = (): void => {
      try {
        this.getUIContext().getFocusController().requestFocus(DOUYIN_CROWN_PANEL_ID);
      } catch (error) {
        console.debug(crownLogTag, 'outer focus failed: ' + error.message);
      }
    };
    request();
    setTimeout(request, 100);
  }
}

@ComponentV2
struct DouYinCrownDebugPanel {
  @Param @Require modeText: string;
  @Param @Require onCrown: (event: CrownEvent) => void;
  @Param @Require onSimulate: (degree: number) => void;

  // 只控制读数/模拟按钮是否可见。面板本身必须始终挂载并持有表冠焦点，
  // release 下缩成 1vp 透明焦点捕获器，外页推卡行为不受影响。
  private dev: boolean = DevFlags.douyinDevUI;

  @Local private focused: boolean = false;
  @Local private totalDegree: number = 0;
  @Local private velocity: number = 0;
  @Local private action: string = 'IDLE';

  build() {
    Column({ space: 4 }) {
      Button()
        .width(this.dev ? 40 : 1)
        .height(this.dev ? 24 : 1)
        .focusable(true)
        .onClick(() => {
          this.refocus();
        })
      if (this.dev) {
        Text(this.focused ? '焦点：已获得' : '焦点：未获得')
          .fontSize(12)
          .fontColor(this.focused ? '#7CFC00' : '#FFB6C1')
        Text(`模式：${this.modeText}  累计角度：${this.totalDegree.toFixed(0)}°`)
          .fontSize(11)
          .fontColor(Color.White)
        Text(`角速度：${this.velocity.toFixed(0)}°/s  动作：${this.action}`)
          .fontSize(10)
          .fontColor('#CCFFFFFF')
        Row({ space: 6 }) {
          Button('推+30°').fontSize(10).height(24).onClick(() => {
            this.onSimulate(-30);
          })
          Button('推-30°').fontSize(10).height(24).onClick(() => {
            this.onSimulate(30);
          })
        }
      }
    }
    .width(this.dev ? '92%' : '1vp')
    .padding({
      left: this.dev ? 12 : 0,
      right: this.dev ? 12 : 0,
      top: this.dev ? 6 : 0,
      bottom: this.dev ? 6 : 0
    })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.dev ? '#8C000000' : Color.Transparent)
    .borderRadius(8)
    .opacity(this.dev ? 1 : 0)
    .clip(true)
    .margin({ top: 6 })
    .id(DOUYIN_CROWN_PANEL_ID)
    .focusable(true)
    .defaultFocus(true)
    .onFocus(() => {
      this.focused = true;
      console.info(crownLogTag, 'outer crown panel focused');
    })
    .onBlur(() => {
      this.focused = false;
      console.warn(crownLogTag, 'outer crown panel blurred');
    })
    .onDigitalCrown((event: CrownEvent) => {
      this.totalDegree += event.degree;
      this.velocity = event.angularVelocity;
      this.action = this.actionName(event.action);
      this.onCrown(event);
    })
  }

  private refocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(DOUYIN_CROWN_PANEL_ID);
    } catch (error) {
      console.warn(crownLogTag, 'refocus failed: ' + error.message);
    }
  }

  private actionName(action: CrownAction): string {
    if (action === CrownAction.BEGIN) { return 'BEGIN'; }
    if (action === CrownAction.UPDATE) { return 'UPDATE'; }
    if (action === CrownAction.END) { return 'END'; }
    return 'UNKNOWN';
  }
}

@ComponentV2
struct DouYinLoadMoreFooter {
  @Param @Require loading: boolean;
  @Param @Require error: string;
  @Param @Require onRetry: () => void;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: '4vp' }) {
        if (this.loading) {
          AnimatedProgressView({ color: DarkTheme.accents.douyin })
            .width('30vp')
            .height('30vp')
          Text('正在加载更多')
            .fontSize('14fp')
            .fontColor(DarkTheme.textPrimary)
        } else {
          Text(this.error)
            .fontSize('14fp')
            .fontColor(DarkTheme.textPrimary)
            .textAlign(TextAlign.Center)
            .width('75%')
          Button('重试')
            .fontSize('14fp')
            .height('30vp')
            .fontColor(Color.White)
            .backgroundColor(DarkTheme.prominentButton)
            .onClick(() => {
              this.onRetry();
            })
        }
      }
      .margin({ bottom: '16vp' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
  }
}
