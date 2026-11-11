import { CardInfo, StackWidgetPage } from "../../components/StackWidgetPage"
import { DouyinCookieStore } from '../../common/douyin/DouyinCookieStore';
import { pushDouYinLoginRequired } from './DouYinLoginRequiredPage';

// 本页专用配色：暗色宝石。低饱和、同明度、统一收尾到近黑墨色，
// 取代原先的糖果色渐变。白字/白图标在亮端最低 5.8:1，过 WCAG AA。
// 只作用于抖音菜单，不进入全局 Theme，避免影响哔哩哔哩菜单。
interface DouYinMenuPalette {
  featured: [ResourceColor, number][]
  collected: [ResourceColor, number][]
  liked: [ResourceColor, number][]
  mine: [ResourceColor, number][]
  contact: [ResourceColor, number][]
  about: [ResourceColor, number][]
}

const DOUYIN_MENU_PALETTE: DouYinMenuPalette = {
  // 精选：保留抖音红 #FE2C55 的 348° 色相，只压暗降饱和
  featured: [['#8E3347', 0], ['#2B1219', 1]],
  // 我的收藏：铜棕暖金，不再是橙黄高亮
  collected: [['#8A5B32', 0], ['#2A1D11', 1]],
  // 我的喜欢：梅紫，和精选同属暖色但偏紫，彻底去掉重复
  liked: [['#873566', 0], ['#291222', 1]],
  // 我的：靛蓝冷色，和喜欢拉开距离
  mine: [['#35487A', 0], ['#141A2B', 1]],
  // 联系我们：松绿，替换原来的亮紫
  contact: [['#2D625C', 0], ['#10201F', 1]],
  // 关于：石墨中性色，不抢前 5 张的情绪色
  about: [['#4E535C', 0], ['#191B1F', 1]]
}


@Builder
export function DouYinMenuBuilder(name: string, param: Object) {
  DouYinMenu()
}

@ComponentV2
export struct DouYinMenu {
  @Computed
  private get cardData() {
    const list: Array<CardInfo> = [
      {
        title: '精选',
        svgIcon: $r("app.media.dou_menu_jingxuan"),
        gradientColors: DOUYIN_MENU_PALETTE.featured,
        onClick:(pageInfos: NavPathStack) => { this.card0Click(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: '我的收藏',
        svgIcon: $r("app.media.dou_menu_jingxuan"),
        gradientColors: DOUYIN_MENU_PALETTE.collected,
        onClick: (pageInfos: NavPathStack) => {
          this.openGuardedPage(pageInfos, 'DouyinCollectedPage', '收藏')
        }
      },
      {
        title: '我的喜欢',
        svgIcon: $r("app.media.dou_menu_login"),
        gradientColors: DOUYIN_MENU_PALETTE.liked,
        onClick: (pageInfos: NavPathStack) => {
          this.openGuardedPage(pageInfos, 'DouyinLikedPage', '喜欢')
        }
      },
      {
        title: "我的",
        svgIcon: $r("app.media.dou_menu_login"),
        gradientColors: DOUYIN_MENU_PALETTE.mine,
        onClick:(pageInfos: NavPathStack) => { this.card1Click(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: '联系我们',
        svgIcon: $r("app.media.stack_contact_us_icon"),
        gradientColors: DOUYIN_MENU_PALETTE.contact,
        onClick:(pageInfos: NavPathStack) => { this.card2Click(pageInfos) } // 在实际点击的时候才调用我的的函数
      },
      {
        title: '关于',
        svgIcon: $r("app.media.AboutIcon"),
        gradientColors: DOUYIN_MENU_PALETTE.about,
        onClick:(pageInfos: NavPathStack) => { this.card3Click(pageInfos) } // 在实际点击的时候才调用我的的函数
      }
    ]
    return list
  }
  @Local
  private myNavID:string | null = null
  private openingGuardedPage: boolean = false
  build() {
    StackWidgetPage({
      cardData:this.cardData,
      onNavReady:(context: NavDestinationContext) => {
        if (context.navDestinationId !== undefined) {
          this.myNavID = context.navDestinationId
        }
      }
    })
  }
  private card0Click(pageInfos: NavPathStack) {
    this.openGuardedPage(pageInfos, "DouYinJingxuanPage", '精选')
  }

  /**
   * 抖音的登录判定要读 Cookie，是异步的；所以入口先查一次，未登录时把登录中间页
   * 插到功能页前面。页内整页拦截仍保留，覆盖启动直达和深链直接打开功能页的情况。
   */
  private async openGuardedPage(pageInfos: NavPathStack, route: string, featureName: string): Promise<void> {
    if (this.openingGuardedPage) { return; }
    this.openingGuardedPage = true;
    const uiContext = this.getUIContext();
    try {
      let loggedIn = false;
      try {
        loggedIn = await DouyinCookieStore.isLoggedIn();
      } catch (error) {
        loggedIn = false;
      }
      if (loggedIn) {
        pageInfos.pushPathByName(route, undefined);
        return;
      }
      if (!pushDouYinLoginRequired(pageInfos, featureName, route)) {
        uiContext.getPromptAction().showToast({
          message: "无法打开页面\n错误信息：导航堆栈未准备就绪"
        });
      }
    } finally {
      this.openingGuardedPage = false;
    }
  }
  private card1Click(pageInfos: NavPathStack) {
    pageInfos.pushPathByName("DouYinLoginPage", undefined)
  }
  private card2Click(pageInfos: NavPathStack) {
    pageInfos.pushPathByName("CustomerServicePage", undefined)
  }
  private card3Click(pageInfos: NavPathStack) {
    pageInfos.pushPathByName("DouYinAboutPage", undefined)
  }
}
