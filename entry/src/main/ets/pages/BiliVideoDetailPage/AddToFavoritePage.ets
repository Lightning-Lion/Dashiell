import { UUID } from '../../common/UUID';
import { focusWatchList } from '../../common/WatchListFocus';
import { DarkTheme } from '../../common/Theme';
import { BilibiliService } from '../../common/BiliService';
import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute, LengthMetrics } from '@kit.ArkUI';
import { FavoriteFolder, getFavoriteChanges } from '../../common/BiliFavoriteModels';

export interface BiliMidApiResponse {
  code: number;
  message: string;
  data: BiliMidApiResponseData;
}

interface BiliMidApiResponseData {
  mid: number;
}

export interface BiliFolderListAllApiResponse {
  code: number;
  message: string;
  data: BiliFolderListAllApiResponseData;
}

interface BiliFolderListAllApiResponseData {
  count: number;
  list: FavoriteFolder[] | null;
}

export interface BiliAddToFavoriteApiResponse {
  code: number;
  message: string;
}

export interface AddToFavoritePagePushData {
  bvid: string;
  avid: number;
  biliService: BilibiliService;
  onResult: () => void;
}

@Builder
export function AddToFavoritePageBuilder(name: string, param: Object) {
  AddToFavoritePage({ data: param as AddToFavoritePagePushData })
}

@ComponentV2
struct AddToFavoritePage {
  @Param @Require data: AddToFavoritePagePushData;
  @Local private folders: FavoriteFolder[] = [];
  @Local private selected: number[] = [];
  private original: number[] = [];
  @Local private loading: boolean = false;
  @Local private saving: boolean = false;
  @Local private loaded: boolean = false;
  @Local private error: string = '';
  private paths: NavPathStack | null = null;
  private listFocusId: string = UUID();

  private async load(): Promise<void> {
    if (this.loading || this.saving) {
      return;
    }
    this.loading = true;
    this.error = '';
    this.loaded = false;
    try {
      const user = await this.data.biliService.getMid(this.data.bvid);
      const response = await this.data.biliService.getFolderListAll(
        user.data.mid.toString(), this.data.avid, this.data.bvid);
      if (response.code !== 0 || !response.data) {
        throw new Error(response.message || '获取收藏夹失败');
      }
      this.folders = response.data.list || [];
      this.original = this.folders.filter(folder => folder.fav_state === 1).map(folder => folder.id);
      this.selected = this.original.slice();
      this.loaded = true;
    } catch (error) {
      this.error = (error as Error).message || '获取收藏夹失败，请重试';
    } finally {
      this.loading = false;
    }
  }

  private async save(): Promise<void> {
    if (this.saving || this.loading || !this.loaded) {
      return;
    }
    this.saving = true;
    this.error = '';
    const changes = getFavoriteChanges(this.original, this.selected);
    try {
      if (changes.add.length > 0 || changes.remove.length > 0) {
        const result = await this.data.biliService.addToFavorite(
          this.data.avid, changes.add, changes.remove, this.data.bvid);
        if (result.code !== 0) {
          throw new Error(result.message || '保存收藏失败');
        }
      }
      this.getUIContext().getPromptAction().showToast({ message: '收藏设置已保存' });
      this.data.onResult();
      this.paths?.pop();
    } catch (error) {
      this.error = (error as Error).message || '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  build() {
    NavDestination() {
      ArcList() {
        ArcListItem() {
          Text('管理视频收藏').fontSize(18).fontWeight(FontWeight.Bold).padding(16)
        }
        if (this.loading || this.saving) {
          ArcListItem() {
            LoadingProgress().width(40).height(40).color($r('app.color.bili_color'))
          }
        }
        ForEach(this.folders, (folder: FavoriteFolder) => {
          ArcListItem() {
            Button() {
              Row({ space: 8 }) {
                Text(this.selected.includes(folder.id) ? '✓' : '○').fontColor($r('app.color.bili_color'))
                Column({ space: 4 }) {
                  Text(folder.title).fontSize(16).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${folder.media_count} 个内容`).fontSize(12).fontColor('#AAAAAA')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%').padding(12)
            }
            .width('100%').backgroundColor(DarkTheme.cardBackground).fontColor(DarkTheme.textPrimary)
            .enabled(!this.loading && !this.saving && this.loaded)
            .onClick(() => {
              this.selected = this.selected.includes(folder.id) ?
                this.selected.filter(id => id !== folder.id) : this.selected.concat([folder.id]);
            })
          }
        }, (folder: FavoriteFolder) => folder.id.toString())
        if (this.error) {
          ArcListItem() {
            Text(this.error).fontSize(14).fontColor('#FF9999').padding(12)
          }
        }
        if (this.loaded && this.folders.length === 0) {
          ArcListItem() {
            Text('暂无可用收藏夹').fontSize(14).padding(12)
          }
        }
        if (this.loaded) {
          ArcListItem() {
            Button('保存收藏设置').backgroundColor($r('app.color.bili_color'))
              .enabled(!this.saving && !this.loading).onClick(() => this.save())
          }
        } else if (!this.loading) {
          ArcListItem() {
            Button('重试').backgroundColor(DarkTheme.cardBackground).fontColor(DarkTheme.primary).onClick(() => this.load())
          }
        }
      }
      .space(LengthMetrics.vp(8))
      .width('100%').height('100%')
      .focusable(true).focusOnTouch(true).defaultFocus(true)
      .id(this.listFocusId)
      .onAppear(() => focusWatchList(this.getUIContext(), this.listFocusId))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => { this.paths = context.pathStack; })
    .onShown(() => {
      focusWatchList(this.getUIContext(), this.listFocusId);
      this.load();
    })
    .onBackPressed(() => this.saving)
  }
}
