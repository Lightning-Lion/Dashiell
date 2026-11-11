import { restoreBiliSessionCookie, getBiliSessionEpoch, isCurrentBiliSessionEpoch, acceptInteractiveBiliLogin } from '../../common/BiliSession';
import { isBiliLoginReturnURL } from '../../common/BiliCookies';
import { webview } from '@kit.ArkWeb';
import { ErrorPrompt, ErrorPromptData } from '../../components/ErrorPages';
import { DeviceMgr } from '../../common/AlwaysOn';
import { Task } from '../../common/sleep';
import { logTag } from '../../common/printLog';
import { AnimatedProgressView } from '../../components/AnimatedProgressView';
import { DarkTheme } from '../../common/Theme';
import { LogEvents } from '../../utils/log/LogEvents.generated';

const BILI_LOGIN_USER_AGENT: string = 'Mozilla/5.0 (Phone; OpenHarmony 7.0; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36  ArkWeb/7.0.0.105 Mobile HuaweiBrowser/6.1.7.303';

// 从模拟器中 ArkWeb 深色登录页的空白区域采样。
const BILI_LOGIN_BACKGROUND: string = '#17181A';

webview.once("webInited", () => {
  console.debug("configCookieSync");
})

@ObservedV2
class WebViewModel {
  needInit: boolean = true
  controller: webview.WebviewController = new webview.WebviewController();
  // 注入一个脚本，以便网页缩放到适合手表屏幕
  private jsStr: string
  private isControllerReady: boolean = false
  timer: number | undefined = undefined
  smsTimer: number | undefined = undefined
  loadTimer: number | undefined = undefined

  failLoading(message: string): void {
    this.loading = false;
    this.loadingUI = false;
    this.isControllerReady = false;
    this.stopTimers();
    this.error0 = { errorCode: null, errorMessage: message };
  }

  stopTimers(): void {
    if (this.timer !== undefined) { clearInterval(this.timer); }
    if (this.smsTimer !== undefined) { clearInterval(this.smsTimer); }
    if (this.loadTimer !== undefined) { clearTimeout(this.loadTimer); }
    this.isControllerReady = false;
  }
  // 哔哩哔哩登录页要用到的
  @Trace
  loading = true
  @Trace
  loadingUI = true

  // 别忘了在页面关闭的时候也取消亮屏
  @Monitor("loading")
  keepScreenOnWhenLoading() {
    this.checkIsNeedAlwaysOn()
  }

  checkIsNeedAlwaysOn() {
    if (this.loading) {
      DeviceMgr.Ins().requestKeepScreenOn("feedLoading", true)
    } else {
      // 在我设为false后，系统还会给7秒点亮时间
      DeviceMgr.Ins().requestKeepScreenOn("feedLoading", false)
    }
  }

  @Trace
  error0: ErrorPromptData | null = null
  private cleanBiliLoginWebPageJS = `
(() => {
  // 清理返回按钮
  const removeNavbarBack = () => {
    const navbarBackElement = document.querySelector("div.v-nav-bar__left-arrow");

    if (navbarBackElement) {
      navbarBackElement.remove();
      console.debug("Navbar back element successfully removed.");
    } else {
      console.debug('No element with class "v-nav-bar__left-arrow" found.');
    }
  };

  // 清理选择国家和地区的按钮，因为弹出来的选择sheet会被部分遮挡，不好看
  const removeSelectCountry = () => {
    const elements = document.getElementsByClassName('form-area-code-picker');
    while(elements.length > 0) {
        elements[0].parentNode.removeChild(elements[0]);
    }
  };

  // 清理用户协议、隐私政策文本框
  const removeUserAgreement = () => {
    const tipElements = document.querySelectorAll("div.explain-tips");
    tipElements.forEach((element) => {
      element.remove();
    });
  };

  try {
    removeNavbarBack();
  } catch (error) {}

  try {
    removeSelectCountry();
  } catch (error) {}

  try {
    removeUserAgreement();
  } catch (error) {}
})();
  `
  private component: CustomComponent

  constructor(component: CustomComponent) {
    this.jsStr = WebViewModel.getJSStr()
    this.component = component
  }

  onPageEnd() {
    this.isControllerReady = true
  }

