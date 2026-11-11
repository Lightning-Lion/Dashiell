import { F, LogErrorSnapshot, LogField } from './LogCore';
import { LogSourceLocator } from './LogSourceLocator';

/**
 * 错误快照 / Error snapshot.
 *
 * 只读取 Error 的 name/message/stack;
 * 自定义字段通过 JSON 可枚举视图提取(不直接强转 Error -> Record)。
 * cause 最多递归 3 层,防止环。
 */
export class LogErrorCapture {
  static capture(err: Object | null | undefined): LogErrorSnapshot | undefined {
    if (err === undefined || err === null) {
      return undefined;
    }
    try {
      if (err instanceof Error) {
        return LogErrorCapture.fromError(err, 0);
      }
      return LogErrorCapture.fromUnknown(err, 0);
    } catch (e) {
      const fallback: LogErrorSnapshot = new LogErrorSnapshot();
      fallback.name = 'Thrown';
      fallback.message = '<error snapshot failed>';
      return fallback;
    }
  }

  private static fromError(err: Error, depth: number): LogErrorSnapshot {
    const snap: LogErrorSnapshot = new LogErrorSnapshot();
    try {
      snap.name = err.name === '' ? 'Error' : err.name;
    } catch (e) {
      snap.name = 'Error';
    }
    try {
      snap.message = err.message;
    } catch (e) {
      snap.message = '';
    }
    try {
      const stack: string | undefined = err.stack;
      if (stack !== undefined) {
        snap.stack = LogSourceLocator.normalizeStack(stack, 32);
      }
    } catch (e) {
      snap.stack = [];
    }
    LogErrorCapture.collectProps(err, snap, depth);
    return snap;
  }

  private static fromUnknown(err: Object, depth: number): LogErrorSnapshot {
    const snap: LogErrorSnapshot = new LogErrorSnapshot();
    snap.name = 'Thrown';
    try {
      snap.message = String(err);
    } catch (e) {
      snap.message = '<unprintable>';
    }
    LogErrorCapture.collectProps(err, snap, depth);
    return snap;
  }

  private static collectProps(err: Object, snap: LogErrorSnapshot, depth: number): void {
    const rec: Record<string, Object | undefined> | undefined = LogErrorCapture.enumerableView(err);
    if (rec === undefined) {
      return;
    }
    try {
      const keys: string[] = Object.keys(rec);
      for (let i = 0; i < keys.length && i < 32; i++) {
        const key: string = keys[i];
        const value: Object | undefined = rec[key];
        if (key === 'cause') {
          continue;
        }
        if (key === 'name') {
          if (typeof value === 'string' && snap.name === 'Thrown') {
            snap.name = value;
          }
          continue;
        }
        if (key === 'message') {
          if (typeof value === 'string' &&
            (snap.message === '' || snap.message === '[object Object]')) {
            snap.message = value;
          }
          continue;
        }
        if (key === 'stack') {
          if (typeof value === 'string' && snap.stack.length === 0) {
            snap.stack = LogSourceLocator.normalizeStack(value, 32);
          }
          continue;
        }
        if (key === 'code' && (typeof value === 'string' || typeof value === 'number')) {
          snap.code = String(value);
          continue;
        }
        if (key === 'httpStatus' && typeof value === 'number') {
          snap.httpStatus = value;
          continue;
        }
        if (value !== undefined && typeof value !== 'function') {
          const fields: LogField[] = snap.props;
          fields.push(F(key, value));
          snap.props = fields;
        }
      }
      if (depth < 3) {
        const cause: Object | undefined = rec['cause'];
        if (cause !== undefined && cause !== null) {
          if (cause instanceof Error) {
            snap.cause = LogErrorCapture.fromError(cause, depth + 1);
          } else {
            snap.cause = LogErrorCapture.fromUnknown(cause, depth + 1);
          }
        }
      }
    } catch (e) {
      // 自定义属性读取失败不影响主错误
    }
  }

  /**
   * 可枚举自有属性视图 / enumerable own-property view.
   *
   * 不用 JSON.stringify/parse 往返:Dashiell 的 scripts/audit-json-boundaries.mjs
   * 要求生产 JSON.parse 只出现在 common/jsonschema/JsonDecode.ets。这里只读
   * 可枚举自有属性,与 JSON 视图一致;Error 的 message/stack 本来就不可枚举,
   * 由 collectProps 单独处理。
   */
  private static enumerableView(err: Object): Record<string, Object | undefined> | undefined {
    try {
      if (err === null || typeof err !== 'object' || Array.isArray(err)) {
        return undefined;
      }
      const keys: string[] = Object.keys(err);
      if (keys.length === 0) {
        return undefined;
      }
      const view: Record<string, Object | undefined> = {};
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        view[key] = (err as Record<string, Object | undefined>)[key];
      }
      return view;
    } catch (e) {
      return undefined;
    }
  }
}
