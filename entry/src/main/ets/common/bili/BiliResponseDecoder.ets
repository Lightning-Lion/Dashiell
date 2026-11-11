import { BiliBusinessError } from './BiliBusinessError';
import { DecodeContext, DecodeResult, JsonNode, JsonDecodeError, DecodeIssue } from '../jsonschema/JsonDecode';
import { BiliSchema } from './schema/BiliDecoders.generated';
import {
  BiliEnvelope, BiliWbiResponse, BiliUPVideosResponse, BiliFavoriteFoldersResponse,
  BiliFavoriteContentsResponse, BiliFavoriteFolderResponse, BiliFavoriteStateResponse,
  BiliMidResponse, BiliHistoryResponse, BiliActionResponse, BiliLikeStateResponse, BiliCoinStateResponse, BiliInsertCoinResponse, BiliUserStatResponse, BiliUserCardResponse, BiliUserCoinResponse, BiliFollowingResponse
} from './schema/BiliModels.generated';
import { BiliHotSearchItem } from '../BiliHotSearch';

export class HotSearchReport {
  items: BiliHotSearchItem[];
  issues: DecodeIssue[];
  received: number;
  skipped: number;
  constructor(items: BiliHotSearchItem[], issues: DecodeIssue[], received: number, skipped: number) {
    this.items = items; this.issues = issues; this.received = received; this.skipped = skipped;
  }
}

export class BiliResponseDecoder {
  static responseText(value: Object): string {
    if (typeof value !== 'string') {
      throw new JsonDecodeError('BiliHTTP', [new DecodeIssue('TYPE_MISMATCH', [], 'response text', typeof value)]);
    }
    return value;
  }

  static parseEnvelope(text: string): BiliEnvelope {
    return BiliSchema.tryParseEnvelope(text).getOrThrow();
  }

  static read<T>(text: string, name: string,
    decoder: (node: JsonNode, context: DecodeContext) => T | undefined): T {
    const context = new DecodeContext(name);
    const root = JsonNode.parse(text, context);
    if (root === undefined) { return context.finish<T>(undefined).getOrThrow(); }
    const status = BiliSchema.decodeEnvelope(root, context);
    if (status === undefined) { return context.finish<T>(undefined).getOrThrow(); }
    if (status.code !== 0) {
      throw new BiliBusinessError(name, status.code);
    }
    return context.finish<T>(decoder(root, context)).getOrThrow();
  }

  private static session(root: JsonNode, context: DecodeContext): boolean {
    const status = BiliSchema.decodeEnvelope(root, context);
    if (status === undefined) { return context.finish<boolean>(undefined).getOrThrow(); }
    if (status.code === -101) { return false; }
    if (status.code !== 0) {
      context.issue('BUSINESS_STATUS', root.field('code'), 'successful code or expired session (-101)');
      return context.finish<boolean>(undefined).getOrThrow();
    }
    const model = BiliSchema.decodeSessionResponse(root, context);
    return context.finish<boolean>(model?.data.isLogin).getOrThrow();
  }

  static parseSession(text: string): boolean {
    const context = new DecodeContext('BiliSession');
    const root = JsonNode.parse(text, context);
    if (root === undefined) { return context.finish<boolean>(undefined).getOrThrow(); }
    return BiliResponseDecoder.session(root, context);
  }

  static validateSession(value: Object): boolean {
    return BiliResponseDecoder.session(new JsonNode(value, []), new DecodeContext('BiliSession'));
  }

  static parseWbi(text: string): BiliWbiResponse {
    // This endpoint is a key payload projection, not a login verdict; preserve guest-key responses.
    return BiliSchema.tryParseWbiResponse(text).getOrThrow();
  }
  static parseUPVideos(text: string): BiliUPVideosResponse {
    return BiliResponseDecoder.read<BiliUPVideosResponse>(text, 'BiliUPVideos', BiliSchema.decodeUPVideosResponse);
  }
  static parseFavoriteFolders(text: string): BiliFavoriteFoldersResponse {
    return BiliResponseDecoder.read<BiliFavoriteFoldersResponse>(text, 'BiliFavoriteFolders', BiliSchema.decodeFavoriteFoldersResponse);
  }
  static parseFavoriteContents(text: string): BiliFavoriteContentsResponse {
    return BiliResponseDecoder.read<BiliFavoriteContentsResponse>(text, 'BiliFavoriteContents', BiliSchema.decodeFavoriteContentsResponse);
  }
  static parseFavoriteFolder(text: string): BiliFavoriteFolderResponse {
    return BiliResponseDecoder.read<BiliFavoriteFolderResponse>(text, 'BiliFavoriteFolder', BiliSchema.decodeFavoriteFolderResponse);
  }
  static parseFavoriteState(text: string): BiliFavoriteStateResponse {
    return BiliResponseDecoder.read<BiliFavoriteStateResponse>(text, 'BiliFavoriteState', BiliSchema.decodeFavoriteStateResponse);
  }
  static parseMid(text: string): BiliMidResponse {
    return BiliResponseDecoder.read<BiliMidResponse>(text, 'BiliMid', BiliSchema.decodeMidResponse);
  }
  static parseHistory(text: string): BiliHistoryResponse {
    return BiliResponseDecoder.read<BiliHistoryResponse>(text, 'BiliHistory', BiliSchema.decodeHistoryResponse);
  }

