import { curves } from '@kit.ArkUI';
import { DarkTheme } from '../../common/Theme';
import { DouYinLoopMode } from './DouYinPlayerUi';

const PANEL_WIDTH = 170;
const PANEL_BG = '#CC101010';
// 抖音播放器的图标一律用 resources/base/media/dou_player_*.svg（色号 #FE2C55），
// 不复用 bili_player_* 那套把 #ea7999 写死的资产——哔哩哔哩粉只留给哔哩哔哩自己的东西。
// 没有 SVG 载体的部分（SymbolGlyph 的 fontColor、Slider 的 selectedColor）直接吃同一个色号。
const DOUYIN_ACCENT = DarkTheme.accents.douyin;

// 233vp 圆屏：菜单圆钮贴底居中，三个子按钮以它为中心呈扇形展开。
const MENU_DIAMETER = 38;
const MENU_X = (233 - MENU_DIAMETER) / 2;
const MENU_Y = 233 - 18 - MENU_DIAMETER;
const MENU_CX = MENU_X + MENU_DIAMETER / 2; // 扇形圆心 = 菜单钮中心
const MENU_CY = MENU_Y + MENU_DIAMETER / 2;
const FAN_DIAMETER = 42;
// 扇形只看两个数：半径决定子钮离菜单钮（X mark）多远，两者圆边间隙 = 半径 − 40（两个半径之和）；
// 相邻间隙决定三颗钮之间的缝，张角由这两者反推，改半径不会把按钮挤到一起。
const FAN_RADIUS = 54;
const FAN_EDGE_GAP = 8;
const FAN_HALF_ANGLE = 2 * Math.asin((FAN_DIAMETER + FAN_EDGE_GAP) / (2 * FAN_RADIUS));
const FAN_DX = FAN_RADIUS * Math.sin(FAN_HALF_ANGLE); // 侧钮相对中钮的水平位移
const FAN_DY = FAN_RADIUS * Math.cos(FAN_HALF_ANGLE); // 侧钮相对中钮的下落量
const MID_REST_X = MENU_CX - FAN_DIAMETER / 2;
const MID_REST_Y = MENU_CY - FAN_DIAMETER / 2 - FAN_RADIUS;
const LEFT_REST_X = MID_REST_X - FAN_DX;
const LEFT_REST_Y = MENU_CY - FAN_DIAMETER / 2 - FAN_DY;
const RIGHT_REST_X = MID_REST_X + FAN_DX;
const RIGHT_REST_Y = LEFT_REST_Y;
// 起始位移：三颗钮都从菜单钮中心弹出（中心 + FROM = 落位中心），改半径/张角时要跟着变。
const LEFT_FROM_X = FAN_DX;
const LEFT_FROM_Y = FAN_DY;
const MID_FROM_X = 0;
const MID_FROM_Y = FAN_RADIUS;
const RIGHT_FROM_X = -FAN_DX;
const RIGHT_FROM_Y = FAN_DY;
const FAN_START_SCALE = 0.8;
const FAN_START_BLUR = 12;

@ComponentV2
struct FanIconButton {
  @Param @Require icon: Resource;
  /** 只给读屏用；扇形上不显示文字，圆钮才能排紧。 */
  @Param @Require label: string;
  @Param @Require onTap: () => void;
  @Param @Require restX: number;
  @Param @Require restY: number;
  @Param @Require interactive: boolean;
  @Param shiftX: number = 0;
  @Param shiftY: number = 0;
  @Param itemScale: number = 1;
  @Param itemBlur: number = 0;
  @Param itemAlpha: number = 1;

  build() {
    Button({ type: ButtonType.Circle }) {
      Image(this.icon)
        .width('24fp')
        .height('24fp')
        .objectFit(ImageFit.Contain)
    }
    .width(FAN_DIAMETER)
    .height(FAN_DIAMETER)
    .backgroundColor('#40FFFFFF')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .position({ x: this.restX, y: this.restY })
    .translate({ x: this.shiftX, y: this.shiftY })
    .scale({ x: this.itemScale, y: this.itemScale, centerX: '50%', centerY: '50%' })
    .blur(this.itemBlur)
    .opacity(this.itemAlpha)
    .accessibilityText(this.label)
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      if (this.interactive) {
        this.onTap();
      }
    })
  }
}

