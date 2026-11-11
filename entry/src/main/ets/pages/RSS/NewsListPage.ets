import { ListDataSource } from '../../common/ListDataSource';
import { ReadRequestScope, ReadRequestCancelled } from '../../common/ReadRequestScope';
import { TimedMemoryCache } from '../../common/TimedMemoryCache';
import { watchWidthFp } from "../../common/ScreenSize"
import { ComponentContent, LengthMetrics } from "@kit.ArkUI"
import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute } from '@kit.ArkUI';
import { AnimatedProgressView } from "../../components/AnimatedProgressView";
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logTag } from "../../common/printLog";
import { convertxml } from "@kit.ArkTS";
import { ErrorPrompt } from "../../components/ErrorPages";
import { UUID } from "../../common/UUID";
import { DeviceMgr } from "../../common/AlwaysOn";
import { feedSourceKindFromURL, feedSourceTopGradient, feedSourceAccent,
  FeedSourceKind } from "../../common/rss/FeedSources";
import { warmUpArkWeb } from "../../common/ArkWebWarmup";
import { ArticleMode, NativeArticlePagePushData } from "./NativeArticlePage";
import { requestFocusWithRetry } from '../../common/WatchListFocus';
import { LogEvents } from '../../utils/log/LogEvents.generated';

/** 缓存命中与网络成功共用,保证 rssListFetchDone 只有一个调用点。 */
function logRssListFetchDone(count: number, elapsedMs: number, cache: boolean): void {
  LogEvents.rssListFetchDone({ count: count, elapsedMs: elapsedMs, cache: cache });
}

// Cache complete feeds under an estimated 2 MiB text budget; fresh entries avoid repeat requests.
// The raw description HTML (the full article body for bundled feeds) dominates the weight.
const rssMemoryCache = new TimedMemoryCache<Array<RSSSourceDetailListItem>>(8, 2 * 1024 * 1024, 60000);
function saveRSSMemoryCache(source: string, items: Array<RSSSourceDetailListItem>): void {
  let weight = 0;
  for (const item of items) {
    weight += 128 + 2 * (item.id.length + (item.title?.length ?? 0) +
      (item.description?.length ?? 0) + (item.url?.length ?? 0)) +
      (item.contentHTML?.length ?? 0);
  }
  rssMemoryCache.put(source, items, weight);
}

export interface ReadingSourcePagePushData {
  displayTitle: string
  sourceURL: string
}

@Builder
export function ReadingSourcePageBuilder(_name: string, param: Object) {
  ReadingSourcePage({
    displayTitle: (param as ReadingSourcePagePushData).displayTitle,
    source: (param as ReadingSourcePagePushData).sourceURL
  })
}

@ObservedV2
class FetchDataError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

@ComponentV2
struct ReadingSourcePage {
  @Param @Require displayTitle: string
  @Param @Require source: string
  @Local
  private pageInfos: NavPathStack | null = null
  @Local
  private items: Array<RSSSourceDetailListItem> | null = null
  @Local
  private errorMessage: string | null = null
  @Local
  private xmlParser: RSSXMLParser = new RSSXMLParser()

  @Computed
  get sourceKind(): FeedSourceKind {
    return feedSourceKindFromURL(this.source);
  }

  private requests: ReadRequestScope = new ReadRequestScope();
  private disposed: boolean = false;
  private requestGeneration: number = 0;
  private fetching: boolean = false;

  aboutToDisappear(): void {
    this.disposed = true;
    this.requestGeneration++;
    this.requests.cancel();
    this.fetching = false;
    DeviceMgr.Ins().requestKeepScreenOn('loadingRSS', false);
  }

