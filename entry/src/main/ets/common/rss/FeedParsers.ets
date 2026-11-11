/**
 * Feed source adapters: turn raw RSS descriptions (or fetched article pages) into Article models.
 * The bundled sources are finite — every branch here corresponds to a feed shape verified
 * against real responses (see the investigation in the plan).
 *
 * URL classification lives in FeedLinks.ets; source identity/palette in FeedSources.ets.
 */

import { Article } from './ArticleModel';
import { HTMLSubsetParser } from './HTMLSubset';
import { FeedSourceKind } from './FeedSources';

function stripTags(text: string): string {
  return text.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}

export function formatPubDate(pubDate: string | null): string {
  if (pubDate === null || pubDate.length === 0) { return ''; }
  const time = Date.parse(pubDate);
  if (isNaN(time)) { return pubDate; }
  const date = new Date(time);
  const pad = (value: number): string => value < 10 ? '0' + value : String(value);
  return pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' + pad(date.getHours()) + ':' +
    pad(date.getMinutes());
}

/** 3DM / IT之家: the RSS description IS the full article HTML. */
export function parseGenericFeedArticle(kind: FeedSourceKind, itemTitle: string, html: string,
  itemURL: string, pubDate: string | null): Article {
  const article = new Article();
  article.title = stripTags(itemTitle);
  const dateText = formatPubDate(pubDate);
  article.subtitle = dateText.length > 0 ? dateText : (kind === FeedSourceKind.ITHome ? 'IT之家' : '3DM');
  article.sourceURL = itemURL;
  article.blocks = HTMLSubsetParser.parse(html);
  return article;
}

/**
 * Zhihu Daily: description carries the full answer HTML wrapped in the site's page chrome.
 * The interesting parts are pre-extracted here (meta/author/title/view-more), and the inner
 * content div goes through the shared subset parser.
 */
export function parseZhihuDailyArticle(itemTitle: string, itemURL: string, html: string,
  enclosureURL: string | null): Article {
  const article = new Article();
  article.sourceURL = itemURL;
  article.heroImage = enclosureURL ?? '';

  // Question title; empty for 24/30 sampled items, so fall back to the list title.
  let questionTitle = '';
  const titleMatch = /<h2 class="question-title">([\s\S]*?)<\/h2>/.exec(html);
  if (titleMatch !== null) { questionTitle = stripTags(titleMatch[1]); }
  article.title = questionTitle.length > 0 ? questionTitle : stripTags(itemTitle);

  // Author meta block.
  const metaMatch = /<div class="meta">([\s\S]*?)<\/div>/.exec(html);
  let author = '';
  let bio = '';
  if (metaMatch !== null) {
    const meta = metaMatch[1];
    const authorMatch = /<span class="author">([^<]*)<\/span>/.exec(meta);
    if (authorMatch !== null) { author = authorMatch[1].trim(); }
    const bioMatch = /<span class="bio">([^<]*)<\/span>/.exec(meta);
    if (bioMatch !== null) { bio = bioMatch[1].trim(); }
    const avatarMatch = /<img class="avatar" src="([^"]+)"/.exec(meta);
    if (avatarMatch !== null) { article.authorAvatar = avatarMatch[1]; }
  }
  if (author.length > 0 && bio.length > 0) { article.subtitle = author + ' · ' + bio; }
  else { article.subtitle = author.length > 0 ? author : bio; }

  // "查看知乎讨论" link becomes the view-more entry point.
  const viewMoreMatch = /<div class="view-more"><a href="([^"]+)"/.exec(html);
  if (viewMoreMatch !== null) { article.viewMoreURL = viewMoreMatch[1]; }

  // Body: exactly one <div class="content"> per item in the sampled feeds.
  const contentOpen = /<div class="content">/.exec(html);
  if (contentOpen !== null) {
    const body = HTMLSubsetParser.extractElementBody(html, contentOpen.index + contentOpen[0].length);
    article.blocks = HTMLSubsetParser.parse(body);
  } else {
    article.blocks = HTMLSubsetParser.parse(html);
  }
  return article;
}

/**
 * Fetched IT之家 / 3DM article pages (server-rendered): title from <title>, body from the
 * known content container. Throws when the container is absent.
 */
export function parseArticlePage(kind: FeedSourceKind, html: string): Article {
  const article = new Article();
  const titleMatch = /<title>([\s\S]*?)<\/title>/.exec(html);
  let title = titleMatch !== null ? stripTags(titleMatch[1]) : '';
  if (kind === FeedSourceKind.ITHome) {
    title = title.split(' - IT之家')[0].split(' - ITHOME')[0].trim();
  } else {
    title = title.split('_3DM')[0].split(' - 3DM')[0].trim();
  }
  article.title = title;
  const containerPattern = kind === FeedSourceKind.ITHome ? 'post_content' : 'news_warp_center';
  const openRe: RegExp = new RegExp('<div[^>]*class="[^"]*' + containerPattern + '[^"]*"[^>]*>');
  const openMatch = openRe.exec(html);
  if (openMatch === null) {
    throw new Error('无法从文章页中提取正文');
  }
  const body = HTMLSubsetParser.extractElementBody(html, openMatch.index + openMatch[0].length);
  article.blocks = HTMLSubsetParser.parse(body);
  if (article.blocks.length === 0) {
    throw new Error('文章正文为空');
  }
  return article;
}
