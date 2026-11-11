import { describe, it, expect } from '@ohos/hypium';
import { Article, ArticleBlock, BlockKind, RunKind } from '../main/ets/common/rss/ArticleModel';
import {
  ZhihuArticleAssembler, ZhihuPartDecoder, ZhihuProgressRow
} from '../main/ets/common/rss/ZhihuHot';

const QUESTION_URL = 'https://www.zhihu.com/question/2083496624882562658';

/**
 * Zhihu's parts arrive in whatever order the page happens to make them available, so these
 * tests drive the assembler one bridge message at a time and check what the reader would show
 * at that instant — not just the final result.
 */

class TestClock {
  now: number = 1000;

  read(): number {
    return this.now;
  }

  advance(ms: number): void {
    this.now += ms;
  }
}

function newAssembler(clock: TestClock): ZhihuArticleAssembler {
  return new ZhihuArticleAssembler((): number => clock.read());
}

/** Feeds one bridge payload the way the loader does; the fixture must decode. */
function feed(assembler: ZhihuArticleAssembler, json: string): boolean {
  const decoded = ZhihuPartDecoder.tryParse(json);
  expect(decoded.isSuccess()).assertTrue();
  return assembler.apply(decoded.getOrThrow());
}

/**
 * The page builds these payloads with JSON.stringify; these fixtures hand-write them, so a quote
 * or backslash inside a value has to be escaped here too — otherwise the "payload" is not JSON
 * and the decoder rejects it, which is a fixture bug rather than a decoder one.
 */
function jsonValue(raw: string): string {
  return raw.split('\\').join('\\\\').split('"').join('\\"');
}

function titleMessage(text: string): string {
  return '{"seq":1,"part":"title","text":"' + jsonValue(text) + '"}';
}

function metaMessage(text: string): string {
  return '{"seq":2,"part":"meta","text":"' + jsonValue(text) + '"}';
}

function detailMessage(html: string): string {
  return '{"seq":3,"part":"detail","html":"' + jsonValue(html) + '"}';
}

function headerMessage(id: string, author: string, votes: string): string {
  return '{"seq":4,"part":"answerHeader","id":"' + id + '","author":"' + jsonValue(author) +
    '","avatar":"https://pic1.zhimg.com/' + id + '.jpg","votes":"' + jsonValue(votes) + '"}';
}

function bodyMessage(id: string, html: string): string {
  return '{"seq":5,"part":"answerBody","id":"' + id + '","html":"' + jsonValue(html) + '"}';
}

/** Visible text, mirroring the reader's own block walk. */
function blockText(blocks: ArticleBlock[]): string {
  let text = '';
  for (const block of blocks) {
    for (const run of block.runs) {
      if (run.kind === RunKind.Text) { text += run.text; }
    }
    if (block.metaText.length > 0) { text += block.metaText; }
    if (block.author.length > 0) { text += block.author; }
    if (block.votes.length > 0) { text += block.votes; }
    text += blockText(block.children);
  }
  return text;
}

function kinds(blocks: ArticleBlock[]): string {
  let text = '';
  for (const block of blocks) {
    text += (text.length === 0 ? '' : ',') + String(block.kind);
  }
  return text;
}

function findBlock(blocks: ArticleBlock[], kind: BlockKind): ArticleBlock | undefined {
  for (const block of blocks) {
    if (block.kind === kind) { return block; }
  }
  return undefined;
}

function countKind(blocks: ArticleBlock[], kind: BlockKind): number {
  let total = 0;
  for (const block of blocks) {
    if (block.kind === kind) { total++; }
  }
  return total;
}

function rowFor(rows: ZhihuProgressRow[], label: string): ZhihuProgressRow | undefined {
  for (const row of rows) {
    if (row.label === label) { return row; }
  }
  return undefined;
}

