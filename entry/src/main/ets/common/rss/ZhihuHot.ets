/**
 * Zhihu hot-list question fetching, in progressive parts.
 *
 * Zhihu's question pages cannot be fetched with plain HTTP (curl returns a 403 challenge page
 * and the /api/v4 answers endpoint returns 40362 without a logged-in session). The only path
 * that works is letting ArkWeb pass the JS/WASM challenge, then reading the server-rendered
 * `<script id="js-initialData">` JSON out of the live page.
 *
 * The JSON is deep-navigated *in the page* (where untyped JS is at home), but instead of
 * flattening everything into one payload it is reported as independent parts: title, question
 * meta line, question detail, and — per answer — the author header and the body separately.
 * Different pages make these available in different orders, so each part is probed and sent on
 * its own, and the host renders whichever parts have arrived.
 *
 * `ZhihuArticleAssembler` merges the parts into `Article` snapshots; `apply` reports whether a
 * message actually changed anything, which drives both the settle check and the re-render.
 */

import { Article, ArticleBlock, BlockKind } from './ArticleModel';
import { DecodeContext, DecodeResult, JsonNode } from '../jsonschema/JsonDecode';
import { HTMLSubsetParser } from './HTMLSubset';

/** Which slice of the question page a bridge message carries. */
export enum ZhihuPartKind {
  Title = 'title',
  Meta = 'meta',
  Detail = 'detail',
  AnswerHeader = 'answerHeader',
  AnswerBody = 'answerBody'
}

const PART_KINDS: string[] = [
  ZhihuPartKind.Title, ZhihuPartKind.Meta, ZhihuPartKind.Detail,
  ZhihuPartKind.AnswerHeader, ZhihuPartKind.AnswerBody
];

function partKindFromText(text: string): ZhihuPartKind | undefined {
  for (const candidate of PART_KINDS) {
    if (candidate === text) { return candidate as ZhihuPartKind; }
  }
  return undefined;
}

/** One part of the page. Fields not relevant to `part` stay empty, matching ArticleBlock's style. */
export class ZhihuPartMessage {
  seq: number = 0;
  part: ZhihuPartKind = ZhihuPartKind.Title;
  // Title / Meta.
  text: string = '';
  // Detail / AnswerBody.
  html: string = '';
  // AnswerHeader / AnswerBody: which answer this belongs to.
  id: string = '';
  // AnswerHeader.
  author: string = '';
  avatar: string = '';
  votes: string = '';
}

export class ZhihuPartDecoder {
  static tryParse(text: string): DecodeResult<ZhihuPartMessage> {
    const context = new DecodeContext('ZhihuPart');
    const node = JsonNode.parse(text, context);
    let message: ZhihuPartMessage | undefined = undefined;
    if (node !== undefined) {
      message = ZhihuPartDecoder.decode(node, context);
    }
    return context.finish<ZhihuPartMessage>(message);
  }

  private static decode(node: JsonNode, context: DecodeContext): ZhihuPartMessage | undefined {
    if (node.kind() !== 'object') {
      context.issue('TYPE', node, 'object');
      return undefined;
    }
    const part = node.field('part');
    if (part.kind() !== 'string') { context.issue('TYPE', part, 'string'); return undefined; }
    const kind = partKindFromText(part.stringValue());
    if (kind === undefined) { context.issue('VALUE', part, 'zhihu part kind'); return undefined; }
    const seq = node.field('seq');
    if (seq.kind() !== 'number') { context.issue('TYPE', seq, 'number'); return undefined; }

    const message = new ZhihuPartMessage();
    message.seq = seq.numberValue();
    message.part = kind;

    if (kind === ZhihuPartKind.Title || kind === ZhihuPartKind.Meta) {
      const text = node.field('text');
      if (text.kind() !== 'string') { context.issue('TYPE', text, 'string'); return undefined; }
      message.text = text.stringValue();
      return message;
    }
    if (kind === ZhihuPartKind.Detail) {
      const html = node.field('html');
      if (html.kind() !== 'string') { context.issue('TYPE', html, 'string'); return undefined; }
      message.html = html.stringValue();
      return message;
    }
    // Both answer parts are keyed by answer id.
    const id = node.field('id');
    if (id.kind() !== 'string' || id.stringValue().length === 0) {
      context.issue('TYPE', id, 'non-empty string'); return undefined;
    }
    message.id = id.stringValue();
    if (kind === ZhihuPartKind.AnswerBody) {
      const html = node.field('html');
      if (html.kind() !== 'string') { context.issue('TYPE', html, 'string'); return undefined; }
      message.html = html.stringValue();
      return message;
    }
    const author = node.field('author');
    const avatar = node.field('avatar');
    const votes = node.field('votes');
    if (author.kind() !== 'string' || avatar.kind() !== 'string' || votes.kind() !== 'string') {
      context.issue('TYPE', author, 'string author/avatar/votes'); return undefined;
    }
    message.author = author.stringValue();
    message.avatar = avatar.stringValue();
    message.votes = votes.stringValue();
    return message;
  }
}

