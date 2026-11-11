import { ListDataSource } from '../../common/ListDataSource';
import { BiliSearchResponse } from '../../common/bili/schema/BiliModels.generated';
import { BilibiliService, BilibiliServiceWithoutLogin } from '../../common/BiliService'
import { VideoItem } from '../BiliHome/BiliHomeL2'
import { BiliSearchFilterStorage, BiliSearchParam, BiliSearchResult } from './BiliSearchFilter'
import { ArcScrollBar, LengthMetrics } from '@kit.ArkUI'
import { DarkTheme } from '../../common/Theme'
import { logTag } from '../../common/printLog'
import { SearchResultVideoCard } from '../VideoCards/SearchResultVideoCard'
import { AnimatedProgressView } from '../../components/AnimatedProgressView'
import { UUID } from '../../common/UUID'
import { url } from '@kit.ArkTS'
import { BiliLoadingErrorView1 } from '../../components/ErrorPages'
import { requestFocusWithRetry } from '../../common/WatchListFocus'
import { resolveAuthenticatedBiliService } from '../../common/BiliServiceRegistry'
import { biliLoginRequiredParam } from '../BiliLogin/BiliLoginRequiredPage'

@Builder
export function BiliSearchListBuilder(_name: string, param: Object) {
  BiliSearchList({ initialParam: param as BiliSearchListParam })
}

export class BiliSearchListParam {
  private keyword: string
  private biliService: BilibiliService | undefined

  constructor(keyword: string = "", biliService?: BilibiliService) {
    this.keyword = keyword
    this.biliService = biliService
  }

  getKeyword() {
    return this.keyword
  }

  getBilibiliService() {
    return this.biliService
  }
}

@ObservedV2
class BiliSearchListViewModel {
  param: BiliSearchListParam | undefined
  observer: BiliSearchObserver | undefined

  constructor(param?: BiliSearchListParam, observer?: BiliSearchObserver) {
    this.param = param
    this.observer = observer
  }

  @Trace
  videoItems: VideoItem[] = [];
  @Trace
  isLoading: boolean = false;
  @Trace
  errorMessage: string = "";

  getParam() {
    return this.param ?? new BiliSearchListParam("")
  }

  readonly dataSource: ListDataSource<VideoItem> = new ListDataSource<VideoItem>();
  @Trace loadedOnce: boolean = false;
  private disposed: boolean = false;

  dispose(): void {
    this.disposed = true;
    this.generation++;
    this.isLoading = false;
    this.videoItems = [];
    this.dataSource.replace([]);
  }

  private page = 1
  private generation: number = 0
  @Trace hasMore: boolean = true

  async fetchNextPage(biliService: BilibiliService | BilibiliServiceWithoutLogin): Promise<void> {
    if (this.disposed || this.isLoading || !this.hasMore) { return; }
    const generation = this.generation;
    try {
      this.isLoading = true;
      this.errorMessage = '';
      const urlParams = new url.URLParams()
      urlParams.set("search_type", "video")
      urlParams.set("keyword", this.param?.getKeyword() ?? '')
      urlParams.set("page", this.page.toString())
      urlParams.set("order", this.observer?.getOrderType() ?? '')
      const response =
        await biliService.requestSearch(urlParams.toString())
      if (generation !== this.generation) { return; }
      const items = searchToVideoItem(response);
      const seen = new Set(this.videoItems.map((item: VideoItem) => item.bvid || item.aid));
      const additions: VideoItem[] = [];
      for (const item of items) {
        const key = item.bvid || item.aid;
        if (!seen.has(key)) { seen.add(key); additions.push(item); }
      }
      this.videoItems = [...this.videoItems, ...additions];
      this.dataSource.append(additions);
      this.loadedOnce = true;
      this.page++;
      this.hasMore = items.length > 0;
    } catch (e) {
      if (generation === this.generation) {
        this.errorMessage = "搜索加载失败，请检查网络后重试";
      }
    } finally {
      if (generation === this.generation) { this.isLoading = false; }
    }
  }

