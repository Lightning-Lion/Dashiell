import {
  ArcList,
  ArcListItem,
  ComponentContent,
  LengthMetrics,
  ArcListAttribute,
  ArcListItemAttribute
} from '@kit.ArkUI';
import { requestFocusWithRetry } from '../../common/WatchListFocus';

@Builder
export function BiliSearchFilterBuilder() {
  BiliSearchFilter()
}

export namespace BiliSearchFilterStorage {
  export type Order = "totalrank"
    | "click"
    | "pubdate"
    | "dm"
    | "stow"
    | "scores"
  export
  const defaultOrder:Order = "totalrank"
}

export class BiliSearchResult {
  private orderType: BiliSearchFilterStorage.Order = "totalrank"

  constructor(orderType: BiliSearchFilterStorage.Order) {
    this.orderType = orderType
  }

  getOrderType() {
    return this.orderType
  }
}

export class BiliSearchParam {
  orderType: BiliSearchFilterStorage.Order = "totalrank"

  constructor(orderType: BiliSearchFilterStorage.Order) {
    this.orderType = orderType
  }
}

@Builder
function headerContentBuilder() {
  Text("排序方式")
}

@Entry
@ComponentV2
struct BiliSearchFilter {
  @Local private pathInfos: NavPathStack | undefined = undefined
  @Local param: BiliSearchParam | undefined = undefined
  @Local scroller: Scroller = new Scroller()
  private readonly biliSearchFilterListId: string = "biliSearchFilterListIdListId"

  private onBtnClick(orderType: BiliSearchFilterStorage.Order) {
    if (this.param) {
      this.param.orderType = orderType
    }
    this.pathInfos?.pop(new BiliSearchResult(orderType))
  }

  private focusBiliSearchFilterList() {
    try {
      requestFocusWithRetry(this.getUIContext(), this.biliSearchFilterListId)
      console.debug("🐔 成功focus BiliSearchFilter")
    } catch (e) {
      const err = e as Error
      console.debug("🐔 失败focus BiliSearchFilter", err.message)
    }
  }

  build() {
    NavDestination() {
      Column() {
        ArcList({ header: new ComponentContent(this.getUIContext(), wrapBuilder(headerContentBuilder)), scroller: this.scroller }) {
          ArcListItem() {
            FilterListItem({ text: "综合排序", selected: this.param?.orderType === 'totalrank' })
              .onClick(() => this.onBtnClick('totalrank'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
            FilterListItem({ text: "最多点击", selected: this.param?.orderType === 'click' })
              .onClick(() => this.onBtnClick('click'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
            FilterListItem({ text: "最新发布", selected: this.param?.orderType === 'pubdate' })
              .onClick(() => this.onBtnClick('pubdate'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
            FilterListItem({ text: "最多弹幕", selected: this.param?.orderType === 'dm' })
              .onClick(() => this.onBtnClick('dm'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
            FilterListItem({ text: "最多收藏", selected: this.param?.orderType === 'stow' })
              .onClick(() => this.onBtnClick('stow'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
            FilterListItem({ text: "最多评论", selected: this.param?.orderType === 'scores' })
              .onClick(() => this.onBtnClick('scores'))
          }.margin({ start: LengthMetrics.vp(15), end: LengthMetrics.vp(15) })

          ArcListItem() {
          }
          // 放置一个空点击事件，把焦点引到这来（因为其它几个元素的onClick在组件内部，对ArcList透明，导致无法获焦），这样可以正常获焦点
          .onClick(() => {
          })
        }
        // 更Q弹的动画
        .chainAnimation(true)
        // 列表项目的间距
        .space(LengthMetrics.vp(10))
        // 启用表冠滚动
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .digitalCrownSensitivity(CrownSensitivity.LOW)
        .id(this.biliSearchFilterListId)
        .onAppear(() => this.focusBiliSearchFilterList())
      }
    }
    .onReady(context => {
      this.pathInfos = context.pathStack
      this.param = context.pathInfo.param as BiliSearchParam
    })
    .hideTitleBar(true)
  }
}

@ComponentV2
struct FilterListItem {
  @Param text: string = ""
  @Param selected: boolean = false

  build() {
    Button({ stateEffect: true }) {
      Row({ space: 5 }) {
        if (this.selected) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontColor(['#70AEFF'])
        }
        Text(this.text).fontColor(this.selected ? '#70AEFF' : Color.White)
      }
    }
    .type(ButtonType.Capsule)
    .stateEffect(true)
    .backgroundColor("#ff2d2c2c")
    .width("100%")
    .padding({ top: LengthMetrics.vp(15), bottom: LengthMetrics.vp(15) })
  }
}