/** 从菜单按钮冒出的三个按钮：暂停/继续、全屏、更多。 */
@ComponentV2
export struct DouYinFanMenu {
  @Param @Require expanded: boolean;
  @Param @Require playing: boolean;
  @Param @Require fullscreen: boolean;
  @Param @Require onOpen: () => void;
  @Param @Require onTogglePlay: () => void;
  @Param @Require onToggleFullscreen: () => void;
  @Param @Require onMore: () => void;
  @Param @Require onClose: () => void;

  @Local private scrimAlpha: number = 0;
  @Local private menuScale: number = 1;
  @Local private dotsAlpha: number = 1;
  @Local private dotsScale: number = 1;
  @Local private dotsBlur: number = 0;
  @Local private markAlpha: number = 0;
  @Local private markScale: number = 0.7;
  @Local private markBlur: number = 16;
  @Local private leftShiftX: number = LEFT_FROM_X;
  @Local private leftShiftY: number = LEFT_FROM_Y;
  @Local private leftScale: number = FAN_START_SCALE;
  @Local private leftBlur: number = FAN_START_BLUR;
  @Local private leftAlpha: number = 0;
  @Local private midShiftX: number = MID_FROM_X;
  @Local private midShiftY: number = MID_FROM_Y;
  @Local private midScale: number = FAN_START_SCALE;
  @Local private midBlur: number = FAN_START_BLUR;
  @Local private midAlpha: number = 0;
  @Local private rightShiftX: number = RIGHT_FROM_X;
  @Local private rightShiftY: number = RIGHT_FROM_Y;
  @Local private rightScale: number = FAN_START_SCALE;
  @Local private rightBlur: number = FAN_START_BLUR;
  @Local private rightAlpha: number = 0;
  private timers: number[] = [];

