import { BilibiliService } from "../../common/BiliService"
import { BiliInsertCoinPagePushData } from "./BiliInsertCoinPage";

export interface BiliHasCoinBeenInsertedApiResponse {
  code: number;
  message: string;
  ttl: number;
  data: BiliHasCoinBeenInsertedApiResponseData;
}

interface BiliHasCoinBeenInsertedApiResponseData {
  multiply: number;
}

@ObservedV2
export class BiliCoinViewModel {
  @Trace
  biliService: BilibiliService

  constructor(biliService: BilibiliService) {
    this.biliService = biliService
  }

  // 当前已投的硬币数
  @Trace
  multiply: number = 0

  @Computed
  get hasCoinInserted(): boolean {
    console.debug("🚩当前硬币数" + this.multiply)
    switch (this.multiply) {
      case 0:
        return false
        break
      case 1:
        return true
        break
      case 2:
        return true
        break
      default:
        return false
        console.debug("🚩不应该啊2")
        break
    }
  }

  @Trace
  sending: boolean = false

  updateHasCoinInserted(bvid: string) {
    (async () => {
      try {
        const result = await this.biliService.hasCoinInserted(bvid)
        const data = result.data
        this.multiply = data.multiply
        console.debug("🚩已投币数量" + this.multiply)
      } catch (error) {
        console.debug("🚩获取投币状态出错")
      }
    })()
  }

  onHasCoinInserted(depositedCoins: number) {
    console.debug("🚩投出了" + depositedCoins + "枚硬币")
    this.multiply += depositedCoins
    console.debug("🚩当前硬币数" + this.multiply)
  }
}

@ComponentV2
export struct BiliCoinView {
  @Param @Require bvid: string
  // 这个视频得到的总硬币量
  @Param @Require coinCount: number
  @Param @Require pageInfos: NavPathStack | null
  // 让外界持有，确保点赞状态稳定，而不是刷新就重复请求
  @Param @Require vm: BiliCoinViewModel

  aboutToAppear(): void {
    // 先更新一下现态
    this.vm.updateHasCoinInserted(this.bvid)
  }

  build() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column() {
          Image($r(this.vm.hasCoinInserted ? "app.media.bili_video_detail_page_coin_deposited" :
            "app.media.bili_video_detail_page_coin_count"))
            .objectFit(ImageFit.Cover)
            .width("18fp")
            .height("18fp")
          Text(this.formatNumber(this.coinCount))
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const pushInsertCoinPage = () => {
          if (this.pageInfos !== null) {
            const data: BiliInsertCoinPagePushData = {
              bvid: this.bvid,
              startingCoins: this.vm.multiply,
              biliService: this.vm.biliService,
              onHasCoinInserted: (depositedCoins: number): void => {
                this.vm.onHasCoinInserted(depositedCoins)
              }
            }
            this.pageInfos.pushPathByName("BiliInsertCoinPage", data)
          } else {
            this.getUIContext().getPromptAction().showToast({ message: "404-17" })
          }
        }
        switch (this.vm.multiply) {
          case 0:
            // 可以投2硬币
            pushInsertCoinPage()
            break
          case 1:
            // 可以投1硬币
            pushInsertCoinPage()
            break
          case 2:
            // 满了，不能再投了
            this.getUIContext().getPromptAction().showToast({ message: "超过投币上限啦~" })
            break
          default:
            this.getUIContext().getPromptAction().showToast({ message: "404-21" })
            break
        }
      })
    }
    .layoutWeight(1)
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