  build() {
    NavDestination() {
      Column() {
        if (this.items !== null) {
          if (this.errorMessage !== null) {
            Button('更新失败，点击重试').fontSize(12).height(30)
              .onClick(() => this.fetchData(true))
          }
          ArcListView({
            displayTitle: this.displayTitle,
            items: this.items,
            pageInfos: this.pageInfos
          })
            .layoutWeight(1)
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        } else if (this.errorMessage !== null) {
          ErrorPrompt({
            errorCode: null,
            errorMessage: this.errorMessage,
            showCloseButton: false,
            showRetryButton: true,
            onRetry: () => {
              this.fetchData(true)
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        } else {
          Column({ space: "30px" }) {
            AnimatedProgressView({ color: feedSourceAccent(this.sourceKind) })
              .width(50)
              .height(50)
            Text("加载中")
              .fontColor(feedSourceAccent(this.sourceKind))
              .fontWeight(FontWeight.Bold)
          }
          .justifyContent(FlexAlign.Center)
          .width("100%")
          .height("100%")
          // 不铺底色，让 NavDestination 上该模块的顶部渐变透出来
          .onAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn("loadingRSS", true)
          })
          .onDisAppear(() => {
            DeviceMgr.Ins().requestKeepScreenOn("loadingRSS", false)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width("100%")
      .height("100%")

    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不能铺不透明底色，否则会盖住它
    // 每个资讯源用自己的色相，认不出源的自定义 RSS 退回品牌红
    .linearGradient({ colors: feedSourceTopGradient(this.sourceKind) })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onAppear(() => {
      // 知乎热榜的条目点进去是隐藏 ArkWeb 过安全校验再取 initialData 的：趁读者还在挑条目，
      // 先把 Web 引擎和 zhihu.com 的连接准备好，那段时间就不再算在打开问答页的等待里。
      if (this.sourceKind === FeedSourceKind.ZhihuHot) {
        warmUpArkWeb('https://www.zhihu.com/')
      }
      this.fetchData()
    })
  }

  private async fetchData(force: boolean = false): Promise<void> {
    if (this.disposed || this.fetching) { return; }
    const started = Date.now();
    this.errorMessage = null;
    const cached = rssMemoryCache.get(this.source);
    if (cached !== undefined) {
      this.items = cached.value;
      if (!force && cached.expiresAt > Date.now()) {
        logRssListFetchDone(cached.value.length, Date.now() - started, true);
        return;
      }
    }
    this.fetching = true;
    const generation = ++this.requestGeneration;
    try {
      const response = await this.requests.get(this.source, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'Dashiell/1.0', 'Accept': 'application/rss+xml, application/xml, text/xml' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 8000
      });
      if (this.disposed || generation !== this.requestGeneration) { return; }
      if (response.responseCode !== 200) { throw new FetchDataError(`资讯源暂不可用（HTTP ${response.responseCode}），请稍后重试`); }
      if (typeof response.result !== 'string') { throw new FetchDataError('资讯源返回数据格式异常'); }
      const items = this.xmlParser.parserXMLGeneric(response.result, this.sourceKind);
      saveRSSMemoryCache(this.source, items);
      this.items = items;
      logRssListFetchDone(items.length, Date.now() - started, false);
    } catch (error) {
      if (this.disposed || generation !== this.requestGeneration || error instanceof ReadRequestCancelled) { return; }
      const reason = error instanceof FetchDataError ? error.message : 'load-failed';
      LogEvents.rssListFetchFailed({ reason: reason });
      this.errorMessage = error instanceof FetchDataError ? error.message : '资讯加载失败，请检查网络后重试';
    } finally {
      if (generation === this.requestGeneration) { this.fetching = false; }
    }
  }


}
@ObservedV2
class RSSXMLParser {
  private parserCSDNXML(strXML: string) {
    try {
      let conv = new convertxml.ConvertXML();
      let options: convertxml.ConvertOptions = {
        trim: false,
        declarationKey: "_declaration",
        instructionKey: "_instruction",
        attributesKey: "_attributes",
        textKey: "_text",
        cdataKey: "_cdata",
        doctypeKey: "_doctype",
        commentKey: "_comment",
        parentKey: "_parent",
        typeKey: "_type",
        nameKey: "_name",
        elementsKey: "_elements"
      };
      const xml: XMLModel = conv.fastConvertToJSObject(strXML, options) as XMLModel;
      if (xml._elements.length > 0) {
        const root = xml._elements[0];
        if (root._elements.length > 0) {
          const channel = root._elements[0];
          if (channel._elements.length > 0) {
            const channelElements = channel._elements;
            for (let i = 0; i < channelElements.length; i++) {
              if (channelElements[i]._name === "item") {
              }
            }
          } else {
            console.debug(logTag, `${channel._name} 为空`)
          }
        } else {
          console.debug(logTag, `${root._name} 没有子元素`)
        }
      } else {
        console.debug(logTag, "当前XML为空")
      }
    } catch (e) {
      console.debug(logTag, `parserXML error: ${e}`)
    }
  }

  parserXMLGeneric(strXML: string, sourceKind: FeedSourceKind) {
    let rssItems: RSSSourceDetailListItem[] = []
    try {
      let conv = new convertxml.ConvertXML();
      let options: convertxml.ConvertOptions = {
        trim: false,
        declarationKey: "_declaration",
        instructionKey: "_instruction",
        attributesKey: "_attributes",
        textKey: "_text",
        cdataKey: "_cdata",
        doctypeKey: "_doctype",
        commentKey: "_comment",
        parentKey: "_parent",
        typeKey: "_type",
        nameKey: "_name",
        elementsKey: "_elements"
      };
      const xml: XMLModel = conv.fastConvertToJSObject(strXML, options) as XMLModel;
      const root = xml._elements?.find((element: Element) => element._name === 'rss');
      const channel = root?._elements?.find((element: Element) => element._name === 'channel');
      if (root === undefined || channel === undefined) {
        throw new FetchDataError('资讯源没有返回有效 RSS，可能暂时不可用，请稍后重试');
      }
      const identifiers: Map<string, number> = new Map();
      for (const item of channel._elements ?? []) {
        if (item._name !== 'item') { continue; }
        const elements = item._elements ?? [];
        const title = this.elementContent(elements.find((element: Element) => element._name === 'title'));
        const link = this.elementContent(elements.find((element: Element) => element._name === 'link'));
        const description = this.elementContent(elements.find((element: Element) => element._name === 'description'));
        const enclosure = elements.find((element: Element) => element._name === 'enclosure');
        const enclosureURL = enclosure !== undefined && enclosure._attributes !== undefined ?
          this.undefinedStringToNullString(enclosure._attributes['url']) : null;
        const pubDate = this.elementContent(elements.find((element: Element) => element._name === 'pubDate'));
        const base = this.elementContent(elements.find((element: Element) => element._name === 'guid')) ||
          link || title || 'item-' + rssItems.length;
        const duplicate = identifiers.get(base) ?? 0;
        identifiers.set(base, duplicate + 1);
        rssItems.push({ id: base.length + ':' + base + ':' + duplicate,
          title: title, description: description === null ? null : this.cleanHtml(description), url: link,
          contentHTML: description, enclosureURL: enclosureURL, pubDate: pubDate, sourceKind: sourceKind });
      }
    } catch (error) {
      if (error instanceof FetchDataError) { throw error; }
      throw new FetchDataError('资讯数据解析失败，请稍后重试');
    }
    return rssItems
  }

  private undefinedStringToNullStringWithMap(undefinedString: string | undefined,
    mapAction: (stringValu: string) => string) {
    if (undefinedString !== undefined) {
      return mapAction(undefinedString)
    } else {
      return null
    }
  }

  private undefinedStringToNullString(undefinedString: string | undefined) {
    if (undefinedString !== undefined) {
      return undefinedString
    } else {
      return null
    }
  }

  private elementContent(element: Element | undefined): string | null {
    if (element === undefined || !element._elements || element._elements.length === 0) {
      return null
    }
    const child = element._elements[0]
    return child._text ?? child._cdata ?? null
  }

  private cleanHtml(html: string): string {
    if (!html) {
      return ''
    }

    // 移除HTML标签并解码HTML实体
    return html
      .replace(/<[^>]*>/g, '') // 移除HTML标签
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&nbsp;/g, ' ')
      .trim()
      .substring(0, 200) // 限制描述长度
  }
}


export class Element {
  _type: string = "";
  _name: string = "";
  _parent: string = "";
  _cdata: string = "";
  _text: string = "";
  _elements: Element[] = [];
  _attributes: Record<string, string> = {};
}

export class Attributes {
  version: string = "";
  encoding: string = "utf-8";
}

export class Declaration {
  _attributes: Attributes = new Attributes();
}

export class XMLModel {
  _declaration: Declaration = new Declaration();
  _elements: Element[] = [];
}

interface RSSSourceDetailListItem {
  id: string,
  title: string | null
  description: string | null
  url: string | null
  // Raw description HTML: for the bundled feeds this IS the full article body.
  contentHTML: string | null
  enclosureURL: string | null
  pubDate: string | null
  sourceKind: FeedSourceKind
}

interface ParamsInterface {
  text: string;
}

@Entry
@ComponentV2
export struct ArcListView {
  @Param @Require displayTitle: string
  @Param @Require items: Array<RSSSourceDetailListItem>
  @Param @Require
  pageInfos: NavPathStack | null = null
  @Local
  private listSize: string = (watchWidthFp * 0.78) + "fp" // item宽度
  @Local
  private listRowBackgroundColor: Resource = $r("app.color.list_row_background_color")
  @Local
  private titleView: ComponentContent<Object> = new ComponentContent<ParamsInterface>(this.getUIContext(),
    wrapBuilder<[ParamsInterface]>(ArcListTitleView), {
      text: this.displayTitle
    }, { nestingBuilderSupported: true });
  @Local
  private pageID: string = UUID()

  private dataSource: ListDataSource<RSSSourceDetailListItem> = new ListDataSource<RSSSourceDetailListItem>();

  aboutToAppear(): void { this.dataSource.replace(this.items); }

  @Monitor('items')
  private refreshItems(): void { this.dataSource.replace(this.items); }

  aboutToDisappear(): void {
    this.titleView.dispose();
    this.dataSource.replace([]);
  }

  @Builder
  buildList2() {
    Stack() {
      if (this.items.length === 0) {
        Text("这个RSS源没有资讯")
      } else {
        ArcList({ initialIndex: 0, header: this.titleView }) {
          LazyForEach(this.dataSource, (rssItem: RSSSourceDetailListItem) => {
            ArcListItem() {
              Button({ type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true }) {
                Column({ space: "3fp" }) {
                  Text(rssItem.title)
                    .textAlign(TextAlign.Start)
                    .fontSize('16fp')
                    .fontWeight(FontWeight.Medium)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ start: LengthMetrics.fp(3), end: LengthMetrics.fp(3) })
                    .width("100%")

                  if (rssItem.description) {
                    Text(rssItem.description)
                      .textAlign(TextAlign.Start)
                      .fontSize("12fp")
                      .fontColor($r("app.color.font_color_secondary"))
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width("100%")
                      .padding({ start: LengthMetrics.fp(3), end: LengthMetrics.fp(3) })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .padding(12)
              }
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                // 点击处理逻辑 - 可以打开详情页面或外部链接
                if (rssItem.url) {
                  console.debug(logTag, `Opening URL: ${rssItem.url}`)
                  if (this.pageInfos !== null) {
                    // Zhihu hot descriptions are one-line summaries: open the question
                    // through the ArkWeb challenge path instead of the feed body.
                    const isZhihuHot = rssItem.sourceKind === FeedSourceKind.ZhihuHot;
                    const pushData: NativeArticlePagePushData = {
                      mode: isZhihuHot ? ArticleMode.ZhihuQuestion : ArticleMode.Feed,
                      sourceKind: rssItem.sourceKind,
                      title: rssItem.title ?? '',
                      url: rssItem.url,
                      contentHTML: rssItem.contentHTML ?? '',
                      enclosureURL: rssItem.enclosureURL ?? '',
                      pubDate: rssItem.pubDate ?? ''
                    }
                    this.pageInfos.pushPathByName("NativeArticlePage", pushData)
                  } else {
                    this.getUIContext()
                      .getPromptAction()
                      .showToast({ message: "打开资讯详情页面失败。\n错误详情：页面导航组件出现问题。" })
                  }
                } else {
                  this.getUIContext().getPromptAction().showToast({ message: "这条资讯不支持查看详情" })
                }
              })
              .width(this.listSize)
              .backgroundColor(this.listRowBackgroundColor)
              .borderRadius(22)
            }.align(Alignment.Center)
          }, (rssItem: RSSSourceDetailListItem) => rssItem.id)
        }
        .cachedCount(2)
        .space(LengthMetrics.px(10))
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .onAppear(() => {
          try {
              requestFocusWithRetry(this.getUIContext(), this.pageID + "5a67c35d-cdaa-41c3-bdc7-61076cf31c7c")
          } catch (error) {
            console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
          }
        })
        .id(this.pageID + "5a67c35d-cdaa-41c3-bdc7-61076cf31c7c")
      }
    }
    .align(Alignment.Center)
    .width("100%")
    .height("100%")
  }

  build() {
    Column() {
      this.buildList2()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}

@Builder
function ArcListTitleView(displayTitle: ParamsInterface) {
  Column() {
    Text(displayTitle.text)
      .fontSize('20fp')
      .fontWeight(FontWeight.Bold)
      .textOverflow({ overflow: TextOverflow.MARQUEE })
      .maxLines(1)
      .width("100%")
      .textAlign(TextAlign.Center)
  }
  .margin({ top: 16, bottom: 12 })
  .width("100%")
}