  aboutToAppear(): void {
    if (this.expanded) {
      this.snapOpen();
    } else {
      this.snapClosed();
    }
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  @Monitor('expanded')
  private onExpandedChanged(monitor: IMonitor): void {
    if (this.expanded) {
      this.playOpen();
    } else {
      this.playClose();
    }
  }

  private schedule(delay: number, action: () => void): void {
    const timer = setTimeout(action, delay);
    this.timers.push(timer);
  }

  private clearTimers(): void {
    for (const timer of this.timers) {
      clearTimeout(timer);
    }
    this.timers = [];
  }

  private snapClosed(): void {
    this.scrimAlpha = 0;
    this.menuScale = 1;
    this.dotsAlpha = 1;
    this.dotsScale = 1;
    this.dotsBlur = 0;
    this.markAlpha = 0;
    this.markScale = 0.7;
    this.markBlur = 16;
    this.leftShiftX = LEFT_FROM_X;
    this.leftShiftY = LEFT_FROM_Y;
    this.leftScale = FAN_START_SCALE;
    this.leftBlur = FAN_START_BLUR;
    this.leftAlpha = 0;
    this.midShiftX = MID_FROM_X;
    this.midShiftY = MID_FROM_Y;
    this.midScale = FAN_START_SCALE;
    this.midBlur = FAN_START_BLUR;
    this.midAlpha = 0;
    this.rightShiftX = RIGHT_FROM_X;
    this.rightShiftY = RIGHT_FROM_Y;
    this.rightScale = FAN_START_SCALE;
    this.rightBlur = FAN_START_BLUR;
    this.rightAlpha = 0;
  }

  private snapOpen(): void {
    this.scrimAlpha = 1;
    this.menuScale = 1;
    this.dotsAlpha = 0;
    this.dotsScale = 0.68;
    this.dotsBlur = 10;
    this.markAlpha = 1;
    this.markScale = 1;
    this.markBlur = 0;
    this.leftShiftX = 0;
    this.leftShiftY = 0;
    this.leftScale = 1;
    this.leftBlur = 0;
    this.leftAlpha = 1;
    this.midShiftX = 0;
    this.midShiftY = 0;
    this.midScale = 1;
    this.midBlur = 0;
    this.midAlpha = 1;
    this.rightShiftX = 0;
    this.rightShiftY = 0;
    this.rightScale = 1;
    this.rightBlur = 0;
    this.rightAlpha = 1;
  }

  private emit(index: number): void {
    if (index === 0) {
      this.getUIContext().animateTo({
        duration: 480,
        curve: curves.springMotion(0.42, 0.55)
      }, () => {
        this.leftShiftX = 0;
        this.leftShiftY = 0;
        this.leftScale = 1;
      });
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.leftBlur = 0;
        this.leftAlpha = 1;
      });
    } else if (index === 1) {
      this.getUIContext().animateTo({
        duration: 480,
        curve: curves.springMotion(0.42, 0.55)
      }, () => {
        this.midShiftX = 0;
        this.midShiftY = 0;
        this.midScale = 1;
      });
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.midBlur = 0;
        this.midAlpha = 1;
      });
    } else {
      this.getUIContext().animateTo({
        duration: 480,
        curve: curves.springMotion(0.42, 0.55)
      }, () => {
        this.rightShiftX = 0;
        this.rightShiftY = 0;
        this.rightScale = 1;
      });
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.rightBlur = 0;
        this.rightAlpha = 1;
      });
    }
  }

  private playOpen(): void {
    this.clearTimers();
    this.snapClosed();
    const ui = this.getUIContext();
    ui.animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.scrimAlpha = 1;
      this.menuScale = 0.94;
      this.dotsAlpha = 0;
      this.dotsScale = 0.68;
      this.dotsBlur = 10;
    });
    this.schedule(0, () => this.emit(0));
    this.schedule(35, () => this.emit(1));
    this.schedule(70, () => this.emit(2));
    this.schedule(100, () => {
      ui.animateTo({ duration: 260, curve: curves.springMotion(0.38, 0.62) }, () => {
        this.markAlpha = 1;
        this.markScale = 1;
        this.markBlur = 0;
      });
    });
    this.schedule(180, () => {
      ui.animateTo({ duration: 240, curve: curves.springMotion(0.4, 0.7) }, () => {
        this.menuScale = 1;
      });
    });
  }

  private playClose(): void {
    this.clearTimers();
    const ui = this.getUIContext();
    ui.animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.scrimAlpha = 0;
      this.markAlpha = 0;
      this.markScale = 0.7;
      this.markBlur = 16;
      this.leftShiftX = LEFT_FROM_X;
      this.leftShiftY = LEFT_FROM_Y;
      this.leftScale = FAN_START_SCALE;
      this.leftBlur = FAN_START_BLUR;
      this.leftAlpha = 0;
      this.midShiftX = MID_FROM_X;
      this.midShiftY = MID_FROM_Y;
      this.midScale = FAN_START_SCALE;
      this.midBlur = FAN_START_BLUR;
      this.midAlpha = 0;
      this.rightShiftX = RIGHT_FROM_X;
      this.rightShiftY = RIGHT_FROM_Y;
      this.rightScale = FAN_START_SCALE;
      this.rightBlur = FAN_START_BLUR;
      this.rightAlpha = 0;
    });
    this.schedule(80, () => {
      ui.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.dotsAlpha = 1;
        this.dotsScale = 1;
        this.dotsBlur = 0;
        this.menuScale = 1;
      });
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .opacity(this.scrimAlpha)
        .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          if (this.expanded) {
            this.onClose();
          }
        })

      FanIconButton({
        icon: this.playing ? $r('app.media.dou_player_pause_icon') : $r('app.media.dou_player_play_icon'),
        label: this.playing ? '暂停' : '继续',
        restX: LEFT_REST_X,
        restY: LEFT_REST_Y,
        interactive: this.expanded && this.leftAlpha > 0.35,
        shiftX: this.leftShiftX,
        shiftY: this.leftShiftY,
        itemScale: this.leftScale,
        itemBlur: this.leftBlur,
        itemAlpha: this.leftAlpha,
        onTap: () => {
          this.onTogglePlay();
        }
      })

      FanIconButton({
        icon: this.fullscreen ? $r('app.media.dou_player_minimize_icon') : $r('app.media.dou_player_expend_icon'),
        label: this.fullscreen ? '适应' : '全屏',
        restX: MID_REST_X,
        restY: MID_REST_Y,
        interactive: this.expanded && this.midAlpha > 0.35,
        shiftX: this.midShiftX,
        shiftY: this.midShiftY,
        itemScale: this.midScale,
        itemBlur: this.midBlur,
        itemAlpha: this.midAlpha,
        onTap: () => {
          this.onToggleFullscreen();
        }
      })

      FanIconButton({
        icon: $r('app.media.dou_player_menu_icon'),
        label: '更多',
        restX: RIGHT_REST_X,
        restY: RIGHT_REST_Y,
        interactive: this.expanded && this.rightAlpha > 0.35,
        shiftX: this.rightShiftX,
        shiftY: this.rightShiftY,
        itemScale: this.rightScale,
        itemBlur: this.rightBlur,
        itemAlpha: this.rightAlpha,
        onTap: () => {
          this.onMore();
        }
      })

      Button({ type: ButtonType.Circle }) {
        Stack() {
          Image($r('app.media.dou_player_menu_icon'))
            .width('22fp')
            .height('22fp')
            .objectFit(ImageFit.Contain)
            .scale({ x: this.dotsScale, y: this.dotsScale })
            .blur(this.dotsBlur)
            .opacity(this.dotsAlpha)

          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize('20fp')
            // 三点翻成 X 时不能变色，所以 X 也跟着用抖音强调色。
            .fontColor([DOUYIN_ACCENT])
            .scale({ x: this.markScale, y: this.markScale })
            .blur(this.markBlur)
            .opacity(this.markAlpha)
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }
      .width(MENU_DIAMETER)
      .height(MENU_DIAMETER)
      .backgroundColor('#33FFFFFF')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .position({ x: MENU_X, y: MENU_Y })
      .scale({ x: this.menuScale, y: this.menuScale })
      .onClick(() => {
        if (this.expanded) {
          this.onClose();
        } else {
          this.onOpen();
        }
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

// 完整菜单网格：一行 3 个圆钮，两行放不进 233vp 圆屏，超出部分交给 Scroll 滚动。
const FULL_CELL_DIAMETER = 46;
const FULL_CELL_WIDTH = 58;
const FULL_GRID_HEIGHT = 124;
// 让开底部菜单钮：18（贴底）+ 38（钮径）+ 6（缝）。可见带 y≈47..171，两行都在圆屏弦内。
const FULL_GRID_BOTTOM_MARGIN = 62;

/** 完整菜单的图标按钮：材质圆钮 + 文案 + 可选数值，结构对齐哔哩哔哩播放菜单的 IconButton。 */
@ComponentV2
struct FullMenuIconButton {
  @Param @Require icon0: Resource;
  @Param icon1: Resource | null = null;
  @Param showVersion1: boolean = false;
  @Param @Require text0: string;
  @Param text1: string = '';
  @Param value: string = '';
  @Param @Require onTap: () => void;

  build() {
    Column({ space: '5vp' }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Stack() {
          Image(this.icon0)
            .width('22fp')
            .height('22fp')
            .objectFit(ImageFit.Contain)
            .opacity(this.showVersion1 ? 0 : 1)
          if (this.icon1 !== null) {
            Image(this.icon1)
              .width('22fp')
              .height('22fp')
              .objectFit(ImageFit.Contain)
              .opacity(this.showVersion1 ? 1 : 0)
          }
        }
        .width('100%')
        .height('100%')
      }
      .width(FULL_CELL_DIAMETER)
      .height(FULL_CELL_DIAMETER)
      .backgroundColor('#40FFFFFF')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      // 按钮不参与焦点引擎：内页表冠面板是整页唯一消费者，点「循环模式」这类不切层的按钮
      // 不会触发表冠重新聚焦，抢到焦点后音量表冠就哑了。
      .focusable(false)
      .focusOnTouch(false)
      .tabIndex(-1)
      .onClick(() => {
        this.onTap();
      })

      Text(this.showVersion1 && this.text1 !== '' ? this.text1 : this.text0)
        .fontSize('11fp')
        .fontColor(Color.White)
        .maxLines(1)

      // 没有数值的格子也占位，保证三列文案对齐。
      Text(this.value)
        .fontSize('9fp')
        .fontColor('#B2B6C3')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .visibility(this.value === '' ? Visibility.Hidden : Visibility.Visible)
    }
    .width(FULL_CELL_WIDTH)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 完整菜单：Scroll 里每行 3 个图标按钮，整层 BACKGROUND_THIN 毛玻璃，
 * 底部那颗圆形菜单钮负责关闭（回到扇形层）。
 */
@ComponentV2
export struct DouYinFullMenu {
  @Param @Require fullscreen: boolean;
  @Param @Require loopMode: DouYinLoopMode;
  @Param @Require volumePercent: number;
  @Param @Require positionText: string;
  @Param @Require onVolume: () => void;
  @Param @Require onSeek: () => void;
  @Param @Require onInfo: () => void;
  @Param @Require onToggleLoop: () => void;
  @Param @Require onToggleFullscreen: () => void;
  @Param @Require onExitPlayback: () => void;
  @Param @Require onClose: () => void;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 整层毛玻璃；点网格外的空白也按关闭处理（Scroll 带内的空白由滚动条区域吃掉）。
      Column()
        .width('100%')
        .height('100%')
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onClick(() => {
          this.onClose();
        })

      Scroll() {
        Column({ space: '12vp' }) {
          Row({ space: '6vp' }) {
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_progress_icon'),
              text0: '调进度',
              value: this.positionText,
              onTap: () => {
                this.onSeek();
              }
            })
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_expend_icon'),
              icon1: $r('app.media.dou_player_minimize_icon'),
              showVersion1: this.fullscreen,
              text0: '全屏',
              text1: '缩小',
              onTap: () => {
                this.onToggleFullscreen();
              }
            })
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_volume_icon'),
              text0: '调音量',
              value: Math.round(this.volumePercent) + '%',
              onTap: () => {
                this.onVolume();
              }
            })
          }

          Row({ space: '6vp' }) {
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_info_icon'),
              text0: '视频信息',
              onTap: () => {
                this.onInfo();
              }
            })
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_loop_icon'),
              text0: '循环模式',
              value: this.loopMode === DouYinLoopMode.Single ? '单集循环' : '自动联播',
              onTap: () => {
                this.onToggleLoop();
              }
            })
            FullMenuIconButton({
              icon0: $r('app.media.dou_player_exit_icon'),
              text0: '退出播放',
              onTap: () => {
                this.onExitPlayback();
              }
            })
          }
        }
        .width('100%')
        .padding({ top: '10vp', bottom: '10vp' })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(FULL_GRID_HEIGHT)
      .margin({ bottom: FULL_GRID_BOTTOM_MARGIN })
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 滚动靠手指拖动，不吃表冠：表冠留给音量，且 Scroll 获焦会把整个内页的焦点抢走。
      .focusable(false)
      .focusOnTouch(false)
      .tabIndex(-1)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Image($r('app.media.dou_player_menu_icon'))
          .width('22fp')
          .height('22fp')
          .objectFit(ImageFit.Contain)
      }
      .width(MENU_DIAMETER)
      .height(MENU_DIAMETER)
      .backgroundColor('#33FFFFFF')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .margin({ bottom: 18 })
      .focusable(false)
      .focusOnTouch(false)
      .tabIndex(-1)
      .onClick(() => {
        this.onClose();
      })
    }
    .width('100%')
    .height('100%')
  }
}

