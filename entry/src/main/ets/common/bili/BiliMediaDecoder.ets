import { DecodeContext, JsonNode } from '../jsonschema/JsonDecode';
import { BiliSchema } from './schema/BiliDecoders.generated';
import { BiliHomeResponse, BiliSearchResponse, BiliCidResponse, BiliDetailResponse,
  BiliPlaybackResponse, BiliNavResponse } from './schema/BiliModels.generated';
import { BiliResponseDecoder } from './BiliResponseDecoder';
import { BiliMediaMapping } from './BiliMediaMapping';

/** Full validation of each consumer's declared projection; unknown API metadata is intentionally stripped. */
export class BiliMediaDecoder {
  static positiveId(value: string | number | undefined): boolean {
    return value !== undefined && /^[0-9]+$/.test(String(value)) && !/^0+$/.test(String(value));
  }
  private static decodeHome(root: JsonNode, context: DecodeContext): BiliHomeResponse | undefined {
    const model = BiliSchema.decodeHomeResponse(root, context);
    if (model === undefined) { return undefined; }
    for (let index = 0; index < model.data.item.length && !context.exhausted(); index++) {
      const item = model.data.item[index];
      const row = root.field('data').field('item').element(index);
      // Validate decimal wire IDs even on placeholders. Never coerce strings through Number.
      if (typeof item.id === 'string' && !/^[0-9]+$/.test(item.id)) {
        context.issue('INVALID_VALUE', row.field('id'), 'decimal id string');
      }
      if (typeof item.cid === 'string' && !/^[0-9]+$/.test(item.cid)) {
        context.issue('INVALID_VALUE', row.field('cid'), 'decimal cid string');
      }
      if (BiliMediaMapping.isHomePlaceholder(item)) { continue; }
      if (!BiliMediaDecoder.positiveId(item.id)) { context.issue('INVALID_VALUE', row.field('id'), 'positive video id'); }
      if (item.bvid === undefined || item.bvid.trim().length === 0) {
        context.issue(item.bvid === undefined ? 'MISSING_FIELD' : 'INVALID_VALUE', row.field('bvid'), 'non-empty video bvid');
      }
      if (!BiliMediaDecoder.positiveId(item.cid)) {
        context.issue(item.cid === undefined ? 'MISSING_FIELD' : 'INVALID_VALUE', row.field('cid'), 'positive video cid');
      }
      if (item.owner !== undefined && item.owner !== null && !item.owner.name?.trim()) {
        context.issue(item.owner.name === undefined ? 'MISSING_FIELD' : 'INVALID_VALUE', row.field('owner').field('name'), 'non-empty owner name');
      }
    }
    return model;
  }
  static parseHome(text: string): BiliHomeResponse {
    return BiliResponseDecoder.read<BiliHomeResponse>(text, 'BiliHome', BiliMediaDecoder.decodeHome);
  }
  static parseSearch(text: string): BiliSearchResponse {
    return BiliResponseDecoder.read<BiliSearchResponse>(text, 'BiliSearch', (root: JsonNode, context: DecodeContext): BiliSearchResponse | undefined => {
      const model = BiliSchema.decodeSearchResponse(root, context);
      if (model !== undefined) {
        for (let index = 0; index < model.data.result.length && !context.exhausted(); index++) {
          if (!BiliMediaDecoder.positiveId(model.data.result[index].id)) {
            context.issue('INVALID_VALUE', root.field('data').field('result').element(index).field('id'), 'positive video id');
          }
        }
      }
      return model;
    });
  }
  static parseCid(text: string, expectedBvid: string): BiliCidResponse {
    return BiliResponseDecoder.read<BiliCidResponse>(text, 'BiliCid', (root: JsonNode, context: DecodeContext): BiliCidResponse | undefined => {
      const model = BiliSchema.decodeCidResponse(root, context);
      if (model !== undefined) {
        if (!BiliMediaDecoder.positiveId(model.data.cid)) { context.issue('INVALID_VALUE', root.field('data').field('cid'), 'positive cid'); }
        if (model.data.bvid !== undefined && model.data.bvid !== expectedBvid) {
          context.issue('ID_MISMATCH', root.field('data').field('bvid'), 'requested bvid');
        }
      }
      return model;
    });
  }
  static parseDetail(text: string, expectedBvid: string): BiliDetailResponse {
    return BiliResponseDecoder.read<BiliDetailResponse>(text, 'BiliDetail', (root: JsonNode, context: DecodeContext): BiliDetailResponse | undefined => {
      const model = BiliSchema.decodeDetailResponse(root, context);
      if (model !== undefined) {
        if (model.data.View.bvid !== expectedBvid) { context.issue('ID_MISMATCH', root.field('data').field('View').field('bvid'), 'requested bvid'); }
        if (!BiliMediaDecoder.positiveId(model.data.View.cid)) { context.issue('INVALID_VALUE', root.field('data').field('View').field('cid'), 'positive cid'); }
      }
      return model;
    });
  }
  static parsePlayback(text: string): BiliPlaybackResponse {
    return BiliResponseDecoder.read<BiliPlaybackResponse>(text, 'BiliPlayback', (root: JsonNode, context: DecodeContext): BiliPlaybackResponse | undefined => {
      const model = BiliSchema.decodePlaybackResponse(root, context);
      if (model !== undefined) {
        if (model.data.timelength < 0) { context.issue('OUT_OF_RANGE', root.field('data').field('timelength'), 'non-negative duration'); }
        const parts = BiliMediaMapping.playbackParts(model);
        if (parts.length === 0 || parts.some((part) => part.urls.length === 0)) {
          context.issue('NO_PLAYABLE_URL', root.field('data').field('durl'), 'playable URL for every segment');
        }
      }
      return model;
    });
  }
  static parseNav(text: string): BiliNavResponse {
    return BiliResponseDecoder.read<BiliNavResponse>(text, 'BiliNav', (root: JsonNode, context: DecodeContext): BiliNavResponse | undefined => {
      const model = BiliSchema.decodeNavResponse(root, context);
      if (model !== undefined && model.data.isLogin && !BiliMediaDecoder.positiveId(model.data.mid)) {
        context.issue(model.data.mid === undefined ? 'MISSING_FIELD' : 'INVALID_VALUE', root.field('data').field('mid'), 'positive mid for authenticated user');
      }
      return model;
    });
  }
}
