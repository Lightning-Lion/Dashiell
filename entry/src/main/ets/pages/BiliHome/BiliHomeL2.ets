import { ArcButton, ArcButtonPosition, ArcButtonOptions } from '@kit.ArkUI'
import { BusinessError } from '@ohos.base';
import { BilibiliService, BilibiliServiceWithoutLogin, GetHomeFeedError } from "../../common/BiliService";
import { BiliStackWidgetPushData } from "./BiliStackWidgetPage";
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { logTag } from '../../common/printLog';
import { ArcScrollBar, LengthMetrics } from '@kit.ArkUI';
import { UUID } from '../../common/UUID';
import { GetUPsVideosError, GetUPsVideosResponseDataListVlistItem } from '../../common/Wbi';
import { HomeFeedVideoCard } from '../VideoCards/HomeFeedVideoCard';
import { DarkTheme } from '../../common/Theme';
import { common } from '@kit.AbilityKit';
import { BiliLoadingErrorView0 } from '../../components/ErrorPages';
import { requestFocusWithRetry } from '../../common/WatchListFocus';
import { BiliHistoryItem } from '../../common/BiliHistoryModels';
import { BiliVideoDetailPagePushData } from '../BiliVideoDetailPage/BiliVideoDetailPage';
import { AppDatabase } from '../../common/storage/AppDatabase';
import { StorageKeys, StorageNamespaces } from '../../common/storage/StorageKeys';
import { BiliResumeCard } from './BiliResumeCard';

// Wire validation and normalized DTOs are independent of this ArkUI component.
import { BiliHomeFeedApiResponse, BiliHomeFeedApiResponseOwner, BiliHomeFeedApiResponseStat } from '../../common/bili/BiliMediaModels';
export { BiliHomeFeedApiResponse };

// 视频项目数据接口
interface OwnerInterface {
  name: string;
  face?: string;
}

interface StateInterface {
  view: number;
  like: number;
}

// 添加类型转换函数并处理可能的错误
function convertToOwnerInterface(apiOwner: BiliHomeFeedApiResponseOwner | undefined): OwnerInterface | undefined {
  if (!apiOwner) {
    return undefined;
  }

  try {
    if (!apiOwner.name) {
      throw new Error("Owner data missing required name field");
    }

    return {
      name: apiOwner.name,
      face: apiOwner.face
    };
  } catch (error) {
    const err = error as Error;
    throw new Error(`Failed to convert owner data: ${err.message}`);
  }
}

function convertToStateInterface(apiStat: BiliHomeFeedApiResponseStat | undefined): StateInterface | undefined {
  if (!apiStat) {
    return undefined;
  }

  try {
    if (apiStat.view === undefined || apiStat.like === undefined) {
      throw new Error("Stats data missing required view or like fields");
    }

    return {
      view: apiStat.view,
      like: apiStat.like
    };
  } catch (error) {
    const err = error as Error;
    throw new Error(`Failed to convert stats data: ${err.message}`);
  }
}

export interface VideoItem {
  aid: string;
  bvid: string;
  cid?: string;
  title: string;
  goto?: string;
  pic?: string;
  owner?: OwnerInterface;
  stat?: StateInterface;
  duration?: number | string;
  // 仅历史记录入口填充：观看进度（秒）与是否已看完。
  watchedSeconds?: number;
  watchFinished?: boolean;
}

interface StaticParams {
  web_location: string,
  y_num: string,
  fresh_type: string,
  feed_version: string,
  homepage_ver: string,
  ps: string,
  last_y_num: string,
  screen: string,
  seo_info: string,
}

interface DynamicParams {
  fresh_idx_1h: number;
  fresh_idx: number;
  brush: number;
  last_showlist: string;
}


@ObservedV2
class GetFeedVideosError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