/** 音量层：滑杆只是触摸兜底，表冠仍然由内页面板接管。 */
@ComponentV2
export struct DouYinVolumePanel {
  @Param @Require level: number;
  @Param @Require maximum: number;
  @Param @Require onLevel: (value: number) => void;
  @Param @Require onClose: () => void;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.onClose();
        })

      Column({ space: '10vp' }) {
        Text('音量 ' + Math.round(this.level / Math.max(1, this.maximum) * 100) + '%')
          .fontSize('13fp')
          .fontColor(Color.White)
        Slider({
          min: 0,
          max: this.maximum,
          value: this.level,
          style: SliderStyle.OutSet,
          direction: Axis.Horizontal
        })
          .width(PANEL_WIDTH)
          .selectedColor(DOUYIN_ACCENT)
          .onChange((value: number) => {
            this.onLevel(value);
          })
        Text('旋转表冠也可以调节')
          .fontSize('10fp')
          .fontColor('#B2B6C3')
      }
      .width(PANEL_WIDTH)
      .padding('14vp')
      .backgroundColor(PANEL_BG)
      .borderRadius('12vp')
    }
    .width('100%')
    .height('100%')
  }
}

/** 进度层：打开时把焦点交给 Slider，表冠原生拖动；关闭后由外层收回焦点。 */
@ComponentV2
export struct DouYinSeekPanel {
  @Param @Require positionMs: number;
  @Param @Require durationMs: number;
  @Param @Require focusId: string;
  @Param @Require onSeek: (ms: number) => void;
  @Param @Require onClose: () => void;