  static parseActionResponse(text: string): BiliActionResponse {
    return BiliResponseDecoder.read<BiliActionResponse>(text, 'BiliActionResponse', BiliSchema.decodeActionResponse);
  }
  static parseLikeStateResponse(text: string): BiliLikeStateResponse {
    return BiliResponseDecoder.read<BiliLikeStateResponse>(text, 'BiliLikeStateResponse', BiliSchema.decodeLikeStateResponse);
  }
  static parseCoinStateResponse(text: string): BiliCoinStateResponse {
    return BiliResponseDecoder.read<BiliCoinStateResponse>(text, 'BiliCoinStateResponse', BiliSchema.decodeCoinStateResponse);
  }
  static parseInsertCoinResponse(text: string): BiliInsertCoinResponse {
    return BiliResponseDecoder.read<BiliInsertCoinResponse>(text, 'BiliInsertCoinResponse', BiliSchema.decodeInsertCoinResponse);
  }
  static parseUserStatResponse(text: string): BiliUserStatResponse {
    return BiliResponseDecoder.read<BiliUserStatResponse>(text, 'BiliUserStatResponse', BiliSchema.decodeUserStatResponse);
  }
  static parseUserCardResponse(text: string): BiliUserCardResponse {
    return BiliResponseDecoder.read<BiliUserCardResponse>(text, 'BiliUserCardResponse', BiliSchema.decodeUserCardResponse);
  }
  static parseUserCoinResponse(text: string): BiliUserCoinResponse {
    return BiliResponseDecoder.read<BiliUserCoinResponse>(text, 'BiliUserCoinResponse', BiliSchema.decodeUserCoinResponse);
  }
  static parseFollowingResponse(text: string): BiliFollowingResponse {
    return BiliResponseDecoder.read<BiliFollowingResponse>(text, 'BiliFollowingResponse', BiliSchema.decodeFollowingResponse);
  }

  /** Explicit per-item tolerance; unlike strict endpoint decoders, returns diagnostics for skipped rows/fallbacks. */
  static parseHotSearchReport(text: string): HotSearchReport {
    const context = new DecodeContext('BiliHotSearch');
    const root = JsonNode.parse(text, context);
    if (root === undefined) { return context.finish<HotSearchReport>(undefined).getOrThrow(); }
    const status = BiliSchema.decodeEnvelope(root, context);
    if (status === undefined) { return context.finish<HotSearchReport>(undefined).getOrThrow(); }
    if (status.code !== 0) {
      context.issue('BUSINESS_STATUS', root.field('code'), 'successful code (0)');
      return context.finish<HotSearchReport>(undefined).getOrThrow();
    }
    const container = BiliSchema.decodeHotSearchContainer(root, context);
    if (container === undefined) { return context.finish<HotSearchReport>(undefined).getOrThrow(); }
    const list = root.field('data').field('trending').field('list');
    if (list.kind() !== 'array') {
      context.issue(list.kind() === 'missing' ? 'MISSING_FIELD' : 'TYPE_MISMATCH', list, 'array');
      return context.finish<HotSearchReport>(undefined).getOrThrow();
    }
    if (list.length() > DecodeContext.MAX_ITEMS) {
      context.issue('LIMIT_EXCEEDED', list, 'array within item limit');
      return context.finish<HotSearchReport>(undefined).getOrThrow();
    }
    const items: BiliHotSearchItem[] = [];
    const issues: DecodeIssue[] = [];
    let skipped = 0;
    let invalid = 0;
    for (let index = 0; index < list.length(); index++) {
      const node = list.element(index);
      const row = new DecodeContext('BiliHotSearchItem');
      const decoded = row.finish(BiliSchema.decodeHotSearchKeyword(node, row));
      if (!decoded.isSuccess()) {
        invalid++; skipped++;
        BiliResponseDecoder.collectIssues(issues, decoded.getFailure());
        continue;
      }
      const keyword = decoded.getOrThrow().keyword.trim();
      if (keyword.length === 0) { skipped++; continue; }
      const displayContext = new DecodeContext('BiliHotSearchDisplay');
      const display = displayContext.finish(BiliSchema.decodeHotSearchDisplay(node, displayContext));
      let showName = keyword;
      if (display.isSuccess()) {
        const name = display.getOrThrow().show_name?.trim();
        if (name !== undefined && name.length > 0) { showName = name; }
      } else {
        BiliResponseDecoder.collectIssues(issues, display.getFailure());
      }
      items.push({ keyword: keyword, show_name: showName });
    }
    // A completely broken response must not look like a legitimate empty ranking.
    if (items.length === 0 && invalid > 0) { throw new JsonDecodeError('BiliHotSearch', issues); }
    return new HotSearchReport(items, issues, list.length(), skipped);
  }

  private static collectIssues(target: DecodeIssue[], error: JsonDecodeError): void {
    for (const issue of error.issues) {
      if (target.length >= DecodeContext.MAX_ISSUES) { return; }
      target.push(issue);
    }
  }
}
