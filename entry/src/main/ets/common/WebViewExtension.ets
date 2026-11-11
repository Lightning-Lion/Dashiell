import { LocalSchema } from './local/schema/LocalDecoders.generated';

// ArkWeb returns JSON text. A legitimate null is distinct from a schema/JSON error.
// These functions throw JsonDecodeError on invalid/wrongly typed returns; callers have error boundaries.
export const jsReturnValueToString = (rawResult: string): string | null => {
  return LocalSchema.tryParseScriptString(rawResult).getOrThrow();
};
export const jsReturnValueToNumber = (rawResult: string): number | null => {
  return LocalSchema.tryParseScriptNumber(rawResult).getOrThrow();
};
export const jsReturnValueToBoolean = (rawResult: string): boolean | null => {
  return LocalSchema.tryParseScriptBoolean(rawResult).getOrThrow();
};