export default function zhihuProgressiveTest() {
  describe('ZhihuProgressiveTest', () => {
    it('assembles_parts_that_arrive_out_of_order', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      // Body before header, detail before title: no ordering assumption anywhere.
      clock.advance(200);
      expect(feed(assembler, bodyMessage('a1', '<p>好家伙，连续跑65个小时55分钟22秒。</p>'))).assertTrue();
      clock.advance(400);
      expect(feed(assembler, headerMessage('a1', '风前横笛', '476 赞同'))).assertTrue();
      clock.advance(300);
      expect(feed(assembler, detailMessage('<div class="wrs-question-detail"><p>以 65:55:22 的成绩夺冠。</p></div>')))
        .assertTrue();
      clock.advance(100);
      expect(feed(assembler, titleMessage('赵家驹夺冠，如何评价？'))).assertTrue();

      const article = assembler.snapshot(QUESTION_URL);
      expect(article.title).assertEqual('赵家驹夺冠，如何评价？');
      // The detail block keeps its position; the answer follows it as header-then-body.
      expect(kinds(article.blocks)).assertEqual('p,answerHeader,p');
      const header = findBlock(article.blocks, BlockKind.AnswerHeader);
      expect(header !== undefined).assertTrue();
      if (header !== undefined) {
        expect(header.author).assertEqual('风前横笛');
        expect(header.votes).assertEqual('476 赞同');
        expect(header.authorAvatar).assertEqual('https://pic1.zhimg.com/a1.jpg');
      }
      const text = blockText(article.blocks);
      expect(text).assertContain('以 65:55:22 的成绩夺冠');
      expect(text).assertContain('连续跑65个小时55分钟22秒');
    });

    it('shows_only_what_has_arrived_so_far', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      expect(assembler.hasContent()).assertFalse();
      expect(assembler.snapshot(QUESTION_URL).blocks.length).assertEqual(0);

      clock.advance(120);
      expect(feed(assembler, titleMessage('标题先到'))).assertTrue();
      let article = assembler.snapshot(QUESTION_URL);
      expect(article.title).assertEqual('标题先到');
      expect(article.blocks.length).assertEqual(0);
      expect(assembler.hasContent()).assertTrue();

      clock.advance(180);
      expect(feed(assembler, metaMessage('37 个回答 · 101988 浏览'))).assertTrue();
      article = assembler.snapshot(QUESTION_URL);
      expect(article.subtitle).assertEqual('37 个回答 · 101988 浏览');
      expect(article.blocks.length).assertEqual(0);

      clock.advance(90);
      expect(feed(assembler, detailMessage('<div class="wrs-question-detail"><p>详情</p></div>'))).assertTrue();
      article = assembler.snapshot(QUESTION_URL);
      expect(article.blocks.length).assertEqual(1);

      // Blocks only ever grow: a reader scrolled past the top keeps its place.
      clock.advance(500);
      expect(feed(assembler, headerMessage('a1', '张三', '12 赞同'))).assertTrue();
      article = assembler.snapshot(QUESTION_URL);
      expect(article.blocks.length).assertEqual(2);
      expect(kinds(article.blocks)).assertEqual('p,answerHeader');

      clock.advance(50);
      expect(feed(assembler, bodyMessage('a1', '<p>正文一</p><p>正文二</p>'))).assertTrue();
      article = assembler.snapshot(QUESTION_URL);
      expect(article.blocks.length).assertEqual(4);
      expect(kinds(article.blocks)).assertEqual('p,answerHeader,p,p');
      expect(assembler.blockCount()).assertEqual(article.blocks.length);
    });

    it('renders_a_header_before_its_body_exists', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      expect(feed(assembler, headerMessage('a1', '只有头', '3 赞同'))).assertTrue();
      const article = assembler.snapshot(QUESTION_URL);
      expect(article.blocks.length).assertEqual(1);
      expect(countKind(article.blocks, BlockKind.AnswerHeader)).assertEqual(1);
      expect(assembler.answerCount()).assertEqual(1);
      // The author line is on screen even though there is no body yet.
      expect(blockText(article.blocks)).assertContain('只有头');
    });

    it('replaces_a_growing_body_without_touching_other_answers', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      expect(feed(assembler, headerMessage('a1', '甲', '1 赞同'))).assertTrue();
      expect(feed(assembler, bodyMessage('a1', '<p>第一段</p>'))).assertTrue();
      expect(feed(assembler, headerMessage('a2', '乙', '2 赞同'))).assertTrue();
      expect(feed(assembler, bodyMessage('a2', '<p>乙的正文</p>'))).assertTrue();
      expect(assembler.snapshot(QUESTION_URL).blocks.length).assertEqual(4);

      // a1's body grew: only its own blocks are replaced.
      expect(feed(assembler, bodyMessage('a1', '<p>第一段</p><p>第二段</p>'))).assertTrue();
      const article = assembler.snapshot(QUESTION_URL);
      expect(kinds(article.blocks)).assertEqual('answerHeader,p,p,answerHeader,p');
      const text = blockText(article.blocks);
      expect(text).assertContain('第一段');
      expect(text).assertContain('第二段');
      expect(text).assertContain('乙的正文');
      // Answer order is arrival order and never reshuffles.
      expect(assembler.answerCount()).assertEqual(2);
      expect(assembler.blockCount()).assertEqual(5);
    });

    it('repeated_parts_report_no_change', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      expect(feed(assembler, titleMessage('标题'))).assertTrue();
      // The same part again: nothing moved, so the reader must not repaint.
      expect(feed(assembler, titleMessage('标题'))).assertFalse();
      expect(feed(assembler, detailMessage('<div class="wrs-question-detail"><p>详情</p></div>'))).assertTrue();
      expect(feed(assembler, detailMessage('<div class="wrs-question-detail"><p>详情</p></div>'))).assertFalse();
      expect(feed(assembler, headerMessage('a1', '张三', '12 赞同'))).assertTrue();
      expect(feed(assembler, headerMessage('a1', '张三', '12 赞同'))).assertFalse();
      expect(feed(assembler, bodyMessage('a1', '<p>正文</p>'))).assertTrue();
      expect(feed(assembler, bodyMessage('a1', '<p>正文</p>'))).assertFalse();
      // A changed vote count is a real change and does repaint.
      expect(feed(assembler, headerMessage('a1', '张三', '99 赞同'))).assertTrue();
      expect(assembler.snapshot(QUESTION_URL).blocks.length).assertEqual(3);
    });

    it('rejects_malformed_parts', 0, () => {
      // Not JSON at all.
      expect(ZhihuPartDecoder.tryParse('{"part":').isSuccess()).assertFalse();
      // Unknown part kind.
      expect(ZhihuPartDecoder.tryParse('{"seq":1,"part":"video","text":"x"}').isSuccess()).assertFalse();
      // Missing seq.
      expect(ZhihuPartDecoder.tryParse('{"part":"title","text":"x"}').isSuccess()).assertFalse();
      // Title without text.
      expect(ZhihuPartDecoder.tryParse('{"seq":1,"part":"title"}').isSuccess()).assertFalse();
      // Answer body without an id: parts are keyed by answer.
      expect(ZhihuPartDecoder.tryParse('{"seq":1,"part":"answerBody","html":"<p>x</p>"}').isSuccess()).assertFalse();
      // Answer header missing its avatar field.
      expect(ZhihuPartDecoder.tryParse('{"seq":1,"part":"answerHeader","id":"a1","author":"甲","votes":""}')
        .isSuccess()).assertFalse();
      // A well-formed part, for contrast.
      expect(ZhihuPartDecoder.tryParse('{"seq":1,"part":"answerBody","id":"a1","html":"<p>x</p>"}')
        .isSuccess()).assertTrue();
    });

    it('progress_rows_carry_per_part_arrival_times', 0, () => {
      const clock = new TestClock();
      const assembler = newAssembler(clock);
      const waiting = assembler.progress();
      // title / meta / detail are always listed; answers join once they are mentioned.
      expect(waiting.length).assertEqual(3);
      const waitingTitle = rowFor(waiting, 'title');
      expect(waitingTitle !== undefined).assertTrue();
      if (waitingTitle !== undefined) {
        expect(waitingTitle.ready).assertFalse();
        expect(waitingTitle.at).assertEqual(0);
      }

      clock.advance(1200);
      feed(assembler, titleMessage('标题'));
      clock.advance(800);
      feed(assembler, headerMessage('a1', '甲', '1 赞同'));

      const rows = assembler.progress();
      expect(rows.length).assertEqual(4);
      const title = rowFor(rows, 'title');
      expect(title !== undefined).assertTrue();
      if (title !== undefined) {
        expect(title.ready).assertTrue();
        // absolute stamp; the loader subtracts its own mount time to print "+1.2s"
        expect(title.at).assertEqual(2200);
        expect(title.blocks).assertEqual(2);
      }
      const answer = rowFor(rows, 'answer#1');
      expect(answer !== undefined).assertTrue();
      if (answer !== undefined) {
        expect(answer.ready).assertTrue();
        expect(answer.at).assertEqual(3000);
        expect(answer.bodyReady).assertFalse();
        expect(answer.bodyBlocks).assertEqual(-1);
      }

      clock.advance(400);
      feed(assembler, bodyMessage('a1', '<p>正文</p>'));
      const withBody = rowFor(assembler.progress(), 'answer#1');
      expect(withBody !== undefined).assertTrue();
      if (withBody !== undefined) {
        expect(withBody.bodyReady).assertTrue();
        expect(withBody.bodyAt).assertEqual(3400);
        expect(withBody.bodyBlocks).assertEqual(1);
      }
    });

    it('snapshots_are_fresh_instances_so_the_reader_repaints', 0, () => {
      const assembler = newAssembler(new TestClock());
      feed(assembler, titleMessage('标题'));
      const first: Article = assembler.snapshot(QUESTION_URL);
      const second: Article = assembler.snapshot(QUESTION_URL);
      expect(first === second).assertFalse();
      expect(first.sourceURL).assertEqual(QUESTION_URL);
      expect(second.title).assertEqual('标题');
    });
  })
}
