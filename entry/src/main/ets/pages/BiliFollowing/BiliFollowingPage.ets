import { UUID } from '../../common/UUID';
import { focusWatchList } from '../../common/WatchListFocus';
import { DarkTheme } from '../../common/Theme';
import { BilibiliService, BiliFollowingItem } from '../../common/BiliService';
import { resolveAuthenticatedBiliService } from '../../common/BiliServiceRegistry';
import { biliLoginRequiredParam } from '../BiliLogin/BiliLoginRequiredPage';

@Builder
export function BiliFollowingPageBuilder(_name: string, param: Object) {
  BiliFollowingPage({ service: param as BilibiliService });
}

@ComponentV2
struct BiliFollowingPage {
  @Param @Require service: BilibiliService;
  @Local private items: BiliFollowingItem[] = [];
  @Local private page: number = 1;
  @Local private total: number = 0;
  @Local private loading: boolean = false;
  @Local private hasMore: boolean = true;
  @Local private error: string = '';
  private listFocusId: string = UUID();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 直达/旧导航栈可能没有登录态；先不发请求，等 onReady 把页面替换成登录中间页。
    if (resolveAuthenticatedBiliService(this.service) === null) { return; }
    this.loadPage(true);
  }

  private async loadPage(reset: boolean): Promise<void> {
    if (this.loading || (!reset && !this.hasMore)) {
      return;
    }
    this.loading = true;
    this.error = '';
    const nextPage: number = reset ? 1 : this.page + 1;
    try {
      const currentUser = await this.service.getCurrentUserInfo();
      const mid = currentUser.data.mid;
      if (!mid) {
        throw new Error('无法获取当前账号信息');
      }
      const response = await this.service.getFollowingList(mid, nextPage, 20);
      if (response.code !== 0 || !response.data) {
        throw new Error(response.message || '关注列表加载失败');
      }
      const nextItems: BiliFollowingItem[] = response.data.list || [];
      this.items = reset ? nextItems : this.items.concat(nextItems);
      this.page = nextPage;
      this.total = response.data.total || this.items.length;
      this.hasMore = nextItems.length > 0 && this.items.length < this.total;
    } catch (error) {
      this.error = (error as Error).message || '关注列表加载失败';
    } finally {
      this.loading = false;
      focusWatchList(this.getUIContext(), this.listFocusId);
    }
  }

  build() {
    NavDestination() {
      List({ space: 0, scroller: this.scroller }) {
        ListItem() {
          Column({ space: 4 }) {
            Text('关注').fontSize(20).fontWeight(FontWeight.Bold).fontColor(DarkTheme.textPrimary)
            Text(this.total > 0 ? `${this.total} 位 UP 主` : '正在读取关注列表')
              .fontSize(12).fontColor(DarkTheme.textSecondary)
          }
          .width('100%').padding({ left: 28, right: 28, top: 10, bottom: 14 })
        }

        if (this.error) {
          ListItem() {
            Column({ space: 10 }) {
              Text(this.error).fontSize(12).fontColor(DarkTheme.textSecondary)
              Button('重试').height(36).fontSize(13).fontColor(DarkTheme.primary)
                .backgroundColor(DarkTheme.cardBackground)
                .onClick(() => this.loadPage(true))
            }.width('100%').alignItems(HorizontalAlign.Center)
          }.padding({ left: 28, right: 28, top: 12, bottom: 12 })
        }

        ForEach(this.items, (item: BiliFollowingItem) => {
          ListItem() {
            Row({ space: 12 }) {
              Image(item.face || $r('app.media.layered_image'))
                .width(44).height(44).borderRadius(22)
              Column({ space: 4 }) {
                Text(item.uname || `用户 ${item.mid}`)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(DarkTheme.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.sign || '这个 UP 主还没有填写简介')
                  .fontSize(11).fontColor(DarkTheme.textSecondary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
            .width('100%').padding({ left: 28, right: 28, top: 10, bottom: 10 })
          }
        }, (item: BiliFollowingItem) => `${item.mid}`)

        if (this.loading || this.hasMore) {
          ListItem() {
            Button(this.loading ? '加载中...' : '加载更多')
              .width('100%').height(40).fontSize(13).fontColor(DarkTheme.primary)
              .backgroundColor(DarkTheme.cardBackground).enabled(!this.loading)
              .onClick(() => this.loadPage(false))
          }.padding({ left: 28, right: 28, top: 8, bottom: 20 })
        } else if (!this.loading && this.items.length > 0) {
          ListItem() {
            Text('已经到底了').fontSize(12).fontColor(DarkTheme.textSecondary)
          }.width('100%').padding({ top: 10, bottom: 20 })
        }
      }
      .width('100%').height('100%').contentStartOffset(40).contentEndOffset(28)
      .onReachEnd(() => this.loadPage(false))
      .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
      .focusable(true).focusOnTouch(true).defaultFocus(true)
      .id(this.listFocusId)
      .onAppear(() => focusWatchList(this.getUIContext(), this.listFocusId))
    }
    .hideTitleBar(true)
    .backgroundColor(DarkTheme.background)
    .onReady((context: NavDestinationContext) => {
      if (resolveAuthenticatedBiliService(this.service) === null) {
        context.pathStack.replacePathByName("BiliLoginRequiredPage", biliLoginRequiredParam('关注'));
      }
    })
  }
}
