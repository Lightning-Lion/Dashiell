import { curves } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';

/**
 * 音量胶囊条：哔哩哔哩播放页与抖音内页共用。
 * progress 取 0..100，宽度按比例填充；右侧圆角 + 外层裁切，避免低进度时圆角退化。
 *
 * 进场是 blur-in：同一条 spring 曲线同时驱动 blur + opacity + scale。
 * blur 必须用 foregroundFilter + uiEffect.createFilter().blur(px)，不能用 .blur()：
 * 后者在手表上走 filter_ / 主画布快照，会把背后的视频一起糊掉，还会被节点 frame 裁成方块。
 * 外层 BLUR_PAD 是留给模糊半径溢出的绘制余量；滤镜层本身不缩放，缩放只作用在内容层上。
 */

/** 滤镜离屏按节点 bounds 裁切，四周留够半径溢出空间，否则高模糊时边缘会被切成直角。 */
const BLUR_PAD: number = 20;
/** 进场时长。springCurve 已按归一化时间喂值（实测 interpolate(t) 与时长无关），
 *  主要变化落在前 ~45%，所以 420ms 的实际观感约 190ms，尾巴是弹簧收尾。 */
const ENTER_MS: number = 420;
/** 阻尼比 ≈ 0.83：轻微过冲，收尾不拖泥带水。 */
const ENTER_CURVE: curves.ICurve = curves.springCurve(0, 1, 210, 24);
/** 起始模糊半径（vp）。uiEffect 的半径是 px，观感约为同值 .blur 的两倍，故再乘 0.5。 */
const BLUR_FROM_VP: number = 10;
const FILTER_RADIUS_SCALE: number = 0.5;
/** 起始缩放与透明度：条子从偏小、偏淡、发虚的状态落到清晰。 */
const SCALE_FROM: number = 0.86;
const OPACITY_FROM: number = 0.2;
/** 驱动帧间隔。foregroundFilter 参数不是可动画属性，只能自己按帧喂值。 */
const FRAME_MS: number = 16;

@ComponentV2
export struct CapsuleVolumeBar {
  @Param @Require progress: number;
  @Param text: string = '音量';
  @Param icon: Resource | null = null;
  @Param barWidth: number = 61;
  @Param barHeight: number = 10;
  /** 进场时长，默认 420ms；探针页会放大它来逐帧观察。 */
  @Param enterMs: number = ENTER_MS;

  /** 进场进度：0 = 最糊 + 最小 + 最淡，1 = 原样。spring 过冲时会略大于 1。 */
  @Local private enter: number = 0;
  private enterTimer: number = -1;
  private enterStart: number = 0;

  aboutToAppear(): void {
    this.enter = 0;
    this.enterStart = Date.now();
    this.enterTimer = setInterval(() => {
      this.tickEnter();
    }, FRAME_MS);
  }

  aboutToDisappear(): void {
    this.stopEnter();
  }

  build() {
    // 外层只负责给模糊留绘制余量并挂前景滤镜；命中一律 None，HUD 不抢视频的手势。
    Column() {
      Column() {
        Row({ space: '5vp' }) {
          Row({ space: '0vp' }) {
            if (this.icon !== null) {
              Image(this.icon)
                .width('19fp')
                .height('19fp')
            }
            Text(this.text)
          }
          Stack() {
            Column() {
            }
            .backgroundColor('#B2B6C3')
            .borderRadius(this.barHeight / 2 + 'vp')
            .width(this.barWidth + 'vp')
            .height(this.barHeight + 'vp')

            Row() {
              Column() {
              }
              .backgroundColor('#F7F8FA')
              .borderRadius({
                topRight: this.barHeight / 2 + 'vp',
                bottomRight: this.barHeight / 2 + 'vp'
              })
              .width(this.barWidth * (this.clampProgress() / 100) + 'vp')
              .height(this.barHeight + 'vp')
              Blank()
            }
            .clip(true)
            .borderRadius(this.barHeight / 2 + 'vp')
            .width(this.barWidth + 'vp')
          }
          .width(this.barWidth + 'vp')
          .height(this.barHeight + 'vp')
        }
      }
      .padding('10vp')
      .borderRadius('10vp')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .scale({ x: this.enterScale(), y: this.enterScale() })
      .opacity(this.enterOpacity())
    }
    .padding(BLUR_PAD)
    .foregroundFilter(this.enterFilter())
    .hitTestBehavior(HitTestMode.None)
  }

  private tickEnter(): void {
    const t: number = (Date.now() - this.enterStart) / this.enterMs;
    if (t >= 1) {
      this.enter = 1;
      this.stopEnter();
      return;
    }
    this.enter = ENTER_CURVE.interpolate(t);
  }

  private stopEnter(): void {
    if (this.enterTimer >= 0) {
      clearInterval(this.enterTimer);
      this.enterTimer = -1;
    }
  }

  /** 模糊按 0..1 收，过冲不回糊；缩放/透明度保留过冲，收尾才有弹簧感。 */
  private enterFilter(): uiEffect.Filter {
    const p: number = this.enter < 0 ? 0 : (this.enter > 1 ? 1 : this.enter);
    return uiEffect.createFilter().blur(vp2px(BLUR_FROM_VP * (1 - p) * FILTER_RADIUS_SCALE));
  }

  private enterScale(): number {
    return SCALE_FROM + (1 - SCALE_FROM) * this.enter;
  }

  private enterOpacity(): number {
    const o: number = OPACITY_FROM + (1 - OPACITY_FROM) * this.enter;
    return o > 1 ? 1 : o;
  }

  private clampProgress(): number {
    if (this.progress <= 0) { return 0; }
    if (this.progress >= 100) { return 100; }
    return this.progress;
  }
}
