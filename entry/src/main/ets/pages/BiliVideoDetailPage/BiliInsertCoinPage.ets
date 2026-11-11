import { BilibiliService } from '../../common/BiliService'
import { watchSizeFp } from '../../common/ScreenSize'

export interface BiliInsertCoinApiResponse {
  code: number,
  message: string,
  ttl: number,
  data: BiliInsertCoinApiResponseData
}

interface BiliInsertCoinApiResponseData {
  like: boolean
}

export interface BiliInsertCoinPagePushData {
  bvid: string
  startingCoins: number
  biliService: BilibiliService
  onHasCoinInserted: (depositedCoins: number) => void
}

@Builder
export function BiliInsertCoinPageBuilder(_name: string, param: BiliInsertCoinPagePushData) {
  BiliInsertCoinPage({
    bvid: (param as BiliInsertCoinPagePushData).bvid,
    startingCoins: (param as BiliInsertCoinPagePushData).startingCoins,
    biliService: (param as BiliInsertCoinPagePushData).biliService,
    onHasCoinInserted: (param as BiliInsertCoinPagePushData).onHasCoinInserted,
  })
}


@ObservedV2
class BiliInsertCoinViewModel {
  backgroundColor = "#22232B"
  @Trace
  biliService: BilibiliService
  onHasCoinInserted: (depositedCoins: number) => void
  @Trace
  pageInfos: NavPathStack | null = null
  private component: CustomComponent

  constructor(onHasCoinInserted: (depositedCoins: number) => void, biliService: BilibiliService,
    component: CustomComponent) {
    this.onHasCoinInserted = (depositedCoins: number) => {
      onHasCoinInserted(depositedCoins)
    }
    this.biliService = biliService
    this.component = component
  }

  @Trace
  sending: boolean = false

  insertCoin(bvid: string, multiply: number) {
    (async () => {
      this.sending = true
      try {
        const result = await this.biliService.insertCoin(bvid, multiply)
        console.debug("🚩投币结果", JSON.stringify(result, null, 2))
        //   {
        //   "code": 0,
        //   "message": "0",
        //   "ttl": 1,
        //   "data": {
        //     "like": true
        //   }
        // }
        // 或
        // {"code":0,"message":"0","ttl":1,"data":{"like":false}}
        // 或
        // {"code":34005,"message":"超过投币上限啦~","ttl":1,"data":{"like":false}}
        if (result.code === 0) {
          // 投了几个币，减去几个币
          this.onHasCoinInserted(multiply)
        } else if (result.code === 34005) {
          // 没投币成功，不减
          this.onHasCoinInserted(0)
        } else {
          // 硬币不足、不能给自己投币
          this.component.getUIContext().getPromptAction().showToast({ message: result.message })
        }
        // 不管怎么样，总是要dismiss的
        if (this.pageInfos === null) {
          this.component.getUIContext().getPromptAction().showToast({ message: "404-20" })
          return
        }
        this.pageInfos.removeByName("BiliInsertCoinPage")
      } catch (error) {
        console.debug("🚩点赞出错")
      }
      this.sending = false
    })()
  }

}

@Entry
@ComponentV2
struct BiliInsertCoinPage {
  @Param @Require bvid: string;
  // 我已经给这个视频投了的硬币数量
  @Param @Require startingCoins: number;
  @Param @Require biliService: BilibiliService
  @Param @Require onHasCoinInserted: (depositedCoins: number) => void
  @Local private vm: BiliInsertCoinViewModel =
    new BiliInsertCoinViewModel(this.onHasCoinInserted, this.biliService, this)

  build() {
    NavDestination() {
      Column() {
        Stack() {
          Column() {
            if (this.startingCoins === 0) {
              this.coinCountSelectionView(true)
            } else if (this.startingCoins === 1) {
              this.coinCountSelectionView(false)
            } else if (this.startingCoins === 2) {
              // 已经投满了，就不应该显示我这个页面
              Text("404-18")
            } else {
              // 未适配的硬币数
              Text("404-19")
            }
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .height('100%')
          .width('100%')

          if (this.vm.sending) {
            Column() {
            }
            .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
            .height('100%')
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
        }
      }
      .height('100%')
      .width('100%')
      .backgroundColor(this.vm.backgroundColor)
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.vm.pageInfos = context.pathStack
    })
  }

  @Builder
  coinCountSelectionView(showTwoCoin: boolean) {
    Column() {
    }.height("28fp")

    Text(showTwoCoin ? "给UP主投上1枚或者2枚硬币" : "给UP主投上 1 枚硬币")
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Image($r("app.media.bili_video_detail_insert_coin_page_one_coin"))
          .objectFit(ImageFit.Cover)
          .width(watchSizeFp * 0.4)
      }
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        console.debug("🚩投1枚硬币")
        this.vm.insertCoin(this.bvid, 1)
      })

      if (showTwoCoin) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Image($r("app.media.bili_video_detail_insert_coin_page_two_coin"))
            .objectFit(ImageFit.Cover)
            .width(watchSizeFp * 0.4)
        }
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          console.debug("🚩投2枚硬币")
          this.vm.insertCoin(this.bvid, 2)
        })
      }
    }
  }
}