// 分页相关状态类
@ObservedV2
export class BilibiliHomeFeedState {
  @Trace
  videoItems: VideoItem[] = [];
  @Trace
  isLoading: boolean = false;
  @Trace
  errorMessage: string = "";
  // 静态参数
  @Trace
  private staticParams: StaticParams = {
    web_location: "1430650",
    y_num: "4",
    fresh_type: "3",
    feed_version: "V8",
    homepage_ver: "1",
    ps: "10",
    last_y_num: "4",
    screen: "466-466", // 手表尺寸
    seo_info: "",
  };
  // 动态参数
  @Trace
  private dynamicParams: DynamicParams = {
    fresh_idx_1h: 0,
    fresh_idx: 0,
    brush: 0,
    last_showlist: ""
  };
  // 仅在华为推荐的时候需要用到
  @Trace
  private pn: number = 1
  // 已加载的视频ID
  @Trace
  private loadedVideos: string[] = [];

  private async getFeedVideos(biliService: BilibiliService | BilibiliServiceWithoutLogin): Promise<VideoItem[]> {
    // 更新动态参数
    if (this.dynamicParams.fresh_idx > 0) {
      this.dynamicParams.brush = (this.dynamicParams.brush as number) + 1;
    }

    this.dynamicParams.fresh_idx_1h = (this.dynamicParams.fresh_idx_1h as number) + 1;
    this.dynamicParams.fresh_idx = (this.dynamicParams.fresh_idx as number) + 1;

    // 构建URL参数
    let queryParams =
      `web_location=${this.staticParams.web_location}&y_num=${this.staticParams.y_num}&fresh_type=${this.staticParams.fresh_type}&feed_version=${this.staticParams.feed_version}&homepage_ver=${this.staticParams.homepage_ver}&ps=${this.staticParams.ps}&last_y_num=${this.staticParams.last_y_num}&screen=${this.staticParams.screen}&seo_info=${this.staticParams.seo_info}`;
    queryParams += `&fresh_idx_1h=${this.dynamicParams.fresh_idx_1h}&fresh_idx=${this.dynamicParams.fresh_idx}&brush=${this.dynamicParams.brush}&last_showlist=${this.dynamicParams.last_showlist}`;

    // 发起请求
    const data: BiliHomeFeedApiResponse = await biliService.getHomeFeed(queryParams)

    if (data.code === 0 && data.data && data.data.item) {
      const items = data.data.item;

      // 提取视频ID并更新last_showlist
      const newVideoIds: string[] = [];
      const newItems: VideoItem[] = [];

      for (const item of items) {
        // The business mapper already removed recognized placeholders and normalized IDs.
        const videoType = item.goto || 'av';
        newVideoIds.push(`${videoType}_${item.id}`);
        newItems.push({
          aid: item.id,
          bvid: item.bvid,
          cid: item.cid,
          title: item.title || "No Title",
          goto: item.goto,
          pic: item.pic,
          owner: convertToOwnerInterface(item.owner),
          stat: convertToStateInterface(item.stat),
          duration: item.duration
        });
      }

      // 将新视频ID添加到已加载列表中
      this.loadedVideos = [...this.loadedVideos, ...newVideoIds];

      // 更新last_showlist参数
      if (this.loadedVideos.length > 20) {
        // 按批次分组，每10个视频为一组
        const videoBatches: string[][] = [];
        for (let i = 0; i < this.loadedVideos.length; i += 10) {
          const endIndex = Math.min(i + 10, this.loadedVideos.length);
          const batch: string[] = [];
          for (let j = i; j < endIndex; j++) {
            batch.push(this.loadedVideos[j]);
          }
          videoBatches.push(batch);
        }

        // 将每组转换为字符串并用分号连接
        let lastShowlist: string = '';
        for (let i = 0; i < videoBatches.length; i++) {
          if (i > 0) {
            lastShowlist += ';';
          }
          lastShowlist += videoBatches[i].join(',');
        }
        this.dynamicParams.last_showlist = lastShowlist;
      } else {
        let lastShowlist: string = '';
        for (let i = 0; i < this.loadedVideos.length; i++) {
          if (i > 0) {
            lastShowlist += ',';
          }
          lastShowlist += this.loadedVideos[i];
        }
        this.dynamicParams.last_showlist = lastShowlist;
      }
      return newItems
    } else {
      throw new GetFeedVideosError("获取首页推荐视频失败：\n" + data.message || "未知错误")
    }
  }

