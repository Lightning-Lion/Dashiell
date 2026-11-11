import { LocalSchema } from './schema/LocalDecoders.generated';
import { JsonDecodeError, DecodeIssue } from '../jsonschema/JsonDecode';

export class LocalDataDecoder {
  static parseRSSSourceIds(stored: Object): string[] {
    if (typeof stored !== 'string') {
      throw new JsonDecodeError('RSSSourceIds', [new DecodeIssue('TYPE_MISMATCH', [], 'stored JSON text', typeof stored)]);
    }
    return LocalSchema.tryParseRSSSourceIds(stored).getOrThrow();
  }
}
