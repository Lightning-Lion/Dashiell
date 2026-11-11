import { ArcScrollBar } from '@ohos.arkui.ArcScrollBar'
import { LengthMetrics } from '@kit.ArkUI'
import { BusinessError, pasteboard } from '@kit.BasicServicesKit'
import { randomElement } from '../../common/ArrayExtension'

interface AddRSSItem {
  title: string
  description: string
  url: string
  highlight: boolean
}

@Builder
export function FindMoreRSSPageBuilder() {
  FindMoreRSSPage()
}

@ObservedV2
class FindMoreRSSPageViewModel {
  @Trace
  items: AddRSSItem[] = [
    {
      title: "哔哩哔哩RSS",
      description: "🔥【力荐】哔哩哔哩RSS",
      url: "https://rss.dashiell.cn/",
      highlight: true
    },
    {
      title: "抖音RSS",
      description: "这是一个聚合了抖音平台上热门、有趣、富有创意的短视频内容的资讯源，涵盖了生活技巧、娱乐热点、知识科普、音乐舞蹈、美食旅行等多领域的高热度推荐内容。",
      url: "https://www.douyin.com/",
      highlight: false
    },
    {
      title: "3DM - 新闻中心",
      description: "这是一个专注于游戏新闻、行业动态、新作发布及相关硬件资讯的资讯源。",
      url: "https://rss.dashiell.cn/3dmgame/news/",
      highlight: false
    },
    {
      title: "IT之家",
      description: "这是一个聚焦于科技、数码、汽车、AI、互联网等领域最新新闻和产品资讯的资讯源。",
      url: "https://www.ithome.com/rss/",
      highlight: false
    },
    {
      title: "知乎日报",
      description: randomElement(["这是一个提供多样化话题内容的资讯平台，涵盖科学、文化、历史、科技等领域，以通俗易懂的方式呈现深度知识和讨论的资讯源。",
        "这是一个提供多样化话题内容的资讯平台，涵盖科学、文化、历史、科技、心理学等领域，以深度解析和趣味性问答形式吸引读者的资讯源。"]) ??
        "加载失败（0x033D）",
      url: "https://rss.dashiell.cn/zhihu/daily/",
      highlight: false
    },
    {
      title: "知乎热榜",
      description: "这是一个内容涵盖时事新闻、社会热点、科技、娱乐、体育等多个领域，提供最新的讨论话题和深度分析的资讯源。",
      url: "https://rss.dashiell.cn/zhihu/hot/",
      highlight: false
    },
  ]
}

@ComponentV2
struct FindMoreRSSPage {
  @Local
  private vm: FindMoreRSSPageViewModel = new FindMoreRSSPageViewModel()
  @Local
  private scroller: Scroller = new Scroller()

  build() {
    NavDestination() {
      Column() {
        Stack({ alignContent: Alignment.End }) {
          Scroll(this.scroller) {
            Column({
              space: "22fp"
            }) {
              Text("腕上RSS 推荐")
                .fontSize("24fp")
                .fontWeight(FontWeight.Medium)
                .copyOption(CopyOptions.InApp)
                .padding({
                  start: LengthMetrics.fp(20),
                  end: LengthMetrics.fp(20)
                })
              ForEach(this.vm.items, (item: AddRSSItem) => {
                RSSItemsCard({
                  title: item.title,
                  description: item.description,
                  url: item.url,
                  highlight: item.highlight
                })
              })
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width("100%")
            .padding({
              top: LengthMetrics.fp(70),
              bottom: LengthMetrics.fp(50)
            })
          }
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
          .focusable(true)
          .defaultFocus(true)
          .focusOnTouch(true)

          ArcScrollBar({ scroller: this.scroller })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")
      .height("100%")
    }
    .hideBackButton(true)
  }
}


@ComponentV2
struct RSSItemsCard {
  @Param @Require title: string
  @Param @Require description: string
  @Param @Require url: string
  @Param @Require highlight: boolean

  build() {
    Column({ space: "16fp" }) {
      Column({ space: "13fp" }) {
        Row({ space: "8fp" }) {
          Text(this.title)
            .fontSize("18fp")
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.InApp)
          Blank()
          Button({
            type: ButtonType.Normal,
            role: ButtonRole.NORMAL,
            buttonStyle: ButtonStyleMode.NORMAL,
            stateEffect: true
          }) {
            Text("复制")
              .fontColor(Color.Black)
              .padding("8fp")
          }
          .backgroundColor("#86DFBA")
          .borderRadius("2fp")
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.copyText(this.url)
          })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width("100%")

        Column({ space: "8fp" }) {
          Text(this.description)
            .fontSize("12fp")
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.InApp)
          Text("源地址 " + this.url)
            .fontSize("12fp")
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.InApp)
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .width("100%")
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding("14fp")
      .width("100%")
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .border({
      color: this.highlight ? $r("app.color.brand_color") : "#2A2A2C",
      width: "1fp"
    })
    .backgroundColor(this.highlight ? "#8F0A1D" : "#1E1E1E")
    .width("90%")
  }

  private copyText(text: string) {
    (async () => {
      try {
        const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        systemPasteboard.setData(pasteboardData)
        await systemPasteboard.getData()
        this.getUIContext().getPromptAction().showToast({ message: "已复制口令 请从左侧划动返回", duration: 1000 })
      } catch (error) {
        const typedError: BusinessError = error
        this.getUIContext().getPromptAction().showToast({ message: typedError.message })
      }
    })()
  }
}