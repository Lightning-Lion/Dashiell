import { ArcScrollBar, LengthMetrics } from "@kit.ArkUI";
import { BilibiliService, BilibiliServiceWithoutLogin } from "../../common/BiliService";
import { BiliHotSearchItem } from "../../common/BiliHotSearch";
import { BiliSearchListParam } from "./BiliSearchList";
import { BiliSearchHistory } from "./BiliSearchHistory";
import { logTag } from "../../common/printLog";
import { UUID } from "../../common/UUID";
import { DarkTheme } from "../../common/Theme";
import { requestFocusWithRetry } from '../../common/WatchListFocus';
import { resolveAuthenticatedBiliService } from "../../common/BiliServiceRegistry";
import { pushBiliLoginRequired } from "../BiliLogin/BiliLoginRequiredPage";

@Builder
export function BiliSearchBuilder() {
  BiliSearch()
}


@Entry
@ComponentV2
struct BiliSearch {
  @Local private pathInfos: NavPathStack | null = null;
  @Local private keyword: string = '';
  @Local private param: BilibiliService | undefined = undefined;
  @Local private scroller: Scroller = new Scroller()
  @Local private searchHistories: BiliSearchHistory = new BiliSearchHistory(getContext())
  @Local private loadSearchHistoryError: Error | null = null
  @Local private namespace: string = UUID()
  @Local private hotSearchItems: BiliHotSearchItem[] = [];
  @Local private hotSearchLoading: boolean = false;
  @Local private hotSearchFailed: boolean = false;

  private searchController: SearchController = new SearchController();
  private pageVisible: boolean = true;
  @Local private editingAllowed: boolean = false;
  private editSessionStarted: boolean = false;
  // 未登录时先记下用户本来想做的事，登录中间页返回后继续，避免用户再操作一遍。
  private pendingSearchKeyword: string | undefined = undefined;
  private pendingOpenSearchEditor: boolean = false;

  private resolveSearchService(): BilibiliService | undefined {
    return resolveAuthenticatedBiliService(this.param) ?? undefined;
  }

  private openLoginGate(): void {
    this.closeEditing();
    if (!pushBiliLoginRequired(this.pathInfos, '搜索')) {
      this.getUIContext().getPromptAction().showToast({
        message: "无法打开页面，App导航堆栈状态异常，建议重启App。\n错误信息：导航堆栈未准备就绪。"
      })
    }
  }

  private requireLoginForSearch(keyword?: string, openEditor: boolean = false): boolean {
    if (this.resolveSearchService() !== undefined) { return true; }
    const trimmed = (keyword ?? '').trim();
    this.pendingOpenSearchEditor = openEditor;
    this.pendingSearchKeyword = openEditor || trimmed.length === 0 ? undefined : trimmed;
    this.openLoginGate();
    return false;
  }

  private restoreScrollFocus(): void {
    if (!this.pageVisible) { return; }
    try {
      // Focus a non-editable leaf, not the List scope which can restore its remembered Search child.
      this.getUIContext().getFocusController().requestFocus(this.namespace + 'search-scroll-anchor');
    } catch (error) { console.debug(logTag, 'Search scroll focus unavailable'); }
  }

  private closeEditing(): void {
    this.editingAllowed = false;
    this.editSessionStarted = false;
    try { this.searchController.stopEditing(); } catch (error) { }
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.closeEditing();
  }

  aboutToAppear() {
    this.loadHotSearch();
  }

  private async loadHotSearch(): Promise<void> {
    if (this.hotSearchLoading) {
      return;
    }
    this.hotSearchLoading = true;
    this.hotSearchFailed = false;
    try {
      this.hotSearchItems = await BilibiliServiceWithoutLogin.getHotSearch();
    } catch (error) {
      this.hotSearchFailed = true;
    } finally {
      this.hotSearchLoading = false;
    }
  }

  private search(keyword: string = this.keyword) {
    keyword = keyword.trim();
    if (keyword.length === 0) { return; }
    const biliService = this.resolveSearchService();
    if (biliService === undefined) {
      this.requireLoginForSearch(keyword);
      return;
    }
    this.closeEditing();
    // 不用阻塞
    (async () => {
      // 添加历史记录出错可以不影响搜索页面推出
      try {
        await this.searchHistories.add(keyword)
      } catch (error) {
        this.loadSearchHistoryError = error
      }
    })()
    if (this.pathInfos !== null) {
      console.debug(logTag,"search(keyword:"+keyword)
      this.pathInfos.pushPathByName("BiliSearchList", new BiliSearchListParam(keyword, biliService))
    } else {
      this.getUIContext().getPromptAction().showToast({ message: "无法打开页面，App导航堆栈状态异常，建议重启App。\n错误信息：导航堆栈未准备就绪。" })
    }
  }