  private getRandomNumberInRange(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  private shuffleArray<T>(array: T[]): T[] {
    const shuffled = array.slice(); // 复制数组，避免改原数组
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1)); // 随机选一个 0..i 之间的索引
      const temp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = temp; // 交换
    }
    return shuffled;
  }

  private async getFeedVideosHuawei(biliService: BilibiliService): Promise<VideoItem[]> {
    try {
      // 发起请求
      const videos: GetUPsVideosResponseDataListVlistItem[] = await biliService.getHomeFeedHuawei(this.pn)
      this.pn += 1
      return videos.map((item) => {
        const mappedItem: VideoItem = {
          aid: item.aid.toString(),
          bvid: item.bvid,
          title: item.title,
          pic: item.pic,
          owner: {
            name: item.author
          },
          stat: {
            view: this.getRandomNumberInRange(1000, 10000),
            like: this.getRandomNumberInRange(1, 1000)
          },
          duration: this.getRandomNumberInRange(1, 1000),
          cid: '0'
        }
        return mappedItem
      })
    } catch (error) {
      if (error instanceof GetUPsVideosError) {
        const typedError: GetUPsVideosError = error as GetUPsVideosError
        console.debug(logTag,
          "BilibiliHomeFeedState调用getFeedVideosHuawei时出现了Error：\n" + typedError.message)
        throw new GetFeedVideosError("获取华为终端推荐视频失败：\n" + typedError.message)
      } else {
        try {
          const businessError = error as BusinessError
          const businessErrorDescription: string =
            "Error name: " + businessError.name + "\n" + "Error message:" + businessError.message + "\n" +
              "Error stack:" + businessError.stack + "\n" + "Error code:" + businessError.code + "\n" +
              "Error data:" + businessError.data
          console.debug(logTag,
            "BilibiliHomeFeedState调用getFeedVideosHuawei时出现了BusinessError：\n" + businessErrorDescription)
          throw new GetFeedVideosError("获取华为终端推荐视频失败：\n" + businessErrorDescription)
        } catch (_) {
          console.debug(logTag,
            "BilibiliHomeFeedState调用getFeedVideosHuawei时出现了Error：\n" + error.message ?? JSON.stringify(error, null, 2))
          throw new GetFeedVideosError("获取华为终端推荐视频失败：\n" + error.message ?? JSON.stringify(error, null, 2))
        }
      }
    }

  }

  // 加载下一页
  async fetchNextPage(biliService: BilibiliService | BilibiliServiceWithoutLogin): Promise<void> {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';


    try {
      if (biliService instanceof BilibiliService) {
        // 已登录
        console.debug(logTag, "触发加载正常首页推荐视频")
        const newItems = await this.getFeedVideos(biliService)
        // 更新视频列表
        this.videoItems = [...this.videoItems, ...newItems];
      } else {
        // 未登录
        console.debug(logTag, "触发加载正常首页推荐视频")
        const newItems = await this.getFeedVideos(biliService)
        // 更新视频列表
        this.videoItems = [...this.videoItems, ...newItems];
      }
    } catch (error) {
      if (error instanceof GetHomeFeedError) {
        console.debug(logTag, "BilibiliHomeFeedState的fetchNextPage遇到了GetHomeFeedError")
        this.errorMessage = error.message;
      } else if (error instanceof GetFeedVideosError) {
        console.debug(logTag, "BilibiliHomeFeedState的fetchNextPage遇到了GetFeedVideosError")
        this.errorMessage = error.message;
      } else {
        try {
          const businessError = error as BusinessError
          const businessErrorDescription: string =
            "Error name: " + businessError.name + "\n" + "Error message:" + businessError.message + "\n" +
              "Error stack:" + businessError.stack + "\n" + "Error code:" + businessError.code + "\n" +
              "Error data:" + businessError.data
          console.debug(logTag,
            "BilibiliHomeFeedState的fetchNextPage遇到了BusinessError：\n" + businessErrorDescription)
          this.errorMessage = "获取首页推荐视频失败：\n" + businessErrorDescription
        } catch (_) {
          console.debug(logTag,
            "BilibiliHomeFeedState的fetchNextPage遇到了Error：\n" + error.message ?? JSON.stringify(error, null, 2))
          this.errorMessage = "获取首页推荐视频失败：\n" + error.message ?? JSON.stringify(error, null, 2)
        }
      }
    } finally {
      this.isLoading = false;
    }

  }

  // 重置并刷新
  refresh(biliService: BilibiliService | BilibiliServiceWithoutLogin): void {
    // 重置状态
    this.videoItems = [];
    this.loadedVideos = [];
    this.dynamicParams = {
      fresh_idx_1h: 0,
      fresh_idx: 0,
      brush: 0,
      last_showlist: ""
    };

    // 加载第一页
    this.fetchNextPage(biliService);
  }
}

