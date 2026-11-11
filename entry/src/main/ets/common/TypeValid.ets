// Compatibility entrypoints. Validation is generated; no opaque error-point codes or typed-assignment checks.
import { DecodeContext, JsonNode } from './jsonschema/JsonDecode';
import { BiliSchema } from './bili/schema/BiliDecoders.generated';
import { DouyinSchema } from './douyin/schema/DouyinDecoders.generated';
import { DouyinFeedMapping } from './douyin/DouyinFeedMapping';
import { DouYinRecommandAwemeData } from '../pages/DouYin/DouYinWebView';

/** @deprecated New entrypoints throw JsonDecodeError with structured paths. */
export class ValidationError extends Error {
  errorMessage: string;
  constructor(message: string) { super(message); this.errorMessage = message; }
}

export const validGetUPsVideosResponse = (value: Object | null | undefined): void => {
  const context = new DecodeContext('BiliUPVideos');
  context.finish(BiliSchema.decodeUPVideosResponse(new JsonNode(value, []), context)).getOrThrow();
};

export const validGetWbiKeysResponse = (value: Object | null | undefined): void => {
  const context = new DecodeContext('BiliWbi');
  context.finish(BiliSchema.decodeWbiResponse(new JsonNode(value, []), context)).getOrThrow();
};

export const validateAwemeData = (value: Object | null | undefined): DouYinRecommandAwemeData => {
  const context = new DecodeContext('DouyinWebFeed');
  const model = context.finish(DouyinSchema.decodeWebFeedResponse(new JsonNode(value, []), context)).getOrThrow();
  return DouyinFeedMapping.items(model.items);
};
