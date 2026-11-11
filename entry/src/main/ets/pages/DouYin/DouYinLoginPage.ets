import { UUID } from '../../common/UUID';
import { SerialTaskTimer } from '../../common/SerialTaskTimer';
import { DouyinCookieStore } from '../../common/douyin/DouyinCookieStore';
import { webview } from "@kit.ArkWeb";
import { CustomContentDialog, LengthMetrics, PopoverDialogV2, promptAction } from "@kit.ArkUI";
import { logTag } from "../../common/printLog";
import { harmonyZhuoYiTongChromiumUA } from "../../common/UserAgent";
import { Task } from "../../common/sleep";
import { DarkTheme } from "../../common/Theme";
import { ArcButton, ArcButtonOptions, ArcButtonPosition, ArcButtonStyleMode, ColorMetrics } from '@kit.ArkUI';
import { DouYinLoadingErrorView1, ErrorPrompt } from "../../components/ErrorPages";
import { jsReturnValueToBoolean, jsReturnValueToString } from "../../common/WebViewExtension";
import { DeviceMgr } from "../../common/AlwaysOn";
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { DouYinAvaliabilityCheck } from "./AvaliabilityCheckView";
import { DevFlags } from '../../common/dev/DevFlags';

/** 精选页的登录拦截页会传这个参数；菜单和启动直达传 undefined，行为保持不变。 */
export interface DouYinLoginPagePushData {
  openJingxuanAfterLogin: boolean
  afterLoginPage?: string
}

@Builder
export function DouYinLoginPageBuilder(name: string, param: Object) {
  DouYinLoginPage({
    openJingxuanAfterLogin: (param as DouYinLoginPagePushData)?.openJingxuanAfterLogin === true,
    afterLoginPage: (param as DouYinLoginPagePushData)?.afterLoginPage ?? 'DouYinJingxuanPage'
  })
}

@ComponentV2
export struct DouYinLoginPage {
  @Param openJingxuanAfterLogin: boolean = false
  @Param afterLoginPage: string = 'DouYinJingxuanPage'
  @Local
  private pageInfos: NavPathStack | null = null