// 主页面组件
@ComponentV2
export struct BilibiliHomeFeedView {
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack
  @Local private feedState: BilibiliHomeFeedState = new BilibiliHomeFeedState();
  @Local private scroller: Scroller = new Scroller();
  @Local private pageID: string = UUID()
  @Local private resumeItem: BiliHistoryItem | null = null;
  @Local private resumeDismissed: boolean = false;
  private resumeCardRequested: boolean = false;

  /**
   * 取观看历史里最近一条未看完、且未被本机关闭过的记录，作为首页顶部续播卡片。
   * 请求失败只降级为不显示卡片，不影响首页 feed。
   */
  private async loadResumeCard(): Promise<void> {
    if (this.resumeCardRequested) {
      return;
    }
    const service = this.biliService;
    if (!(service instanceof BilibiliService)) {
      return;
    }
    this.resumeCardRequested = true;
    try {
      const dismissedBvid = await this.readDismissedResumeBvid();
      const response = await service.getHistoryList();
      if (response.code !== 0 || response.data === undefined) {
        console.debug(`[BiliResumeCard] history unavailable code=${response.code} message=${response.message}`);
        return;
      }
      const list: BiliHistoryItem[] = response.data.list === undefined ? [] : response.data.list;
      let picked: BiliHistoryItem | null = null;
      for (let index = 0; index < list.length; index++) {
        const item = list[index];
        const history = item.history;
        const bvid = history === undefined ? '' : (history.bvid ?? '');
        if (bvid.length === 0 || bvid === dismissedBvid) {
          continue;
        }
        const progress = item.progress ?? 0;
        if (progress <= 0 || item.is_finish === 1) {
          continue;
        }
        const duration = item.duration ?? 0;
        if (duration > 0 && progress >= duration - 1) {
          continue;
        }
        picked = item;
        break;
      }
      this.resumeItem = picked;
      if (picked !== null) {
        const history = picked.history;
        const pickedBvid = history === undefined ? '' : (history.bvid ?? '');
        console.info(`[BiliResumeCard] loaded count=${list.length} bvid=${pickedBvid} ` +
          `progress=${picked.progress ?? 0} duration=${picked.duration ?? 0} ` +
          `viewAt=${picked.view_at ?? 0} finished=${picked.is_finish ?? -1} dismissed=${dismissedBvid}`);
      } else {
        console.info(`[BiliResumeCard] no eligible history count=${list.length} dismissed=${dismissedBvid}`);
      }
    } catch (error) {
      console.debug(`[BiliResumeCard] load failed: ${(error as Error).message || String(error)}`);
    }
  }

