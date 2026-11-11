/**
 * URL classification for links found in RSS article bodies.
 *
 * This is the contract between the native reader and the fallback WebView: only hosts and
 * paths listed here get a native page, everything else is handed to ArticleLinkPage.
 * Keeping the patterns together makes it obvious what a newly supported source needs.
 */

export function extractHost(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/.exec(url.trim());
  return match !== null ? match[1].toLowerCase() : '';
}

/** IT之家 article links, e.g. https://www.ithome.com/1/003/217.htm */
export function isITHomeArticleURL(url: string): boolean {
  const host = extractHost(url);
  return (host === 'ithome.com' || host.endsWith('.ithome.com')) &&
    /\/(\d+\/){2,}\d+\.html?/.test(url);
}

/** 3DM news article links, e.g. https://www.3dmgame.com/news/202609/3953454.html */
export function is3DMArticleURL(url: string): boolean {
  const host = extractHost(url);
  return (host === '3dmgame.com' || host.endsWith('.3dmgame.com')) &&
    /\/news\/\d+\/\d+\.html?/.test(url);
}

/** Zhihu question links, e.g. https://www.zhihu.com/question/2083496624882562658 */
export function isZhihuQuestionURL(url: string): boolean {
  const host = extractHost(url);
  return (host === 'zhihu.com' || host.endsWith('.zhihu.com')) && /\/question\/\d+/.test(url);
}

/** Where native navigation can take over, and the fallback web page for everything else. */
export enum LinkDestination {
  NativeArticlePage = 'nativeArticle',
  ZhihuQuestion = 'zhihuQuestion',
  Web = 'web'
}

export function linkDestination(url: string): LinkDestination {
  if (isITHomeArticleURL(url) || is3DMArticleURL(url)) { return LinkDestination.NativeArticlePage; }
  if (isZhihuQuestionURL(url)) { return LinkDestination.ZhihuQuestion; }
  return LinkDestination.Web;
}
