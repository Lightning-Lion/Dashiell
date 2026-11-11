import { describe, it, expect } from '@ohos/hypium';
import { ArticleBlock, BlockKind, EmbedType, RunKind } from '../main/ets/common/rss/ArticleModel';
import { HTMLSubsetParser } from '../main/ets/common/rss/HTMLSubset';
import { FeedSourceKind } from '../main/ets/common/rss/FeedSources';
import {
  isITHomeArticleURL, is3DMArticleURL, isZhihuQuestionURL, linkDestination, LinkDestination
} from '../main/ets/common/rss/FeedLinks';
import {
  formatPubDate, parseArticlePage, parseGenericFeedArticle, parseZhihuDailyArticle
} from '../main/ets/common/rss/FeedParsers';

// Real descriptions captured from the bundled feeds (2026-09-16), trimmed to stay structural.
const DM3_WITH_IFRAME = `<p style="text-indent:2em;">
Capcom公布了《怪物猎人：荒野》"凌越"扩展的新预告，集中展示扩展中14种武器的强化动作。该扩展定于2027年推出。
</p>
<p align="center">
<iframe width="640" height="498" src="https://player.bilibili.com/player.html?bvid=BV1xfbc6XEty&amp;&amp;autoplay=0;p=1" frameborder="no" allowfullscreen="true" referrerpolicy="no-referrer">
</iframe>
</p>
<p style="text-indent:2em;">
"凌越"扩展将加入大师等级挑战。玩家可以继续使用自己熟悉的武器，并通过新的强化动作进一步提升对各类武器的掌握程度。
</p>
<p align="center">
<img src="https://img.3dmgame.com/uploads/images/news/20260916/1789547425_525508_jpg_r.jpg" alt="预告图" referrerpolicy="no-referrer">
</p>
<p style="text-indent:2em;">
Nintendo Switch 2版在12月19日前售价为29.99美元，此后将调整为39.99美元。
</p>`;

const ITHOME_WITH_TABLE = `<p data-vmark="d3d2">IT之家 9 月 16 日消息，中国航天科技集团今日发布严正声明。</p>
<p data-vmark="6fa5">IT之家附中国航天科技集团严正声明原文如下：</p>
<blockquote><p data-vmark="6c59">中国航天科技集团有限公司成立于 1999 年 7 月。</p>
<p data-vmark="9aa4">经我公司核实，<strong>华航天特（福建）智能科技有限公司为假冒国企</strong>，与我公司及所属单位无任何隶属或股权关系。</p>
<p style="text-align: center;" data-vmark="b148">假冒国企名单</p>
<table><tbody><tr class="firstRow"><td valign="middle" align="center"><p style="text-align: center;">假冒国企名称</p></td><td valign="middle" align="center"><p>统一社会信用代码</p></td></tr>
<tr><td valign="middle" align="center"><p>华航天特（福建）智能科技有限公司</p></td><td valign="middle" align="center"><p>91350104MADUNXT16P</p></td></tr></tbody></table>
<ul class="medium-size list-paddingleft-2"><li><p>1.<strong>提高警惕</strong>，切勿轻易相信。</p></li><li><p>2.我公司将采取必要的法律措施。</p></li></ul>
</blockquote>`;

// Real structure of a Zhihu Daily item (author meta + empty question title + content + view-more).
const ZHIHU_DAILY_SAMPLE = `<div class="main-wrap content-wrap">
<div class="headline">
<div class="img-place-holder"></div>
</div>
<div class="content-inner">
<div class="question">
<h2 class="question-title"></h2>
<div class="answer">
<div class="meta">
<img class="avatar" src="https://pica.zhimg.com/v2-652019051dfa85d752205f054c120f1d_l.jpg?source=8673f162" referrerpolicy="no-referrer">
<span class="author">唐唐，</span><span class="bio">一个30+独居女生和她的生活方式。</span>
<a href="https://www.zhihu.com/question/2070215170673080006/answer/2070297388854539201" class="originUrl" hidden="">查看知乎原文</a>
</div>
<div class="content">
<p>因为它不是单一的死亡芭比粉，</p>
<p>而是严密构建的一整套粉色时光挽歌。</p>
<figure><img class="content-image" src="https://picx.zhimg.com/v2-af69d9ab6627c4a7f058e4243e36e4bb_720w.jpg?source=8673f162" alt="" referrerpolicy="no-referrer"><figcaption>哪怕不是电影，单独拎出来也足够优雅。</figcaption></figure>
<blockquote>
<div class="css-1gomreu"><a class="UserLink-link" href="https://www.zhihu.com/people/3d7e5e28">@封霄</a></div>
：它也可以不用「嗯」开头（）
</blockquote>
<p><a class="member_mention" href="http://www.zhihu.com/people/4db4fcecb19acf43">@知乎家居</a></p>
</div>
</div>
<div class="view-more"><a href="https://www.zhihu.com/question/2070215170673080006">查看知乎讨论</a></div>
</div>
</div>
</div>`;

