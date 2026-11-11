import { BiliImageDownsizer } from "../../common/BiliImageDownSizer";
import { BilibiliService } from "../../common/BiliService";
import { ErrorPrompt, ErrorPromptData } from "../../components/ErrorPages";
import { ArcScrollBar } from "@kit.ArkUI";
import { VideoPlayingPagePushData } from "../BiliVideoPlayer/BiliVideoPlayerPage";
import { RelatedVideosViewDataSource } from "./BiliRelatedVideosLazyLoading";
import { ShareVideoPagePushData } from "./ShareVideoPage";
import { BiliLikeView, BiliLikeViewModel } from "./BiliLikeView";
import { BiliCoinView, BiliCoinViewModel } from "./BiliCoinView";
import { BiliViewCount } from "./BiliViewCount";
import { BiliFavoriteView, BiliFavoriteViewModel } from "./BiliFavoriteView";
import { logTag } from "../../common/printLog";
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { UUID } from "../../common/UUID";

import { BiliDetailResponse as BiliVideoDetailApiResponse, BiliDetailVideo as VideoData,
  BiliRelatedVideo as ApiResponseRelatedData } from '../../common/bili/schema/BiliModels.generated';
import { JsonDecodeError } from '../../common/jsonschema/JsonDecode';
import { DarkTheme } from '../../common/Theme';
export { BiliVideoDetailApiResponse, ApiResponseRelatedData };

export interface BiliVideoDetailPagePushData {
  bvid: string
  biliService: BilibiliService
  // 历史/续播入口传入的观看进度（秒），普通入口不传。
  resumeAt?: number
}

@Builder
export function BiliVideoDetailPageBuilder(_name: string, param: BiliVideoDetailPagePushData) {
  BiliVideoDetailPage({
    bvid: (param as BiliVideoDetailPagePushData).bvid,
    biliService: (param as BiliVideoDetailPagePushData).biliService,
    resumeAt: (param as BiliVideoDetailPagePushData).resumeAt ?? 0
  })
}

@ObservedV2
class BiliVideoDetailPageViewModel {
  @Trace
  biliService: BilibiliService
  @Trace
  error0: ErrorPromptData | null = null
  @Trace
  videoData: VideoData | null = null;
  @Trace
  relatedVideos: Array<ApiResponseRelatedData> | null = null;
  @Trace
  showCoverLargeImage: boolean = false
  @Trace
  isRefreshing: boolean = false
  @Trace
  likeVM: BiliLikeViewModel
  @Trace
  coinVM: BiliCoinViewModel
  @Trace
  favoriteVM: BiliFavoriteViewModel
  readonly component: CustomComponent

  constructor(biliService: BilibiliService, component: CustomComponent) {
    this.biliService = biliService
    this.component = component
    this.likeVM = new BiliLikeViewModel(biliService, this.component)
    this.coinVM = new BiliCoinViewModel(biliService)
    this.favoriteVM = new BiliFavoriteViewModel(biliService)
  }

  async fetchVideoDetails(bvid: string) {
    this.error0 = null;

    try {
      const response = await this.biliService.getVideoDetails(bvid);
      if (response.code === 0) {
        const viewData = response.data.View;
        this.videoData = viewData;
        this.relatedVideos = response.data.Related?.slice(0, 15) ?? [];
      } else {
        this.error0 = { errorCode: "404-14", errorMessage: "加载详情出错，请检查网络" };
      }
    } catch (error) {
      if (error instanceof JsonDecodeError) { console.warn(error.message); }
      this.error0 = { errorCode: "404-15", errorMessage: "加载详情出错，请检查网络" };
    }
  }
}

