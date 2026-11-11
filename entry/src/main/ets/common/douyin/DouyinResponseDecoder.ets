import { DecodeContext, DecodeResult, JsonNode } from '../jsonschema/JsonDecode';
import { DouyinSchema } from './schema/DouyinDecoders.generated';
import { DouyinFeedResponse, DouyinDetailResponse, DouyinWebFeedResponse, DouyinSelfProfileResponse } from './schema/DouyinModels.generated';

/** Endpoint semantics stay outside the schema compiler. Strict: never silently drops invalid array items. */
export class DouyinResponseDecoder {
  private static successfulEnvelope(text: string, context: DecodeContext): JsonNode | undefined {
    const root = JsonNode.parse(text, context);
    if (root === undefined) { return undefined; }
    const status = DouyinSchema.decodeApiStatus(root, context);
    if (status === undefined) { return undefined; }
    // A valid server error must not be misreported as a missing success payload.
    if (status.statusCode !== 0) {
      context.issue('BUSINESS_STATUS', root.field('status_code'), 'successful status_code (0)');
      return undefined;
    }
    return root;
  }

  static tryParseFeed(text: string): DecodeResult<DouyinFeedResponse> {
    const context = new DecodeContext('DouyinFeed');
    const root = DouyinResponseDecoder.successfulEnvelope(text, context);
    return context.finish<DouyinFeedResponse>(root === undefined ? undefined : DouyinSchema.decodeFeedResponse(root, context));
  }

  static parseFeed(text: string): DouyinFeedResponse {
    return DouyinResponseDecoder.tryParseFeed(text).getOrThrow();
  }

  static tryParseDetail(text: string, expectedId: string): DecodeResult<DouyinDetailResponse> {
    const context = new DecodeContext('DouyinDetail');
    const root = DouyinResponseDecoder.successfulEnvelope(text, context);
    if (root === undefined) { return context.finish<DouyinDetailResponse>(undefined); }
    const detail = DouyinSchema.decodeDetailResponse(root, context);
    if (detail !== undefined && detail.item.id !== expectedId) {
      context.issue('ID_MISMATCH', root.field('aweme_detail').field('aweme_id'), 'requested video id');
    }
    return context.finish<DouyinDetailResponse>(detail);
  }

  static parseDetail(text: string, expectedId: string): DouyinDetailResponse {
    return DouyinResponseDecoder.tryParseDetail(text, expectedId).getOrThrow();
  }
  // Web interception and old caches may omit status_code; if present it must be valid and successful.
  static tryParseWebFeed(text: string): DecodeResult<DouyinWebFeedResponse> {
    const context = new DecodeContext('DouyinWebFeed');
    const root = JsonNode.parse(text, context);
    if (root === undefined) { return context.finish<DouyinWebFeedResponse>(undefined); }
    if (root.kind() === 'object' && root.field('status_code').kind() !== 'missing') {
      const status = DouyinSchema.decodeApiStatus(root, context);
      if (status === undefined) { return context.finish<DouyinWebFeedResponse>(undefined); }
      if (status.statusCode !== 0) {
        context.issue('BUSINESS_STATUS', root.field('status_code'), 'successful status_code (0)');
        return context.finish<DouyinWebFeedResponse>(undefined);
      }
    }
    return context.finish<DouyinWebFeedResponse>(DouyinSchema.decodeWebFeedResponse(root, context));
  }

  static parseWebFeed(text: string): DouyinWebFeedResponse {
    return DouyinResponseDecoder.tryParseWebFeed(text).getOrThrow();
  }

  static tryParseSelfProfile(text: string): DecodeResult<DouyinSelfProfileResponse> {
    const context = new DecodeContext('DouyinSelfProfile');
    const root = DouyinResponseDecoder.successfulEnvelope(text, context);
    return context.finish<DouyinSelfProfileResponse>(root === undefined ? undefined :
      DouyinSchema.decodeSelfProfileResponse(root, context));
  }

  static parseSelfProfile(text: string): DouyinSelfProfileResponse {
    return DouyinResponseDecoder.tryParseSelfProfile(text).getOrThrow();
  }

}