function flattenText(blocks: ArticleBlock[]): string {
  let text = '';
  for (const block of blocks) {
    for (const run of block.runs) {
      if (run.kind === RunKind.Text) { text += run.text; }
      else { text += ' '; }
    }
    // Captions render under their images; they are part of the visible text.
    if (block.caption.length > 0) { text += block.caption; }
    if (block.metaText.length > 0) { text += block.metaText; }
    text += flattenText(block.children);
    for (const row of block.rows) {
      for (const cell of row.cells) { text += flattenText(cell.blocks); }
    }
  }
  return text;
}

function stripTags(input: string): string {
  // Hidden elements are intentionally dropped by the parser; mirror that here.
  const withoutHidden = input.replace(/<[^>]*hidden[^>]*>[\s\S]*?<\/[a-zA-Z]+>/g, '');
  return withoutHidden.replace(/<[^>]*>/g, '').replace(/\s+/g, '');
}

export default function articleParserTest() {
  describe('ArticleParserTest', () => {
    it('parses_3dm_blocks_and_embed', 0, () => {
      const blocks = HTMLSubsetParser.parse(DM3_WITH_IFRAME);
      const paragraphs = blocks.filter((block: ArticleBlock) => block.kind === BlockKind.Paragraph);
      const images = blocks.filter((block: ArticleBlock) => block.kind === BlockKind.Image);
      const embeds = blocks.filter((block: ArticleBlock) => block.kind === BlockKind.Embed);
      // The <p> wrapping only the <img> yields no empty paragraph block.
      expect(paragraphs.length).assertEqual(3);
      expect(images.length).assertEqual(1);
      expect(images[0].src).assertContain('img.3dmgame.com');
      expect(embeds.length).assertEqual(1);
      expect(embeds[0].embedType).assertEqual(EmbedType.Bilibili);
      expect(embeds[0].bvid).assertEqual('BV1xfbc6XEty');
    });

    it('parses_ithome_table_list_and_quote', 0, () => {
      const blocks = HTMLSubsetParser.parse(ITHOME_WITH_TABLE);
      const quotes = blocks.filter((block: ArticleBlock) => block.kind === BlockKind.Quote);
      expect(quotes.length).assertEqual(1);
      const quoteChildren = quotes[0].children;
      const tables = quoteChildren.filter((block: ArticleBlock) => block.kind === BlockKind.Table);
      const lists = quoteChildren.filter((block: ArticleBlock) => block.kind === BlockKind.List);
      expect(tables.length).assertEqual(1);
      expect(tables[0].rows.length).assertEqual(2);
      expect(tables[0].rows[0].cells.length).assertEqual(2);
      expect(lists.length).assertEqual(1);
      expect(lists[0].children.length).assertEqual(2);
      expect(lists[0].ordered).assertFalse();
      // The strong text inside the quote survives with its bold run.
      const strongText = flattenText(quoteChildren);
      expect(strongText).assertContain('华航天特（福建）智能科技有限公司为假冒国企');
    });

    it('decodes_entities', 0, () => {
      const decoded = HTMLSubsetParser.decodeEntities('A &amp; B &lt;tag&gt; &#39;ok&#39; &#x4F60;&#22909;');
      expect(decoded).assertEqual('A & B <tag> \'ok\' 你好');
    });

    it('extracts_nested_element_body', 0, () => {
      const html = '<div><div class="content">外层<div class="inner"><p>内层</p></div>结束</div><div class="view-more">尾部</div></div>';
      const open = /<div class="content">/.exec(html);
      expect(open === null).assertFalse();
      if (open !== null) {
        const body = HTMLSubsetParser.extractElementBody(html, open.index + open[0].length);
        expect(body).assertContain('<div class="inner"><p>内层</p></div>');
        expect(body).assertContain('结束');
        // Siblings after the container's closing tag are excluded.
        expect(body.includes('view-more')).assertFalse();
        expect(body.includes('尾部')).assertFalse();
      }
    });

    it('zhihu_daily_adapter_extracts_meta_and_falls_back_to_item_title', 0, () => {
      const article = parseZhihuDailyArticle('列表标题：布达佩斯大饭店',
        'https://daily.zhihu.com/story/123', ZHIHU_DAILY_SAMPLE,
        'https://pic1.zhimg.com/hero.jpg');
      // question-title is empty in this sample -> item title wins.
      expect(article.title).assertEqual('列表标题：布达佩斯大饭店');
      expect(article.subtitle).assertContain('唐唐');
      expect(article.subtitle).assertContain('一个30+独居女生');
      expect(article.authorAvatar).assertContain('pica.zhimg.com');
      expect(article.heroImage).assertContain('pic1.zhimg.com/hero.jpg');
      expect(article.viewMoreURL).assertEqual('https://www.zhihu.com/question/2070215170673080006');
      expect(article.blocks.length).assertLarger(1);
      const text = flattenText(article.blocks);
      expect(text).assertContain('粉色时光挽歌');
      // hidden link text must not leak into the body.
      expect(text.includes('查看知乎原文')).assertFalse();
      // quote with author link survives as link runs.
      const quoteLinkFound = article.blocks.some((block: ArticleBlock) =>
        block.kind === BlockKind.Quote && flattenText(block.children).includes('它也可以不用「嗯」开头'));
      expect(quoteLinkFound).assertTrue();
    });

    it('picks_the_lazy_image_url_over_the_inline_placeholder', 0, () => {
      // Zhihu's inline images: `src` is an empty SVG that carries only the aspect ratio and the
      // real URL is in data-original. Taking src first made every image fail to load.
      const html = '<figure><img src="data:image/svg+xml;utf8,<svg width=1212 height=1170></svg>" ' +
        'data-original="https://pic1.zhimg.com/v2-abc_1440w.jpg" class="origin_image lazy" ' +
        'data-rawwidth="1212" data-rawheight="1170" referrerpolicy="no-referrer">' +
        '<figcaption>注射层次和操作方式</figcaption></figure>';
      const images = HTMLSubsetParser.parse(html)
        .filter((block: ArticleBlock) => block.kind === BlockKind.Image);
      expect(images.length).assertEqual(1);
      expect(images[0].src).assertEqual('https://pic1.zhimg.com/v2-abc_1440w.jpg');
      expect(images[0].caption).assertEqual('注射层次和操作方式');
    });

    it('keeps_a_figure_whose_only_source_is_a_placeholder', 0, () => {
      // No real URL anywhere: the block survives so its caption is not silently dropped, and
      // RemoteImage rejects the data: URL instead of attempting a request that cannot work.
      const html = '<figure><img src="data:image/svg+xml;utf8,<svg width=464 height=777></svg>" ' +
        'class="lazy"><figcaption>没有原图</figcaption></figure>';
      const images = HTMLSubsetParser.parse(html)
        .filter((block: ArticleBlock) => block.kind === BlockKind.Image);
      expect(images.length).assertEqual(1);
      expect(images[0].src).assertContain('data:image/svg+xml');
      expect(images[0].caption).assertEqual('没有原图');
    });

    it('generic_feed_article_formats_date', 0, () => {
      const article = parseGenericFeedArticle(FeedSourceKind.ThreeDM, '标题',
        '<p>正文</p>', 'https://www.3dmgame.com/news/1/1.html',
        'Wed, 16 Sep 2026 09:24:16 GMT');
      expect(article.title).assertEqual('标题');
      expect(article.blocks.length).assertEqual(1);
      // Local-time rendering: assert the shape, not a fixed offset.
      expect(/^\d{2}-\d{2} \d{2}:\d{2}$/.test(article.subtitle)).assertTrue();
      expect(formatPubDate(null)).assertEqual('');
      expect(formatPubDate('不是日期')).assertEqual('不是日期');
    });

    it('parses_ithome_article_page', 0, () => {
      const page = '<html><head><title>某新闻标题 - IT之家</title></head><body>' +
        '<div class="post_content " id="paragraph"><p>正文第一段</p><img src="https://img.ithome.com/a.png">' +
        '<p>正文第二段</p></div><div class="related">相关</div></body></html>';
      const article = parseArticlePage(FeedSourceKind.ITHome, page);
      expect(article.title).assertEqual('某新闻标题');
      const text = flattenText(article.blocks);
      expect(text).assertContain('正文第一段');
      expect(text).assertContain('正文第二段');
      // Content outside the post_content container must not leak in.
      expect(text.includes('相关')).assertFalse();
    });

    it('article_page_without_container_throws', 0, () => {
      let threw = false;
      try {
        parseArticlePage(FeedSourceKind.ITHome, '<html><body>没有正文容器</body></html>');
      } catch (_) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('link_destination_routing', 0, () => {
      expect(isITHomeArticleURL('https://www.ithome.com/1/003/217.htm')).assertTrue();
      expect(is3DMArticleURL('https://www.3dmgame.com/news/202609/3953454.html')).assertTrue();
      expect(isZhihuQuestionURL('https://www.zhihu.com/question/2083496624882562658')).assertTrue();
      expect(linkDestination('https://www.ithome.com/1/003/217.htm'))
        .assertEqual(LinkDestination.NativeArticlePage);
      expect(linkDestination('https://www.zhihu.com/question/1'))
        .assertEqual(LinkDestination.ZhihuQuestion);
      expect(linkDestination('https://example.com/x'))
        .assertEqual(LinkDestination.Web);
    });

    it('no_text_loss_on_real_feeds', 0, () => {
      // Full-length real descriptions: parsed text must not lose >5% of the tag-stripped text.
      const samples: string[] = [DM3_WITH_IFRAME, ITHOME_WITH_TABLE, ZHIHU_DAILY_SAMPLE];
      for (const sample of samples) {
        const blocks = HTMLSubsetParser.parse(sample);
        const parsed = flattenText(blocks).replace(/\s+/g, '');
        const source = stripTags(sample);
        expect(parsed.length * 20).assertLarger(source.length * 19);
      }
    });
  })
}