@ComponentV2
struct BiliVideoDetailPage {
  @Param @Require bvid: string
  @Param @Require biliService: BilibiliService
  @Param resumeAt: number = 0
  @Local vm: BiliVideoDetailPageViewModel = new BiliVideoDetailPageViewModel(this.biliService, this)
  pageInfos: NavPathStack | null = null
  // 控制分享菜单显示
  @Local isShareMenuOpen: boolean = false
  @Local private scroller: Scroller = new Scroller()
  @Local private relatedVideoListScroller: Scroller = new Scroller()
  @Local private focusOnRelevantRecommendArea: boolean = false
  @Local
  private focusThisPage: boolean = true
  // 在导航堆栈中的多个视频详情页有各自的命名空间
  @Local
  private pageID: string = UUID()

  @Computed
  private get showFloatingButton(): boolean {
    return !this.focusOnRelevantRecommendArea
  }

  aboutToAppear() {
    // 获取视频详情
    this.vm.fetchVideoDetails(this.bvid);
  }

  // 定义圆形头像组件
  @Builder
  AvatarCircle(face: string, name: string) {
    Stack() {
      AvatarWithTransition({ originImageSrc: face })

      Text(name[0].toUpperCase())
        .fontSize(20)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor('#333333')
        .opacity(this.urlError(face) ? 1 : 0)
    }
    .width(50)
    .height(50)
  }