/**
 * One failure raised inside the page, sent over the bridge so the host can log it.
 *
 * Only failures that the extraction itself can explain are reported — the injected code's own
 * dead ends and the page's uncaught errors. Everything the page merely prints stays where it is:
 * a full console capture would drown the signal in Zhihu's own chatter.
 */
export class ZhihuDiag {
  kind: string = '';
  message: string = '';
  /** Where the error was raised (script URL for page errors, empty for our own diagnostics). */
  source: string = '';
  line: number = 0;
  col: number = 0;
  stack: string = '';
  /** `document.readyState` at the time: tells "too early" apart from "never". */
  readyState: string = '';
}

export class ZhihuDiagDecoder {
  static tryParse(text: string): DecodeResult<ZhihuDiag> {
    const context = new DecodeContext('ZhihuDiag');
    const node = JsonNode.parse(text, context);
    let diag: ZhihuDiag | undefined = undefined;
    if (node !== undefined) {
      diag = ZhihuDiagDecoder.decode(node, context);
    }
    return context.finish<ZhihuDiag>(diag);
  }

  /** A payload the decoder rejected, kept as a diagnostic of its own instead of being dropped. */
  static asMalformed(raw: string): ZhihuDiag {
    const diag = new ZhihuDiag();
    diag.kind = 'malformed';
    diag.message = raw;
    return diag;
  }

  private static decode(node: JsonNode, context: DecodeContext): ZhihuDiag | undefined {
    if (node.kind() !== 'object') {
      context.issue('TYPE', node, 'object');
      return undefined;
    }
    const kind = node.field('kind');
    if (kind.kind() !== 'string' || kind.stringValue().length === 0) {
      context.issue('TYPE', kind, 'non-empty string');
      return undefined;
    }
    const message = node.field('message');
    if (message.kind() !== 'string') {
      context.issue('TYPE', message, 'string');
      return undefined;
    }
    const diag = new ZhihuDiag();
    diag.kind = kind.stringValue();
    diag.message = message.stringValue();
    // Optional fields: absent or mistyped leaves the default rather than failing the decode.
    diag.source = ZhihuDiagDecoder.optionalString(node.field('source'));
    diag.stack = ZhihuDiagDecoder.optionalString(node.field('stack'));
    diag.readyState = ZhihuDiagDecoder.optionalString(node.field('readyState'));
    diag.line = ZhihuDiagDecoder.optionalNumber(node.field('line'));
    diag.col = ZhihuDiagDecoder.optionalNumber(node.field('col'));
    return diag;
  }

  private static optionalString(node: JsonNode): string {
    return node.kind() === 'string' ? node.stringValue() : '';
  }

  private static optionalNumber(node: JsonNode): number {
    return node.kind() === 'number' ? node.numberValue() : 0;
  }
}

/**
 * Bounds what a misbehaving page can write to the log. The page re-raises the same failure on
 * every poll (1.5s apart, for up to 75s), so the count matters more than the repetition: each
 * distinct failure prints a couple of times, and past the line budget only the counters move.
 */
