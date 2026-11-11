import { ArcScrollBar } from '@kit.ArkUI';
import { UUID } from '../../common/UUID';
import { focusWatchList } from '../../common/WatchListFocus';
import { DarkTheme } from '../../common/Theme';
import { BilibiliService } from '../../common/BiliService';
import { getCurrentBiliService, resolveAuthenticatedBiliService } from '../../common/BiliServiceRegistry';
import { biliLoginRequiredParam } from '../BiliLogin/BiliLoginRequiredPage';
import { BiliHistoryCursor, BiliHistoryItem } from '../../common/BiliHistoryModels';
import { VideoItem } from '../BiliHome/BiliHomeL2';
import { HomeFeedVideoCard } from '../VideoCards/HomeFeedVideoCard';

@Builder
export function BiliHistoryPageBuilder(_name: string, param: Object) {
  BiliHistoryPage({ service: getCurrentBiliService() || param as BilibiliService });
}

@ComponentV2
struct BiliHistoryPage {
  @Param @Require service: BilibiliService;
  @Local private cursor: BiliHistoryCursor | null = null;
  @Local private items: BiliHistoryItem[] = [];
  @Local private videoItems: VideoItem[] = [];
  @Local private busy: boolean = false;
  @Local private hasMore: boolean = true;
  @Local private error: string = '';
  private scroller: Scroller = new Scroller();
  private listFocusId: string = UUID();
  pageInfos: NavPathStack | null = null;

  aboutToAppear(): void {
    // 直达/旧导航栈可能没有登录态；先不发请求，等 onReady 把页面替换成登录中间页。
    if (resolveAuthenticatedBiliService(this.service) === null) { return; }
    this.loadHistory(true);
  }

  private toVideoItem(item: BiliHistoryItem): VideoItem | null {
    const history = item.history;
    if (!history?.bvid || !history.oid) {
      return null;
    }
    return {
      aid: history.oid.toString(),
      bvid: history.bvid,
      // Avoid optional method calls here. On some ArkTS runtimes `value?.toString()`
      // is lowered to a call on an undefined value when the API omits `cid`.
      cid: history.cid === undefined ? undefined : history.cid.toString(),
      title: item.title || item.show_title || '未命名视频',
      pic: item.cover || '',
      owner: { name: item.author_name || '' },
      duration: item.duration || 0,
      watchedSeconds: item.progress,
      watchFinished: item.is_finish === 1,
      stat: { view: 0, like: 0 }
    };
  }

  private async loadHistory(reset: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const response = await this.service.getHistoryList(
        reset ? undefined : this.cursor ?? undefined
      );
      if (response.code !== 0 || !response.data) {
        throw new Error(response.message || '加载历史记录失败');
      }
      const nextItems = response.data.list || [];
      this.cursor = response.data.cursor || null;
      this.items = reset ? nextItems : this.items.concat(nextItems);
      const playableItems: VideoItem[] = [];
      this.items.forEach(item => {
        const videoItem = this.toVideoItem(item);
        if (videoItem) {
          playableItems.push(videoItem);
        }
      });
      this.videoItems = playableItems;
      // 空列表代表当前没有可展示的观看记录，不应继续显示“加载更多”。
      this.hasMore = nextItems.length > 0 && !!this.cursor;
      if (reset && nextItems.length > 0) {
        const latest = nextItems[0];
        const latestHistory = latest.history;
        const latestBvid = latestHistory === undefined ? '' : (latestHistory.bvid ?? '');
        console.info(`[BiliHistory] latest bvid=${latestBvid} progress=${latest.progress ?? 0} ` +
          `duration=${latest.duration ?? 0} viewAt=${latest.view_at ?? 0} ` +
          `finished=${latest.is_finish ?? -1}`);
      }
    } catch (error) {
      const failure = error as Error;
      console.error(`[BiliHistory] loadHistory failed: ${failure.message || String(error)} stack=${failure.stack || ''}`);
      this.error = failure.message || '加载历史记录失败';
    } finally {
      this.busy = false;
      focusWatchList(this.getUIContext(), this.listFocusId);
    }
  }

  build() {
    NavDestination() {
      Stack() {
        List({ space: 10, scroller: this.scroller }) {
          ListItem() {
            Column({ space: 4 }) {
              Text('观看历史').fontSize(20).fontColor(DarkTheme.textPrimary).fontWeight(FontWeight.Bold)
              Text('按最近观看顺序浏览，支持继续回看').fontSize(12).fontColor(DarkTheme.textSecondary)
            }.width('100%').padding({ top: 4, bottom: 8 })
          }.padding({ left: 28, right: 28 })

          if (this.error) {
            ListItem() {
              Text(this.error).fontSize(12).fontColor(DarkTheme.textSecondary).width('100%').textAlign(TextAlign.Center)
            }.padding({ left: 28, right: 28, top: 8 })
          }

          if (this.videoItems.length > 0) {
            ListItem() {
              Text(`已加载 ${this.videoItems.length} 条`)
                .fontSize(12).fontColor(DarkTheme.textSecondary)
                .padding({ left: 28, right: 28, top: 2, bottom: 4 })
            }
            ForEach(this.videoItems, (item: VideoItem, index: number) => {
              ListItem() {
                if (this.pageInfos) {
                  HomeFeedVideoCard({ item, biliService: this.service, pageInfos: this.pageInfos })
                }
              }.padding({ left: 16, right: 16 })
            }, (item: VideoItem, index: number) => `${item.bvid}_${index}`)
          }

          if (!this.busy && !this.error && this.items.length === 0) {
            ListItem() {
              Text('暂无观看历史')
                .fontSize(14)
                .fontColor(DarkTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Center)
            }.padding({ left: 28, right: 28, top: 36, bottom: 36 })
          }

          if (this.hasMore) {
            ListItem() {
              Button(this.busy ? '加载中...' : '加载更多')
                .width('100%').height(42)
                .fontSize(14).fontColor(DarkTheme.primary)
                .backgroundColor(DarkTheme.cardBackground)
                .enabled(!this.busy)
                .onClick(() => this.loadHistory(false))
            }.padding({ left: 28, right: 28, top: 4, bottom: 20 })
          } else if (!this.busy && this.items.length > 0) {
            ListItem() {
              Text('已经到底了').fontSize(12).fontColor(DarkTheme.textSecondary).width('100%').textAlign(TextAlign.Center)
            }.padding({ top: 8, bottom: 18 })
          }
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(40)
        .contentEndOffset(32)
        .onReachEnd(() => {
          if (this.hasMore && !this.busy) {
            this.loadHistory(false);
          }
        })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        // Make the scrollable list the page's default crown focus target.
        .focusable(true).focusOnTouch(true).defaultFocus(true)
        .id(this.listFocusId)
        .onAppear(() => focusWatchList(this.getUIContext(), this.listFocusId))
        ArcScrollBar({ scroller: this.scroller, state: BarState.On })
      }
      .width('100%')
      .height('100%')
      .clip(true)
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不能铺不透明底色，否则会盖住它
    .linearGradient({ colors: DarkTheme.pageTopGradients.history })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
      if (resolveAuthenticatedBiliService(this.service) === null) {
        context.pathStack.replacePathByName("BiliLoginRequiredPage", biliLoginRequiredParam('历史'));
      }
    })
    .onShown(() => {
      focusWatchList(this.getUIContext(), this.listFocusId);
    })
  }
}