  private async readDismissedResumeBvid(): Promise<string> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const db = await AppDatabase.open(context);
      return await db.values.getString(StorageKeys.BILI_HOME_RESUME_CARD_DISMISSED_BVID, '');
    } catch (error) {
      console.debug(`[BiliResumeCard] read dismissed bvid failed: ${(error as Error).message || String(error)}`);
      return '';
    }
  }

  private async rememberDismissedResumeBvid(bvid: string): Promise<void> {
    if (bvid.length === 0) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const db = await AppDatabase.open(context);
      await db.values.setString(StorageKeys.BILI_HOME_RESUME_CARD_DISMISSED_BVID,
        StorageNamespaces.STATE, bvid);
      console.info(`[BiliResumeCard] dismissed bvid=${bvid}`);
    } catch (error) {
      console.debug(`[BiliResumeCard] persist dismissed bvid failed: ${(error as Error).message || String(error)}`);
    }
  }

  private closeResumeCard(): void {
    const item = this.resumeItem;
    const history = item === null ? undefined : item.history;
    const bvid = history === undefined ? '' : (history.bvid ?? '');
    this.resumeDismissed = true;
    this.rememberDismissedResumeBvid(bvid);
  }

  private continueResumeCard(): void {
    const item = this.resumeItem;
    if (item === null) {
      return;
    }
    const history = item.history;
    const bvid = history === undefined ? '' : (history.bvid ?? '');
    const service = this.biliService;
    if (bvid.length === 0 || !(service instanceof BilibiliService)) {
      return;
    }
    const resumeAt = item.progress ?? 0;
    const data: BiliVideoDetailPagePushData = {
      bvid: bvid,
      biliService: service,
      resumeAt: resumeAt
    };
    console.info(`[BiliResumeCard] continue bvid=${bvid} resumeAt=${resumeAt}`);
    this.pageInfos.pushPathByName('BiliVideoDetailPage', data);
  }

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
        BiliLoadingErrorView0()
          .transition(TransitionEffect.OPACITY.animation({ duration:300, curve:Curve.Smooth }))
      }
    }
    .width('100%')
    .height('100%')
    // 不铺底色，让 NavDestination 的顶部渐变透上来
    .onAppear(() => {
      // 组件挂载时加载第一页数据
      this.feedState.fetchNextPage(this.biliService);
      this.loadResumeCard();
    })

  }

  @Builder
  loadingView() {
    // 首次加载中的显示
    Column({ space: "15vp" }) {
      AnimatedProgressView({ color: DarkTheme.accents.biliHome })
        .width("50vp")
        .height("50vp")
      Text("正在加载")
        .fontColor(DarkTheme.accents.biliHome)
        .fontWeight(FontWeight.Bold)
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    // 不铺底色，让 NavDestination 上哔哩哔哩首页的蓝渐变透出来
  }

  @Builder
  videoList() {
    Stack({ alignContent: Alignment.Top }) {
      List({ space: 8, scroller: this.scroller }) {
        if (this.resumeItem !== null && !this.resumeDismissed) {
          ListItem() {
            BiliResumeCard({
              item: this.resumeItem,
              onClose: () => {
                this.closeResumeCard()
              },
              onContinue: () => {
                this.continueResumeCard()
              }
            })
          }
          .padding({ left: 16, right: 16 })
          .width('100%')
        }

        ForEach(this.feedState.videoItems, (item: VideoItem) => {
          ListItem() {
            HomeFeedVideoCard({
              item: item,
              biliService: this.biliService,
              pageInfos: this.pageInfos
            })
          }
          .padding({ left: 16, right: 16 })
          .width('100%')
        })

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
          } else {
            Button('加载更多')
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
      .contentStartOffset(48)
      .contentEndOffset(25)
      .listDirection(Axis.Vertical)
      // 到达底部时自动加载更多
      .onReachEnd(() => {
        if (!this.feedState.isLoading) {
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
          requestFocusWithRetry(this.getUIContext(), this.pageID + "10ceee42-9162-4c19-9c07-54e2dd9c77a8")
        } catch (error) {
          console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
        }
      })
      .id(this.pageID + "10ceee42-9162-4c19-9c07-54e2dd9c77a8")
      .width("100%")
      .height("100%")

      ArcScrollBar({ scroller: this.scroller })
      MoreMenu({
        feedState: this.feedState,
        biliService: this.biliService,
        pageInfos: this.pageInfos,
      })
    }
  }
}


@ComponentV2
struct MoreMenu {
  @Param @Require feedState: BilibiliHomeFeedState
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack

  build() {
    Button({ type: ButtonType.Normal, role: ButtonRole.NORMAL, buttonStyle: ButtonStyleMode.NORMAL }) {
      Text("更多")
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
      this.pageInfos.removeByName("BiliStackWidgetPage")
      const pushData: BiliStackWidgetPushData = {
        service: this.biliService as BilibiliService,
        loggedIn: !(this.biliService instanceof BilibiliServiceWithoutLogin)
      }
      this.pageInfos.pushPathByName("BiliStackWidgetPage", pushData)
    })
    .width("100%")
  }
}
