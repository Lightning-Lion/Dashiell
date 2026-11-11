/**
 * Native article content model shared by the HTML subset parser, feed adapters and the reader page.
 * A single class with a kind discriminant carries every block shape: ArkTS forbids union-typed
 * arrays, so all variants live on one ArticleBlock and only the fields matching the kind are used.
 */

export enum BlockKind {
  Paragraph = 'p',
  Heading = 'h',
  Quote = 'quote',
  List = 'list',
  ListItem = 'li',
  Table = 'table',
  Image = 'img',
  Divider = 'hr',
  Embed = 'embed',
  AnswerHeader = 'answerHeader',
  Meta = 'meta'
}

export enum RunKind {
  Text = 'text',
  Break = 'br'
}

export enum EmbedType {
  Bilibili = 'bilibili',
  Other = 'other'
}

export class InlineRun {
  kind: RunKind = RunKind.Text;
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  code: boolean = false;
  superscript: boolean = false;
  subscript: boolean = false;
  // Non-empty for link runs; clicking dispatches to native or web navigation.
  url: string = '';
}

export class TableCell {
  blocks: ArticleBlock[] = [];

  constructor() {
    this.blocks = [];
  }
}

export class TableRow {
  cells: TableCell[] = [];
  header: boolean = false;

  constructor() {
    this.cells = [];
    this.header = false;
  }
}

export class ArticleBlock {
  kind: BlockKind = BlockKind.Paragraph;
  // Heading level (1-6), only used for kind === Heading.
  level: number = 0;
  // List ordering, only used for kind === List.
  ordered: boolean = false;
  // Inline content, used for Paragraph / Heading / ListItem / TableCell contents.
  runs: InlineRun[] = [];
  // Image fields, only used for kind === Image.
  src: string = '';
  alt: string = '';
  caption: string = '';
  width: number = 0;
  height: number = 0;
  // Small round avatar image; not part of the fullscreen viewer.
  avatar: boolean = false;
  // Embed fields, only used for kind === Embed.
  embedType: EmbedType = EmbedType.Other;
  embedURL: string = '';
  bvid: string = '';
  // Container children, used for Quote / List / ListItem.
  children: ArticleBlock[] = [];
  // Table rows, only used for kind === Table.
  rows: TableRow[] = [];
  // Answer header fields (Zhihu hot answers).
  author: string = '';
  authorAvatar: string = '';
  votes: string = '';
  // Meta line fields (Zhihu hot question stats).
  metaText: string = '';

  constructor() {
    this.runs = [];
    this.children = [];
    this.rows = [];
  }
}

export class Article {
  title: string = '';
  // Author · bio / question stats line, shown under the title.
  subtitle: string = '';
  authorAvatar: string = '';
  // Hero image (Zhihu Daily enclosure), '' when absent.
  heroImage: string = '';
  // Original URL of this article.
  sourceURL: string = '';
  // "View more" link (Zhihu Daily question link), '' when absent.
  viewMoreURL: string = '';
  blocks: ArticleBlock[] = [];

  constructor() {
    this.blocks = [];
  }
}

/** Flattens a block tree (including table cells) into its visible text, for diagnostics. */
export function articleTextPreview(article: Article, maxLength: number): string {
  let text = '';
  const collect = (blocks: ArticleBlock[]): void => {
    if (text.length >= maxLength) { return; }
    for (const block of blocks) {
      for (const run of block.runs) {
        if (run.kind === RunKind.Text) { text += run.text; }
      }
      collect(block.children);
      for (const row of block.rows) {
        for (const cell of row.cells) { collect(cell.blocks); }
      }
    }
  };
  collect(article.blocks);
  return text.substring(0, maxLength);
}