  build() {
    NavDestination() {
      Stack() {
        List({ scroller: this.scroller }) {
          ListItem() {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Image($r("app.media.BiliSearch")).size({ width: 40, height: 40 })
            }
            .id(this.namespace + 'search-scroll-anchor')
            .backgroundColor(Color.Transparent)
            .focusable(true)
            .defaultFocus(true)
            .onAppear(() => this.restoreScrollFocus())
            .onClick(() => this.restoreScrollFocus())
            .width("100%")
            .margin({ top: LengthMetrics.vp(40) })
          }

          ListItem() {
            if (!this.editingAllowed) {
              // Keep no editable node in the scrolling page until an explicit tap.
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 8 }) {
                  Image($r('app.media.BiliSearch')).width(20).height(20)
                  Text(this.keyword || '搜索...').fontSize(16).fontColor(Color.White).layoutWeight(1).maxLines(1)
                }.padding({ left: 12, right: 12 }).width('100%')
              }
              .id(this.namespace + 'search-launcher')
              .width('100%').height(40).borderRadius(24).backgroundColor('#1bffffff')
              .onClick(() => {
                if (!this.requireLoginForSearch(undefined, true)) { return; }
                this.editSessionStarted = false;
                this.editingAllowed = true;
              })
            } else {
            Search({ placeholder: "搜索...", value: $$this.keyword, controller: this.searchController })
              .id(this.namespace + 'search-input')
              .defaultFocus(true)
              .onAppear(() => {
                if (!this.pageVisible || !this.editingAllowed) { return; }
                try { this.getUIContext().getFocusController().requestFocus(this.namespace + 'search-input'); }
                catch (error) { }
              })
              .onEditChange((editing: boolean) => {
                if (editing) { this.editSessionStarted = true; }
                else if (this.editSessionStarted) { this.closeEditing(); this.restoreScrollFocus(); }
              })
              .onSubmit(() => this.search())
              // 在模拟器里，没有软键盘，需要长按确认搜索
              .editMenuOptions({
                onCreateMenu: (menuItems: TextMenuItem[]): TextMenuItem[] => {
                  menuItems.push({
                    id:TextMenuItemId.SEARCH,
                    content:"搜索"
                  })
                  return menuItems
                },
                onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean => {
                  if (menuItem.id.equals(TextMenuItemId.SEARCH)) {
                    this.search()
                    return true;
                  } else {
                    return false;
                  }
                }
              })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
            }
          }.padding({ left: 30, right: 30, top: 15 })