  @Local private dragging: boolean = false;
  @Local private previewMs: number = 0;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.onClose();
        })

      Column({ space: '8vp' }) {
        Text(this.timeText(this.dragging ? this.previewMs : this.positionMs) + ' / ' + this.timeText(this.durationMs))
          .fontSize('12fp')
          .fontColor(Color.White)
        Slider({
          min: 0,
          max: this.durationMs > 0 ? this.durationMs : 1,
          value: this.dragging ? this.previewMs : this.positionMs,
          style: SliderStyle.OutSet,
          direction: Axis.Horizontal
        })
          .width(PANEL_WIDTH)
          .id(this.focusId)
          .focusable(true)
          .defaultFocus(true)
          .focusOnTouch(true)
          .enableHapticFeedback(true)
          .digitalCrownSensitivity(CrownSensitivity.LOW)
          .selectedColor(DOUYIN_ACCENT)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.previewMs = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.dragging = false;
              this.onSeek(value);
            } else {
              this.dragging = true;
            }
          })
          .onAppear(() => {
            try {
              this.getUIContext().getFocusController().requestFocus(this.focusId);
            } catch (error) {
              console.debug('seek focus failed: ' + error.message);
            }
          })
      }
      .width(PANEL_WIDTH)
      .padding('14vp')
      .backgroundColor(PANEL_BG)
      .borderRadius('12vp')
    }
    .width('100%')
    .height('100%')
  }

  private timeText(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }
}