export class ZhihuDiagBudget {
  static readonly MAX_PER_SIGNATURE: number = 2;
  static readonly MAX_LINES: number = 25;
  static readonly MAX_MESSAGE_CHARS: number = 160;
  static readonly MAX_STACK_CHARS: number = 240;
  static readonly MAX_SOURCE_CHARS: number = 80;
  private lines: number = 0;
  private counts: Map<string, number> = new Map<string, number>();
  private distinctCount: number = 0;
  private totalCount: number = 0;

  /** Counts the diagnostic either way; true when it still earns a log line. */
  accept(signature: string): boolean {
    this.totalCount++;
    const previous = this.counts.get(signature);
    if (previous === undefined) { this.distinctCount++; }
    const count = previous === undefined ? 1 : previous + 1;
    this.counts.set(signature, count);
    if (this.lines >= ZhihuDiagBudget.MAX_LINES) { return false; }
    if (count > ZhihuDiagBudget.MAX_PER_SIGNATURE) { return false; }
    this.lines++;
    return true;
  }

  /** Occurrences seen so far, including this one — `accept` has to be called first. */
  countOf(signature: string): number {
    const count = this.counts.get(signature);
    return count === undefined ? 0 : count;
  }

  distinct(): number { return this.distinctCount; }
  total(): number { return this.totalCount; }
  logged(): number { return this.lines; }

  static truncate(text: string, max: number): string {
    return text.length > max ? text.slice(0, max) : text;
  }

  static signatureOf(diag: ZhihuDiag): string {
    return diag.kind + '|' + diag.message + '|' + diag.source + ':' + diag.line;
  }
}

/**
 * Runs inside the Zhihu page, as early as possible — installed at document start so it is in
 * place before the challenge script can throw, and re-run (idempotently) at the head of every
 * poll because that script can replace `window.onerror` out from under us.
 *
 * It hooks only uncaught errors and unhandled rejections: those are the failures that leave the
 * page half-built with nothing to show for it. Console output is deliberately left alone.
 *
 * Written with no template literals and no backslash escapes — this string is itself a template
 * literal in ArkTS, so `${` would be interpolated here and `\n` consumed before the page ever
 * sees it. Everything is built with `+` for that reason, not for style.
 */
export const ZHIHU_DIAG_HOOK_JS: string = `(() => {
  const W = window;
  const S = W.__wrsZhihu || (W.__wrsZhihu = { seq: 0, seen: {} });
  // A poll may have created the cache first; fill in whatever is missing.
  if (!S.seen) { S.seen = {}; }
  if (!S.pending) { S.pending = []; }
  if (S.sent === undefined) { S.sent = 0; }
  const cut = (value, max) => {
    const text = (value === undefined || value === null) ? '' : String(value);
    return text.length > max ? text.slice(0, max) : text;
  };
  // Truncation happens before the stringify: a page stack is easily hundreds of kilobytes, and
  // these fire while the render process is already the thing that is stuck.
  S.deliver = (msg) => {
    try { ZhihuBridge.onZhihuDiag(JSON.stringify(msg)); return true; }
    catch (e) { return false; }
  };
  // A failure raised before the proxy exists waits here; the next poll drains it. Bounded on
  // both ends so a page that throws in a loop cannot queue without limit.
  S.flush = () => {
    if (typeof ZhihuBridge === 'undefined') { return; }
    while (S.pending.length > 0 && S.sent < 40) {
      const msg = S.pending.shift();
      if (!S.deliver(msg)) { S.pending.unshift(msg); return; }
      S.sent = S.sent + 1;
    }
  };
  S.report = (kind, message, source, line, col, stack) => {
    const msg = {
      kind: kind,
      message: cut(message, 160),
      source: cut(source, 80),
      line: line || 0,
      col: col || 0,
      stack: cut(stack, 240),
      readyState: cut(document.readyState, 16)
    };
    const signature = kind + '|' + msg.message + '|' + msg.source + ':' + msg.line;
    if (S.seen['d:' + signature]) { return; }
    S.seen['d:' + signature] = 1;
    if (S.pending.length >= 5) { S.pending.shift(); }
    S.pending.push(msg);
    S.flush();
  };
  // Re-installed whenever the page has replaced it; the wrapper chains to whatever took our
  // place, so the page keeps working exactly as it would without us.
  if (S.onerrorFn === undefined || W.onerror !== S.onerrorFn) {
    const previous = W.onerror;
    S.onerrorFn = function (message, source, line, col, error) {
      try { S.report('page-error', message, source, line, col, error && error.stack); } catch (e) { }
      if (typeof previous === 'function') { return previous.apply(W, arguments); }
      return false;
    };
    W.onerror = S.onerrorFn;
  }
  if (S.rejectionFn === undefined) {
    S.rejectionFn = (event) => {
      try {
        const reason = event && event.reason;
        const text = (reason && reason.message) ? reason.message : reason;
        S.report('rejection', text, '', 0, 0, reason && reason.stack);
      } catch (e) { }
    };
  }
  // The same listener reference re-registers as a no-op, so this survives a re-run.
  W.addEventListener('unhandledrejection', S.rejectionFn);
  S.flush();
})();`;

