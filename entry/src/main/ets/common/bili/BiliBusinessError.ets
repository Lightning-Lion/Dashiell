import { JsonDecodeError, DecodeIssue } from '../jsonschema/JsonDecode';

/** Business status is metadata, not the untrusted response message/body. */
export class BiliBusinessError extends JsonDecodeError {
  code: number;
  constructor(schema: string, code: number) {
    super(schema, [new DecodeIssue('BUSINESS_STATUS', ['code'], 'successful code (0)', 'number')]);
    this.code = code;
  }
}