  openLoginWebPage(loginWebPageUrl: string) {
    if (!this.needInit) {
      return
    } // 在$rawfile('index.html')完成后，做一次就行了
    this.needInit = false
    // 查看h5页面
    this.controller.setCustomUserAgent(BILI_LOGIN_USER_AGENT)
    // 打开哔哩哔哩的登录页面
    this.controller.loadUrl(loginWebPageUrl)
    // 哔哩哔哩登录完成，会返回到https://m.bilibili.com/
  }

  private static

  getJSStr() {
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
    const isDoneZoomProperty = generateRandomPropertyName()
    const script = `
(() => {
  // 确保在每个页面只设置一次
  if (window.${isDoneZoomProperty}) { return }
  const setViewportScale = () => {
    const zoomLevel = 0.45;
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
    return script
  }

  controllerReady() {
    this.isControllerReady = true
    console.debug("🚩已经标记为isControllerReady = true")
  }

  scaleWebPage() {
    if (!this.isControllerReady) {
      return
    } // 需要先等待WebviewController已经关联到Web组件，在页面刚加载或者卸载后，事情不是这样的
    // 由于在window对象上注入了标记属性，对于每个页面只会执行一次缩放操作
    this.controller.runJavaScript(this.jsStr).catch(() => {})
  }

  cleanBiliLoginWebPage() {
    if (!this.isControllerReady) { return; }
    this.controller.runJavaScript(this.cleanBiliLoginWebPageJS).catch(() => {})
  }

  @Trace
  phoneNumber: string = ""
  @Trace
  fillingPhoneNumberAndHitSendButton: boolean = false
  @Trace
  isPhoneNumberFilledAndSMSSent: boolean = false

  async programmaticFillInPhoneNumberAndHitSendButton() {
    const script0 = `
    (function() {
    // Find the input element by its specific attributes
    const phoneInput = document.querySelector('input[data-v-153f314e][placeholder="请输入手机号码"][type="number"]');

    // Check if the input element exists
    if (phoneInput) {
        // Set the value
        phoneInput.value = '${this.phoneNumber}';

        // Trigger input event for potential listeners
        const inputEvent = new Event('input', { bubbles: true });
        phoneInput.dispatchEvent(inputEvent);

        // Trigger change event for potential listeners
        const changeEvent = new Event('change', { bubbles: true });
        phoneInput.dispatchEvent(changeEvent);

        console.debug('Phone number has been filled successfully');
    } else {
        console.debug('Phone input field not found on the page');
    }
})();
    `
    if (!this.isControllerReady) {
      this.component.getUIContext().getPromptAction().showToast({ message: "等待WebviewController" })
    } // 需要先等待WebviewController已经关联到Web组件，在页面刚加载或者卸载后，事情不是这样的
    // 由于在window对象上注入了标记属性，对于每个页面只会执行一次缩放操作
    await this.controller.runJavaScript(script0)

    const script1 = `
(function() {
  // 查找具有特定选择器的元素
  const verificationButton = document.querySelector('div[data-v-304e0e1f].risk-item-after');

  // 判断元素是否存在
  if (verificationButton) {
    // 调用 click() 触发该按钮
    verificationButton.click();
    console.debug('已点击"获取验证码"按钮');
  } else {
    console.debug('未找到"获取验证码"按钮，请检查选择器是否正确');
  }
})();
`
    await this.controller.runJavaScript(script1)
    // 等待"获取验证码"按钮反应一下，把人机验证弹出来
    await Task.sleep(1.6)
    this.isPhoneNumberFilledAndSMSSent = true
  }

  @Trace
  showEnterVerificationCodeView: boolean = false

  checkIsSMSSent() {
    const script = `
(function() {
  const wrap = document.querySelector('.v-toast__wrap--mask .v-toast__content');
  return !!wrap && wrap.textContent.trim() === '验证码短信已下发';
})();
    `
    if (!this.isControllerReady) {
      return
    } // 需要先等待WebviewController已经关联到Web组件，在页面刚加载或者卸载后，事情不是这样的
    // 由于在window对象上注入了标记属性，对于每个页面只会执行一次缩放操作
    (async () => {
      try {
        const haveSentToast = await this.controller.runJavaScript(script);
        if (this.isControllerReady && haveSentToast === "true") {
          this.showEnterVerificationCodeView = true;
        }
      } catch (_) {
        // The renderer may exit while this request is in flight.
      }
    })()
  }

  @Trace
  verificationCode: string = ""
  @Trace
  fillingVerificationCodeAndTappingDoneLoginButton: boolean = false
  @Trace
  isVerificationCodeEnteredAndDoneLoginButtonTapped: boolean = false

  async programmaticFillInVerificationCodeAndHitDoneLoginButton() {
    const script0 = `
    (function() {
    // Find the verification code input element by its specific attributes
    const verificationInput = document.querySelector('input[placeholder="请输入验证码"][type="text"].risk-input-dom');

    // Check if the input element exists
    if (verificationInput) {
        // Set the value
        verificationInput.value = '${this.verificationCode}';

        // Trigger input event for potential listeners
        const inputEvent = new Event('input', { bubbles: true });
        verificationInput.dispatchEvent(inputEvent);

        // Trigger change event for potential listeners
        const changeEvent = new Event('change', { bubbles: true });
        verificationInput.dispatchEvent(changeEvent);

        console.debug('Verification code has been filled successfully');
    } else {
        console.debug('Verification code input field not found on the page');
    }
})();
    `
    if (!this.isControllerReady) {
      this.component.getUIContext().getPromptAction().showToast({ message: "等待WebviewController" })
      return
    } // 需要先等待WebviewController已经关联到Web组件，在页面刚加载或者卸载后，事情不是这样的
    // 由于在window对象上注入了标记属性，对于每个页面只会执行一次缩放操作
    await this.controller.runJavaScript(script0)
    // 网页要确认验证码输入框里已经有数字了，登录按钮才会亮起来
    this.component.getUIContext().getPromptAction().showToast({ message: "登录中", duration: 1 * 1000 })
    await new Promise<void>(resolve => setTimeout(resolve, 1 * 1000));
    const clickConfirmLoginButton = `
(() => {
  const loginButtons = document.querySelectorAll('div[type="pink"].form-btn.login-btn');
  for (const btn of loginButtons) {
    const r = btn.getBoundingClientRect();
    const style = window.getComputedStyle(btn);
    if (r.width > 0 && r.height > 0 && style.visibility !== 'hidden' &&
        style.visibility !== 'collapse' && !btn.hasAttribute('disabled') &&
        btn.getAttribute('aria-disabled') !== 'true') {
      btn.click();
      break;
    }
  }
})();
    `
    await this.controller.runJavaScript(clickConfirmLoginButton)
    this.isVerificationCodeEnteredAndDoneLoginButtonTapped = true
  }
}


@ObservedV2
export class BiliIsLoggedInData {
  @Trace
  public isLoggedIn: boolean = false;
  public verifiedCookie: string | undefined = undefined;
  public verifiedEpoch: number = -1;

  constructor(defaultValue: boolean) {
    this.isLoggedIn = defaultValue
  }
}

export interface WebViewInitData {
  loginWebPageUrl: string
  redirectWebPageUrl: string
}

export const bilibiliWebView: WebViewInitData = {
  loginWebPageUrl: "https://passport.bilibili.com/h5-app/passport/login?gourl=https%3A%2F%2Fm.bilibili.com%2F",
  redirectWebPageUrl: "https://m.bilibili.com/"
}

// 如果用户是刚刚完成登录的，在返回的时候需要强制重新进入一下，这样会使用BilibiliService而不是BilibiliServiceWithoutLogin
@ObservedV2
export class NewlyDoneLoginModel {
  @Trace
  newlyDoneLogin:boolean = false
}

@Entry
@ComponentV2
export struct BiliLoginWebViewPage {
  @Param @Require isLoggedInPack: BiliIsLoggedInData
  @Param @Require webViewInitData: WebViewInitData
  @Local
  private vm: WebViewModel = new WebViewModel(this);
  @Param @Require newlyDoneLoginModel:NewlyDoneLoginModel

  private loginEpoch: number = getBiliSessionEpoch();
  private verifyingLogin: boolean = false;
  private disposed: boolean = false;

  private async finishLogin(address: string): Promise<void> {
    if (this.disposed || !isCurrentBiliSessionEpoch(this.loginEpoch) || this.verifyingLogin ||
      this.isLoggedInPack.isLoggedIn || !isBiliLoginReturnURL(address)) {
      return;
    }
    this.verifyingLogin = true;
    const epoch = this.loginEpoch;
    try {
      const cookie = await restoreBiliSessionCookie(address, epoch);
      if (cookie === undefined || this.disposed) { return; }
      await webview.WebCookieManager.saveCookieAsync();
      if (this.disposed || !isCurrentBiliSessionEpoch(epoch)) { return; }
      acceptInteractiveBiliLogin();
      this.isLoggedInPack.verifiedEpoch = getBiliSessionEpoch();
      this.isLoggedInPack.verifiedCookie = cookie;
      this.newlyDoneLoginModel.newlyDoneLogin = true;
      this.vm.stopTimers();
      this.vm.loading = false;
      this.isLoggedInPack.isLoggedIn = true;
      LogEvents.biliLoginSucceeded();
    } catch (error) {
      LogEvents.biliLoginFailed(error);
      if (!this.disposed) {
        this.vm.failLoading('登录状态验证或保存失败，请返回后重试；无需先退出账号');
      }
    } finally { this.verifyingLogin = false; }
  }

  aboutToAppear(): void {
    console.debug('🚩Navigation--->页面显示时的回调:aboutToAppear');
    this.vm.timer = setInterval(() => {
      this.vm.scaleWebPage()
      this.vm.cleanBiliLoginWebPage()
    }, 1000)
    // 快速检查，捕捉到这个弹窗
    this.vm.smsTimer = setInterval(() => {
      this.vm.checkIsSMSSent()
    }, 250)
    this.vm.loadTimer = setTimeout(() => {
      this.vm.failLoading("登录网页加载超时，请返回后重试");
    }, 30000)
    console.debug("🚩当前的IntervalId", this.vm.timer)
    this.vm.checkIsNeedAlwaysOn()
  }

  aboutToDisappear(): void {
    console.debug('🚩Navigation--->页面销毁时的回调');
    this.disposed = true;
    this.vm.stopTimers();
    DeviceMgr.Ins().requestKeepScreenOn("feedLoading", false);
    if (this.vm.timer != undefined) {
      console.debug("🚩当前的IntervalId", this.vm.timer)
      clearInterval(this.vm.timer)
    }
  }

  build() {
    Stack() {
      Column() {
        // 创建WebView（无遮挡）
        Column() {
          Web({ src: this.webViewInitData.loginWebPageUrl, controller: this.vm.controller })
            .userAgent(BILI_LOGIN_USER_AGENT)
            .darkMode(WebDarkMode.On)
            .forceDarkAccess(true)
            .onPageEnd((event) => {
              if (this.vm.error0 !== null || this.disposed) { return; }
              if (this.vm.loadTimer !== undefined) { clearTimeout(this.vm.loadTimer); }
              this.vm.loading = false;
              this.vm.loadingUI = false;
              this.vm.controllerReady();
              if (event) { this.finishLogin(event.url); }
            })
            .onErrorReceive((event) => {
              if (event.request.isMainFrame()) {
                console.debug(logTag, "发生了错误：\n" + event.error.getErrorInfo())
                this.vm.failLoading("登录网页加载失败，请返回后重试")
              }
            })
            .onRenderExited(() => {
              this.vm.failLoading("登录网页进程已退出，请返回后重试");
            })
            .overScrollMode(OverScrollMode.NEVER)
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
            // 不然一开始加载中就是白色背景
            .backgroundColor(Color.Transparent)
        }
        .height('90%')
        .width('80%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center) // 垂直居中
      .alignItems(HorizontalAlign.Center) // 水平居中
      .backgroundColor(BILI_LOGIN_BACKGROUND) // 与强制深色网页保持一致
      if (
        (this.vm.showEnterVerificationCodeView === true) // 已经发出了短信验证码
          &&
          (this.vm.isVerificationCodeEnteredAndDoneLoginButtonTapped === false) // 还没有输入短信验证码
      ) {
        Column({ space: "10vp" }) {
          Text("验证码已发送")
            .fontWeight(FontWeight.Bold)
          TextInput({ placeholder: "请输入验证码", text: $$this.vm.verificationCode })
            .backgroundColor(DarkTheme.textFieldBackground)
            .type(InputType.Number)
            .textAlign(TextAlign.Center)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Column() {
              Row() {
                if (this.vm.fillingVerificationCodeAndTappingDoneLoginButton === true) {
                  LoadingProgress().width(20).height(20).color(0xFFFFFF)
                } else {
                  Text("完成登录").fontSize(18).fontWeight(FontWeight.Medium).fontColor(0xffffff)
                }
              }.alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
            }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).width(120).height(40)
          }.backgroundColor(0x317aff)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            if (this.vm.verificationCode.length !== 0) {
              (async () => {
                this.getUIContext().animateTo({ duration: 300 }, () => {
                  this.vm.fillingVerificationCodeAndTappingDoneLoginButton = true
                })
                try {
                  await this.vm.programmaticFillInVerificationCodeAndHitDoneLoginButton();
                } catch (error) {
                  if (!this.disposed) {
                    this.getUIContext().getPromptAction().showToast({ message: '验证码提交未完成，请在登录页面重试' });
                  }
                } finally {
                  this.vm.fillingVerificationCodeAndTappingDoneLoginButton = false;
                }
              })()
            }
          })
        }
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
        .backgroundColor(BILI_LOGIN_BACKGROUND)
        // 入场也需要动画
        .transition(TransitionEffect.OPACITY.animation({}))
      }

      if (this.vm.isPhoneNumberFilledAndSMSSent === false) {
        Column({ space: "20px" }) {
          Text("登录哔哩哔哩账号")
            .fontWeight(FontWeight.Bold)
            .margin({ left: "30px", right: "30px" })
          TextInput({ placeholder: "输入手机号", text: $$this.vm.phoneNumber })
            .backgroundColor(DarkTheme.textFieldBackground)
            .type(InputType.PhoneNumber)
            .contentType(ContentType.PHONE_NUMBER)
            .textAlign(TextAlign.Center)
            .clickEffect({ level: ClickEffectLevel.LIGHT })

          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Column() {
              Row() {
                if (this.vm.fillingPhoneNumberAndHitSendButton === true) {
                  LoadingProgress().width(20).height(20).color(0xFFFFFF)
                } else {
                  Text("发送验证码").fontSize(18).fontWeight(FontWeight.Medium).fontColor(0xffffff)
                }
              }.alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
            }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).width(120).height(40)
          }
          .backgroundColor(0x317aff)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            if (this.vm.phoneNumber.length !== 0) {
              (async () => {
                this.getUIContext().animateTo({ duration: 300 }, () => {
                  this.vm.fillingPhoneNumberAndHitSendButton = true
                })
                await this.vm.programmaticFillInPhoneNumberAndHitSendButton()
                this.getUIContext().animateTo({ duration: 300 }, () => {
                  this.vm.fillingPhoneNumberAndHitSendButton = false
                })
              })()
            } else {
              this.getUIContext().getPromptAction().showToast({ message: '请输入您的哔哩哔哩账号绑定的手机号' });
            }
          })
        }
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
        .backgroundColor(BILI_LOGIN_BACKGROUND)
        // 渐隐离场
        .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY, TransitionEffect.OPACITY.animation({})))
      }

      if (this.vm.loadingUI === true) {
        Column({ space: "30px" }) {
          AnimatedProgressView({ color: DarkTheme.biliPink })
            .width(50)
            .height(50)
          Text("正在加载")
            .fontColor(DarkTheme.biliPink)
            .fontWeight(FontWeight.Bold)
        }
        .justifyContent(FlexAlign.Center)
        .width("100%")
        .height("100%")
        // 这一层压着登录 WebView，底色保持 BILI_LOGIN_BACKGROUND：
        // 它要和强制深色网页一致，换成彩色渐变会在网页加载途中闪色
        .backgroundColor(BILI_LOGIN_BACKGROUND)
        // 渐隐离场
        .transition(TransitionEffect.asymmetric(TransitionEffect.IDENTITY, TransitionEffect.OPACITY))
      }
      if (this.vm.error0 !== null) {
        Stack() {
          Column() {
          }.width("100%").height("100%").backgroundColor(BILI_LOGIN_BACKGROUND)

          ErrorPrompt({
            errorCode: this.vm.error0.errorCode,
            errorMessage: this.vm.error0.errorMessage,
            showCloseButton: false,
            showRetryButton: false
          }).defaultFocus(true)
            .focusable(true)
            .focusOnTouch(true)
        }
        .transition(TransitionEffect.OPACITY.animation({}))
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
      }
    }
    .onDisAppear(() => {
      DeviceMgr.Ins().requestKeepScreenOn("feedLoading", false)
    })
    .width('100%')
    .height('100%')
  }
}