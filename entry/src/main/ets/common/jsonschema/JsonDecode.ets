/** Small JSON boundary shared by statically generated decoders. No schema interpreter. */
export class DecodeIssue {
  code: string;
  path: Array<string | number>;
  expected: string;
  actualType: string;

  constructor(code: string, path: Array<string | number>, expected: string, actualType: string) {
    this.code = code;
    this.path = path.slice();
    this.expected = expected;
    this.actualType = actualType;
  }

  pathText(): string {
    let text = '$';
    for (const segment of this.path) {
      if (typeof segment === 'number') {
        text += '[' + String(segment) + ']';
      } else if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(segment)) {
        text += '.' + segment;
      } else {
        text += '[' + JSON.stringify(segment) + ']';
      }
    }
    return text;
  }
}

export class JsonDecodeError extends Error {
  schema: string;
  issues: DecodeIssue[];

  constructor(schema: string, issues: DecodeIssue[]) {
    // Only metadata is included: never the JSON body, signed URLs, cookies, or parser exception text.
    super(schema + ': ' + issues.map((issue: DecodeIssue): string =>
      issue.code + ' at ' + issue.pathText() + ' expected=' + issue.expected + ' actual=' + issue.actualType).join('; '));
    this.schema = schema;
    this.issues = issues.slice();
  }
}

export class DecodeResult<T> {
  private value: T | undefined;
  private failure: JsonDecodeError | undefined;

  private constructor(value: T | undefined, failure: JsonDecodeError | undefined) {
    this.value = value;
    this.failure = failure;
  }

  static success<T>(value: T): DecodeResult<T> {
    return new DecodeResult<T>(value, undefined);
  }

  static failed<T>(error: JsonDecodeError): DecodeResult<T> {
    return new DecodeResult<T>(undefined, error);
  }

  isSuccess(): boolean { return this.failure === undefined; }

  getOrThrow(): T {
    if (this.failure !== undefined) { throw this.failure; }
    if (this.value === undefined) { throw new Error('Invalid DecodeResult invariant'); }
    return this.value;
  }

  getFailure(): JsonDecodeError {
    if (this.failure === undefined) { throw new Error('Successful DecodeResult has no failure'); }
    return this.failure;
  }
}

export class DecodeContext {
  readonly schema: string;
  private issues: DecodeIssue[] = [];
  private count: number = 0;
  static readonly MAX_ISSUES: number = 32;
  static readonly MAX_DEPTH: number = 48;
  static readonly MAX_ITEMS: number = 4096;
  // UTF-16 code units, not bytes. This check happens before JSON.parse; no streaming guarantee.
  static readonly MAX_TEXT_LENGTH: number = 2097152;

  constructor(schema: string) { this.schema = schema; }

  issue(code: string, node: JsonNode, expected: string): void {
    this.count++;
    if (this.issues.length < DecodeContext.MAX_ISSUES) {
      this.issues.push(new DecodeIssue(code, node.path, expected, node.kind()));
    }
  }

  issueCount(): number { return this.count; }
  exhausted(): boolean { return this.count >= DecodeContext.MAX_ISSUES; }

  finish<T>(value: T | undefined): DecodeResult<T> {
    if (this.count !== 0) {
      return DecodeResult.failed<T>(new JsonDecodeError(this.schema, this.issues));
    }
    if (value === undefined) { throw new Error('Decoder returned no model and no issue'); }
    return DecodeResult.success<T>(value);
  }
}

/** Dynamic JSON access is confined here. Domain models are never asserted from JSON.parse. */
export class JsonNode {
  private value: Object | null | undefined;
  readonly path: Array<string | number>;

  constructor(value: Object | null | undefined, path: Array<string | number>) {
    this.value = value;
    this.path = path;
  }

  static parse(text: string, context: DecodeContext): JsonNode | undefined {
    const empty = new JsonNode(undefined, []);
    if (text.length > DecodeContext.MAX_TEXT_LENGTH) {
      context.issue('LIMIT_EXCEEDED', empty, 'JSON text within length limit');
      return undefined;
    }
    try {
      const value: Object | null = JSON.parse(text) as Object | null;
      return new JsonNode(value, []);
    } catch (_) {
      context.issue('INVALID_JSON', empty, 'valid JSON text');
      return undefined;
    }
  }

  kind(): string {
    if (this.value === undefined) { return 'missing'; }
    if (this.value === null) { return 'null'; }
    if (Array.isArray(this.value)) { return 'array'; }
    return typeof this.value;
  }

  withinDepth(context: DecodeContext): boolean {
    if (this.path.length > DecodeContext.MAX_DEPTH) {
      context.issue('LIMIT_EXCEEDED', this, 'nesting depth <= ' + String(DecodeContext.MAX_DEPTH));
      return false;
    }
    return true;
  }

  field(key: string): JsonNode {
    const object = this.value as Record<string, Object | null | undefined>;
    const path = this.path.slice();
    path.push(key);
    // Own keys only, so missing fields cannot be satisfied by Object.prototype.
    return new JsonNode(Object.keys(object).includes(key) ? object[key] : undefined, path);
  }

  element(index: number): JsonNode {
    const array = this.value as Array<Object | null>;
    const path = this.path.slice();
    path.push(index);
    return new JsonNode(array[index], path);
  }

  length(): number { return (this.value as Array<Object | null>).length; }
  stringValue(): string { return this.value as string; }
  numberValue(): number { return this.value as number; }
  booleanValue(): boolean { return this.value as boolean; }
}