  build() {
    NavDestination() {
      // 登录页同样强拦：无网络时不进页。登录进行中已请求保持亮屏，
      // 网络句柄不会因息屏被回收，因此不会误拆正在进行的登录。
      DouYinAvaliabilityCheck({
        requireNetwork: true,
        pageInfos: this.pageInfos,
        content: () => {
          this.buildDouYinLoginPageInner({
            pageInfos: this.pageInfos,
            openJingxuanAfterLogin: this.openJingxuanAfterLogin,
            afterLoginPage: this.afterLoginPage
          })
        }
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }

  // 定义为组件内的@Builder，因为如果定义成全局的@Builder，会因为：https://developer.huawei.com/consumer/cn/forum/topic/0203170527095268768
  // 崩溃
  // 注意：全局 @Builder 里误读 this 会取到 undefined，所以保持组件内定义
  @Builder
  private buildDouYinLoginPageInner(param: DouYinLoginPageInnerBuilderParam) {
    DouYinLoginPageInner({
      pageInfos: param.pageInfos,
      openJingxuanAfterLogin: param.openJingxuanAfterLogin,
      afterLoginPage: param.afterLoginPage
    })
  }
}

// 按引用传递：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder#按引用传递参数
class DouYinLoginPageInnerBuilderParam {
  public pageInfos: NavPathStack | null = null
  public openJingxuanAfterLogin: boolean = false
  public afterLoginPage: string = 'DouYinJingxuanPage'
}


@ComponentV2
export struct DouYinLoginPageInner {
  @Param @Require pageInfos: NavPathStack | null
  @Param openJingxuanAfterLogin: boolean = false
  @Param afterLoginPage: string = 'DouYinJingxuanPage'
  @Local
  private isError: boolean = false
  @Local private loadFailure: string | null = null;
  @Local private attempt: number = 0;

  /** 回到首页，重新进入抖音，以便使用已登录的Cookie。拦截页进来的登录完成后再多进一跳精选。 */
  private goToDouYinHome(openJingxuan: boolean): void {
    if (this.pageInfos === null) {
      this.isError = true
      return
    }
    this.pageInfos.clear(true)
    this.pageInfos.pushPathByName("DouYinMenu", undefined)
    if (openJingxuan) {
      const destination = this.afterLoginPage === 'DouyinCollectedPage' || this.afterLoginPage === 'DouyinLikedPage' ?
        this.afterLoginPage : 'DouYinJingxuanPage';
      this.pageInfos.pushPathByName(destination, undefined)
    }
  }

  build() {
    if (this.loadFailure !== null) {
      ErrorPrompt({
        errorMessage: this.loadFailure,
        showRetryButton: true,
        showCloseButton: false,
        onRetry: () => {
          this.attempt++;
          this.loadFailure = null;
        }
      })
    } else if (this.isError === false) {
      ForEach([this.attempt], (attempt: number) => {
        DouYinLoginPageL0({
          onFailure: (message: string): void => {
            if (attempt === this.attempt) {
              this.loadFailure = message;
            }
          },
          closeMe: () => {
            // 退出登录、加载失败兜底都回菜单，不能带着刚被清掉的 Cookie 去精选
            this.goToDouYinHome(false)
          },
          finishLogin: () => {
            this.goToDouYinHome(this.openJingxuanAfterLogin)
          }
        })
      }, (attempt: number) => String(attempt))
    } else {
      DouYinLoadingErrorView1({
        pageInfos: this.pageInfos
      })
    }
  }
}

// 抖音这个网页是React架构，比如input元素包含属性[
//     "__reactFiber$fsm35di7cak",
//     "__reactProps$fsm35di7cak",
//     "__reactEvents$fsm35di7cak",
//     "value",
//     "_valueTracker"
// ]
// 在填入验证码的时候要确保使用React内部事件

// 登录链路里可能夹带充值等与登录无关的界面，直接暴露容易引起误解，所以整块盖住网页；即使网页结构变了，表现也只是登录不上，而不会把内部结构呈现给用户
// 既然用户看不到网页，所有弹出提示（比如手机号错误、验证码错误）都要在前端呈现出来，这个要高频检测，避免弹窗转瞬即逝，前端文本要额外多显示几秒。
// 前端需要先校验一下手机号是不是11位数字、1开头、验证码是不是6位数字

// 选择通过Cookie标记来检查用户是否已成功登录，加载很快速（进来经过短暂黑屏就能知道是不是已经有登录Cookie了）
// 通过DevTools对比登录前后的Cookie，认为passport_assist_user这个key是在登录后才会出现的，作为标记；
// 现在标记的名单在DouyinCookieStore.hasLoginMarker里，精选页的登录拦截用的是同一份判定。
// 退出登录只清理抖音的 Cookie 与本应用导入文件，不影响其他站点。
// 理想情况下应该点击网页里的退出登录按钮，这样用户在手机上管理已登录设备里手表对应的条目也会消失。
@ComponentV2
struct DouYinLoginPageL0 {
  @Param @Require onFailure: (message: string) => void;
  private loadTimer: number | undefined = undefined;
  private screenOwner: string = UUID();
  private disposed: boolean = false;
  private failed: boolean = false;
  // 首次 runScripts 必须等到「抖音登录页加载完成」（onProgressChange 到 100）再触发：
  // 加载完成前跑 openLoginPopup，controller.runJavaScript() 的 await 会一直挂起不返回，
  // 而 SerialTaskTimer 那一轮任务不结束，runningGeneration 就一直占着，后面每个 tick 都被挡掉，
  // 状态轮询从此彻底停摆（登录控件再出现也没人看见）。
  // 一次加载里进度可能多次上报 100（重定向、重新加载），用标记保证只触发一次。
  private scriptsStarted: boolean = false;
  @Param @Require closeMe: () => void
  // 「完成登录」与「退出登录」的落点不同：退出登录后必须回菜单，不能去精选页
  @Param @Require finishLogin: () => void
  // 登录网页的URL
  @Local
  private selectedURL: string = "https://www.douyin.com/pay"
  @Local
  private vm: DouYinLoginViewModel = new DouYinLoginViewModel()
  @Local
  private zoomMod: DouYinLoginPageZoomModel = new DouYinLoginPageZoomModel()
  @Local
  private isLoggedInMod: DouYinLoginPageCheckIsLoggedInModel = new DouYinLoginPageCheckIsLoggedInModel()
  @Local
  private scriptMod: DouYinLoginPageScriptModel = new DouYinLoginPageScriptModel()

  private clearLoadTimer(): void {
    if (this.loadTimer !== undefined) {
      clearTimeout(this.loadTimer);
    }
    this.loadTimer = undefined;
  }

  private stopLoginWork(): void {
    this.clearLoadTimer();
    this.zoomMod.onControllerDeattached();
    this.isLoggedInMod.stop();
    this.scriptMod.onControllerDeattached();
    DeviceMgr.Ins().requestKeepScreenOn('douYinLoginWebLoading', false, this.screenOwner);
  }

  private failLoading(message: string): void {
    if (this.disposed || this.failed) {
      return;
    }
    this.failed = true;
    this.stopLoginWork();
    this.onFailure(message);
  }

  @Monitor('scriptMod.loginViewReady', 'scriptMod.showVerificationCodeBox', 'scriptMod.alert',
    'isLoggedInMod.isLoggedIn')
  private loginUsable(): void {
    if (this.disposed || this.failed) {
      return;
    }
    if (this.scriptMod.loginViewReady || this.scriptMod.showVerificationCodeBox ||
      this.scriptMod.alert !== null || this.isLoggedInMod.isLoggedIn === true) {
      this.clearLoadTimer();
      DeviceMgr.Ins().requestKeepScreenOn('douYinLoginWebLoading', false, this.screenOwner);
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stopLoginWork();
  }

  aboutToAppear(): void {
    // debug 构建才允许 DevTools 接入；release 构建保持关闭。
    webview.WebviewController.setWebDebuggingAccess(DevFlags.isDebugBuild);
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Web({
          src: this.selectedURL,
          controller: this.vm.controller
        })
        // 避免加载过程中闪白
          .backgroundColor(Color.Transparent)
          .userAgent(harmonyZhuoYiTongChromiumUA)
          .onControllerAttached(() => {
            if (this.disposed || this.failed) {
              return;
            }
            this.clearLoadTimer();
            this.loadTimer = setTimeout(() => this.failLoading(this.vm.webPageLoadingProgress >= 100 ?
              '页面已加载但登录控件未就绪，请稍后重试' : '登录页面加载超时，请检查网络后重试'), 30000);
            this.zoomMod.zoom(this.vm.controller)
            this.isLoggedInMod.run(this.selectedURL)
            // 新一次加载（重新挂载控制器）不在挂载时就开轮询，等 onProgressChange 到 100 再开：
            // 加载完成前跑 openLoginPopup 会把 await controller.runJavaScript(script) 挂死。
            this.scriptsStarted = false
            // 在加载完成、加载出错、关闭页面的时候取消常亮。
            DeviceMgr.Ins().requestKeepScreenOn("douYinLoginWebLoading", true, this.screenOwner)
          })
          .onProgressChange((event) => {
            if (this.disposed || this.failed) {
              return;
            }
            this.vm.webPageLoadingProgress = event.newProgress
            if (event.newProgress >= 100) {
              this.loginUsable();
              console.debug(logTag, "抖音登录页加载完成")
              DeviceMgr.Ins().requestKeepScreenOn("douYinLoginWebLoading", false, this.screenOwner)
              // 到了这里（而不是 onControllerAttached）才开首轮轮询：加载完成前 openLoginPopup 的
              // await controller.runJavaScript(script) 会持续挂起，把之后所有状态轮询都拖死。
              if (!this.scriptsStarted) {
                this.scriptsStarted = true
                this.scriptMod.runScripts(this.vm.controller)
              }
            }
          })
          .onErrorReceive((event) => {
            // -3 is a cancelled navigation, not a lost network. Subresource errors must not cancel login.
            if (event.request.isMainFrame() && event.error.getErrorCode() !== -3) {
              this.failLoading('登录页面请求失败，请检查网络后重试');
            }
          })
          .onHttpErrorReceive((event) => {
            if (event.request.isMainFrame() && event.response.getResponseCode() >= 400) {
              this.failLoading('登录页面暂不可用（HTTP ' + event.response.getResponseCode() + '），请稍后重试');
            }
          })
          .onRenderExited(() => this.failLoading('登录页面进程已退出，请重试'))
          .onDisAppear(() => this.stopLoginWork())
          // 把网页整个盖起来了，不用点击
          .hitTestBehavior(HitTestMode.Transparent)
          .height("70.71%")
          .width("70.71%")
        // 把网页盖起来；只有显式开启 DEV_DOUYIN_DEV_UI（debug）时才露出 WebView。
        if (!DevFlags.douyinDevUI) {
          Column() {

          }
          .backgroundColor(DarkTheme.navDestDefaultBackground)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
          .width("100%")
          .height("100%")
        }
        CoverPage({
          vm: this.vm,
          scriptMod: this.scriptMod
        })
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
        ToastLayerWithDelay({
          loadingToast: this.scriptMod.loadingToast || false, // Debug才|| true
          toast: this.scriptMod.toast
        })
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
        AlertLayer({
          alert: this.scriptMod.alert
        })
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
        AlreadyLoggedInLayer({
          isLoggedIn: (this.isLoggedInMod.isLoggedIn === true),
          onFinishLogin: () => {
            this.finishLogin()
          },
          onLogoutDone: () => {
            this.closeMe()
          }
        })
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
        LoadingLayerForCheckingLoginStatus({
          checking: (this.isLoggedInMod.isLoggedIn === null)
        })
          .opacity(this.vm.debugIsShow ? 1 : 0.5)
          .hitTestBehavior(this.vm.debugIsHit ? HitTestMode.None : HitTestMode.Transparent)
        // 调试开关：仅 DEV_DOUYIN_DEV_UI 打开时出现，用来压暗覆盖层观察网页状态。
        if (DevFlags.douyinDevUI) {
          Toggle({
            isOn: $$this.vm.debugIsShow,
            type: ToggleType.Switch
          })
            .position({ x: '8vp', y: '8vp' })
            .zIndex(10)
        }
      }
      .width("100%")
      .height("100%")
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}


@ComponentV2
struct CoverPage {
  @Param @Require
  private vm: DouYinLoginViewModel
  @Param @Require
  private scriptMod: DouYinLoginPageScriptModel

  build() {
    Column() {
      if (this.scriptMod.showVerificationCodeBox === false) {
        BeforeSentCoverPage({
          vm: this.vm,
          scriptMod: this.scriptMod
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      } else {
        AfterSentCoverPage({
          vm: this.vm,
          scriptMod: this.scriptMod
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}


@ComponentV2
struct BeforeSentCoverPage {
  @Param @Require
  private vm: DouYinLoginViewModel
  @Param @Require
  private scriptMod: DouYinLoginPageScriptModel

  @Computed
  private get isPhoneNumberValid(): boolean {
    // 校验手机号是11位数字，并且以1开头（因为腕上RSS只处理中国大陆的手机号）
    if (this.vm.phoneNumber.length === 11) {
      if (this.vm.phoneNumber.startsWith("1") === true) {
        return true
      }
    }
    return false
  }

  // 从95%开始走，避免用户太着急，配个最小点击间隔1秒差不多
  // 我最大取4，这样不超过99%
  // 因为真的100%了按钮就直接能点了，不需要我这个进度条
  @Local
  private preReadyTriggeredCount: number = 0

  build() {
    Column() {
      Blank()
      Text("登录抖音账号")
        .fontWeight(FontWeight.Bold)
      Blank()
      TextInput({ placeholder: "输入手机号", text: $$this.vm.phoneNumber })
        .backgroundColor(DarkTheme.textFieldBackground)
        .type(InputType.PhoneNumber)
        .contentType(ContentType.PHONE_NUMBER)
        .textAlign(TextAlign.Center)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .margin({ left: "10vp", right: "10vp" })
      Blank()
      SendSMSButtonWithThrottle({
        isEnable: ((this.scriptMod.loginViewReady === true) && this.isPhoneNumberValid && !this.vm.sendSMSLoading),
        clickAction: () => {
          // 内部保证了只有isEnable的时候才触发clickAction
          (async () => {
            this.vm.sendSMSLoading = true
            await this.scriptMod.sendSMS(this.vm.phoneNumber, this.vm.controller)
            // 等2秒再释放加载，实测执行完这个脚本，到网页能弹出验证码加载动画（这时候会阻断触控），至少需要2秒钟，在这期间如果多次点击，会导致重复发送验证码，触发发送验证码过于频繁的提示
            await Task.sleep(2)
            this.vm.sendSMSLoading = false
          })()
        },
        beforeReadyCheckAction: () => {
          // 卡在95%，因为网页加载完成后点击了按钮，还需要等待网页内弹窗出来
          // 避免超过99%
          // 这个duration：1秒配合的正是SendSMSButtonWithThrottle的1秒节流
          const dynamicProgress: number = this.mapInputToOutput(this.vm.webPageLoadingProgress)
          if (dynamicProgress === 95) {
            // 动态进度已到头，再显示取悦用户的进度，从0%开始，每点击一次+1%，最终卡在99%
            this.preReadyTriggeredCount += 1
            // 虽然是曲线跟随，但因为要呈现给用户，取整数值
            this.getUIContext()
              .getPromptAction()
              .showToast({
                message: "加载中，请稍后再试\n加载进度：" +
                  (Math.round((dynamicProgress + Math.min(this.preReadyTriggeredCount, 4)))) + "%",
                duration: 1000
              })
          } else {
            // 没到头，直接显示动态进度
            // 虽然是曲线跟随，但因为要呈现给用户，取整数值
            this.getUIContext()
              .getPromptAction()
              .showToast(
                { message: "加载中，请稍后再试\n加载进度：" + (Math.round((dynamicProgress))) + "%", duration: 1000 })
          }
        },
        isLoading: this.vm.sendSMSLoading
      })
      Blank()
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }

  /**
   * 将输入值映射到0~95的输出值
   * 0~50：输出 = 输入（完全跟随）
   * 50~100：输出从50开始，增速逐渐减慢，平滑趋向95
   * 全程输出 ≤ 输入，永不超前
   *
   * @param input 输入值（0~100）
   * @param curve 控制滞后程度，默认2.0。越大滞后越多，曲线越平缓
   * @returns 输出值（0~95）
   */
  private mapInputToOutput(input: number, curve: number = 2.0): number {
    // 限制输入范围
    const x = Math.max(0, Math.min(100, input));

    // 0~50：完全跟随
    if (x <= 50) {
      return x;
    }

    // 50~100：指数饱和曲线，增速递减，永不超前
    // k值控制衰减速度，curve越大，k越大，增长越慢
    const k = 15 + curve * 5;

    // 计算进度（0~1）
    const progress = (x - 50) / 50;

    // 指数饱和公式：y = 50 + 45 * (1 - exp(-progress * 50 / k))
    // 使用Math.exp计算指数
    const y = 50 + 45 * (1 - Math.exp(-progress * 50 / k));

    // 确保永不超前（理论上已满足，做保护）
    return Math.min(y, x);
  }
}

// 外界需要保证只有在发送了验证码之后才显示我
@ComponentV2
struct AfterSentCoverPage {
  @Param @Require
  private vm: DouYinLoginViewModel
  @Param @Require
  private scriptMod: DouYinLoginPageScriptModel
  @Local
  private sending: boolean = true

  @Computed
  private get isVerificationCodeValid(): boolean {
    // 校验验证码是6位数
    if (this.vm.verificationCode.length === 6) {
      return true
    }
    return false
  }

  build() {
    Column() {
      if (this.sending) {
        // 把文字置于屏幕下方，避免和此时因为网页加载，屏幕中出现的LoadingProgress()重叠
        Blank()
        Text("短信验证码发送中……")
          .fontWeight(FontWeight.Bold)
          .padding({
            bottom: LengthMetrics.vp(50)
          })
      } else {
        Blank()
        Text("短信验证码已发送")
          .fontWeight(FontWeight.Bold)
        Blank()
        TextInput({ placeholder: "请输入短信验证码", text: $$this.vm.verificationCode })
          .backgroundColor(DarkTheme.textFieldBackground)
          .type(InputType.PhoneNumber)
          .contentType(ContentType.PHONE_NUMBER)
          .textAlign(TextAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .margin({ left: "10vp", right: "10vp" })
        Blank()
        LoginButton({
          isEnable: (this.isVerificationCodeValid),
          clickAction: () => {
            // 内部保证了只有isEnable的时候才触发clickAction
            (async () => {
              this.vm.confirmLoginLoading = true
              await this.scriptMod.confirmLogin(this.vm.verificationCode, this.vm.controller)
              this.vm.confirmLoginLoading = false
            })()
          },
          isLoading: this.vm.confirmLoginLoading
        })
        Blank()
      }
    }
    .onAppear(() => {
      // 等待验证码送达需要3秒
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
          this.sending = false
        })
      }, 3000) // 3s
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 因为在发送验证码的步骤，网页里的旋转按钮消失了，需要再3秒才能显示“60s 后重新获取”，并且还需要1秒才能被JS脚本检出。
// 这段时间我需要硬控，避免用户重复点击发送按钮。
// delay 4秒
@ComponentV2
struct ToastLayerWithDelay {
  @Param @Require loadingToast: boolean
  @Local private loadingToastInner: boolean = false
  @Local private loadingToastDismissDelayToken: number | null = null
  @Param @Require toast: string | null
  @Local private toastInner: string | null = null
  @Local private toastDismissDelayToken: number | null = null

  @Computed
  private get onLoadingToastChange(): void {
    if (this.loadingToast !== false) {
      // loadingToast出现，立刻显示
      if (this.loadingToastDismissDelayToken !== null) {
        clearTimeout(this.loadingToastDismissDelayToken)
      }
      this.loadingToastInner = this.loadingToast
    } else {
      // loadingToast消失
      // 延迟4秒
      this.loadingToastDismissDelayToken = setTimeout(() => {
        this.loadingToastInner = false
      }, 4000)
    }
    return
  }

  @Computed
  private get onToastChange(): void {
    if (this.toast !== null) {
      // toast出现，立刻显示
      if (this.toastDismissDelayToken !== null) {
        clearTimeout(this.toastDismissDelayToken)
      }
      this.toastInner = this.toast
    } else {
      // toast消失
      // 延迟1秒
      this.toastDismissDelayToken = setTimeout(() => {
        this.toastInner = null
      }, 1000)
    }
    return
  }

  @Computed
  private get onToastInnerChange(): void {
    console.debug(logTag, "显示了toast:" + this.toastInner)
    return
  }

  build() {
    Column() {
      if (this.toastInner !== null) {
        Text(this.toastInner)
          .padding("10vp")
          .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .borderRadius("5vp")
          .margin("10vp")
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
      }
      if (this.loadingToastInner === true) {
        // 我需要阻断触摸，因为网页在加载，此时放任用户重复点击按钮是危险的
        Column() {
          LoadingProgress()
            .width("79vp")
            .height("79vp")
            .color(DarkTheme.primary)
            .padding("15vp")
            .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
            .borderRadius("999vp")
        }
        .justifyContent(FlexAlign.Center)
        // 阻断触摸
        .hitTestBehavior(HitTestMode.Block)
        .width("100%")
        .height("100%")
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        .onAppear(() => {
          DeviceMgr.Ins().requestKeepScreenOn("douYinLoginProgressing", true)
        })
        .onDisAppear(() => {
          DeviceMgr.Ins().requestKeepScreenOn("douYinLoginProgressing", false)
        })
      }
    }
    .hitTestBehavior(HitTestMode.Transparent)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 这个是外部传入了非null的 alert: string 会触发弹窗
@ComponentV2
struct AlertLayer {
  @Param @Require alert: string | null
  // 能透出这个，说明前面的分支逻辑有问题
  @Local private alertCopy: string = "登录失败"

  @Computed
  private get showAlert(): void {
    if (this.alert !== null) {
      this.alertCopy = this.alert
      console.debug(logTag,"触发dialogController.open()，传入文本：",this.alert)
      this.dialogController.open()
    }
    // 让用户自己去点击关闭
    return
  }

  @Local
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      contentBuilder: () => {
        this.dialogTitleView();
      },
      buttons: [
        {
          value: '好',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {

          }
        }
      ],
    }),
    width: "100%",
    height: "100%"
  });

  // 用自定义标题栏，这样标题可以居中显示，而不是吸在最上面
  @Builder
  private dialogTitleView(): void {
    Column() {
      // 文本尺寸和系统的弹窗标题是一致的
      Text(this.alertCopy)
        .fontSize("15fp")
        .fontWeight(FontWeight.Bold)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    // 把按钮推下去，而不是在屏幕中间
    .height("157vp")
  }

  build() {
    // 无内容，仅占位，确保逻辑执行
    Column() {

    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .width("100%")
    .height("100%")
  }
}

@ComponentV2
struct LoadingLayerForCheckingLoginStatus {
  @Param @Require checking: boolean

  build() {
    Column() {
      if (this.checking === true) {
        Column({ space: "15vp" }) {
          AnimatedProgressView({ color: DarkTheme.accents.douyin })
            .width("50vp")
            .height("50vp")
          Text("加载中")
            .fontSize("19fp")
            .fontWeight(FontWeight.Bold)
            .fontColor(DarkTheme.accents.douyin)
        }
        .backgroundColor(Color.Black)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .width("100%")
    .height("100%")
  }
}

@ComponentV2
struct AlreadyLoggedInLayer {
  @Param @Require isLoggedIn: boolean
  @Param @Require onFinishLogin: () => void
  @Param @Require onLogoutDone: () => void
  @Local
  private logoutMod: DouYinLogoutViewModel = new DouYinLogoutViewModel()

  build() {
    Column() {
      if (this.isLoggedIn === true) {
        Column() {
          Blank()
          Blank()
          Blank()
          Text("已登录")
            .fontSize("30fp")
            .fontWeight(FontWeight.Bold)
            .padding({ start: LengthMetrics.vp(16.7), end: LengthMetrics.vp(16.7) })
          Blank()

          Button("退出登录")
            .fontColor(DarkTheme.destructiveColor)
            // 保持胶囊的触摸范围
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.dialogControllerConfirm.open()
            })

          Blank()
          // 背景是这块覆盖层的 Color.Black；用抖音红保持登录链路的主色。
          ArcButton({
            options: new ArcButtonOptions({
              label: "完成登录",
              position: ArcButtonPosition.BOTTOM_EDGE,
              styleMode: ArcButtonStyleMode.CUSTOM,
              backgroundColor: ColorMetrics.rgba(254, 44, 85),
              fontColor: ColorMetrics.rgba(255, 255, 255),
              fontSize: LengthMetrics.fp(18),
              shadowEnabled: true,
              shadowColor: ColorMetrics.rgba(254, 44, 85, 0.45),
              onClick: () => {
                this.onFinishLogin()
              }
            })
          })
        }
        .backgroundColor(Color.Black)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .width("100%")
    .height("100%")
  }

  @Local
  private dialogControllerConfirm: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      contentBuilder: () => {
        this.dialogTitleView();
      },
      buttons: [
        {
          value: '退出登录',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          role: ButtonRole.ERROR,
          action: () => {
            (async () => {
              try {
                await this.logoutMod.clearCookiesForDomainL1()
                // 返回，让WebView重新加载一次，从已登录界面加载到登录界面
                this.onLogoutDone()
              } catch (error) {
                console.debug(logTag, "AlreadyLoggedInLayer的dialogControllerConfirm的buttons第一个按钮出错")
              }
            })()
          }
        },
        {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {

          }
        }
      ],
    }),
    width: "100%",
    height: "100%"
  });

  // 用自定义标题栏，这样标题可以居中显示，而不是吸在最上面
  @Builder
  private dialogTitleView(): void {
    Column() {
      // 文本尺寸和系统的弹窗标题是一致的
      Text("确认退出登录吗？")
        .fontSize("15fp")
        .fontWeight(FontWeight.Bold)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    // 把按钮推下去，而不是在屏幕中间
    .height("157vp")
  }
}

@ObservedV2
class DouYinLogoutViewModel {
  async clearCookiesForDomainL1() {
    const domain: string = ".douyin.com"
    await this.clearCookiesForDomain(domain)
  }

  /**
   * 清理指定域名下的所有 Cookie.
   *
   * @param domain 要清理 Cookie 的域名（例如：".bilibili.com"）.
   */
  private async clearCookiesForDomain(domain: string) {
    if (domain !== '.douyin.com') {
      throw new Error('退出登录域名不匹配');
    }
    await DouyinCookieStore.clear();
  }
}

@ObservedV2
class DouYinLoginViewModel {
  @Trace
  checkingLoginStatus: boolean = true // 一打开需要先等待首次检查Cookie确认登录状态
  @Trace
  webPageLoadingProgress: number = 0 // 0-100
  @Trace
  phoneNumber: string = "" // 仅 debug 构建使用的预填号码；真实号码不要提交进仓库
  @Trace
  controller: webview.WebviewController = new webview.WebviewController();
  @Trace
  sendSMSLoading: boolean = false
  @Trace
  verificationCode: string = ""
  @Trace
  confirmLoginLoading: boolean = false
  @Trace
  debugIsShow: boolean = true
  @Trace
  debugIsHit: boolean = true
}

// 我保证只有isEnable且不isLoading的时候才触发clickAction
// 1s节流，避免用户频繁点击导致在不稳定状态的时候触发事件，比如在输入完手机号和提交验证码之间再次输入了手机号，导致提交时提交的是空的手机号
@ComponentV2
struct SendSMSButtonWithThrottle {
  @Param @Require isEnable: boolean
  @Param @Require clickAction: () => void
  @Param beforeReadyCheckAction: (() => void) | null = null
  @Param @Require isLoading: boolean
  // 两次点击最小间隔：1秒
  @Local
  private lastClickDate: Date | null = null

  @Computed
  private get buttonColor(): string {
    if (this.isEnable) {
      return DarkTheme.prominentButton
    } else {
      // 如果提供了准备好前的点击事件，就显示可以点击的颜色
      if (this.beforeReadyCheckAction !== null) {
        return DarkTheme.prominentButton
      } else {
        return DarkTheme.disabledButton
      }
    }
  }

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Column() {
        Row() {
          if (this.isLoading === true) {
            LoadingProgress().width(20).height(20).color(0xFFFFFF)
          } else {
            Text("发送验证码").fontSize(18).fontWeight(FontWeight.Medium).fontColor(0xffffff)
          }
        }.alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).width(120).height(40)
    }
    .backgroundColor(this.buttonColor)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      if (this.throttlePassed() === true) {
        // 更新上次点击时间
        this.lastClickDate = new Date()
        if (this.isLoading !== true) {
          if (this.isEnable) {
            console.debug(logTag, "触发clickAction")
            this.clickAction()
          } else {
            if (this.beforeReadyCheckAction !== null) {
              console.debug(logTag, "触发beforeReadyCheckAction")
              this.beforeReadyCheckAction()
            } else {
              console.debug(logTag, "无行为，因为没有提供beforeReadyCheckAction")
            }
          }
        } else {
          console.debug(logTag, "无行为，因为this.isLoading === true")
        }
      } else {
        console.debug(logTag, "无行为，因为throttle没有Passed")
      }
    })
  }

  private throttlePassed(): boolean {
    if (this.lastClickDate === null) {
      console.debug(logTag, "throttlePassed，因为lastClickDate === null")
      return true
    } else {
      if (this.isMoreThanOneSecondAgo(this.lastClickDate) === true) {
        console.debug(logTag, "throttlePassed，因为isMoreThanOneSecondAgo === true")
        return true
      } else {
        console.debug(logTag, "throttle不Passed，因为isMoreThanOneSecondAgo !== true")
        return false
      }
    }
  }

  private isMoreThanOneSecondAgo(targetDate: Date): boolean {
    // 校验输入是否为有效的Date对象
    if (!(targetDate instanceof Date) || isNaN(targetDate.getTime())) {
      console.error('输入不是有效的Date对象');
      return false; // 或根据你的业务需求抛出异常
    }

    // 获取目标时间的时间戳（毫秒）
    const targetTime = targetDate.getTime();
    // 获取当前时间的时间戳
    const currentTime = Date.now();

    // 计算时间差（当前时间 - 目标时间），单位：毫秒
    const timeDiff = currentTime - targetTime;

    // 判断是否超过1秒（1000毫秒）
    return timeDiff > 1000;
  }
}


// 我保证只有isEnable的时候才触发clickAction
@ComponentV2
struct LoginButton {
  @Param @Require isEnable: boolean
  @Param @Require clickAction: () => void
  @Param @Require isLoading: boolean

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Column() {
        Row() {
          if (this.isLoading === true) {
            LoadingProgress().width(20).height(20).color(0xFFFFFF)
          } else {
            Text("继续登录").fontSize(18).fontWeight(FontWeight.Medium).fontColor(0xffffff)
          }
        }.alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).width(120).height(40)
    }
    .backgroundColor(this.isEnable ? DarkTheme.prominentButton : DarkTheme.disabledButton)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      if (this.isEnable) {
        this.clickAction()
      }
    })
  }
}

// 观察网页，登录sheet是一直在的，只是用户点击前它在页面最底下，点击后会有CSS变化，从
// <div class="dux-popup-content dux-popup-content-position-bottom dux-popup-content-bg-grey">
// 变成
// <div class="dux-mask dux-mask-enter">
// 等待几十毫秒，似乎在上报事件
// 变成，开始弹起动画
// <div class="dux-mask dux-mask-enter dux-mask-enter-active">
// 直到弹起动画完成
// 变成
// <div class="dux-mask dux-mask-enter-done">
@ObservedV2
class DouYinLoginPageScriptModel {
  @Trace
  loginViewReady: boolean = false
  @Trace
  showVerificationCodeBox: boolean = false
  @Trace
  loadingToast: boolean = false
  @Trace
  toast: string | null = null
  @Trace
  alert: string | null = null

  @Computed
  get onLoginViewReady(): void {
    if (this.loginViewReady === true) {
      console.debug(logTag, "登录视图准备好了")
    }
    return
  }

  private statePoller: SerialTaskTimer = new SerialTaskTimer();
  private toastPoller: SerialTaskTimer = new SerialTaskTimer();
  @Trace
  private openLoginPopup = `
(() => {
  if (false) {
  } else {
    /**
     * 查找并点击class包含"login_button"的div元素
     * @returns {boolean} 操作是否成功
     */
    const clickLoginButton = () => {
      try {
        // 1. 使用querySelector查找第一个class包含login_button的div元素
        // 注意：.login_button 匹配class完全等于的情况，*= 匹配包含的情况
        const loginButton = document.querySelector(
          'div[class*="login_button"]',
        );

        // 2. 检查元素是否存在
        if (!loginButton) {
          console.error('未找到class包含"login_button"的div元素');
          return false;
        }

        // 3. 触发点击操作
        // 直接调用 DOM 的 click() 接口触发点击
        loginButton.click();

        console.log("成功点击了登录按钮元素");
        return true;
      } catch (error) {
        console.error("点击登录按钮时发生错误：", error);
        return false;
      }
    };

    // 执行函数
    const clicked = clickLoginButton();
  }

  // 查找目标元素的核心函数
  const findAndClickTarget = () => {
    // 查找包含"手机号登录"文本的div（支持精准/去空格/包含三种匹配）
    const xpathList = [
      "//div[text()='手机号登录']", // 精准匹配
      "//div[normalize-space(text())='手机号登录']", // 忽略前后空格
      "//div[contains(text(),'手机号登录')]", // 包含匹配
    ];

    let targetElement = null;
    // 依次尝试三种匹配方式
    for (const xpath of xpathList) {
      const result = document.evaluate(
        xpath,
        document,
        null,
        XPathResult.FIRST_ORDERED_NODE_TYPE,
        null,
      );
      if (result.singleNodeValue) {
        targetElement = result.singleNodeValue;
        break;
      }
    }

    // 找到元素则执行点击并停止观察
    if (targetElement) {
      targetElement.click(); // 点击元素
      console.log('✅ 成功找到并点击"手机号登录"div元素');
      return true;
    }
    return false;
  };

  findAndClickTarget();
})();
  `
  @Trace
  private checkIsReadyToTypeInPhoneNumber = `
(() => {
  const element = document.querySelector('div.dux-popup-content.dux-popup-content-position-bottom.dux-popup-show.dux-popup-content-bg-grey');
  if (!element) return false;
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0 && rect.bottom >= 0 && rect.bottom <= window.innerHeight;
})();
  `
  @Trace
  private typeInPhoneNumber: string = `
(() => {
  const input = document.querySelector('input[placeholder="请输入手机号"]');

  if (input) {
    // 获取React的内部实例（Fiber节点）
    const reactKey = Object.keys(input).find((key) =>
      key.startsWith("__reactFiber$"),
    );

    if (reactKey) {
      const fiber = input[reactKey];
      // 找到最近的React事件处理器
      if (fiber && fiber.memoizedProps) {
        // 如果有onChange或onInput事件处理器
        const props = fiber.memoizedProps;

        // 设置DOM值
        input.value = "😳";

        // 触发React的事件处理器
        if (props.onChange) {
          const nativeEvent = new Event("input", { bubbles: true });
          Object.defineProperty(nativeEvent, "target", { value: input });

          // 创建合成事件对象
          const syntheticEvent = {
            target: input,
            currentTarget: input,
            type: "change",
            nativeEvent: nativeEvent,
            persist: () => {},
            isDefaultPrevented: () => false,
            isPropagationStopped: () => false,
            preventDefault: () => {},
            stopPropagation: () => {},
            bubbles: true,
            cancelable: true,
          };

          // 执行事件处理器
          props.onChange(syntheticEvent);
        }

        if (props.onInput) {
          const nativeEvent = new Event("input", { bubbles: true });
          Object.defineProperty(nativeEvent, "target", { value: input });

          const syntheticEvent = {
            target: input,
            currentTarget: input,
            type: "input",
            nativeEvent: nativeEvent,
            persist: () => {},
            isDefaultPrevented: () => false,
            isPropagationStopped: () => false,
            preventDefault: () => {},
            stopPropagation: () => {},
          };

          props.onInput(syntheticEvent);
        }

        console.log("通过React内部方法设置手机号");
      }
    }
  }
})();
  `
  @Trace
  private tapSendSMSButton: string = `
(() => {
  // 查找目标元素的核心函数
  const findAndClickTarget = () => {
    // 查找包含"获取验证码"文本的div（支持精准/去空格/包含三种匹配）
    const xpathList = [
      "//div[text()='获取验证码']", // 精准匹配
      "//div[normalize-space(text())='获取验证码']", // 忽略前后空格
      "//div[contains(text(),'获取验证码')]", // 包含匹配
    ];

    let targetElement = null;
    // 依次尝试三种匹配方式
    for (const xpath of xpathList) {
      const result = document.evaluate(
        xpath,
        document,
        null,
        XPathResult.FIRST_ORDERED_NODE_TYPE,
        null,
      );
      if (result.singleNodeValue) {
        targetElement = result.singleNodeValue;
        break;
      }
    }

    // 找到元素则执行点击并停止观察
    if (targetElement) {
      targetElement.click(); // 点击元素
      console.log('✅ 成功找到并点击"获取验证码"div元素');
      return true;
    }
    return false;
  };

  findAndClickTarget()
})();
  `
  @Trace
  private checkIsInPostSendSMSState: string = `
(() => {
  /**
   * 检查网页中是否存在包含 "Xs 后重新获取" 格式的 div 元素（X为0-60的整数）
   * @returns {Object} 检查结果：found(是否找到)、element(找到的元素)、seconds(匹配到的秒数)
   */
  function checkRefreshDiv() {
    // 固定后缀文本
    const suffixText = "s 后重新获取";

    // 获取页面中所有的 div 元素
    const allDivs = document.querySelectorAll("div");

    // 遍历所有 div 查找匹配的元素
    for (const div of allDivs) {
      // 清理文本前后空白
      const text = div.textContent.trim();

      // 检查文本是否以指定后缀结尾
      if (text.endsWith(suffixText)) {
        // 提取后缀前的数字部分
        const numberPart = text.substring(0, text.length - suffixText.length).trim();

        // 验证是否为有效数字且在 0-60 范围内
        const seconds = Number(numberPart);
        if (!isNaN(seconds) && Number.isInteger(seconds) && seconds >= 0 && seconds <= 60) {
          return {
            found: true,
            element: div,
            seconds: seconds,
          };
        }
      }
    }

    // 未找到匹配元素
    return {
      found: false,
      element: null,
      seconds: null,
    };
  }

  // --------------- 调用示例 ---------------
  // 单次检查
  const result = checkRefreshDiv();
  if (result.found) {
    console.log("✅ 找到目标元素："+result.seconds+"s 后重新获取");
    console.log("元素详情：", result.element);
    return true;
  } else {
    console.log('❌ 未找到包含 "Xs 后重新获取" 的 div 元素');
    return false;
  }
})();
  `
  @Trace
  private typeInVerificationCode: string = `
(() => {
  const input = document.querySelector('input[placeholder="请输入验证码"]');

  if (input) {
    // 获取React的内部实例（Fiber节点）
    const reactKey = Object.keys(input).find((key) =>
      key.startsWith("__reactFiber$"),
    );

    if (reactKey) {
      const fiber = input[reactKey];
      // 找到最近的React事件处理器
      if (fiber && fiber.memoizedProps) {
        // 如果有onChange或onInput事件处理器
        const props = fiber.memoizedProps;

        // 设置DOM值
        input.value = "📳";

        // 触发React的事件处理器
        if (props.onChange) {
          const nativeEvent = new Event("input", { bubbles: true });
          Object.defineProperty(nativeEvent, "target", { value: input });

          // 创建合成事件对象
          const syntheticEvent = {
            target: input,
            currentTarget: input,
            type: "change",
            nativeEvent: nativeEvent,
            persist: () => {},
            isDefaultPrevented: () => false,
            isPropagationStopped: () => false,
            preventDefault: () => {},
            stopPropagation: () => {},
            bubbles: true,
            cancelable: true,
          };

          // 执行事件处理器
          props.onChange(syntheticEvent);
        }

        if (props.onInput) {
          const nativeEvent = new Event("input", { bubbles: true });
          Object.defineProperty(nativeEvent, "target", { value: input });

          const syntheticEvent = {
            target: input,
            currentTarget: input,
            type: "input",
            nativeEvent: nativeEvent,
            persist: () => {},
            isDefaultPrevented: () => false,
            isPropagationStopped: () => false,
            preventDefault: () => {},
            stopPropagation: () => {},
          };

          props.onInput(syntheticEvent);
        }

        console.log("输入了验证码");
      }
    }
  }
})();
  `
  @Trace
  private tapComfirmLogin: string = `
(function simulateRealClick() {
    // 1. 获取所有候选元素
    const allButtons = document.querySelectorAll('div.dux-button-text');
    let targetButton = null;

    // 2. 筛选并排序，找到最匹配的元素
    if (allButtons.length > 0) {
        // 步骤1：先筛选出文本严格为"立即登录"的元素
        const loginButtons = Array.from(allButtons).filter(button => {
            // 去除前后空格，精准匹配文本
            return button.textContent.trim() === '立即登录';
        });

        if (loginButtons.length === 0) {
            console.warn('未找到文本为"立即登录"的按钮');
            return;
        }

        // 步骤2：对筛选结果排序，选出"最匹配"的（优先级：可见 > 可点击 > 第一个）
        loginButtons.sort((a, b) => {
            // 获取元素的可见性和可点击状态
            const isAVisible = isElementVisible(a);
            const isBVisible = isElementVisible(b);
            const isAEnabled = !a.hasAttribute('disabled') && a.style.pointerEvents !== 'none';
            const isBEnabled = !b.hasAttribute('disabled') && b.style.pointerEvents !== 'none';

            // 规则1：可见元素优先于不可见元素
            if (isAVisible && !isBVisible) return -1;
            if (!isAVisible && isBVisible) return 1;

            // 规则2：可点击元素优先于不可点击元素
            if (isAEnabled && !isBEnabled) return -1;
            if (!isAEnabled && isBEnabled) return 1;

            // 规则3：默认按在DOM中的顺序（靠前的优先）
            return 0;
        });

        // 取排序后的第一个（最匹配的）
        targetButton = loginButtons[0];
        console.log("找到"+loginButtons.length+"个“立即登录”按钮，已选中最匹配的一个");
    } else {
        console.warn('未找到任何class为dux-button-text的div元素');
        return;
    }

    // 3. 工具函数：判断元素是否可见（排除隐藏、不可见、宽高为0的情况）
    function isElementVisible(element) {
        const rect = element.getBoundingClientRect();
        const computedStyle = window.getComputedStyle(element);
        return (
            rect.width > 0 &&
            rect.height > 0 &&
            computedStyle.display !== 'none' &&
            computedStyle.visibility !== 'hidden' &&
            computedStyle.opacity !== '0'
        );
    }

    // 4. 构造 MouseEvent 的工具函数：坐标取按钮中心，供下面的事件序列复用
    const createMouseEvent = (eventType) => {
        return new MouseEvent(eventType, {
            bubbles: true,
            cancelable: true,
            view: window,
            button: 0,
            clientX: targetButton.getBoundingClientRect().x + (targetButton.offsetWidth / 2), // 点击按钮中心
            clientY: targetButton.getBoundingClientRect().y + (targetButton.offsetHeight / 2),
            screenX: window.screenX + targetButton.getBoundingClientRect().x + 10,
            screenY: window.screenY + targetButton.getBoundingClientRect().y + 10
        });
    };

    // 5. 依次派发 mouseover / mousedown / mouseup / click，每步间隔 100ms
    setTimeout(() => {
        targetButton.dispatchEvent(createMouseEvent('mouseover'));
        console.log('事件：mouseover 已派发（目标为最匹配的按钮）');
    }, 100);

    setTimeout(() => {
        targetButton.dispatchEvent(createMouseEvent('mousedown'));
        console.log('事件：mousedown 已派发');
    }, 200);

    setTimeout(() => {
        targetButton.dispatchEvent(createMouseEvent('mouseup'));
        console.log('事件：mouseup 已派发');
    }, 300);

    setTimeout(() => {
        targetButton.dispatchEvent(createMouseEvent('click'));
        console.log('事件：click 已派发（目标为“立即登录”按钮）');
    }, 400);

    setTimeout(() => {
        targetButton.dispatchEvent(createMouseEvent('mouseout'));
    }, 500);
})();
  `
  @Trace
  private getToast: string = `
(() => {
  const getToastText = () => {
    // 1. 查找目标元素
    const toastElement = document.querySelector(".dux-toast-text");

    // 2. 检查元素是否存在，避免报错
    if (!toastElement) {
      console.warn("未找到 class 为 dux-toast-text 的元素");
      return null;
    }

    // 3. 获取文本内容（优先使用 textContent，兼容性更好）
    const textContent = toastElement.textContent?.trim() || "";

    // 可选：也可以使用 innerText（会受样式影响，比如隐藏文本不会被获取）
    // const textContent = toastElement.innerText?.trim() || '';

    console.log("获取到的 toast 文本：", textContent);
    return textContent;
  };
  return getToastText();
})();
  `
  @Trace
  private getAlert: string = `
(() => {
  /**
   * 获取指定类名元素的文本内容，多子元素文本间用换行分隔
   * 无元素/无有效文本返回null，自动过滤首尾空白
   * @returns {string|null} 处理后的文本或null
   */
  function getDialogContentText() {
    // 1. 获取目标元素，无元素直接返回null
    const targetElement = document.querySelector(".dux-dialog-content");
    if (!targetElement) return null;

    // 2. 获取所有直接子元素的文本（过滤空文本/纯空白文本）
    const childTexts = Array.from(targetElement.children)
      .map((child) => child.textContent.trim()) // 子元素文本单独去空白
      .filter((text) => text); // 过滤掉空字符串（无文本/纯空白的子元素）

    // 3. 无有效子元素文本，返回null
    if (childTexts.length === 0) return null;

    // 4. 多子元素文本用换行符\\n连接，最终结果再整体去首尾空白
    const resultText = childTexts.join("\\n").trim();

    // 5. 兜底判断（避免极端情况空文本），返回有效文本或null
    return resultText ? resultText : null;
  }

  // 调用示例
  const result = getDialogContentText();
  return result;
})();
  `

  runScripts(controller: webview.WebviewController) {
    this.statePoller.start(async (current: () => boolean): Promise<void> => {
      // 运行三个脚本
      console.debug(logTag, "运行三个脚本A")
      try {
        console.debug(logTag, "运行三个脚本A1")
        if (!current()) {
          console.debug(logTag, "运行三个脚本A2")
          return;
        }
        console.debug(logTag, "运行三个脚本A3")
        if (!this.loginViewReady && !this.showVerificationCodeBox) {
          const script = this.openLoginPopup
          console.debug(logTag, "运行三个脚本A4")
          const rawResult: string = await controller.runJavaScript(script)
          console.debug(logTag, "运行三个脚本A5")
          if (!current()) {
            console.debug(logTag, "运行三个脚本A6")
            return;
          }
          console.debug(logTag, "运行三个脚本A7")
        }
      } catch (_) {
        // 忽略错误
      }
      console.debug(logTag, "运行三个脚本B")
      try {
        if (!current()) {
          return;
        }
        const script = this.checkIsReadyToTypeInPhoneNumber
        const rawResult: string = await controller.runJavaScript(script)
        if (!current()) {
          return;
        }
        const typedResult: boolean | null = jsReturnValueToBoolean(rawResult)
        if (typedResult !== null) {
          const isReadyToTypeInPhoneNumber: boolean = typedResult
          console.debug(logTag, "准备好手机号输入框了吗？", isReadyToTypeInPhoneNumber)
          this.loginViewReady = isReadyToTypeInPhoneNumber
        } else {
          console.debug(logTag, "准备好手机号输入框了吗？", false)
          this.loginViewReady = false
        }
      } catch (_) {
        if (!current()) {
          return;
        }
        // Wrongly typed script results must not retain a stale ready/verified state.
        this.loginViewReady = false
      }
      console.debug(logTag, "运行三个脚本C")
      // 倒计时有60秒呢，总能捕获到的，一秒一次够了
      try {
        if (!current()) {
          return;
        }
        const script = this.checkIsInPostSendSMSState
        const rawResult: string = await controller.runJavaScript(script)
        if (!current()) {
          return;
        }
        const typedResult: boolean | null = jsReturnValueToBoolean(rawResult)
        if (typedResult !== null) {
          const showVerificationCodeBox: boolean = typedResult
          console.debug(logTag, "准备好验证码输入框了吗？", showVerificationCodeBox)
          // 在60秒倒计时结束后，这个值会变成false，刚好用户一分钟没输验证码估计是过期了，就切回发送验证码的页面
          this.showVerificationCodeBox = showVerificationCodeBox
        } else {
          console.debug(logTag, "准备好验证码输入框了吗？", false)
          // 没获取到当然得卡在当前步骤而不是莽撞进入下一步，false
          this.showVerificationCodeBox = false
        }
      } catch (_) {
        if (!current()) {
          return;
        }
        console.debug(logTag, "准备好验证码输入框了吗？", false)
        // Wrongly typed script results must not retain a stale ready/verified state.
        this.showVerificationCodeBox = false
      }
      // alert是长存的，而不像toast转瞬即逝，因此轮询不必很快（不需要0.1s一次）
      try {
        if (!current()) {
          return;
        }
        const script = this.getAlert
        const rawResult: string = await controller.runJavaScript(script)
        if (!current()) {
          return;
        }
        const alert: string | null = jsReturnValueToString(rawResult)
        this.alert = alert
      } catch (_) {
        // 忽略错误
      }
    }, 1000)
    this.toastPoller.start(async (current: () => boolean): Promise<void> => {
      // 运行脚本，我需要保证快速（0.1s一次），因为toast转瞬即逝
      try {
        if (!current()) {
          return;
        }
        const script = this.getToast
        const rawResult: string = await controller.runJavaScript(script)
        if (!current()) {
          return;
        }
        const typedToast: string | null = jsReturnValueToString(rawResult)
        // runJavaScript会把JS侧返回的null变成"null"
        // 注入的JS在该元素内没有文本（比如网页实际上显示的是加载转圈圈而不是文本）的时候，会返回""（注意不是空字符串）
        if (typedToast === null) {
          // 网页上没有显示toast或loadingToast
          this.loadingToast = false
          this.toast = null
        } else if (typedToast === "") {
          // 网页上显示了loadingToast
          this.loadingToast = true
          this.toast = null
        } else {
          // 有toast文本
          this.loadingToast = false
          this.toast = typedToast
        }
      } catch (_) {
        // 忽略错误
      }
    }, 100)
  }

  // 调用者需要检测手机号是11位数字并且以1开头
  async sendSMS(phoneNumber: string, controller: webview.WebviewController) {
    try {
      let script: string = this.typeInPhoneNumber
      // 替换插值
      script = script.replace("😳", phoneNumber)
      await controller.runJavaScript(script)
    } catch (_) {
      // 忽略错误
    }
    // 等待0.16秒再点击发送按钮，让React有时间更新按钮状态
    await Task.sleep(0.16)
    try {
      const script: string = this.tapSendSMSButton
      await controller.runJavaScript(script)
    } catch (_) {
      // 忽略错误
    }
  }

  // 调用者需要检测验证码是6位数字
  async confirmLogin(verificationCode: string, controller: webview.WebviewController) {
    try {
      let script: string = this.typeInVerificationCode
      // 替换插值
      script = script.replace("📳", verificationCode)
      await controller.runJavaScript(script)
    } catch (_) {
      // 忽略错误
    }
    // 等待0.16秒再点击发送按钮，让React有时间更新按钮状态
    await Task.sleep(0.16)
    try {
      const script: string = this.tapComfirmLogin
      await controller.runJavaScript(script)
    } catch (_) {
      // 忽略错误
    }
  }

  onControllerDeattached() {
    this.statePoller.stop();
    this.toastPoller.stop();
  }
}

@ObservedV2
class DouYinLoginPageCheckIsLoggedInModel {
  @Trace
  isLoggedIn: boolean | null = null
  private poller: SerialTaskTimer = new SerialTaskTimer();

  run(cookieURL: string = 'https://www.douyin.com/') {
    this.poller.start(async (current: () => boolean): Promise<void> => {
      const loggedIn = await this.checkIsLoggedIn(cookieURL);
      if (current()) {
        this.isLoggedIn = loggedIn;
      }
    }, 1000);
  }

  stop() {
    this.poller.stop();
  }

  private async checkIsLoggedIn(cookieURL: string): Promise<boolean> {
    try {
      const cookieString: string = await this.getCookiesForDomain(cookieURL)
      // 判定标准与精选页拦截共用一份，但来源仍是 WebCookieManager：
      // 登录页只认「在这个 WebView 里登录过」，开发 Cookie 与导入的 Cookie 文件对它不可见。
      return DouyinCookieStore.hasLoginMarker(cookieString)
    } catch (error) {
      console.debug(logTag,
        "DouYinLoginPageCheckIsLoggedInModel的run()出错：" + error.message ?? JSON.stringify(error, null, 2))
    }
    return false
  }

  /**
   * 获取指定域名的Cookie字符串
   */
  async getCookiesForDomain(domain: string): Promise<string> {
    try {
      if (!domain) {
        throw new Error("getCookiesForDomain失败：参数domain: string是空的");
      }

      // 使用WebCookieManager获取所有cookie
      const cookieManager = webview.WebCookieManager;
      const cookieString = await cookieManager.fetchCookie(domain);
      return cookieString
    } catch (error) {
      throw new Error("getCookiesForDomain失败：" + error.message ?? JSON.stringify(error, null, 2))
    }
  }
}

@ObservedV2
class DouYinLoginPageZoomModel {
  private poller: SerialTaskTimer = new SerialTaskTimer();

  zoom(controller: webview.WebviewController) {

    const isDoneZoomProperty = generateRandomPropertyName()

    this.poller.start(async (_current: () => boolean): Promise<void> => {
      if (controller) {
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
        await controller.runJavaScript(script)
      }
    }, 1000)
  }

  onControllerDeattached() {
    this.poller.stop();
  }
}

@ComponentV2
struct DouYinLoginPlaygroundPage {
  // 在抖音网页里未登录点各个按钮点出来会弹窗的链接
  // 然后登录后再找那些能点的按钮的链接，复制到为登录的浏览器，看看是不是一打开就会弹登录
  // 2026年1月26日测下来，在全功能的WebView下
  // https://www.douyin.com/chat不行
  // https://www.douyin.com/aisearch、https://www.douyin.com/series、https://www.douyin.com/follow、https://www.douyin.com/user可以加载出二维码
  // https://www.douyin.com/pay、https://creator.douyin.com/、https://anchor.douyin.com/加载最快
  // 在默认WebView下，
  // https://www.douyin.com/pay可以加载出来
  @Local
  private loginURLList: Array<string> = ["https://www.douyin.com/follow?from_nav=1",
    "https://www.douyin.com/follow?from_nav=1",
    "https://www.douyin.com/user/self?from_nav=1",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=like",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=favorite_collection",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=record",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=watch_later",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=post",
    "https://www.douyin.com/user/self?enter_from=error_homepage&enter_method=personal_panel&from_tab_name=main&showTab=my_appointment",
    "https://creator.douyin.com/",
    "https://creator.douyin.com/creator-micro/content/manage?enter_from=dou_web",
    "https://creator.douyin.com/creator-micro/data/stats/overview",
    "https://anchor.douyin.com/login?from=lingji_redirect&login_after_redirect=/anchor/dashboard/home",
    "https://creator.douyin.com/creator-school",
    "https://creator.douyin.com/",
    "https://www.douyin.com/chat?isPopup=1",
    "https://www.douyin.com/series?from_nav=1",
    "https://www.douyin.com/pay",
    "https://www.douyin.com/aisearch?from_nav=1"
  ]
  @Local
  private selectedURL: string | null = null
  @Local
  private controller: webview.WebviewController = new webview.WebviewController();
  @Local
  private timerToken: number | null = null

  build() {
    Column() {
      if (this.selectedURL !== null) {
        Web({
          src: this.selectedURL,
          controller: this.controller
        })
          .onControllerAttached(() => {

            const isDoneZoomProperty = generateRandomPropertyName()

            this.timerToken = setInterval(() => {
              if (this.controller) {
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
                this.controller.runJavaScript(script)
              }
            }, 100)
          })
          .onDisAppear(() => {
            // WebviewController解除挂载了就停止使用
            if (this.timerToken !== null) {
              clearInterval(this.timerToken)
            }
          })
          .height("70.71%")
          .width("70.71%")
      } else {
        Scroll() {
          Column() {
            Column({
              space: "7vp"
            }) {
              ForEach(this.loginURLList, (item: string, index: number) => {
                Button(index + "：" + item)
                  .onClick(() => {
                    this.selectedURL = item
                  })
                  .width("100%")
              }, (item: string, index: number) => {
                // 静态列表，索引不变的
                return index.toString()
              })
            }
            .padding({
              start: LengthMetrics.vp(5),
              end: LengthMetrics.vp(5)
            })
            .width("100%")
          }
          .width("100%")
          .padding({
            top: LengthMetrics.vp(50),
            bottom: LengthMetrics.vp(50)
          })
        }
        .edgeEffect(EdgeEffect.Spring)
        .width("100%")
        .height("100%")
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}


// 这不是UUID，而是合法的变量名，用的是下划线而不是横杠
const generateRandomPropertyName = () => {
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