          if (this.loadSearchHistoryError !== null) {
            ListItem() {
              Row() {
                // 加载搜索历史记录出错了，请联系开发者。
                // 点此联系开发者。
                Text(this.loadSearchHistoryError.message)
                  .lineBreakStrategy(LineBreakStrategy.GREEDY)
                  .fontColor("#3cffffff")
                  .fontSize(12)
                  // 文字在屏幕两边无法会被遮挡
                  .width("87%")
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    // 用户点击跳转联系开发者页面
                    if (this.pathInfos !== null) {
                      this.pathInfos.pushPathByName("CustomerServicePage", undefined)
                    } else {
                      this.getUIContext().getPromptAction().showToast({
                        message: "无法打开页面，App导航堆栈状态异常，建议重启App。\n错误信息：导航堆栈未准备就绪。"
                      })
                    }
                  })
              }
              .justifyContent(FlexAlign.Center)
              .width("100%")
              .margin({ top: LengthMetrics.vp(20) })
            }
          } else if (this.searchHistories.length === 0) {
            ListItem() {
              Row() {
                Text("没有历史搜索记录")
                  .fontColor("#3cffffff")
                  .fontSize(12)
              }.justifyContent(FlexAlign.Center)
              .width("100%")
              .margin({ top: LengthMetrics.vp(20) })
            }
          } else {
            ListItem() {
              Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
                Text("历史记录")
                  .fontSize(14)
                  .fontColor("#B8B7B7")

                if (this.searchHistories.length !== 0) {
                  Button() {
                    SymbolGlyph($r('sys.symbol.trash'))
                      .fontSize(15)
                      .fontColor([Color.White])
                      .onClick(async () => {
                        const res = await this.getUIContext().getPromptAction().showDialog({
                          message: "是否清空历史记录？",
                          buttons: [
                            { text: "取消", color: "#ffffff" },
                            { text: "确定", color: '#fffc2323' }
                          ],
                        })
                        if (res.index !== 1) {
                          return;
                        }
                        try {
                          await this.searchHistories.clear()
                        } catch (error) {
                          this.loadSearchHistoryError = error
                        }
                      })
                  }.backgroundColor("#6A4353")
                  .padding(4)
                  .borderRadius(99)
                }
              }.margin({ start: LengthMetrics.vp(35), end: LengthMetrics.vp(35), top: LengthMetrics.vp(10) })
            }

            ForEach(this.searchHistories.histories, (item: string, index: number) => {
              ListItem() {
                this.SearchHistoryItem(item)
              }
              .margin({
                start: LengthMetrics.vp(40),
                end: LengthMetrics.vp(40),
                top: LengthMetrics.vp(15)
              })
            }, (key: string) => key)
          }

          ListItem() {
            Text("热搜榜")
              .fontSize(14)
              .fontColor("#B8B7B7")
          }
          .margin({ start: LengthMetrics.vp(35), top: LengthMetrics.vp(24), bottom: LengthMetrics.vp(8) })

          if (this.hotSearchLoading) {
            ListItem() {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color("#B8B7B7")
                Text("正在加载热搜榜").fontSize(12).fontColor("#B8B7B7")
              }.width("100%").justifyContent(FlexAlign.Center)
            }
          } else if (this.hotSearchFailed || this.hotSearchItems.length === 0) {
            ListItem() {
              Button(this.hotSearchFailed ? "加载失败，点击重试" : "暂无热搜，点击刷新")
                .fontSize(12)
                .fontColor("#B8B7B7")
                .backgroundColor("#1bffffff")
                .width("100%")
                .onClick(() => this.loadHotSearch())
            }.margin({ start: LengthMetrics.vp(35), end: LengthMetrics.vp(35) })
          } else {
            ForEach(this.hotSearchItems, (item: BiliHotSearchItem, index: number) => {
              ListItem() {
                Button() {
                  Row({ space: 8 }) {
                    Text(`${index + 1}`)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(index < 3 ? DarkTheme.primary : "#B8B7B7")
                      .width(24)
                    Text(item.show_name || item.keyword)
                      .fontSize(14)
                      .fontColor(Color.White)
                      .textAlign(TextAlign.Start)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }.width("100%")
                }
                .width("100%")
                .constraintSize({ minHeight: 44 })
                .padding(10)
                .borderRadius(8)
                .backgroundColor("#1bffffff")
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  this.keyword = item.keyword;
                  this.search(item.keyword);
                })
              }.margin({ start: LengthMetrics.vp(35), end: LengthMetrics.vp(35), top: LengthMetrics.vp(8) })
            }, (item: BiliHotSearchItem, index: number) => `${index}:${item.keyword}`)
          }
          ListItem() {
            Row().height(50)
          }
        }
        .width("100%")
        .height("100%")
        .scrollBar(BarState.Off)
        .focusable(true)
        .focusOnTouch(false)
        .defaultFocus(true)
        .id(this.namespace + "5f7b4be2-15a6-4c0d-b62a-fa9007e8f360")
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(async () => {
          try {
            await this.searchHistories.fetchNextPage()
          } catch (error) {
            this.loadSearchHistoryError = error
          }
        })

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })
      }
    }
    .hideTitleBar(true)
    // 在页面首次被推入导航堆栈、页面重新出现（比如进入了搜索详情页、然后返回到我这页），都会触发这个事件，刷新历史记录
    // 避免输入内容，进入搜索详情页，然后返回我这页时，还是显示“没有历史记录”，没有及时更新状态
    .onShown(async () => {
      this.pageVisible = true;
      this.closeEditing();
      this.restoreScrollFocus();
      // 从登录中间页返回时，onShown 会再次触发；登录成功则继续用户刚才的操作。
      const pendingKeyword = this.pendingSearchKeyword;
      const pendingEditor = this.pendingOpenSearchEditor;
      this.pendingSearchKeyword = undefined;
      this.pendingOpenSearchEditor = false;
      try {
        await this.searchHistories.refresh()
      } catch (error) {
        this.loadSearchHistoryError = error
      }
      if (!this.pageVisible || this.resolveSearchService() === undefined) { return; }
      if (pendingEditor) {
        this.editSessionStarted = false;
        this.editingAllowed = true;
      } else if (pendingKeyword !== undefined) {
        this.search(pendingKeyword);
      }
    })
    .onShown(() => {
      // 在从搜索详情页返回而来时，获取焦点
      try {
        requestFocusWithRetry(this.getUIContext(), this.namespace + "5f7b4be2-15a6-4c0d-b62a-fa9007e8f360")
      } catch (error) {
        console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
      }
    })
    .onHidden(() => {
      this.pageVisible = false;
      this.closeEditing();
    })
    .onBackPressed(() => {
      if (this.editingAllowed) {
        this.closeEditing();
        this.restoreScrollFocus();
        return true;
      }
      return false;
    })
    .onReady(context => {
      this.pathInfos = context.pathStack
      this.param = context.pathInfo.param as BilibiliService
    })
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
  }

  @Builder
  SearchHistoryItem(keyword: string) {
    Button() {
      Text(keyword).textAlign(TextAlign.Start)
    }
    .stateEffect(true)
    .backgroundColor("#1bffffff")
    .width("100%")
    .borderRadius(4)
    .padding({
      top: 7,
      bottom: 7,
      left: 5,
      right: 5
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture().onAction(async () => {
          // 使用debug，避免调试日志在发布版本里也出现
          // 总是使用logTag，这样方便筛选日志
          console.debug(logTag, '长按事件触发')
          const res = await this.getUIContext().getPromptAction().showDialog({
            message: "是否删除该历史记录？",
            buttons: [
              { text: "取消", color: "#ffffff" },
              { text: "确定", color: '#fffc2323' }
            ]
          })
          if (res.index !== 1) {
            return;
          }
          try {
            await this.searchHistories.remove(keyword)
          } catch (error) {
            this.loadSearchHistoryError = error
          }
        }),
        TapGesture({ count: 1 }).onAction(() => this.search(keyword)),
      )
    )
  }
}