  // 判断URL是否加载失败
  urlError(url: string): boolean {
    // 简单判断：如果URL为空或无效则显示文字头像
    return !url || url.length < 5;
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

  // 格式化时长（将秒转为mm:ss格式）
  formatDuration(seconds: number): string {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  // 格式化日期（将时间戳转为可读格式）
  formatDate(timestamp: number): string {
    const date = new Date(timestamp * 1000);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate()
      .toString()
      .padStart(2, '0')}`;
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景色
        Column() {
        }
        .backgroundColor('#121212')
        .width('100%')
        .height('100%')

        // 加载中或错误状态
        if (!this.vm.videoData && this.vm.error0 === null) {
          Column({ space: "30px" }) {
            AnimatedProgressView({ color: DarkTheme.biliPink })
              .width(50)
              .height(50)
            Text("加载中")
              .fontColor(DarkTheme.biliPink)
              .fontWeight(FontWeight.Bold)
          }
          .justifyContent(FlexAlign.Center)
          .width("100%")
          .height("100%")
          .backgroundColor(Color.Black)
          // 渐隐
          .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,
            TransitionEffect.OPACITY.animation({ duration: 300 })))
        } else if (this.vm.error0 !== null) {
          ErrorPrompt({
            errorCode: this.vm.error0.errorCode,
            errorMessage: this.vm.error0.errorMessage,
            showCloseButton: false,
            showRetryButton: true,
            onRetry: () => {
              this.vm.fetchVideoDetails(this.bvid);
            }
          })
            .transition(TransitionEffect.OPACITY.animation({}))
        } else if (this.vm.videoData) {
          Stack() {
            Stack({ alignContent: Alignment.Center }) {
              // 视频内容展示
              Refresh({ refreshing: $$this.vm.isRefreshing, builder: this.pullAreaContent() }) {
                Scroll(this.scroller) {
                  Column() {
                    // 视频封面区域
                    Stack({ alignContent: Alignment.BottomStart }) {
                      VideoCoverWithTransition({ originImageSrc: this.vm.videoData.pic })
                        .onClick(() => {
                          this.getUIContext().animateTo({
                            duration: 350,
                            curve: Curve.Friction
                          }, () => {
                            this.vm.showCoverLargeImage = true
                          })
                        })
                        .geometryTransition("CoverImage", { follow: true })

                      // 视频时长标签
                      Text(this.formatDuration(this.vm.videoData.duration))
                        .fontSize(12)
                        .fontColor(Color.White)
                        .backgroundColor('rgba(0, 0, 0, 0.6)')
                        .borderRadius(10)
                        .padding({
                          left: 6,
                          right: 6,
                          top: 2,
                          bottom: 2
                        })
                        .margin(10)
                    }
                    .width('100%')

                    // 视频标题和信息
                    Column() {
                      Column() {
                        Text(this.vm.videoData.title)
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .margin({ top: 10, bottom: 10 })

                        // 用户信息行
                        Row() {
                          // 头像
                          this.AvatarCircle(this.vm.videoData.owner.face, this.vm.videoData.owner.name)

                          Column() {
                            Text(this.vm.videoData.owner.name)
                              .fontSize(14)
                              .fontColor(Color.White)
                              .margin({ bottom: 2 })

                            Text(this.formatDate(this.vm.videoData.pubdate))
                              .fontSize(12)
                              .fontColor('#AAAAAA')
                          }
                          .alignItems(HorizontalAlign.Start)
                          .margin({ left: 10 })
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .alignItems(VerticalAlign.Center)
                        .margin({ bottom: 15 })

                        // 视频统计数据
                        Row() {
                          // 观看数
                          BiliViewCount({ view: this.vm.videoData.stat.view })

                          // 点赞数
                          BiliLikeView({
                            bvid: this.vm.videoData.bvid,
                            vm: this.vm.likeVM,
                            likeCount: this.vm.videoData.stat.like
                          })

                          // 投币数
                          BiliCoinView({
                            bvid: this.vm.videoData.bvid,
                            vm: this.vm.coinVM,
                            pageInfos: this.pageInfos,
                            coinCount: this.vm.videoData.stat.coin
                          })

                          // 收藏数
                          BiliFavoriteView({
                            bvid: this.vm.videoData.bvid,
                            avid: this.vm.videoData.aid,
                            vm: this.vm.favoriteVM,
                            pageInfos: this.pageInfos,
                            favoriteCount: this.vm.videoData.stat.favorite
                          })
                        }
                        .width('100%')
                        .padding({ top: 10, bottom: 10 })
                        .borderRadius(16)
                        .backgroundColor('#1E1E1E')

                        // 水平简介
                        if (this.vm.videoData.desc) {
                          Text(this.vm.videoData.desc)
                            .fontSize(14)
                            .fontColor('#DDDDDD')
                            .textAlign(TextAlign.Start)
                            .margin({ top: 15, bottom: 15 })
                            .width('100%')
                        }

                      }
                      .padding({ left: 15, right: 15 })

                      // 相关视频标题
                      if (this.vm.relatedVideos && this.vm.relatedVideos.length > 0) {
                        Text('相关推荐')
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                          .width('100%')
                          .margin({ top: 10, bottom: 15 })

                        // 相关视频列表
                        RelatedVideosView({
                          relatedVideos: this.vm.relatedVideos,
                          relatedVideoListScroller: this.relatedVideoListScroller,
                          pageInfos: this.pageInfos,
                          biliService: this.biliService,
                          pageID: this.pageID
                        })
                        // 确保滚动到相关推荐区域的时候，不限制Floating按钮
                          .onVisibleAreaChange([0.0], (isVisible: boolean, currentRatio: number) => {
                            if (!isVisible && currentRatio <= 0.0) {
                              console.debug(logTag, "不可见了")
                              this.focusOnRelevantRecommendArea = false
                            } else {
                              console.debug(logTag, "可见了")
                              this.focusOnRelevantRecommendArea = true
                            }
                          })
                          .onVisibleAreaChange([0.9], (isVisible: boolean, currentRatio: number) => {
                            // 表冠聚焦到列表
                            if (isVisible && currentRatio >= 0.9) {
                              console.debug(logTag, "几乎完全可见了")
                              if (this.focusThisPage) {
                                try {
                                  console.debug(logTag, "表冠聚焦到列表")
                                  this.getUIContext()
                                    .getFocusController()
                                    .requestFocus(this.pageID + "f6a74819-84e8-48a4-8003-4df0962604f6")
                                } catch (error) {
                                  console.debug(logTag,
                                    'requestFocus failed code is ' + error.code + ' message is ' + error.message)
                                }
                              }
                            } else {
                              // 表冠聚焦到Scroll
                              console.debug(logTag, "并不是完全可见了")
                              if (this.focusThisPage) {
                                console.debug(logTag, "表冠聚焦到Scroll-0")
                                try {
                                  this.getUIContext()
                                    .getFocusController()
                                    .requestFocus(this.pageID + "9f6f86bc-720b-4314-8966-5db6c277f0d4")
                                } catch (error) {
                                  console.debug(logTag,
                                    'requestFocus failed code is ' + error.code + ' message is ' + error.message)
                                }
                              }
                            }
                          })
                      }
                    }
                    .width('100%')
                  }
                  .width('100%')
                }
                // 会在ArcScrollBar单独显示ScrollBar
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                // 支持表冠
                .focusable(true)
                .focusOnTouch(true)
                .defaultFocus(true)
                .onAppear(() => {
                  if (this.focusThisPage) {
                    try {
                      console.debug(logTag, "表冠聚焦到Scroll-1")
                      this.getUIContext()
                        .getFocusController()
                        .requestFocus(this.pageID + "9f6f86bc-720b-4314-8966-5db6c277f0d4")
                    } catch (error) {
                      console.debug(logTag,
                        'requestFocus failed code is ' + error.code + ' message is ' + error.message)
                    }
                  }
                })
                .id(this.pageID + "9f6f86bc-720b-4314-8966-5db6c277f0d4")
              }
              .width('100%')
              .height('100%')
              .onRefreshing(() => {
                this.getUIContext().animateTo({
                  duration: 350,
                  curve: Curve.Friction
                }, () => {
                  this.vm.showCoverLargeImage = true
                })
              })

              // 如果在上半区域，显示上半区域的滚动条，如果显示在相关推荐区域，显示相关推荐区域的滚动条
              ArcScrollBar({
                scroller: this.focusOnRelevantRecommendArea ? this.relatedVideoListScroller : this.scroller,
                state: BarState.Auto
              })
            }

            // 底部操作栏（固定在底部）
            this.bottomFloatBar()
          }
          // 渐显
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        }
      }
      .width('100%')
      .height('100%')
      .bindContentCover(this.vm.showCoverLargeImage,
        this.coverImageLarge(), { modalTransition: ModalTransition.NONE })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => {
      console.debug(logTag, "onShown" + this.bvid)
      this.focusThisPage = true
    })
    .onHidden(() => {
      console.debug(logTag, "onHidden" + this.bvid)
      this.focusThisPage = false
    })
  }

  @Builder
  bottomFloatBar() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: "5fp" }) {
        Button() {
          Image($r("app.media.bili_video_detail_page_play_button"))
            .objectFit(ImageFit.Cover)
            .width("24fp")
            .height("24fp")

        }
        .width("45fp")
        .height("45fp")
        .borderRadius("22.5fp")
        .backgroundColor(DarkTheme.biliPink)
        .stateEffect(true)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          if ((this.vm.videoData !== null) && (this.pageInfos !== null)) {
            const data: VideoPlayingPagePushData = {
              videoID: {
                bvid: this.vm.videoData.bvid,
                cid: this.vm.videoData.cid.toString()
              },
              biliService: this.biliService,
              resumeAt: this.resumeAt
            }
            console.info(`[BiliVideoDetail] play bvid=${this.vm.videoData.bvid} resumeAt=${this.resumeAt}`)
            this.pageInfos.pushPathByName("BiliVideoPlayerPage", data)
          } else {
            this.getUIContext().getPromptAction().showToast({ message: "视频播放失败" })
          }
        })

        // 分享按钮
        Button() {
          Image($r("app.media.bili_video_detail_page_share_button"))
            .objectFit(ImageFit.Cover)
            .width("24fp")
            .height("24fp")

        }
        .width("45fp")
        .height("45fp")
        .borderRadius("22.5fp")
        .backgroundColor(DarkTheme.biliPink)
        .stateEffect(true)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.isShareMenuOpen = true;
          if (this.pageInfos !== null) {
            if (this.vm.videoData !== null) {
              const data: ShareVideoPagePushData = {
                bvid: this.vm.videoData.bvid,
              }
              this.pageInfos.pushPathByName("ShareVideoPage", data)
            } else {
              this.getUIContext().getPromptAction().showToast({ message: '404-16' });
            }
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '404-15' });
          }
        })
      }
      .height("60fp")
      .padding({ left: "10fp", right: "10fp" })
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: "5fp" })
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius("30fp")
    }
    .hitTestBehavior(HitTestMode.None)
    .width("100%")
    .height("100%")
    .visibility(this.showFloatingButton ? Visibility.Visible : Visibility.Hidden)
    .animation({ duration: 300, curve: Curve.Smooth })
  }

  @Builder
  pullAreaContent() {
    Column() {

    }
    .width("100%")
    // 设置最小高度约束保证自定义组件高度随下拉区域高度变化时自定义组件高度不会低于minHeight
    .height("32fp")
  }

  @Builder
  coverImageLarge() {
    Column({ space: 20 }) {
      if (this.vm.videoData !== null) {
        VideoCoverLarge({ originImageSrc: this.vm.videoData.pic })
        // 头像配置共享元素效果，与点击的头像的id匹配
          .geometryTransition("CoverImage")
      } else {
        LoadingProgress()
          .color(DarkTheme.primary)
          .width(50)
          .height(50)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.getUIContext().animateTo({
        duration: 350,
        curve: Curve.Friction
      }, () => {
        this.vm.isRefreshing = false
        this.vm.showCoverLargeImage = false
      });
    })
    .transition(TransitionEffect.OPACITY)
  }
}

@ComponentV2
struct RelatedVideosView {
  @Param @Require relatedVideos: ApiResponseRelatedData[]
  @Param @Require relatedVideoListScroller: Scroller
  @Param @Require pageInfos: NavPathStack | null = null
  @Param @Require biliService: BilibiliService
  @Param @Require pageID: string
  @Local private lazyDataSource: RelatedVideosViewDataSource = new RelatedVideosViewDataSource();

  aboutToAppear(): void {
    this.lazyDataSource.updateAllData(this.relatedVideos)
  }

  build() {
    List({ space: "10fp", scroller: this.relatedVideoListScroller }) {
      LazyForEach(this.lazyDataSource, (item: ApiResponseRelatedData) => {
        ListItem() {
          Column() {
            Column() {
              Stack() {
                RelatedVideosCoverWithTransition({ originImageSrc: item.pic })

                // 视频时长
                Text(this.formatDuration(item.duration))
                  .fontSize(12)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(0, 0, 0, 0.6)')
                  .borderRadius(10)
                  .padding({
                    left: 6,
                    right: 6,
                    top: 2,
                    bottom: 2
                  })
                  .position({ x: 5, y: 5 })
              }
              .width('100%')
              .height(100)

              // 视频标题
              Text(item.title)
                .fontSize(14)
                .fontColor(Color.White)
                .maxLines(2)
                .textAlign(TextAlign.Start)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 5, bottom: 5 })

              // UP主名称和播放量
              Row() {
                Text(item.owner.name)
                  .fontSize(12)
                  .fontColor('#AAAAAA')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Blank()
                Row() {
                  Image($r("app.media.bili_video_detail_page_watch_count"))
                    .objectFit(ImageFit.Cover)
                    .width("14fp")
                    .height("14pfp")
                  Text(this.formatNumber(item.stat.view))
                    .fontSize(12)
                    .fontColor('#AAAAAA')
                    .margin({ left: 3 })
                }
              }
              .width('100%')
            }
            .backgroundColor('#1E1E1E')
            .borderRadius(12)
            .padding(10)
            .width('100%')
          }
          // 左右留白
          .padding({ left: 15, right: 15 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            // 点击跳转到相关视频
            if (this.pageInfos !== null) {
              const data: BiliVideoDetailPagePushData = {
                bvid: item.bvid,
                biliService: this.biliService
              }
              this.pageInfos.pushPathByName("BiliVideoDetailPage", data)
            } else {
              this.getUIContext().getPromptAction().showToast({ message: "打开相关视频失败" })
            }
          })
        }
        .onAppear(() => {
          // 通过onAppear记录组件创建的次数
          console.debug("🚩appear:" + item.bvid)
        })
      })
    }
    // 效果
    .chainAnimation(true)
    // 底部安全区
    .contentEndOffset(70)
    .cachedCount(5)
    // 向下滑的时候，因为外部Scroll已经在底部了，所以总是滑得动内部List。向上滑的时候，因为内部List已经在顶部了，可以滑动外部Scroll。
    .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    // 会在ArcScrollBar单独显示ScrollBar
    .scrollBar(BarState.Off)
    .id(this.pageID + "f6a74819-84e8-48a4-8003-4df0962604f6")
    .height($r('app.float.watch_screen_size_fp'))
    .width($r('app.float.watch_screen_size_fp'))
  }

  // 格式化时长（将秒转为mm:ss格式）
  formatDuration(seconds: number): string {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  // 格式化数字（将大数字转为K/M格式）
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

@ComponentV2
struct VideoCoverWithTransition {
  @Param @Require originImageSrc: string

  @Computed
  get downSampledImageSrc(): string {
    return BiliImageDownsizer.transformBilibiliImageUrl(this.originImageSrc, 375, 210)
  }

  @Local private imageOpacity: number = 0.0

  aboutToAppear(): void {
    console.debug(logTag, "[mark:0]正在请求视频封面：" + this.downSampledImageSrc)
  }

  build() {
    Image(this.downSampledImageSrc)
      .objectFit(ImageFit.Cover)
      .width('100%')
      .aspectRatio(16 / 9)
      .opacity(this.imageOpacity)
      .onComplete(() => {
        this.getUIContext().animateTo({
          curve: Curve.EaseOut,
          duration: 300
        }, () => {
          this.imageOpacity = 1
        })
      })
  }
}


@ComponentV2
struct VideoCoverLarge {
  @Param @Require originImageSrc: string

  @Computed
  get downSampledImageSrc(): string {
    return BiliImageDownsizer.transformBilibiliImageUrl(this.originImageSrc, 375, 210)
  }

  @Local private imageOpacity: number = 0.0

  build() {
    Image(this.downSampledImageSrc)
      .objectFit(ImageFit.Cover)
      .width('100%')
      .aspectRatio(16 / 9)
      .opacity(this.imageOpacity)
      .onComplete(() => {
        this.getUIContext().animateTo({
          curve: Curve.EaseOut,
          duration: 300
        }, () => {
          this.imageOpacity = 1
        })
      })
  }
}


@ComponentV2
struct AvatarWithTransition {
  @Param @Require originImageSrc: string

  @Computed
  get downSampledImageSrc(): string {
    return BiliImageDownsizer.transformBilibiliImageUrl(this.originImageSrc, 56, 56)
  }

  @Local private imageOpacity: number = 0.0

  build() {
    Image(this.downSampledImageSrc)
      .width(50)
      .height(50)
      .opacity(this.imageOpacity)
      .onComplete(() => {
        this.getUIContext().animateTo({
          curve: Curve.EaseOut
        }, () => {
          this.imageOpacity = 1
        })
      })
      .backgroundColor('#333333')
      .borderRadius(25)
  }
}

@ComponentV2
struct RelatedVideosCoverWithTransition {
  @Param @Require originImageSrc: string

  @Computed
  get downSampledImageSrc(): string {
    return BiliImageDownsizer.transformBilibiliImageUrl(this.originImageSrc, 336, 190)
  }

  @Local private imageOpacity: number = 0.0

  build() {
    Image(this.downSampledImageSrc)
      .width('100%')
      .height(100)
      .borderRadius(10)
      .objectFit(ImageFit.Cover)
      .opacity(this.imageOpacity)
      .onComplete(() => {
        this.getUIContext().animateTo({
          curve: Curve.EaseOut
        }, () => {
          this.imageOpacity = 1
        })
      })

  }
}