/**
 * Runs inside the Zhihu page. Each part is probed independently and reported the moment it has
 * content, so a part that is ready early is never held back by one that is not.
 *
 * `runJavaScript` re-executes this IIFE on every poll with no memory of the previous run, so the
 * sent-signature cache lives on `window`. Signatures are the value itself for title/meta/
 * answer-header and the *length* for HTML parts — a length change means the body is still
 * growing, and re-sending lets the host replace it. A second `window` field caches the blob's
 * length so polls that find an unchanged document bail before the (expensive) JSON.parse.
 */
export const ZHIHU_EXTRACT_JS: string = `(() => {
  const W = window;
  const S = W.__wrsZhihu || (W.__wrsZhihu = { seq: 0, seen: {} });
  // Every failure below used to be a silent return, which made a stuck page indistinguishable
  // from a slow one: the host watched polls change nothing and had nothing to go on. The hook
  // at the head of ZHIHU_POLL_JS installs the report function; standalone this stays silent.
  const diag = (kind, message) => {
    try { if (S.report) { S.report(kind, message, '', 0, 0, ''); } } catch (e) { }
  };
  // Polling starts at the mount, so early polls legitimately find nothing yet. A missing node or
  // a missing bridge only means something once the document is parsed; before that it is just
  // the page loading, and reporting it would bury the real failures in noise.
  const diagIfSettled = (kind, message) => {
    if (document.readyState !== 'loading') { diag(kind, message); }
  };
  // Names the section a throw came from, so "part-throw detail" reads without a stack.
  let stage = 'boot';
  try {
    const node = document.getElementById('js-initialData');
    if (!node || !node.textContent) {
      diagIfSettled('no-node', node ? '#js-initialData empty' : '#js-initialData missing');
      return;
    }
    const source = node.textContent;
    // Checked before the length cache is written: a poll that runs before the proxy is injected
    // must not leave the cache claiming this blob was already reported.
    if (typeof ZhihuBridge === 'undefined') {
      diagIfSettled('no-bridge', 'ZhihuBridge undefined');
      return;
    }
    // This script re-runs on every poll and the blob is large, so skip the parse while the
    // document is unchanged. Polling starts at the mount now, long before the challenge ends.
    if (S.len === source.length) { return; }
    S.len = source.length;
    let parsed = null;
    try { parsed = JSON.parse(source); } catch (e) {
      diag('parse-fail', (e && e.message ? e.message : 'JSON.parse threw') + ', len=' + String(source.length));
      return;
    }
    const st = parsed && parsed.initialState;
    if (!st) {
      diag('no-state', 'initialState missing, len=' + String(source.length));
      return;
    }
    const entities = st.entities || {};
    const questions = entities.questions || {};
    const answers = entities.answers || {};
    const qKeys = Object.keys(questions);
    const q = qKeys.length > 0 ? questions[qKeys[0]] : null;

    const post = (msg) => {
      try {
        S.seq = S.seq + 1;
        msg.seq = S.seq;
        ZhihuBridge.onZhihuPayload(JSON.stringify(msg));
      } catch (e) {
        // A proxy torn down mid-navigation throws here; without this the poll dies unexplained.
        diag('post-throw', e && e.message ? e.message : 'bridge call threw');
      }
    };
    const once = (key, signature, msg) => {
      if (S.seen[key] === signature) { return; }
      S.seen[key] = signature;
      post(msg);
    };

    stage = 'title';
    if (q && q.title) { once('title', q.title, { part: 'title', text: q.title }); }

    stage = 'meta';
    if (q) {
      const metaParts = [];
      if (q.answerCount > 0) { metaParts.push(String(q.answerCount) + ' 个回答'); }
      if (q.visitCount > 0) { metaParts.push(String(q.visitCount) + ' 浏览'); }
      const meta = metaParts.join(' · ');
      if (meta) { once('meta', meta, { part: 'meta', text: meta }); }
    }

    stage = 'detail';
    if (q) {
      let detail = '';
      if (q.detail && q.detail.length > 0) { detail = q.detail; }
      else if (q.excerpt && q.excerpt.length > 0) { detail = '<p>' + q.excerpt.replace(/\\[图片\\]/g, '') + '</p>'; }
      if (detail) {
        once('detail', String(detail.length), {
          part: 'detail', html: '<div class="wrs-question-detail">' + detail + '</div>'
        });
      }
    }

    const ids = Object.keys(answers);
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      const a = answers[id];
      if (!a) { continue; }
      stage = 'answerHeader:' + id;
      const author = (a.author && a.author.name) ? a.author.name : '知乎用户';
      const avatar = (a.author && a.author.avatarUrl) ? a.author.avatarUrl : '';
      const votes = a.voteupCount > 0 ? String(a.voteupCount) + ' 赞同' : '';
      once('h:' + id, author + '|' + avatar + '|' + votes, {
        part: 'answerHeader', id: id, author: author, avatar: avatar, votes: votes
      });
      if (a.content && a.content.length > 0) {
        stage = 'answerBody:' + id;
        once('b:' + id, String(a.content.length), { part: 'answerBody', id: id, html: a.content });
      }
    }
  } catch (e) {
    diag('part-throw', stage + ': ' + (e && e.message ? e.message : String(e)));
  }
})();`;

