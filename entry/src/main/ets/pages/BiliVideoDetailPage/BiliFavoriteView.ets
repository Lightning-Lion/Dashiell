import { BilibiliService } from "../../common/BiliService"
import { AddToFavoritePagePushData } from "./AddToFavoritePage"
import { logTag } from "../../common/printLog"

export interface BiliHasFavoriteApiResponse {
  code: number;
  message: string;
  ttl: number;
  data: BiliHasFavoriteApiResponseData;
}

interface BiliHasFavoriteApiResponseData {
  favoured: boolean;
}

@ObservedV2
export class BiliFavoriteViewModel {
  @Trace
  isFavorite: boolean = false
  @Trace
  biliService: BilibiliService

  constructor(biliService: BilibiliService) {
    this.biliService = biliService
  }

  updateHasFavorite(avid: number, bvid: string) {
    (async () => {
      try {
        const result = await this.biliService.hasFavorite(avid, bvid)
        if (result.code !== 0 || !result.data) {
          return;
        }
        const data = result.data
        switch (data.favoured) {
          case true:
            console.debug(logTag, "已收藏")
            this.isFavorite = true
            break
          case false:
            console.debug(logTag, "未收藏")
            this.isFavorite = false
            break
          default:
            console.debug(logTag, "不应该啊1")
            break
        }
      } catch (error) {
        console.debug(logTag, "获取是否已收藏状态出错")
      }
    })()
  }
}

@ComponentV2
export struct BiliFavoriteView {
  @Param @Require bvid: string
  @Param @Require avid: number
  // 这个视频得到的总收藏量
  @Param @Require favoriteCount: number
  @Param @Require pageInfos: NavPathStack | null
  @Param @Require vm: BiliFavoriteViewModel

  build() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column() {
          Image($r(this.vm.isFavorite ? "app.media.bili_video_detail_page_has_favorite" :
            "app.media.bili_video_detail_page_favorite_count"))
            .objectFit(ImageFit.Cover)
            .width("18fp")
            .height("18fp")
          Text(this.formatNumber(this.favoriteCount))
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.pushAddtoFavoritePage()
      })
    }
    .layoutWeight(1)
    .onAppear(() => {
      // 先更新一下现态
      this.vm.updateHasFavorite(this.avid, this.bvid)
    })
  }

  pushAddtoFavoritePage() {
    if (this.pageInfos !== null) {
      const data: AddToFavoritePagePushData = {
        bvid: this.bvid,
        avid: this.avid,
        biliService: this.vm.biliService,
        onResult: () => {
          // 更新一下现态
          this.vm.updateHasFavorite(this.avid, this.bvid)
        }
      }
      this.pageInfos.pushPathByName("AddToFavoritePage", data)
    } else {
      this.getUIContext().getPromptAction().showToast({ message: "404-17" })
    }
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