// 简介正文的高度上限：卡片宽 PANEL_WIDTH，圆屏上 170 宽对应的半弦高约 79.7，
// 整张卡片最高 ~159；留出上下 14vp 内边距后正文取 120。
const INFO_BODY_HEIGHT = 120;

/** 视频信息层：只放简介，点屏幕上任意位置都关闭。 */
@ComponentV2
export struct DouYinInfoPanel {
  @Param @Require description: string;
  @Param @Require onClose: () => void;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      Column() {
        Scroll() {
          Text(this.description === '' ? '这条没有简介' : this.description)
            .fontSize('12fp')
            .fontColor('#D0D4DC')
            .lineHeight('17vp')
            .width('100%')
        }
        .height(INFO_BODY_HEIGHT)
        .width('100%')
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        // 只给手指拖动留滚动，不吃焦点：焦点被 Scroll 抢走的话内页的音量表冠就哑了。
        .focusable(false)
        .focusOnTouch(false)
        .tabIndex(-1)
      }
      .width(PANEL_WIDTH)
      .padding('14vp')
      .backgroundColor(PANEL_BG)
      .borderRadius('12vp')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    // 关闭挂在最外层：正文、卡片、遮罩都是它的后代，点击会冒泡上来，所以点哪儿都关。
    // Scroll 只在真的拖动时消费手势，单击仍会走到这里。
    .onClick(() => {
      this.onClose();
    })
  }
}

