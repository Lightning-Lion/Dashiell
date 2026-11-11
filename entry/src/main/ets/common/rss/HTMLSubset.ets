/**
 * Hand-written HTML subset parser for the article feeds this app bundles.
 *
 * Why not a third-party library: the available ohpm HTML parsers (htmlparser2/domhandler,
 * jsoup port) break under this project's useNormalizedOHMUrl: true build option, and the
 * project rule is to keep build-profile.json5 untouched. The feeds themselves (RSSHub for
 * 3DM / Zhihu, ithome.com) only emit a closed set of tags — see the census in the plan —
 * so a strict whitelist parser is both smaller and safer than a general-purpose one.
 *
 * Deliberately unsupported: scripts, styles, images inside links (kept as blocks),
 * unknown elements (their text survives), anything hidden via the `hidden` attribute.
 */

import { ArticleBlock, BlockKind, EmbedType, InlineRun, RunKind, TableCell, TableRow } from './ArticleModel';

class HtmlToken {
  isTag: boolean = false;
  isEnd: boolean = false;
  name: string = '';
  attrs: Map<string, string> = new Map<string, string>();
  selfClose: boolean = false;
  text: string = '';

  constructor() {
    this.attrs = new Map<string, string>();
  }
}

enum FrameType {
  Block = 0, // paragraph/heading/quote container
  List = 1,
  ListItem = 2,
  Table = 3,
  Cell = 4,
  Figure = 5,
  FigCaption = 6
}

class Frame {
  type: FrameType;
  blocks: ArticleBlock[];
  ordered: boolean = false;
  rows: TableRow[] = [];
  images: ArticleBlock[] = [];
  captionText: string = '';

  constructor(type: FrameType) {
    this.type = type;
    this.blocks = [];
    this.rows = [];
    this.images = [];
  }
}

class InlineStyle {
  bold: boolean = false;
  italic: boolean = false;
  code: boolean = false;
  superscript: boolean = false;
  subscript: boolean = false;
  url: string = '';
  name: string = '';
}