/**
 * What a poll actually runs: the hook first so a page that replaces `window.onerror` is caught
 * again on the next tick, then the extraction. Composed once here rather than per poll, and
 * still a single `runJavaScript` per tick — the render process is the thing that jams when this
 * whole flow goes wrong, so it gets no extra round trips.
 */
export const ZHIHU_POLL_JS: string = ZHIHU_DIAG_HOOK_JS + ZHIHU_EXTRACT_JS;

/** One row of the progress log: a part, when it arrived, and how much it brought. */
export class ZhihuProgressRow {
  label: string = '';
  ready: boolean = false;
  at: number = 0;
  blocks: number = -1;
  // Answers only: the body arrives separately from the header.
  bodyReady: boolean = false;
  bodyAt: number = 0;
  bodyBlocks: number = -1;
}

/**
 * Merges arriving parts into `Article` snapshots.
 *
 * Answers keep their arrival order and are only ever appended, so the block array grows
 * monotonically and the reader's `ForEach` keys stay stable for blocks that did not change.
 * The clock is injectable so tests can assert exact arrival offsets.
 */
export class ZhihuArticleAssembler {
  private clock: () => number;
  private title: string = '';
  private titleAt: number = 0;
  private meta: string = '';
  private metaAt: number = 0;
  private detailSignature: string = '';
  private detailAt: number = 0;
  private detailBlocks: ArticleBlock[] = [];
  private order: string[] = [];
  private headerSignatures: Map<string, string> = new Map<string, string>();
  private headers: Map<string, ArticleBlock> = new Map<string, ArticleBlock>();
  private headerAt: Map<string, number> = new Map<string, number>();
  private bodySignatures: Map<string, string> = new Map<string, string>();
  private bodies: Map<string, ArticleBlock[]> = new Map<string, ArticleBlock[]>();
  private bodyAt: Map<string, number> = new Map<string, number>();

  constructor(clock: () => number = () => Date.now()) {
    this.clock = clock;
  }

