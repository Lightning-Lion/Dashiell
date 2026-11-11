/**
 * Feed source identity and palette.
 *
 * A source is only "which bundled feed does this URL belong to" plus the colour identity
 * that list/loading/warning surfaces reuse. Article parsing lives in FeedParsers.ets and
 * link classification lives in FeedLinks.ets; keep those out of this file so a new source
 * does not drag parser imports into pages that only need a gradient.
 */

import { DarkTheme } from '../Theme';

export enum FeedSourceKind {
  ThreeDM = '3dm',
  ITHome = 'ithome',
  ZhihuDaily = 'zhihuDaily',
  ZhihuHot = 'zhihuHot',
  Unknown = 'unknown'
}

export function feedSourceKindFromURL(url: string): FeedSourceKind {
  if (url.includes('3dmgame')) { return FeedSourceKind.ThreeDM; }
  if (url.includes('ithome')) { return FeedSourceKind.ITHome; }
  if (url.includes('zhihu/daily')) { return FeedSourceKind.ZhihuDaily; }
  if (url.includes('zhihu/hot')) { return FeedSourceKind.ZhihuHot; }
  return FeedSourceKind.Unknown;
}

/**
 * 资讯页顶部的渐变色：每个源用自己的色相，和它在 App 里的身份呼应，
 * 认不出源的自定义 RSS 则退回 App 的品牌红。
 */
export function feedSourceTopGradient(kind: FeedSourceKind): Array<[ResourceColor, number]> {
  if (kind === FeedSourceKind.ITHome) { return DarkTheme.pageTopGradients.ithome; }
  if (kind === FeedSourceKind.ThreeDM) { return DarkTheme.pageTopGradients.threeDM; }
  if (kind === FeedSourceKind.ZhihuDaily || kind === FeedSourceKind.ZhihuHot) {
    return DarkTheme.pageTopGradients.zhihu;
  }
  return DarkTheme.pageTopGradients.brand;
}

/**
 * 资讯页加载态用的强调色：和上面 feedSourceTopGradient 同一个色相的前景档，
 * 分支逐行对应，改色相时两个函数要一起改。
 */
export function feedSourceAccent(kind: FeedSourceKind): string {
  if (kind === FeedSourceKind.ITHome) { return DarkTheme.accents.ithome; }
  if (kind === FeedSourceKind.ThreeDM) { return DarkTheme.accents.threeDM; }
  if (kind === FeedSourceKind.ZhihuDaily || kind === FeedSourceKind.ZhihuHot) {
    return DarkTheme.accents.zhihu;
  }
  return DarkTheme.accents.brand;
}