export class HTMLSubsetParser {
  private static readonly VOID: Set<string> = new Set<string>(['img', 'br', 'hr', 'meta', 'link', 'input', 'source',
    'col', 'wbr', 'area', 'base', 'embed', 'param', 'track']);
  private static readonly SKIP: Set<string> = new Set<string>(['script', 'style', 'noscript', 'template', 'svg',
    'head', 'title', 'meta', 'link', 'base', 'object', 'canvas', 'map', 'iframe-body']);
  private static readonly INLINE: Set<string> = new Set<string>(['strong', 'b', 'em', 'i', 'code', 'a', 'span',
    'sup', 'sub', 'u', 's', 'del', 'ins', 'small', 'mark', 'abbr', 'kbd', 'samp', 'var', 'time', 'cite', 'q']);
  private static readonly HEADINGS: Set<string> = new Set<string>(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']);

  private static readonly TAG_SOURCE: string =
    '<(\\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:\\s+[^\\s=\\/>]+(?:\\s*=\\s*(?:"[^"]*"|\'[^\']*\'|[^\\s>]*))?)*)\\s*(\\/?)>';
  private static readonly ATTR_RE: RegExp =
    /([^\s=\/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]*)))?/g;

  // ---------------------------------------------------------------- entities

  /** Decodes the named entities the bundled feeds actually use, plus all numeric entities. */
  static decodeEntities(input: string): string {
    let output = input;
    output = output.split('&amp;').join('&');
    output = output.split('&lt;').join('<');
    output = output.split('&gt;').join('>');
    output = output.split('&quot;').join('"');
    output = output.split('&#39;').join('\'');
    output = output.split('&apos;').join('\'');
    output = output.split('&nbsp;').join(' ');
    output = output.split('&mdash;').join('—');
    output = output.split('&ndash;').join('–');
    output = output.split('&hellip;').join('…');
    output = output.split('&middot;').join('·');
    output = output.split('&ldquo;').join('“');
    output = output.split('&rdquo;').join('”');
    output = output.split('&lsquo;').join('‘');
    output = output.split('&rsquo;').join('’');
    output = output.split('&times;').join('×');
    output = output.split('&divide;').join('÷');
    output = output.split('&copy;').join('©');
    output = output.split('&trade;').join('™');
    output = output.split('&reg;').join('®');
    output = output.split('&deg;').join('°');
    // Numeric entities via a manual exec loop (no regex callbacks in ArkTS).
    const numeric: RegExp = /&#(x[0-9a-fA-F]+|[0-9]+);/g;
    let match: RegExpExecArray | null = numeric.exec(output);
    if (match === null) { return output; }
    const pieces: string[] = [];
    let last = 0;
    while (match !== null) {
      pieces.push(output.substring(last, match.index));
      const raw = match[1];
      let code = -1;
      if (raw.startsWith('x') || raw.startsWith('X')) {
        code = parseInt(raw.substring(1), 16);
      } else {
        code = parseInt(raw, 10);
      }
      if (!isNaN(code) && code > 0 && code <= 0x10FFFF) {
        pieces.push(String.fromCodePoint(code));
      } else {
        pieces.push(match[0]);
      }
      last = match.index + match[0].length;
      match = numeric.exec(output);
    }
    pieces.push(output.substring(last));
    return pieces.join('');
  }

  // ---------------------------------------------------------------- tokenizer

  private static tokenize(input: string): HtmlToken[] {
    const tokens: HtmlToken[] = [];
    const tagRe: RegExp = new RegExp(HTMLSubsetParser.TAG_SOURCE, 'g');
    let i = 0;
    while (i < input.length) {
      const open = input.indexOf('<', i);
      if (open < 0) {
        const tail = new HtmlToken();
        tail.text = input.substring(i);
        tokens.push(tail);
        break;
      }
      if (open > i) {
        const text = new HtmlToken();
        text.text = input.substring(i, open);
        tokens.push(text);
      }
      if (input.startsWith('<!--', open)) {
        const close = input.indexOf('-->', open);
        i = close > 0 ? close + 3 : input.length;
        continue;
      }
      if (input.startsWith('<!', open) || input.startsWith('<?', open)) {
        const close = input.indexOf('>', open);
        i = close > 0 ? close + 1 : input.length;
        continue;
      }
      tagRe.lastIndex = open;
      const match = tagRe.exec(input);
      if (match === null || match.index !== open) {
        // A stray '<' that is not a tag; keep it as literal text.
        const text = new HtmlToken();
        text.text = '<';
        tokens.push(text);
        i = open + 1;
        continue;
      }
      const tag = new HtmlToken();
      tag.isTag = true;
      tag.isEnd = match[1] === '/';
      tag.name = match[2].toLowerCase();
      tag.selfClose = match[4] === '/';
      const attrSource = match[3];
      HTMLSubsetParser.ATTR_RE.lastIndex = 0;
      let attrMatch: RegExpExecArray | null = HTMLSubsetParser.ATTR_RE.exec(attrSource);
      while (attrMatch !== null) {
        const attrName = attrMatch[1].toLowerCase();
        let value = '';
        if (attrMatch[2] !== undefined) { value = attrMatch[2]; }
        else if (attrMatch[3] !== undefined) { value = attrMatch[3]; }
        else if (attrMatch[4] !== undefined) { value = attrMatch[4]; }
        tag.attrs.set(attrName, HTMLSubsetParser.decodeEntities(value));
        attrMatch = HTMLSubsetParser.ATTR_RE.exec(attrSource);
      }
      tokens.push(tag);
      i = match.index + match[0].length;
    }
    return tokens;
  }

  /** Extracts the body of an element whose open tag ends at startIndex, by depth counting. */
  static extractElementBody(input: string, startIndex: number): string {
    const raw = input.substring(startIndex);
    const tagRe: RegExp = new RegExp(HTMLSubsetParser.TAG_SOURCE, 'g');
    let depth = 1;
    let match: RegExpExecArray | null = tagRe.exec(raw);
    while (match !== null) {
      if (match[1] === '/') {
        depth--;
        if (depth === 0) { return raw.substring(0, match.index); }
      } else if (match[4] !== '/' && !HTMLSubsetParser.VOID.has(match[2].toLowerCase())) {
        depth++;
      }
      match = tagRe.exec(raw);
    }
    return raw;
  }

  // ---------------------------------------------------------------- state machine

  private tokens: HtmlToken[] = [];
  private pos: number = 0;
  private root: ArticleBlock[] = [];
  private frames: Frame[] = [];
  private wrap: ArticleBlock | null = null;
  private inline: InlineStyle[] = [];
  private skip: string[] = [];
  // Depth of nested elements inside a hidden container; the '__hidden__' marker pops only at 0.
  private hiddenDepth: number = 0;

  constructor() {
    this.tokens = [];
    this.root = [];
    this.frames = [];
    this.inline = [];
    this.skip = [];
    this.hiddenDepth = 0;
  }

  static parse(input: string): ArticleBlock[] {
    const parser = new HTMLSubsetParser();
    parser.tokens = HTMLSubsetParser.tokenize(input);
    const rootFrame = new Frame(FrameType.Block);
    rootFrame.blocks = parser.root;
    parser.frames.push(rootFrame);
    parser.run();
    return parser.root;
  }

  private nearestContainer(): ArticleBlock[] {
    for (let i = this.frames.length - 1; i >= 0; i--) {
      const frame = this.frames[i];
      if (frame.type === FrameType.Block || frame.type === FrameType.List ||
        frame.type === FrameType.ListItem || frame.type === FrameType.Cell) {
        return frame.blocks;
      }
    }
    return this.root;
  }

  private currentFrame(): Frame {
    return this.frames[this.frames.length - 1];
  }

  private flush(): void {
    if (this.wrap === null) { return; }
    const block = this.wrap;
    this.wrap = null;
    const merged: InlineRun[] = [];
    for (const run of block.runs) {
      const last = merged.length > 0 ? merged[merged.length - 1] : null;
      if (last !== null && last.kind === RunKind.Text && run.kind === RunKind.Text &&
        last.bold === run.bold && last.italic === run.italic && last.code === run.code &&
        last.superscript === run.superscript && last.subscript === run.subscript &&
        last.url === run.url) {
        last.text += run.text;
      } else if (run.kind === RunKind.Text && run.text.length === 0) {
        // drop empty text runs
      } else {
        merged.push(run);
      }
    }
    block.runs = merged;
    if (merged.length > 0) {
      this.nearestContainer().push(block);
    }
  }

  private startTextBlock(kind: BlockKind, level: number = 0): void {
    if (this.wrap !== null && this.wrap.kind === kind && this.wrap.level === level) { return; }
    this.flush();
    const block = new ArticleBlock();
    block.kind = kind;
    block.level = level;
    this.wrap = block;
  }

  private currentStyle(): InlineStyle {
    const style = new InlineStyle();
    for (const item of this.inline) {
      if (item.bold) { style.bold = true; }
      if (item.italic) { style.italic = true; }
      if (item.code) { style.code = true; }
      if (item.superscript) { style.superscript = true; }
      if (item.subscript) { style.subscript = true; }
      if (item.url !== '') { style.url = item.url; }
    }
    return style;
  }

  private addRun(kind: RunKind, text: string): void {
    if (this.skip.length > 0) { return; }
    if (this.wrap === null) {
      this.startTextBlock(BlockKind.Paragraph);
    }
    if (this.wrap === null) { return; }
    const run = new InlineRun();
    run.kind = kind;
    run.text = text;
    if (kind === RunKind.Text) {
      const style = this.currentStyle();
      run.bold = style.bold;
      run.italic = style.italic;
      run.code = style.code;
      run.superscript = style.superscript;
      run.subscript = style.subscript;
      run.url = style.url;
    }
    this.wrap.runs.push(run);
  }

  /**
   * Zhihu's inline images are lazy-loaded: the real URL sits in `data-original`, while `src` is
   * an empty inline SVG carrying only the aspect ratio
   * (`data:image/svg+xml;utf8,<svg width='1212' height='1170'></svg>`). Reading `src` first — the
   * obvious order, and what this used to do — hands the image loader a URL no HTTP stack can
   * fetch, so the first *loadable* candidate wins instead. Feeds that put the real URL in `src`
   * (3DM, IT之家) are unaffected: it is still the first candidate.
   */
  private static imageSource(attrs: Map<string, string>): string {
    const candidates: string[] = [
      attrs.get('src') ?? '', attrs.get('data-actualsrc') ?? '', attrs.get('data-original') ?? ''
    ];
    let placeholder = '';
    for (const candidate of candidates) {
      if (candidate.length === 0) { continue; }
      // Protocol-relative counts as loadable; RemoteImage normalizes it to https.
      if (candidate.startsWith('http://') || candidate.startsWith('https://') ||
        candidate.startsWith('//')) {
        return candidate;
      }
      if (placeholder.length === 0) { placeholder = candidate; }
    }
    // Nothing fetchable: keep the placeholder so the figure still renders its caption and a
    // failed slot instead of vanishing from the article.
    return placeholder;
  }

  private static numericAttr(value: string | undefined): number {
    if (value === undefined) { return 0; }
    let digits = '';
    for (let i = 0; i < value.length; i++) {
      const char = value.charAt(i);
      if (char >= '0' && char <= '9') { digits += char; }
    }
    if (digits.length === 0) { return 0; }
    return parseInt(digits, 10);
  }

  private pushImageBlock(src: string, alt: string, caption: string, width: number, height: number,
    avatar: boolean): void {
    const block = new ArticleBlock();
    block.kind = BlockKind.Image;
    block.src = src;
    block.alt = alt;
    block.caption = caption;
    block.width = width;
    block.height = height;
    block.avatar = avatar;
    if (this.currentFrame().type === FrameType.Figure) {
      this.currentFrame().images.push(block);
    } else {
      this.flush();
      this.nearestContainer().push(block);
    }
  }

  private run(): void {
    for (this.pos = 0; this.pos < this.tokens.length; this.pos++) {
      const token = this.tokens[this.pos];
      if (!token.isTag) {
        if (this.skip.length > 0) { continue; }
        if (this.currentFrame().type === FrameType.FigCaption) {
          this.currentFrame().captionText += HTMLSubsetParser.decodeEntities(token.text);
        } else if (token.text.trim().length > 0 || this.inline.length > 0) {
          this.addRun(RunKind.Text, HTMLSubsetParser.decodeEntities(token.text));
        }
        continue;
      }
      if (token.isEnd) {
        this.endTag(token.name);
      } else {
        this.startTag(token);
      }
    }
    this.flush();
    // Unbalanced stack: hoist any remaining frames into the nearest container.
    while (this.frames.length > 1) {
      const frame = this.frames.pop();
      if (frame !== undefined) {
        for (const block of frame.blocks) { this.nearestContainer().push(block); }
      }
    }
  }

  private startTag(token: HtmlToken): void {
    const name = token.name;
    if (this.skip.length > 0) {
      if (this.skip[this.skip.length - 1] === '__hidden__' && !token.isEnd && !token.selfClose) {
        this.hiddenDepth++;
      }
      if (HTMLSubsetParser.SKIP.has(name) && !token.selfClose) { this.skip.push(name); }
      return;
    }
    if (HTMLSubsetParser.SKIP.has(name)) {
      if (!token.selfClose) { this.skip.push(name); }
      return;
    }
    if (token.attrs.has('hidden')) {
      if (!token.selfClose) {
        this.skip.push('__hidden__');
        this.hiddenDepth = 0;
      }
      return;
    }
    // Video / audio with a direct source become a playable embed card; otherwise skipped.
    if (name === 'video' || name === 'audio') {
      const src = token.attrs.get('src');
      if (src !== undefined && src.length > 0) {
        this.flush();
        const block = new ArticleBlock();
        block.kind = BlockKind.Embed;
        block.embedType = EmbedType.Other;
        block.embedURL = src;
        this.nearestContainer().push(block);
      }
      if (!token.selfClose) { this.skip.push(name); }
      return;
    }
    if (name === 'img') {
      const src = HTMLSubsetParser.imageSource(token.attrs);
      if (src.length > 0) {
        const cls = token.attrs.get('class') ?? '';
        this.pushImageBlock(src, token.attrs.get('alt') ?? '',
          '', HTMLSubsetParser.numericAttr(token.attrs.get('w') ?? token.attrs.get('data-w')),
          HTMLSubsetParser.numericAttr(token.attrs.get('h') ?? token.attrs.get('data-h')),
          cls.includes('avatar'));
      }
      return;
    }
    if (name === 'br') { this.addRun(RunKind.Break, ''); return; }
    if (name === 'hr') {
      this.flush();
      const block = new ArticleBlock();
      block.kind = BlockKind.Divider;
      this.nearestContainer().push(block);
      return;
    }
    if (name === 'iframe') {
      this.flush();
      const block = new ArticleBlock();
      block.kind = BlockKind.Embed;
      const src = token.attrs.get('src') ?? '';
      const bvidMatch = /[?&]bvid=([A-Za-z0-9]+)/.exec(src);
      if (bvidMatch !== null) {
        block.embedType = EmbedType.Bilibili;
        block.bvid = bvidMatch[1];
      } else {
        block.embedType = EmbedType.Other;
      }
      block.embedURL = src;
      this.nearestContainer().push(block);
      return;
    }
    // Zhihu's structural wrappers (wrs-question-detail and friends) are plain containers:
    // the answer header is a structured bridge message now, not markup the script emits.
    if (name === 'div' || name === 'section') {
      // Transparent containers: content flows through.
      return;
    }
    if (HTMLSubsetParser.HEADINGS.has(name)) {
      this.startTextBlock(BlockKind.Heading, parseInt(name.substring(1), 10));
      return;
    }
    if (name === 'p') { this.startTextBlock(BlockKind.Paragraph); return; }
    if (name === 'blockquote') {
      this.flush();
      this.frames.push(new Frame(FrameType.Block));
      return;
    }
    if (name === 'ul' || name === 'ol') {
      this.flush();
      const frame = new Frame(FrameType.List);
      frame.ordered = name === 'ol';
      this.frames.push(frame);
      return;
    }
    if (name === 'li') {
      this.flush();
      this.frames.push(new Frame(FrameType.ListItem));
      return;
    }
    if (name === 'table') {
      this.flush();
      this.frames.push(new Frame(FrameType.Table));
      return;
    }
    if (name === 'tr') {
      this.flush();
      if (this.currentFrame().type === FrameType.Table) {
        const row = new TableRow();
        this.currentFrame().rows.push(row);
      }
      return;
    }
    if (name === 'td' || name === 'th') {
      this.flush();
      const table = this.currentFrame();
      if (table.type === FrameType.Table && table.rows.length > 0) {
        const row = table.rows[table.rows.length - 1];
        const cell = new TableCell();
        row.cells.push(cell);
        if (name === 'th') { row.header = true; }
        const frame = new Frame(FrameType.Cell);
        frame.blocks = cell.blocks;
        this.frames.push(frame);
      }
      return;
    }
    if (name === 'figure') {
      this.flush();
      this.frames.push(new Frame(FrameType.Figure));
      return;
    }
    if (name === 'figcaption') {
      this.flush();
      this.frames.push(new Frame(FrameType.FigCaption));
      return;
    }
    if (HTMLSubsetParser.INLINE.has(name)) {
      const style = new InlineStyle();
      style.name = name;
      if (name === 'strong' || name === 'b') { style.bold = true; }
      if (name === 'em' || name === 'i') { style.italic = true; }
      if (name === 'code') { style.code = true; }
      if (name === 'sup') { style.superscript = true; }
      if (name === 'sub') { style.subscript = true; }
      if (name === 'a') {
        const href = token.attrs.get('href');
        if (href !== undefined && href.length > 0) { style.url = href; }
      }
      this.inline.push(style);
      return;
    }
    // Anything else is a transparent container: keep its text, drop its chrome.
  }

  private endTag(name: string): void {
    if (this.skip.length > 0) {
      const top = this.skip[this.skip.length - 1];
      if (top === '__hidden__') {
        if (this.hiddenDepth > 0) {
          this.hiddenDepth--;
        } else {
          this.skip.pop();
        }
      } else if (name === top) {
        this.skip.pop();
      }
      return;
    }
    if (HTMLSubsetParser.INLINE.has(name)) {
      for (let i = this.inline.length - 1; i >= 0; i--) {
        if (this.inline[i].name === name) {
          this.inline.splice(i, 1);
          break;
        }
      }
      return;
    }
    if (name === 'p' || HTMLSubsetParser.HEADINGS.has(name)) { this.flush(); return; }
    if (name === 'li') {
      this.flush();
      if (this.currentFrame().type === FrameType.ListItem) {
        const frame = this.frames.pop();
        if (frame !== undefined && frame.blocks.length > 0) {
          const block = new ArticleBlock();
          block.kind = BlockKind.ListItem;
          block.children = frame.blocks;
          this.nearestContainer().push(block);
        }
      }
      return;
    }
    if (name === 'ul' || name === 'ol') {
      this.flush();
      if (this.currentFrame().type === FrameType.List) {
        const frame = this.frames.pop();
        if (frame !== undefined) {
          const block = new ArticleBlock();
          block.kind = BlockKind.List;
          block.ordered = frame.ordered;
          block.children = frame.blocks;
          this.nearestContainer().push(block);
        }
      }
      return;
    }
    if (name === 'blockquote') {
      this.flush();
      if (this.currentFrame().type === FrameType.Block) {
        const frame = this.frames.pop();
        if (frame !== undefined && frame.blocks.length > 0) {
          const block = new ArticleBlock();
          block.kind = BlockKind.Quote;
          block.children = frame.blocks;
          this.nearestContainer().push(block);
        }
      }
      return;
    }
    if (name === 'td' || name === 'th') {
      this.flush();
      if (this.currentFrame().type === FrameType.Cell) { this.frames.pop(); }
      return;
    }
    if (name === 'tr') { this.flush(); return; }
    if (name === 'table') {
      this.flush();
      if (this.currentFrame().type === FrameType.Table) {
        const frame = this.frames.pop();
        if (frame !== undefined && frame.rows.length > 0) {
          const block = new ArticleBlock();
          block.kind = BlockKind.Table;
          block.rows = frame.rows;
          this.nearestContainer().push(block);
        }
      }
      return;
    }
    if (name === 'figcaption') {
      this.flush();
      if (this.currentFrame().type === FrameType.FigCaption) {
        const frame = this.frames.pop();
        if (frame !== undefined) {
          const caption = frame.captionText.trim();
          if (caption.length > 0) {
            let attached = false;
            // Attach the caption to every image collected in the enclosing figure.
            for (let i = this.frames.length - 1; i >= 0; i--) {
              if (this.frames[i].type === FrameType.Figure) {
                for (const image of this.frames[i].images) { image.caption = caption; }
                attached = true;
                break;
              }
            }
            if (!attached) {
              // IT之家 puts <figcaption> right after the image without a <figure> wrapper:
              // attach it to the most recent image block, else keep it as a plain paragraph.
              const container = this.nearestContainer();
              for (let i = container.length - 1; i >= 0; i--) {
                if (container[i].kind === BlockKind.Image) {
                  container[i].caption = container[i].caption.length > 0 ?
                    container[i].caption + ' ' + caption : caption;
                  attached = true;
                  break;
                }
              }
              if (!attached) {
                const block = new ArticleBlock();
                block.kind = BlockKind.Paragraph;
                const run = new InlineRun();
                run.text = caption;
                block.runs.push(run);
                container.push(block);
              }
            }
          }
        }
      }
      return;
    }
    if (name === 'figure') {
      this.flush();
      if (this.currentFrame().type === FrameType.Figure) {
        const frame = this.frames.pop();
        if (frame !== undefined) {
          for (const image of frame.images) { this.nearestContainer().push(image); }
        }
      }
      return;
    }
    // Container or unknown close tags: nothing to do.
  }
}