  // 重置并刷新
  refresh(biliService: BilibiliService | BilibiliServiceWithoutLogin): void {
    // A previous filter request must not append stale results after refresh.
    if (this.disposed) { return; }
    this.generation++;
    biliService.cancelPendingRequests();
    this.isLoading = false;
    this.page = 1;
    this.hasMore = true;
    this.videoItems = [];
    this.dataSource.replace([]);
    this.loadedOnce = false;

    // 加载第一页
    this.fetchNextPage(biliService);
  }
}

@ObservedV2
export class BiliSearchObserver {
  @Trace
  private orderType: BiliSearchFilterStorage.Order = "totalrank"

  getOrderType() {
    return this.orderType
  }

  setOrderType(orderType: BiliSearchFilterStorage.Order) {
    this.changed = true
    this.orderType = orderType
  }

  private changed: boolean = false

  isChanged() {
    return this.changed
  }

  reset() {
    this.changed = false
  }
}

@Entry
@ComponentV2
struct BiliSearchList {
  @Param @Require initialParam: BiliSearchListParam
  @Local pageInfos: NavPathStack | undefined = undefined
  @Local private feedState: BiliSearchListViewModel | undefined = undefined;
  @Local private requestService: BilibiliServiceWithoutLogin | undefined = undefined;
  @Provider("biliSearchObserver") observer: BiliSearchObserver = new BiliSearchObserver()

  aboutToDisappear(): void {
    this.feedState?.dispose();
    this.requestService?.releaseHttp();
  }

  build() {
    NavDestination() {
      if (this.pageInfos !== undefined && this.feedState !== undefined && this.requestService !== undefined) {
        BiliSearchListInner({ feedState: this.feedState, biliService: this.requestService, pageInfos: this.pageInfos })
      }
    }.hideTitleBar(true)
    .onReady(context => {
      this.pageInfos = context.pathStack;
      const authenticated = resolveAuthenticatedBiliService(this.initialParam.getBilibiliService());
      if (authenticated === null) {
        // 结果页也可能被旧导航栈或外部路由直接打开，不能在这里退回匿名搜索。
        context.pathStack.replacePathByName("BiliLoginRequiredPage", biliLoginRequiredParam('搜索'));
        return;
      }
      this.feedState = new BiliSearchListViewModel(this.initialParam, this.observer);
      this.requestService = authenticated.forkForRequests();
    })
  }
}

function searchToVideoItem(response: BiliSearchResponse): VideoItem[] {

  const videos: VideoItem[] = []

  for (let i = 0; i < response.data.result.length; i++) {
    videos.push({
      aid: String(response.data.result[i].id),
      bvid: response.data.result?.[i]?.bvid,
      title: parseTitle(response.data.result?.[i]?.title ?? 'No Title'),
      pic: fixPicUrl(response.data.result?.[i]?.pic ?? ''),
      owner: {
        name: response.data.result?.[i]?.author ?? '',
        face: response.data.result?.[i]?.upic ?? '',
      },
      stat: {
        view: response.data.result?.[i]?.play ?? 0,
        like: response.data.result?.[i]?.like ?? 0,
      },
      duration: response.data.result?.[i]?.duration ?? 0,
    })
  }

  return videos
}

