import { BilibiliService } from "../../common/BiliService"
import { logTag } from "../../common/printLog";

export interface BiliHasLikeApiResponse {
  code: number;
  message: string;
  ttl: number;
  data: number;
}

export interface BiliLikeApiResponse {
  code: number;
  message: string;
  ttl: number;
}

export interface BiliDislikeApiResponse {
  code: number;
  message: string;
  ttl: number;
}

@ObservedV2
export class BiliLikeViewModel {
  @Trace
  biliService: BilibiliService
  component: CustomComponent

  constructor(biliService: BilibiliService, component: CustomComponent) {
    this.biliService = biliService
    this.component = component
  }

  @Trace
  liked: boolean = false
  @Trace
  sending: boolean = false

  updateHasLike(bvid: string) {
    (async () => {
      try {
        const result = await this.biliService.hasLike(bvid)
        const data = result.data
        switch (data) {
          case 0:
            console.debug(logTag, "未点赞")
            this.liked = false
            break
          case 1:
            console.debug(logTag, "已点赞")
            this.liked = true
            break
          default:
            console.debug(logTag, "不应该啊1")
            break
        }
      } catch (error) {
        console.debug(logTag, "获取点赞状态出错")
      }
    })()
  }

  like(bvid: string) {
    (async () => {
      this.sending = true
      try {
        const result = await this.biliService.like(bvid)
        console.debug("🚩点赞结果", JSON.stringify(result, null, 2))
        // {
        //   "code": 0,
        // "message": "0",
        // "ttl": 1
        // }
        // 或
        // {
        //   "code": 65006,
        // "message": "已赞过",
        // "ttl": 1
        // }
        if ((result.code === 0) || (result.code === 65006)) {
          this.liked = true
        } else {
          this.component.getUIContext().getPromptAction().showToast({ message: result.message })
        }
      } catch (error) {
        console.debug("🚩点赞出错")
      }
      this.sending = false
    })()
  }

  dislike(bvid: string) {
    (async () => {
      this.sending = true
      try {
        const result = await this.biliService.disLike(bvid)
        console.debug("🚩取消赞结果", JSON.stringify(result, null, 2))
        // {
        //   "code": 0,
        // "message": "0",
        // "ttl": 1
        // }
        // 或
        // {
        //   "code": 65004,
        // "message": "取消赞失败 未点赞过",
        // "ttl": 1
        // }
        if ((result.code === 0) || (result.code === 65004)) {
          this.liked = false
        } else {
          this.component.getUIContext().getPromptAction().showToast({ message: result.message })
        }
      } catch (error) {
        console.debug("🚩取消点赞出错")
      }
      this.sending = false
    })()
  }
}

@ComponentV2
export struct BiliLikeView {
  @Param @Require bvid: string
  // 这个视频得到的总点赞量
  @Param @Require likeCount: number
  // 让外界持有，确保点赞状态稳定，而不是刷新就重复请求
  @Param @Require vm: BiliLikeViewModel

  build() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column() {
          Column() {
            if (this.vm.sending === true) {
              // 在Button的外部统一设置了尺寸
              LoadingProgress()
                .color($r("app.color.bili_color"))
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            } else {
              // 这个icon的切换过程发生在loading时，用户看不到，不需要动画
              Image($r(this.vm.liked ? "app.media.bili_video_detail_page_liked_button" :
                "app.media.bili_video_detail_page_like_count"))
                .objectFit(ImageFit.Cover)
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            }
          }
          .backgroundColor(Color.Transparent)
          .width("18fp")
          .height("18fp")

          Text(this.formatNumber(this.likeCount))
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .onClick(() => {
        // 如果有任何正在进行中的操作，等它结束
        if (this.vm.sending === true) {
          return
        }
        if (this.vm.liked === false) {
          this.vm.like(this.bvid)
        } else {
          this.vm.dislike(this.bvid)
        }
      })
      .backgroundColor(Color.Transparent)
    }
    .layoutWeight(1)
    .onAppear(() => {
      // 先更新一下现态
      this.vm.updateHasLike(this.bvid)
    })
  }

  // 格式化数字
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