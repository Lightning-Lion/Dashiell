import { UUID } from '../../common/UUID';
import { focusWatchList } from '../../common/WatchListFocus';
import { ArcScrollBar } from '@kit.ArkUI';
import { BilibiliService } from '../../common/BiliService';
import { getCurrentBiliService, resolveAuthenticatedBiliService } from '../../common/BiliServiceRegistry';
import { biliLoginRequiredParam } from '../BiliLogin/BiliLoginRequiredPage';
import { FavoriteFolder, FavoriteMedia, canPlayFavorite, favoriteVideoId } from '../../common/BiliFavoriteModels';
import { DarkTheme } from '../../common/Theme';
import { VideoItem } from '../BiliHome/BiliHomeL2';
import { HomeFeedVideoCard } from '../VideoCards/HomeFeedVideoCard';

@Builder
export function BiliFavoritesPageBuilder(name: string, param: Object) {
  BiliFavoritesPage({ service: getCurrentBiliService() || param as BilibiliService })
}

interface FavoriteContentsParams {
  service: BilibiliService;
  folder: FavoriteFolder;
}

@Builder
export function BiliFavoriteContentsPageBuilder(name: string, param: Object) {
  BiliFavoritesPage({
    service: getCurrentBiliService() || (param as FavoriteContentsParams).service,
    initialFolder: (param as FavoriteContentsParams).folder
  })
}

@ComponentV2
struct BiliFavoritesPage {
  @Param @Require service: BilibiliService;
  @Param initialFolder: FavoriteFolder | null = null;
  @Local private folders: FavoriteFolder[] = [];
  @Local private folder: FavoriteFolder | null = null;
  @Local private medias: FavoriteMedia[] = [];
  @Local private hasMore: boolean = false;
  @Local private busy: boolean = false;
  @Local private error: string = '';
  @Local private editing: boolean = false;
  @Local private title: string = '';
  @Local private titleFocusEnabled: boolean = false;
  @Local private isPrivate: boolean = true;
  private page: number = 0;
  private retryReset: boolean = true;
  private paths: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  private listFocusId: string = UUID();
  private titleFocusId: string = UUID();

  aboutToAppear(): void {
    // 直达/旧导航栈可能没有登录态；先不发请求，等 onReady 把页面替换成登录中间页。
    if (resolveAuthenticatedBiliService(this.service) === null) { return; }
    if (this.initialFolder) {
      this.folder = this.initialFolder;
      this.loadContents(true);
    } else {
      this.loadFolders();
    }
  }

  private videoItem(media: FavoriteMedia): VideoItem {
    return {
      aid: media.id.toString(), bvid: favoriteVideoId(media), title: media.title,
      pic: media.cover, duration: media.duration,
      owner: { name: media.upper?.name || '' },
      stat: { view: media.cnt_info?.play || 0, like: 0 }
    };
  }

  private async loadFolders(): Promise<void> {
    if (!this.service || this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const response = await this.service.getFavoriteFolders();
      this.folders = response.data.list || [];
    } catch (error) {
      const failure = error as Error;
      console.error(`[BiliFavorites] loadFolders failed: ${failure.message || String(error)} stack=${failure.stack || ''}`);
      this.error = failure.message || '加载收藏夹失败';
    } finally {
      this.busy = false;
      focusWatchList(this.getUIContext(), this.listFocusId);
    }
  }