function parseTitle(str: string): string {
  return str.replace(/<em class="keyword">.*?<\/em>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#39;/g, '\'')
    .replace(/&quot;/g, '\"')
    .trim()
}

function fixPicUrl(pic: string): string {
  if (pic.startsWith('//')) {
    return 'https:' + pic
  }
  return pic
}

@ComponentV2
export struct BiliSearchListInner {
  @Param @Require feedState: BiliSearchListViewModel
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack
  @Local private scroller: Scroller = new Scroller();
  @Local private pageID: string = UUID()

  build() {
    // 主内容区
    Column() {
      // 视频列表
      if (this.feedState.videoItems.length > 0) {
        Column() {
          this.videoList()
        }.transition(TransitionEffect.OPACITY.animation({}))
      } else if (this.feedState.isLoading) {
        Column() {
          this.loadingView()
        }
        // 渐隐离场
        .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY, TransitionEffect.OPACITY.animation({})))
      } else if (this.feedState.errorMessage) {
        BiliLoadingErrorView1({
          pageInfos: this.pageInfos,
          errorMessage: this.feedState.errorMessage,
          onRetry: () => this.feedState.fetchNextPage(this.biliService)
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      } else if (this.feedState.loadedOnce) {
        Text('没有找到相关视频').fontColor(DarkTheme.textSecondary)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DarkTheme.background) // 深色背景
    .onAppear(() => {
      // 组件挂载时加载第一页数据
      if (!this.feedState.loadedOnce) { this.feedState.fetchNextPage(this.biliService); }
    })

  }

  @Builder
  loadingView() {
    // 首次加载中的显示
    Column({ space: "30px" }) {
      AnimatedProgressView({ color: DarkTheme.accents.brand })
        .width(50)
        .height(50)
      Text("正在搜索")
        .fontColor(DarkTheme.accents.brand)
        .fontWeight(FontWeight.Bold)
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    // 不铺底色，让 NavDestination 上搜索页自己的品牌红渐变透出来
  }

  @Builder
  videoList() {
    Stack({ alignContent: Alignment.Top }) {
      List({ space: 8, scroller: this.scroller }) {
        LazyForEach(this.feedState.dataSource, (item: VideoItem) => {
          ListItem() {
            SearchResultVideoCard({
              item: item,
              biliService: this.biliService,
              pageInfos: this.pageInfos
            })
          }
          .padding({ left: 16, right: 16 })
          .width('100%')
        }, (item: VideoItem) => item.bvid || item.aid)

        // 加载更多项
        ListItem() {
          if (this.feedState.isLoading) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
                .margin({ right: 8 })
                .color(DarkTheme.primary)

              Text('加载中...')
                .fontSize(14)
                .fontColor(DarkTheme.textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .height(60)
          } else if (!this.feedState.hasMore) {
            Text('已经到底了').fontColor(DarkTheme.textSecondary).fontSize(12)
          } else {
            Button(this.feedState.errorMessage ? '加载失败，点击重试' : '加载更多')
              .onClick(() => {
                this.feedState.fetchNextPage(this.biliService);
              })
              .backgroundColor(DarkTheme.primary)
              .fontColor(DarkTheme.textPrimary)
              .width('40%')
              .margin(16)
              .borderRadius(20)
          }
        }
        .padding({ left: 16, right: 16 })
        .width('100%')
        .height(60)
      }
      .cachedCount(2)
      .contentStartOffset(48)
      .contentEndOffset(25)
      .listDirection(Axis.Vertical)
      // 到达底部时自动加载更多
      .onReachEnd(() => {
        if (!this.feedState.isLoading && !this.feedState.errorMessage && this.feedState.hasMore) {
          this.feedState.fetchNextPage(this.biliService);
        }
      })
      // 滚动手感
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      // 支持表冠
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
      .onAppear(() => {
        try {
          requestFocusWithRetry(this.getUIContext(), this.pageID + "91e9103c-28b5-4685-bd0e-837eddd7372b")
        } catch (error) {
          console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
        }
      })
      .id(this.pageID + "91e9103c-28b5-4685-bd0e-837eddd7372b")
      .width("100%")
      .height("100%")

      ArcScrollBar({ scroller: this.scroller })
      FilterMenu({
        feedState: this.feedState,
        biliService: this.biliService,
        pageInfos: this.pageInfos,
      })
    }
  }
}


@ComponentV2
struct FilterMenu {
  @Param @Require feedState: BiliSearchListViewModel
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack
  @Consumer("biliSearchObserver") biliSearchObserver: BiliSearchObserver | undefined = undefined

  build() {
    Button({ type: ButtonType.Normal, role: ButtonRole.NORMAL, buttonStyle: ButtonStyleMode.NORMAL }) {
      Text("筛选")
        .fontColor(Color.White)
        .padding({
          top: LengthMetrics.fp(14),
          bottom: LengthMetrics.fp(8)
        })
    }
    .backgroundColor(DarkTheme.primary)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .stateEffect(true)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.pageInfos.pushPathByName("BiliSearchFilter",
        new BiliSearchParam(this.biliSearchObserver?.getOrderType() ?? BiliSearchFilterStorage.defaultOrder),
        (popInfo: PopInfo) => {
          const result = popInfo.result as BiliSearchResult
          this.biliSearchObserver?.setOrderType(result?.getOrderType())
          this.feedState.refresh(this.biliService)
        })
    })
    .width("100%")
  }
}