  /** Returns true when the message actually changed the assembled article. */
  apply(message: ZhihuPartMessage): boolean {
    if (message.part === ZhihuPartKind.Title) {
      if (message.text === this.title) { return false; }
      this.title = message.text;
      this.titleAt = this.clock();
      return true;
    }
    if (message.part === ZhihuPartKind.Meta) {
      if (message.text === this.meta) { return false; }
      this.meta = message.text;
      this.metaAt = this.clock();
      return true;
    }
    if (message.part === ZhihuPartKind.Detail) {
      if (message.html === this.detailSignature) { return false; }
      this.detailSignature = message.html;
      this.detailAt = this.clock();
      this.detailBlocks = HTMLSubsetParser.parse(message.html);
      return true;
    }
    if (message.part === ZhihuPartKind.AnswerHeader) {
      this.noteAnswer(message.id);
      const signature = message.author + '|' + message.avatar + '|' + message.votes;
      if (this.headerSignatures.get(message.id) === signature) { return false; }
      this.headerSignatures.set(message.id, signature);
      const header = new ArticleBlock();
      header.kind = BlockKind.AnswerHeader;
      header.author = message.author;
      header.authorAvatar = message.avatar;
      header.votes = message.votes;
      this.headers.set(message.id, header);
      this.headerAt.set(message.id, this.clock());
      return true;
    }
    this.noteAnswer(message.id);
    if (this.bodySignatures.get(message.id) === message.html) { return false; }
    this.bodySignatures.set(message.id, message.html);
    this.bodies.set(message.id, HTMLSubsetParser.parse(message.html));
    this.bodyAt.set(message.id, this.clock());
    return true;
  }

  private noteAnswer(id: string): void {
    if (this.order.indexOf(id) === -1) { this.order.push(id); }
  }

  /** True once any part has landed; the loader keeps polling until this holds and then settles. */
  hasContent(): boolean {
    return this.title.length > 0 || this.meta.length > 0 ||
      this.detailBlocks.length > 0 || this.order.length > 0;
  }

  answerCount(): number {
    return this.order.length;
  }

  /** How many blocks the current snapshot renders; used by the completion log line. */
  blockCount(): number {
    let total = this.detailBlocks.length;
    for (const id of this.order) {
      if (this.headers.get(id) !== undefined) { total++; }
      const body = this.bodies.get(id);
      if (body !== undefined) { total += body.length; }
    }
    return total;
  }

  progress(): ZhihuProgressRow[] {
    const rows: ZhihuProgressRow[] = [];
    const simple = (label: string, at: number, blocks: number): ZhihuProgressRow => {
      const row = new ZhihuProgressRow();
      row.label = label;
      row.ready = at > 0;
      row.at = at;
      row.blocks = blocks;
      return row;
    };
    rows.push(simple('title', this.titleAt, this.title.length));
    rows.push(simple('meta', this.metaAt, this.meta.length));
    rows.push(simple('detail', this.detailAt, this.detailBlocks.length));
    for (let index = 0; index < this.order.length; index++) {
      const id = this.order[index];
      const row = new ZhihuProgressRow();
      row.label = 'answer#' + String(index + 1);
      row.ready = this.headerAt.has(id);
      row.at = this.headerAt.get(id) ?? 0;
      row.blocks = row.ready ? 1 : -1;
      const body = this.bodies.get(id);
      row.bodyReady = body !== undefined;
      row.bodyAt = this.bodyAt.get(id) ?? 0;
      row.bodyBlocks = body === undefined ? -1 : body.length;
      rows.push(row);
    }
    return rows;
  }

  /** Fresh instance every call: the reader's @Local re-renders on reference change. */
  snapshot(url: string): Article {
    const article = new Article();
    article.title = this.title;
    article.subtitle = this.meta;
    article.sourceURL = url;
    const blocks: ArticleBlock[] = [];
    for (const block of this.detailBlocks) { blocks.push(block); }
    for (const id of this.order) {
      const header = this.headers.get(id);
      if (header !== undefined) { blocks.push(header); }
      const body = this.bodies.get(id);
      if (body !== undefined) {
        for (const block of body) { blocks.push(block); }
      }
    }
    article.blocks = blocks;
    return article;
  }
}