  private async loadContents(reset: boolean): Promise<void> {
    if (!this.service || !this.folder || this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.retryReset = reset;
    const nextPage = reset ? 1 : this.page + 1;
    try {
      const response = await this.service.getFavoriteContents(this.folder.id, nextPage);
      const items = response.data.medias || [];
      this.folder = response.data.info;
      this.medias = reset ? items : this.medias.concat(items.filter(item =>
        !this.medias.some(existing => existing.id === item.id && existing.type === item.type)));
      this.page = nextPage;
      this.hasMore = response.data.has_more && items.length > 0;
    } catch (error) {
      const failure = error as Error;
      console.error(`[BiliFavorites] loadContents failed: ${failure.message || String(error)} stack=${failure.stack || ''}`);
      this.error = failure.message || '加载收藏内容失败';
    } finally {
      this.busy = false;
      if (reset) { focusWatchList(this.getUIContext(), this.listFocusId); }
    }
  }

  private openFolder(folder: FavoriteFolder): void {
    if (this.busy || this.editing) { return; }
    const params: FavoriteContentsParams = { service: this.service, folder };
    // Keep the navigation call explicit; optional method calls can be lowered
    // incorrectly by the ArkTS runtime when the destination is not ready yet.
    if (this.paths !== null) {
      this.paths.pushPathByName('BiliFavoriteContentsPage', params, true);
    }
  }

  private edit(folder: FavoriteFolder): void {
    if (this.busy) { return; }
    this.title = folder.title;
    this.isPrivate = (folder.attr & 1) !== 0;
    this.setEditor(folder);
  }

  private setEditor(folder: FavoriteFolder | null): void {
    this.titleFocusEnabled = false;
    this.scroller.scrollEdge(Edge.Top);
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.folder = folder;
      this.editing = folder !== null;
      this.error = '';
    });
    focusWatchList(this.getUIContext(), this.listFocusId);
  }

  private async saveFolder(): Promise<void> {
    if (!this.service || this.busy || !this.title.trim()) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      if (this.folder) {
        await this.service.editFavoriteFolder(this.folder.id, this.title, this.isPrivate);
      }
      this.setEditor(null);
      this.getUIContext().getPromptAction().showToast({ message: '收藏夹已保存' });
    } catch (error) {
      this.error = (error as Error).message || '保存收藏夹失败';
    } finally {
      this.busy = false;
    }
    if (!this.editing) {
      if (this.folder) {
        await this.loadContents(true);
      } else {
        await this.loadFolders();
      }
    }
  }

  private back(): boolean {
    // The contents destination pops normally, including while a request is pending.
    if (this.initialFolder) {
      return false;
    }
    if (this.busy) {
      return true;
    }
    if (this.editing) {
      this.setEditor(null);
      return true;
    }
    return false;
  }

  @Builder
  action(label: string, callback: () => void) {
    Button(label, { type: ButtonType.Capsule })
      .backgroundColor(DarkTheme.cardBackground)
      .fontColor(DarkTheme.primary)
      .fontSize(14).width('100%').height(40)
      .enabled(!this.busy).onClick(callback)
  }

  build() {
    NavDestination() {
      Stack() {
        List({ space: 8, scroller: this.scroller }) {
          ListItem() {
            Column({ space: 4 }) {
              Text(this.editing ? '编辑收藏夹' : this.folder?.title || '我的收藏夹')
                .fontSize(18).fontColor(DarkTheme.textPrimary).fontWeight(FontWeight.Bold).maxLines(2)
              if (!this.folder && !this.editing) {
                Text('长按收藏夹可编辑').fontSize(12).fontColor(DarkTheme.textSecondary)
              }
              if (this.folder && !this.editing) {
                Text(`${this.folder.media_count} 个内容`).fontSize(12).fontColor(DarkTheme.textSecondary)
              }
            }.width('100%').padding({ top: 4, bottom: 12 })
          }.padding({ left: 32, right: 32 })
          if (this.editing) {
            ListItem() {
              Column({ space: 10 }) {
                TextInput({ text: this.title, placeholder: '收藏夹名称' })
                  .id(this.titleFocusId).focusable(this.titleFocusEnabled)
                  .onClick(() => {
                    this.titleFocusEnabled = true;
                    focusWatchList(this.getUIContext(), this.titleFocusId);
                  })
                  .backgroundColor(DarkTheme.textFieldBackground).fontColor(DarkTheme.textPrimary)
                  .maxLength(40).enabled(!this.busy).onChange((value: string) => { this.title = value; })
                Button(this.isPrivate ? '私密 · 仅自己可见' : '公开 · 所有人可见')
                  .backgroundColor(DarkTheme.cardBackground).fontColor(DarkTheme.primary)
                  .fontSize(14).width('100%').height(40).enabled(!this.busy)
                  .onClick(() => { this.isPrivate = !this.isPrivate; })
                this.action('保存', () => this.saveFolder())
                this.action('取消', () => { this.back(); })
              }
            }.padding({ left: 28, right: 28 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 18 })))
          } else if (this.folder === null) {
            ForEach(this.folders, (folder: FavoriteFolder) => {
              ListItem() {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 12 }) {
                    Image($r('app.media.bili_video_detail_page_has_favorite'))
                      .width(24).height(24).fillColor(DarkTheme.primary)
                    Column({ space: 5 }) {
                      Text(folder.title).fontSize(16).fontColor(DarkTheme.textPrimary)
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${folder.media_count} 个内容 · ${(folder.attr & 1) !== 0 ? '私密' : '公开'}`)
                        .fontSize(12).fontColor(DarkTheme.textSecondary)
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    Text('›').fontSize(22).fontColor(DarkTheme.textSecondary)
                  }.padding(16).width('100%')
                }.backgroundColor(DarkTheme.cardBackground).borderRadius(16).width('100%')
                .enabled(!this.busy)
                .gesture(
                  GestureGroup(GestureMode.Exclusive,
                    LongPressGesture({ repeat: false, duration: 600 })
                      .onAction(() => this.edit(folder)),
                    TapGesture().onAction(() => this.openFolder(folder))
                  )
                )
              }.padding({ left: 16, right: 16 }).width('100%')
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -18 })))
            }, (folder: FavoriteFolder) => folder.id.toString())
            if (!this.busy && !this.error && this.folders.length === 0) {
              ListItem() { Text('暂无收藏夹').fontColor(DarkTheme.textSecondary).width('100%').textAlign(TextAlign.Center) }
            }
          } else {
            ForEach(this.medias, (media: FavoriteMedia) => {
              ListItem() {
                if (this.paths && canPlayFavorite(media)) {
                  HomeFeedVideoCard({ item: this.videoItem(media), biliService: this.service, pageInfos: this.paths })
                } else {
                  Column({ space: 6 }) {
                    Text(media.title).fontColor(DarkTheme.textPrimary).fontSize(14).maxLines(2)
                    Text((media.attr & 1) !== 0 ? '视频已失效' : '暂不支持此内容类型')
                      .fontColor(DarkTheme.textSecondary).fontSize(12)
                  }.padding(16).width('100%').backgroundColor(DarkTheme.cardBackground).borderRadius(8)
                }
              }.padding({ left: 16, right: 16 }).width('100%')
            }, (media: FavoriteMedia) => `${media.type}:${media.id}`)
            if (!this.busy && !this.error && !this.hasMore) {
              ListItem() {
                Text(this.medias.length === 0 ? '收藏夹还是空的' : '已显示全部内容')
                  .fontColor(DarkTheme.textSecondary).fontSize(12).width('100%').textAlign(TextAlign.Center).padding(12)
              }
            }
          }
          if (this.busy) {
            ListItem() {
              LoadingProgress().width(28).height(28).color(DarkTheme.primary).margin({ left: '44%' })
            }
          }
          if (this.error) {
            ListItem() {
              Text(this.error).fontColor(DarkTheme.errorColor).fontSize(14).padding(16)
            }
          }
          if (!this.editing) {
            ListItem() {
              Column({ space: 8 }) {
                Button(this.error ? '重试' : '刷新')
                  .backgroundColor(DarkTheme.cardBackground).fontColor(DarkTheme.primary)
                  .fontSize(14).width('100%').height(40).enabled(!this.busy).onClick(() => {
                  if (this.folder) { this.loadContents(this.error ? this.retryReset : true); }
                  else { this.loadFolders(); }
                })
              }
            }.padding({ left: 36, right: 36 })
          }
        }
        .contentStartOffset(40).contentEndOffset(40)
        .onReachEnd(() => {
          if (this.folder && this.hasMore && !this.busy && !this.error && !this.editing) {
            this.loadContents(false);
          }
        })
        .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
        // Make the scrollable list the page's default crown focus target.
        .width('100%').height('100%').focusable(true).focusOnTouch(true).defaultFocus(true)
        .id(this.listFocusId)
        .onAppear(() => focusWatchList(this.getUIContext(), this.listFocusId))
        ArcScrollBar({ scroller: this.scroller })
      }.width('100%').height('100%')
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不能铺不透明底色，否则会盖住它
    .linearGradient({ colors: DarkTheme.pageTopGradients.favorite })
    .onReady((context: NavDestinationContext) => {
      this.paths = context.pathStack;
      if (resolveAuthenticatedBiliService(this.service) === null) {
        context.pathStack.replacePathByName("BiliLoginRequiredPage", biliLoginRequiredParam('收藏'));
      }
    })
    .onShown(() => focusWatchList(this.getUIContext(), this.listFocusId))
    .onBackPressed(() => this.back())
  }
}
