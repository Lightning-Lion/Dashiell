// RSS 首页条目点进去时的转场画面：卡片扩展成全屏（上图标、下文字）→ 整体淡出，
// 已经落位在下面的目标页浮出来，形成交叉渐变；整个过程不经过纯黑。
//
// 这个组件必须挂在 NavigationStack 里、Navigation 的兄弟层：
// NavDestination 是 Navigation 子树的一部分，只有后绘制的兄弟节点才能盖住它。
//
// 动画由「隐式动画」驱动：会动的数值全部是本组件的 @Local，配 .animation(...)。
// 不用 animateTo：本机（HarmonyOS 6.1 手表）上 animateTo 改这些属性是直接跳变、不插值。
// 时序由 common/RSSHeroTransition.ets 通过 HeroStage 接口驱动；时长常量也在那边（单一来源）。
// 设计说明：目标页不跑系统动画、直接落位，hero 淡出时就是交叉渐变。

import { curves } from '@kit.ArkUI'
import { AnimatedProgressView } from './AnimatedProgressView'
import { DarkTheme } from '../common/Theme'
import {
  HERO_CROSSFADE_MS,
  HERO_EXPAND_MS,
  HeroGeometry,
  RSSHeroTransition,
} from '../common/RSSHeroTransition'

@ComponentV2
export struct RSSHeroTransitionOverlay {
  @Param @Require hero: RSSHeroTransition

  // hero 表面矩形（窗口坐标）
  @Local private surfaceX: number = 0
  @Local private surfaceY: number = 0
  @Local private surfaceWidth: number = 0
  @Local private surfaceHeight: number = 0
  @Local private surfaceRadius: number = 0

  // 图标、文字相对 hero 表面左上角的位置
  @Local private iconSize: number = 0
  @Local private iconX: number = 0
  @Local private iconY: number = 0
  @Local private textX: number = 0
  @Local private textY: number = 0
  @Local private textWidth: number = 0
  @Local private textSize: number = 0

  @Local private contentOpacity: number = 1
  @Local private surfaceOpacity: number = 1

  aboutToAppear(): void {
    // Overlay 常驻，登记一次即可；点条目时 stage 一定已经就位
    this.hero.attachStage(this)
  }

  build() {
    if (this.hero.active) {
      Stack({ alignContent: Alignment.TopStart }) {
        // hero 表面：起始时与卡片完全重合，结束时是整块屏幕
        Stack({ alignContent: Alignment.TopStart }) {
          // 图文：只在 snap 时整体置 0/1；交叉渐变交给外层 surfaceOpacity，不单独做动画
          Stack({ alignContent: Alignment.TopStart }) {
            Image($r('app.media.rss_icon'))
              .syncLoad(true)
              .objectFit(ImageFit.Auto)
              .width(this.iconSize)
              .height(this.iconSize)
              .position({ x: this.iconX, y: this.iconY })
              // 展开：归一化到固定时长的弹簧，阻尼比 ~0.7，末尾轻微过冲
              .animation({ duration: HERO_EXPAND_MS, curve: curves.springCurve(0, 1, 200, 20) })

            Text(this.hero.title)
              .fontSize(this.textSize)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Start)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(this.textWidth)
              .position({ x: this.textX, y: this.textY })
              .animation({ duration: HERO_EXPAND_MS, curve: curves.springCurve(0, 1, 200, 20) })
          }
          .width('100%')
          .height('100%')
          .opacity(this.contentOpacity)
        }
        .width(this.surfaceWidth)
        .height(this.surfaceHeight)
        .position({ x: this.surfaceX, y: this.surfaceY })
        .borderRadius(this.surfaceRadius)
        .clip(true)
        .linearGradient({ colors: DarkTheme.heroSurface })
        .animation({ duration: HERO_EXPAND_MS, curve: curves.springCurve(0, 1, 200, 20) })
        .opacity(this.surfaceOpacity)
        // 交叉渐变：整块 hero（渐变 + 图标 + 文字）一起淡出，露出已经落位的目标页。
        // EaseOut 前段掉得快，目标页会更早「浮」出来；尾段收得柔，不会像硬切。
        .animation({ duration: HERO_CROSSFADE_MS, curve: Curve.EaseOut })

        // 推页慢于 hero 时给一点反馈，避免看起来像卡死
        if (this.hero.waiting) {
          Column() {
            AnimatedProgressView({ color: DarkTheme.accents.brand })
              .width(44)
              .height(44)
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
        }
      }
      .width('100%')
      .height('100%')
      // 转场期间吞掉所有点击，避免连点条目
      .hitTestBehavior(HitTestMode.Block)
      // hero 真正上屏后才让时序继续展开；否则节点还没首帧，动画会整个丢掉
      .onAppear(() => {
        this.hero.notifyStageReady()
      })
    }
  }

  // ---- 以下由 HeroStage 调用：只改本组件的 @Local，插值交给 .animation() ----

  private applyGeometry(geometry: HeroGeometry): void {
    this.surfaceX = geometry.x
    this.surfaceY = geometry.y
    this.surfaceWidth = geometry.width
    this.surfaceHeight = geometry.height
    this.surfaceRadius = geometry.radius
    this.iconSize = geometry.iconSize
    this.iconX = geometry.iconX
    this.iconY = geometry.iconY
    this.textX = geometry.textX
    this.textY = geometry.textY
    this.textWidth = geometry.textWidth
    this.textSize = geometry.fontSize
  }

  /** 无动画：首帧直接贴到卡片上，并复位透明度 */
  snap(geometry: HeroGeometry, contentVisible: boolean): void {
    this.applyGeometry(geometry)
    this.contentOpacity = contentVisible ? 1 : 0
    this.surfaceOpacity = 1
  }

  expandTo(target: HeroGeometry): void {
    this.applyGeometry(target)
  }

  fadeSurface(target: number): void {
    this.surfaceOpacity = target
  }
}
