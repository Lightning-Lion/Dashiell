import { webview } from '@kit.ArkWeb';
import { logTag } from '../../common/printLog';
import { Task } from '../../common/sleep';
import { UUID } from '../../common/UUID';
import { ErrorPrompt } from '../../components/ErrorPages';
import { http } from '@kit.NetworkKit';
import { DouyinResponseDecoder } from '../../common/douyin/DouyinResponseDecoder';
import { DouyinFeedMapping } from '../../common/douyin/DouyinFeedMapping';
import { DeviceMgr } from '../../common/AlwaysOn';
import { DouYinLoadingErrorView0 } from '../../components/ErrorPages';
import { DouYinCardListModel, DouYinCardListModelCache } from './DouYinCardListModel';
import { common } from '@kit.AbilityKit';
import { DarkTheme } from '../../common/Theme';

// 传递给上层
@ObservedV2
export class CookieStringPack {
  @Trace
  cookieAndVideos: CookieAndVideos | null = null
}

@ObservedV2
export class CookieAndVideos {
  @Trace
  cookieString: string
  @Trace
  recommendVideos:Array<string>
  constructor(cookieString: string,recommendVideos:Array<string>) {
    this.cookieString = cookieString
    this.recommendVideos = recommendVideos
  }
}

enum CookieStatus {
  LOADING,
  SUCCESS,
  ERROR
}


@ObservedV2
export class DouYinIsLoggedInData {
  @Trace
  public isLoggedIn: boolean = false;

  constructor(defaultValue: boolean) {
    this.isLoggedIn = defaultValue
  }
}

/**
 * BiliGetCookieView的ViewModel
 */
@ObservedV2
class BiliGetCookieViewModel {
  @Trace
  isLoggedInPack: DouYinIsLoggedInData = new DouYinIsLoggedInData(false)
  @Trace
  cookieStringPack: CookieStringPack
  private domain: string = '.bilibili.com'

  @Monitor("isLoggedInPack.isLoggedIn")
  fetchCookieStringAfterDoneLogin(monitor: IMonitor) {
    if (this.isLoggedInPack.isLoggedIn === true) {
      console.debug("🚩观察到用户已完成登录")
      // 页面获取Cookie
      this.getCookiesForDomain(this.domain);
    }
  }

  status: CookieStatus = CookieStatus.LOADING
  errorMessage: string = ''
  errorCode: string = ''
  showErrorPrompt: boolean = false

  constructor(cookieStringPack: CookieStringPack) {
    this.cookieStringPack = cookieStringPack
  }

  /**
   * 获取指定域名的Cookie字符串
   *
   * @param domain 要获取Cookie的域名（例如：".bilibili.com"）
   * @returns Promise<void> 成功时resolve，失败时reject
   */
  async getCookiesForDomain(domain: string): Promise<void> {
    console.debug(`Attempting to get cookies for domain: ${domain}`);
    this.status = CookieStatus.LOADING;

    try {
      if (!domain) {
        throw new Error("Domain cannot be empty.");
      }

      // 使用WebCookieManager获取所有cookie
      const cookieManager = webview.WebCookieManager;
      const cookieString = await cookieManager.fetchCookie(domain);
      console.debug("Douyin Cookie read completed");
      // this.cookieStringPack.cookieString = cookieString;
      this.status = CookieStatus.SUCCESS;
    } catch (error) {
      console.debug(`🚩Failed to get cookies for domain ${domain}:`, error);
      this.status = CookieStatus.ERROR;

      // 处理错误
      this.errorMessage = "Cookie获取失败";
      this.errorCode = "404-2";
      this.showErrorPrompt = true;
    }
  }

  /**
   * 关闭错误提示
   */
  closeErrorPrompt(): void {
    this.showErrorPrompt = false;
  }
}

/**
 * BiliGetCookieView组件
 * 用于获取Bilibili网站的Cookie并传递给外部
 */

@ComponentV2
export struct DouYinGetCookieView {
  @Param @Require
  cookieStringPack: CookieStringPack
  @Local
  vm: BiliGetCookieViewModel = new BiliGetCookieViewModel(this.cookieStringPack)

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
      }
      .width('100%')
      .height('100%')

      // 错误提示弹窗
      if (this.vm.showErrorPrompt) {
        ErrorPrompt({
          errorMessage: this.vm.errorMessage,
          errorCode: this.vm.errorCode,
          showRetryButton: false,
          showCloseButton: true,
          onClose: () => {
            this.vm.closeErrorPrompt();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

@ObservedV2
class DouYinWebPageModel {
  @Trace
  loadingProgress:number = 5 // 0-100
  @Trace
  networkError:boolean = false
  httpRequest = http.createHttp();
  needInit: boolean = true
  controllerInner: webview.WebviewController = new webview.WebviewController();
  // 外界别急着用，可能还没Attach到Web组件，用了会抛错
  // 也可能网页关闭了，强行用会The WebviewController must be associated with a Web component
  controller: webview.WebviewController | null = null
  currentLoadingTaskID: string | null = null
  private readonly component: CustomComponent

  constructor(component: CustomComponent) {
    this.component = component
  }

  showLoading(seconds: number, pageInfos: NavPathStack | null) {
    (async () => {
      if (pageInfos === null) {
        this.component.getUIContext().getPromptAction().showToast({ message: "出错了（0x46A1）" })
        return
      }
      if (this.currentLoadingTaskID === null) {
        pageInfos.pushPathByName("DouYinLoadingFullScreenCover", undefined)
      } else {
        // 先前的加载还在屏幕上，我可以复用，我一会儿正常移除加载就行（我会通过更新currentLoadingTaskID来告诉先前的加载任务不用移除了，我会负责移除）
      }
      const myLoadingTaskID = UUID()
      this.currentLoadingTaskID = myLoadingTaskID
      await Task.sleep(seconds)
      if (this.currentLoadingTaskID === myLoadingTaskID) {
        pageInfos.removeByName("DouYinLoadingFullScreenCover")
      } else {
        // 别的任务取代我了，它会负责移除加载的
      }
    })()
  }

  async getResponse(event: OnInterceptRequestEvent): Promise<http.HttpResponse> {
    const url = event.request.getRequestUrl()
    console.debug(logTag, "拦截到 feed 请求 path=" + url.split('?')[0])
    const actualHeader:Record<string, string> = {

    }
    // 请求头必须逐字复刻网页侧的写法，否则服务端会拒掉：onInterceptRequest 给的 headerKey
    // 大小写和网页实际发出的并不一致，下面两个分支就是把 WebView 的键名归一回网页的写法
    // （Accept / Content-Type / Sec-Ch-Ua* / Uifid / X-Secsdk-Csrf-Token 转小写，
    //  Referer / Referrer-Policy / Cookie 转首字母大写）。
    const webViewHeader = event.request.getRequestHeader()
    webViewHeader.forEach((header) => {
      const key = header.headerKey
      // 保持正确的大小写
      if (["Accept", "Content-Type", "Sec-Ch-Ua", "Sec-Ch-Ua-Mobile", "Sec-Ch-Ua-Platform", "Uifid", "X-Secsdk-Csrf-Token"].includes(key)) {
        // 转小写
        actualHeader[key.toLowerCase()] = header.headerValue
      } else if (["referer","referrer-policy","cookie"].includes(key)) {
        // 转大写
        actualHeader[key.replace(/\b\w/g, (match) => match.toUpperCase())] = header.headerValue
      } else {
        actualHeader[key] = header.headerValue
      }
    })
    // 手动添加两个
    actualHeader["Referer"] = "https://www.douyin.com/jingxuan"
    actualHeader["Referrer-Policy"] = "strict-origin-when-cross-origin"
    console.debug(logTag, "开始请求 path=" + url.split('?')[0])
    const response0: Promise<http.HttpResponse> = (this.httpRequest.request(
      url,
      {
        method: http.RequestMethod.POST,
        header: actualHeader,
        extraData:null,
        connectTimeout: 6000,
        readTimeout: 10000
      }
    ))
    const response = await response0
    console.debug(logTag,"请求完成")
    return response
  }
  extractData(jsonString:string):DouYinRecommandAwemeData {
    return DouyinFeedMapping.items(DouyinResponseDecoder.parseWebFeed(jsonString).items);
  }
}



/**
 * 视频播放地址对象接口
 * 包含不同编码/清晰度的视频播放URL列表
 */
export interface DouYinRecommandVideoPlayAddr {
  /** 视频播放地址列表 */
  url_list: string[];
}

/**
 * 视频信息对象接口
 * 包含不同类型的播放地址
 */
export interface DouYinRecommandVideoInfo {
  /** H264编码的视频播放地址 */
  play_addr_h264: DouYinRecommandVideoPlayAddr;
  /** 标准视频播放地址 */
  play_addr: DouYinRecommandVideoPlayAddr;
  /** 低码率视频播放地址 */
  play_addr_lowbr: DouYinRecommandVideoPlayAddr;
  /** H265编码的视频播放地址 */
  play_addr_265: DouYinRecommandVideoPlayAddr;
}

/**
 * 单条视频信息接口
 * 包含该视频的信息
 */
export interface DouYinRecommandAwemeItem {
  // awemeID
  aweme_id:string
  // 视频下面的简介
  preview_title:string
  desc?: string
  /** 播放链接信息 */
  video: DouYinRecommandVideoInfo;
}

/**
 * 根数据接口
 * 包含视频列表的顶层结构
 */
export interface DouYinRecommandAwemeData {
  /** 抖音视频列表 */
  aweme_list: DouYinRecommandAwemeItem[];
}


export class DouYinURL {
  static
  webPageURL = "https://www.douyin.com/jingxuan?from_nav=1"
}

@ComponentV2
export struct DouYinGetCookieWebView {
  @Param @Require pageInfos: NavPathStack | null
  @Param @Require videoListMod:DouYinCardListModel
  @Local
  private vm: DouYinWebPageModel = new DouYinWebPageModel(this)
  private viewportTimer: number | undefined = undefined

  @Local
  private cacheMod:DouYinCardListModelCache = new DouYinCardListModelCache()
  @Computed
  get showPlayer():boolean {
    return this.videoListMod.cardList !== null
  }
  @Computed
  get showLoadingCover():boolean {
    if (this.showPlayer) {
      return false
    } else if (this.vm.networkError) {
      return false
    } else {
      return true
    }
  }

  @Local
  private progressUpdateStarted:boolean = false
  private progressTimer: number | undefined = undefined

  @Computed
  get updateProgress():void {
    if (this.showLoadingCover) {
      if (this.progressUpdateStarted === false) {
        this.progressUpdateStarted = true
        const min = 0
        const max = 100
        // 起始值
        const start = 5
        const startDate = Date.now()
        const speed = (max - start) / 60 // 60秒进度条走满
        this.progressTimer = setInterval(() => {
          const current = this.getCurrentValue(start, startDate, speed)
          const zeroTo100 = Math.min(Math.max(min, current), max)
          this.vm.loadingProgress = zeroTo100
        }, 1000 / 60)
      } else {
        // 已开始过
      }
    }
    return
  }

  @Computed
  get keepScreenOn():void {
    // 加载时保持亮屏，别忘了退出页面也要取消亮屏
    if (this.showLoadingCover) {
      DeviceMgr.Ins().requestKeepScreenOn("douYinLoadingWebPage", true)
    } else {
      DeviceMgr.Ins().requestKeepScreenOn("douYinLoadingWebPage", false)
    }
    return
  }

  build() {
    Column() {
      Stack({
        alignContent: Alignment.Center
      }) {
        Column() {
          Web({ src: DouYinURL.webPageURL, controller: this.vm.controllerInner })
            // 避免加载过程中闪白
            .backgroundColor(Color.Transparent)
            .onControllerAttached(() => {
              this.vm.controller = this.vm.controllerInner
            })
            // 允许使用localStorage和sessionStorage
            .domStorageAccess(true)
            // 允许使用IndexedDB
            .databaseAccess(true)
            // 不加载图像，更快加载
            .onlineImageAccess(false)
            .imageAccess(false)
            .onAppear(async () => {
              // 一打开就获取缓存视频池里的视频，以便加快起播
              // 写入缓存的操作在.onInterceptRequest()里
              try {
                const jsonString:string | null = await this.cacheMod.readCache(this.getUIContext().getHostContext() as common.UIAbilityContext)
                if (jsonString !== null) {
                  console.debug(logTag,"读取到的缓存："+jsonString)
                  const typedResponse:DouYinRecommandAwemeData = this.vm.extractData(jsonString)
                  console.debug(logTag,"缓存解析成功，视频数：" + typedResponse.aweme_list.length)
                  // 一打开就读取缓存，会不会导致用户在缓存有效期内总是看到旧的视频？不会，因为
                  // 在加载了缓存后仍然不销毁WebView，以便继续缓存新的视频并写入缓存
                  this.videoListMod.appendVideoList(typedResponse)
                } else {
                  console.debug(logTag,"暂无缓存")
                }
              } catch (error) {
                console.debug(logTag,"缓存可能有问题",error.message ?? JSON.stringify(error,null,2))
              }
            })
            .onInterceptRequest((event) => {
              // 同时要获取用户真实资源池里的视频
              // 如果获取到了，在视频列表最后面添加上去
              if (event.request.getRequestUrl().startsWith("https://www.douyin.com/aweme/v2/web/module/feed/")) {
                // 立即去请求，拿到内容
                (async () => {
                  try {
                    const response = await this.vm.getResponse(event)
                    if (response.responseCode === 200) {
                      if (typeof response.result !== 'string') { throw new Error('推荐响应不是文本'); }
                      const jsonString = response.result;
                      // Validate before caching: malformed responses must not poison the next launch.
                      const result = this.vm.extractData(jsonString);
                      this.cacheMod.saveCache(jsonString,this.getUIContext().getHostContext() as common.UIAbilityContext);
                      console.debug(logTag,"推荐数据解析成功，视频数：" + result.aweme_list.length)
                      this.videoListMod.appendVideoList(result)
                    } else {
                      console.debug(logTag,"response.responseCode是"+response.responseCode)
                    }
                  } catch (error) {
                    console.debug(logTag,"获取首页推荐视频错误："+error.message ?? JSON.stringify(error,null,2))
                    // 绕开了强制转换类型的危险，因为抛出的不一定是BusinessError，也可能是本模块自定义的错误类型
                    if (error.code === 2300028) {
                      // 请求个https://www.douyin.com/aweme/v2/web/module/feed/都能
                      // {
                      //   "code": 2300028,
                      //   "message": "Timeout was reached"
                      // }
                      // 网速极差，请求基本超时
                      this.vm.networkError = true
                    }
                    // 其它的错误暂不处理，比如解析失败，后续的多次（去掉CSS后允许多次请求）请求可能会成功
                  }
                })()
                return null
              } else {
                const currentURL = event.request.getRequestUrl()
                if (currentURL.endsWith(".css") && true) { // Debug才false
                  // 不加载css文件，减轻渲染压力
                  const responseWeb = new WebResourceResponse()
                  return responseWeb
                } else {
                  // 放行
                  return null
                }
              }
            })
            // 页面关闭，Web销毁，别人不能再用了
            .onDisAppear(() => {
              this.vm.controller = null
              if (this.progressTimer !== undefined) {
                clearInterval(this.progressTimer)
                this.progressTimer = undefined
              }
              this.progressUpdateStarted = false
            })
            .onPageBegin((event) => {
              if (event) {
                console.debug('🚩onPageBegin, url:' + event.url);
              }
            })
            .onPageEnd((event) => {
              console.debug('🚩onPageEnd, url:' + event.url);
            })
            .onErrorReceive((event) => {
              if (event.request.isMainFrame()) {
                console.debug(logTag, "发生了错误：\n" + event.error.getErrorInfo())
                // 测试发现
                // 手表网络断开时，进入抖音RSS，加载几秒会提示"发生了错误",之后仍会一直加载但进不去界面
                // 显示错误页面，避免用户一直看到加载
                this.vm.networkError = true
              }
            })
            .onRenderExited((event) => {
              this.getUIContext()
                .getPromptAction()
                .showToast({ message: "onRenderExited\n" + JSON.stringify(event, null, 2) })
            })
            .onRenderProcessNotResponding(() => {
              this.getUIContext().getPromptAction().showToast({ message: "onRenderProcessNotResponding" })
            })
            .onRenderProcessResponding(() => {
              this.getUIContext().getPromptAction().showToast({ message: "onRenderProcessResponding" })
            })
            .overScrollMode(OverScrollMode.NEVER)
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        }
        .height('70.71%')
        .width('70.71%')
        if (this.showLoadingCover) {
          Stack() {
            // 黑色背景、拦截手势
            // Debug才false

            if (true) {
              Column() {

              }
              .backgroundColor(DarkTheme.navDestDefaultBackground)
              // 淡出
              .width("100%")
              .height("100%")
            }

            Progress({
              value:this.vm.loadingProgress,
              total:100,
              type:ProgressType.Ring,
            })
              .style({
                strokeWidth:"10vp"
              })
              // 放大进入，淡出
              // 退出跟随外界一起淡出
              .transition(TransitionEffect.asymmetric(TransitionEffect.scale({ x:0,y:0 }).animation({ delay:200,duration:670,curve:Curve.EaseOut }),TransitionEffect.IDENTITY))
              .width("50%")
              .height("50%")
          }
          .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY,TransitionEffect.OPACITY.animation({ delay:300,duration: 300, curve: Curve.Smooth })))
          .width("100%")
          .height("100%")
        }
        if (this.vm.networkError) {
          Stack() {
            Column() {
              DouYinLoadingErrorView0()
            }
            .backgroundColor(Color.Black)
            .width("100%")
            .height("100%")
          }
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
          .width("100%")
          .height("100%")
        }
      }
      .width("100%")
      .height("100%")
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center) // 垂直居中
    .alignItems(HorizontalAlign.Center) // 水平居中
    .onAppear(() => {
      const isDoneZoomProperty = this.generateRandomPropertyName()

      this.viewportTimer = setInterval(() => {
        if (this.vm.controller) {
          const script = `
(() => {
  // 确保在每个页面只设置一次
  if (window.${isDoneZoomProperty}) { return }
  const setViewportScale = () => {
    const zoomLevel = 0.27;
    // 检查是否已存在viewport meta标签
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      // 如果不存在，创建一个新的
      viewport = document.createElement("meta");
      viewport.name = "viewport";
      document.head.appendChild(viewport);
    }
    // 设置视口宽度为设备宽度除以缩放比例
    const width = window.innerWidth / zoomLevel;
    viewport.content = "width=" + width + ", initial-scale=" + zoomLevel;
    window.${isDoneZoomProperty} = true
  };
  setViewportScale();
})();
  `
          this.vm.controller.runJavaScript(script)
        }
      }, 100)
    })
    .onDisAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn("douYinLoadingWebPage", false)
      if (this.viewportTimer !== undefined) {
        clearInterval(this.viewportTimer)
        this.viewportTimer = undefined
      }
    })
  }
  getCurrentValue(start:number, startDate:number, speed:number) {
    // 计算从起始时间到现在的时间差（毫秒）
    const timeDiff = Date.now() - startDate;
    // 将时间差转换为秒，乘以速度得到增量，加上初始值即为当前值
    const currentValue = start + (timeDiff / 1000) * speed;

    return currentValue;
  }
  // 这不是UUID，而是合法的变量名，用的是下划线而不是横杠
  generateRandomPropertyName = () => {
  let uuid = 'xxxxxxxx_xxxx_4xxx_yxxx_xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });

  // Check if the first character is a number (0-9)
  if (/^[0-9]/.test(uuid)) {
    // Replace the first character with a letter (a-f)
    const letters = 'abcdef';
    const randomLetter = letters.charAt(Math.floor(Math.random() * letters.length));
    uuid = randomLetter + uuid.substring(1);
  }

  return uuid;
}
}
