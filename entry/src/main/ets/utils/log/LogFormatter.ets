import {
  LogConfig,
  LogErrorSnapshot,
  LogField,
  LogFormat,
  LogLanguage,
  LogLevel,
  LogRecord,
  LogText,
  logLevelName,
  logLevelShort,
  logLevelZh,
} from './LogCore';
import { LogMask } from './LogMask';

/**
 * 日志格式化 / Log formatter.
 * 三种格式:COMPACT 单行、PRETTY 多行详情、JSON 每行一个对象。
 * 格式化器只做纯字符串处理,不访问业务对象。
 */
export class LogFormatter {
  private static readonly INDENT: string = '    ';

  /** 输出一组行 / render one record into lines. */
  static format(record: LogRecord, config: LogConfig): string[] {
    if (config.format === LogFormat.JSON) {
      return [LogFormatter.json(record, config)];
    }
    if (config.format === LogFormat.COMPACT) {
      return LogFormatter.compact(record, config);
    }
    return LogFormatter.pretty(record, config);
  }

  /** 单行 / compact single line. */
  static compact(record: LogRecord, config: LogConfig): string[] {
    const parts: string[] = [];
    parts.push(LogFormatter.timeText(record.time, config));
    parts.push(`${logLevelShort(record.level)}/${LogFormatter.tagWithScope(record)}`);
    if (config.includeSequence) {
      parts.push(`#${LogFormatter.padLeft(String(record.seq), 6, '0')}`);
    }
    if (config.includeThread) {
      parts.push(`tid=${record.tid}`);
    }
    if (record.traceId !== '') {
      parts.push(`trace=${record.traceId}`);
    }
    if (record.site.eventName !== '') {
      parts.push(`evt=${record.site.eventName}`);
    }
    if (config.includeSource) {
      parts.push(record.site.location());
      const sym: string = record.site.symbol();
      if (sym !== '') {
        parts.push(sym);
      }
    }
    parts.push(LogFormatter.text(record.message, config));
    if (config.includeFields) {
      const fields: string = LogFormatter.fieldsText(record.fields, config);
      if (fields !== '') {
        parts.push(`| ${fields}`);
      }
    }
    if (record.error !== undefined) {
      parts.push(`! ${LogFormatter.errorSummary(record.error)}`);
    }
    if (config.includeMeta && record.appVersion !== '') {
      parts.push(`| app=${record.appVersion} dev=${record.device} api=${record.apiVersion}`);
    }

    const lines: string[] = [parts.join(' ')];
    if (record.error !== undefined && record.level >= LogLevel.ERROR) {
      const stack: string[] = LogFormatter.errorStack(record.error, config.maxStackFrames);
      for (let i = 0; i < stack.length; i++) {
        lines.push(`${LogFormatter.INDENT}${stack[i].trim()}`);
      }
    }
    return lines;
  }

  /** 多行详情 / pretty multi-line detail. */
  static pretty(record: LogRecord, config: LogConfig): string[] {
    const lines: string[] = [];
    const head: string[] = [];
    head.push(LogFormatter.timeText(record.time, config));
    head.push(`${logLevelName(record.level)}/${logLevelZh(record.level)}`);
    head.push(LogFormatter.tagWithScope(record));
    if (config.includeSequence) {
      head.push(`#${LogFormatter.padLeft(String(record.seq), 6, '0')}`);
    }
    if (config.includeThread) {
      head.push(`tid=${record.tid}`);
    }
    if (record.traceId !== '') {
      head.push(`trace=${record.traceId}`);
    }
    lines.push(head.join('  '));

    if (record.site.eventName !== '') {
      lines.push(`${LogFormatter.INDENT}evt     ${record.site.eventName}`);
    }
    lines.push(`${LogFormatter.INDENT}${LogFormatter.text(record.message, config)}`);

    if (config.includeSource) {
      const sym: string = record.site.symbol();
      const tail: string = sym === '' ? '' : `  ${sym}`;
      lines.push(`${LogFormatter.INDENT}src     ${record.site.location()}${tail}`);
    }
    if (config.includeFields) {
      const fields: string = LogFormatter.fieldsText(record.fields, config);
      if (fields !== '') {
        lines.push(`${LogFormatter.INDENT}fields  ${fields}`);
      }
    }
    if (config.includeMeta) {
      const meta: string[] = [];
      meta.push(LogFormatter.isoTime(record.time));
      if (record.pid > 0) {
        meta.push(`pid=${record.pid}`);
      }
      if (record.appVersion !== '') {
        meta.push(`app=${record.appVersion}`);
      }
      if (record.buildMode !== '') {
        meta.push(`build=${record.buildMode}`);
      }
      if (record.device !== '') {
        meta.push(`dev=${record.device}`);
      }
      if (record.osVersion !== '') {
        meta.push(`os=${record.osVersion}`);
      }
      if (record.apiVersion > 0) {
        meta.push(`api=${record.apiVersion}`);
      }
      if (record.sessionId !== '') {
        meta.push(`session=${record.sessionId}`);
      }
      lines.push(`${LogFormatter.INDENT}meta    ${meta.join('  ')}`);
    }

    if (record.error !== undefined) {
      const err: LogErrorSnapshot = record.error;
      lines.push(`${LogFormatter.INDENT}error   ${LogFormatter.errorSummary(err)}`);
      if (err.props.length > 0) {
        const props: string = LogFormatter.fieldsText(err.props, config);
        if (props !== '') {
          lines.push(`${LogFormatter.INDENT}        ${props}`);
        }
      }
      const stack: string[] = LogFormatter.errorStack(err, config.maxStackFrames);
      if (stack.length > 0) {
        lines.push(`${LogFormatter.INDENT}stack`);
        for (let i = 0; i < stack.length; i++) {
          lines.push(`${LogFormatter.INDENT}${LogFormatter.INDENT}${stack[i].trim()}`);
        }
      }
      if (err.cause !== undefined) {
        lines.push(`${LogFormatter.INDENT}cause   ${LogFormatter.errorSummary(err.cause)}`);
      }
    }
    return lines;
  }

  /** 单行 JSON / one JSON object. */
  static json(record: LogRecord, config: LogConfig): string {
    const site: Record<string, Object | undefined> = {
      'file': record.site.file,
      'line': record.site.line,
      'column': record.site.column,
      'class': record.site.className,
      'method': record.site.methodName,
      'event': record.site.eventName,
      'valid': record.site.valid(),
    };
    const message: Record<string, Object | undefined> = {
      'zh': record.message.zh,
      'en': record.message.en,
    };
    const fields: Record<string, Object | null | undefined> = {};
    for (let i = 0; i < record.fields.length; i++) {
      const f: LogField = record.fields[i];
      if (f.value === undefined) {
        continue;
      }
      fields[f.key] = LogFormatter.jsonValue(f.key, f.value, config);
    }
    const thread: Record<string, Object | undefined> = {
      'pid': record.pid,
      'tid': record.tid,
    };
    const obj: Record<string, Object | undefined> = {
      'ts': LogFormatter.isoTime(record.time),
      'epochMs': record.time,
      'level': logLevelName(record.level),
      'levelZh': logLevelZh(record.level),
      'tag': record.tag,
      'scope': record.scope,
      'seq': record.seq,
      'traceId': record.traceId,
      'sessionId': record.sessionId,
      'site': site,
      'message': message,
      'fields': fields,
      'thread': thread,
      'app': record.appVersion,
      'build': record.buildMode,
      'device': record.device,
      'os': record.osVersion,
      'api': record.apiVersion,
    };
    if (record.error !== undefined) {
      obj['error'] = LogFormatter.jsonError(record.error, config);
    }
    try {
      const text: string | undefined = JSON.stringify(obj);
      return text === undefined ? '{}' : text;
    } catch (err) {
      return '{"level":"ERROR","message":{"zh":"日志 JSON 序列化失败","en":"log json serialization failed"}}';
    }
  }

  /** 双语文本 / bilingual text. */
  static text(message: LogText, config: LogConfig): string {
    let zh: string = LogFormatter.oneLine(message.zh);
    let en: string = LogFormatter.oneLine(message.en);
    if (config.language === LogLanguage.ZH) {
      return LogFormatter.truncate(zh !== '' ? zh : en, config.maxMessageLength);
    }
    if (config.language === LogLanguage.EN) {
      return LogFormatter.truncate(en !== '' ? en : zh, config.maxMessageLength);
    }
    if (zh === '' || en === '' || zh === en) {
      return LogFormatter.truncate(zh !== '' ? zh : en, config.maxMessageLength);
    }
    return LogFormatter.truncate(`${zh} / ${en}`, config.maxMessageLength);
  }

  /** 字段串 / fields text. */
  static fieldsText(fields: LogField[], config: LogConfig): string {
    const parts: string[] = [];
    for (let i = 0; i < fields.length; i++) {
      const f: LogField = fields[i];
      if (f.value === undefined) {
        continue;
      }
      const value: string = LogFormatter.value(f.key, f.value, config);
      parts.push(`${f.key}=${value}`);
    }
    return parts.join('  ');
  }

  /** 单值渲染 / render one value. */
  static value(key: string, value: Object | null | undefined, config: LogConfig): string {
    if (value === undefined) {
      return 'undefined';
    }
    if (value === null) {
      return 'null';
    }
    if (typeof value === 'string') {
      const masked: string = LogMask.mask(key, value, config.extraMaskKeys);
      const v: string = masked !== '' ? masked : value;
      return LogFormatter.quote(v, config.maxValueLength);
    }
    if (typeof value === 'number') {
      if (value !== value) {
        return 'NaN';
      }
      if (value === Number.POSITIVE_INFINITY) {
        return 'Infinity';
      }
      if (value === Number.NEGATIVE_INFINITY) {
        return '-Infinity';
      }
      return String(value);
    }
    if (typeof value === 'boolean') {
      return value ? 'true' : 'false';
    }
    if (typeof value === 'bigint') {
      return String(value);
    }
    if (value instanceof Error) {
      return `${value.name}: ${value.message}`;
    }
    return LogFormatter.jsonSafe(value, config.maxValueLength);
  }

  /** 时间 HH:mm:ss.SSS 或完整本地时间 / local time. */
  static timeText(ms: number, config: LogConfig): string {
    const d: Date = new Date(ms);
    const clock: string = `${LogFormatter.pad2(d.getHours())}:${LogFormatter.pad2(d.getMinutes())}:` +
      `${LogFormatter.pad2(d.getSeconds())}.${LogFormatter.padLeft(String(d.getMilliseconds()), 3, '0')}`;
    if (!config.fullTimestamp) {
      return clock;
    }
    return `${LogFormatter.dateText(d)} ${clock}${LogFormatter.zoneText(d)}`;
  }

  /** ISO 本地时间 / ISO-like local time with offset. */
  static isoTime(ms: number): string {
    const d: Date = new Date(ms);
    return `${LogFormatter.dateText(d)}T${LogFormatter.pad2(d.getHours())}:` +
      `${LogFormatter.pad2(d.getMinutes())}:${LogFormatter.pad2(d.getSeconds())}.` +
      `${LogFormatter.padLeft(String(d.getMilliseconds()), 3, '0')}${LogFormatter.zoneText(d)}`;
  }

  /** 错误摘要 / error summary. */
  static errorSummary(err: LogErrorSnapshot): string {
    let text: string = err.name;
    if (err.message !== '') {
      text = `${text}: ${err.message}`;
    }
    const parts: string[] = [text];
    if (err.code !== '') {
      parts.push(`code=${err.code}`);
    }
    if (err.httpStatus >= 0) {
      parts.push(`httpStatus=${err.httpStatus}`);
    }
    return parts.join('  ');
  }

  private static errorStack(err: LogErrorSnapshot, max: number): string[] {
    const out: string[] = [];
    for (let i = 0; i < err.stack.length && out.length < max; i++) {
      if (err.stack[i].trim() !== '') {
        out.push(err.stack[i]);
      }
    }
    return out;
  }

  private static jsonError(err: LogErrorSnapshot, config: LogConfig): Record<string, Object | undefined> {
    const props: Record<string, Object | null | undefined> = {};
    for (let i = 0; i < err.props.length; i++) {
      props[err.props[i].key] = LogFormatter.jsonValue(err.props[i].key, err.props[i].value, config);
    }
    const stack: string[] = LogFormatter.errorStack(err, config.maxStackFrames);
    const obj: Record<string, Object | undefined> = {
      'name': err.name,
      'message': err.message,
      'code': err.code,
      'httpStatus': err.httpStatus,
      'stack': stack,
      'props': props,
    };
    if (err.cause !== undefined) {
      obj['cause'] = LogFormatter.jsonError(err.cause, config);
    }
    return obj;
  }

  private static jsonValue(key: string, value: Object | null | undefined,
    config: LogConfig): Object | null | undefined {
    if (value === undefined || value === null) {
      return null;
    }
    if (typeof value === 'string') {
      const masked: string = LogMask.mask(key, value, config.extraMaskKeys);
      return masked !== '' ? masked : LogFormatter.truncate(value, config.maxValueLength);
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'bigint') {
      return String(value);
    }
    if (value instanceof Error) {
      return `${value.name}: ${value.message}`;
    }
    return LogFormatter.jsonSafe(value, config.maxValueLength);
  }

  private static jsonSafe(value: Object, max: number): string {
    try {
      const text: string | undefined = JSON.stringify(value);
      if (text === undefined) {
        return '<undefined>';
      }
      return LogFormatter.truncate(text, max);
    } catch (err) {
      return '<unserializable>';
    }
  }

  private static quote(value: string, max: number): string {
    let v: string = value;
    v = v.replace(/\r/g, '\\r').replace(/\n/g, '\\n');
    v = LogFormatter.truncate(v, max);
    if (v === '') {
      return "''";
    }
    if (/[\s=|]/.test(v)) {
      return `'${v}'`;
    }
    return v;
  }

  private static oneLine(value: string): string {
    return value.replace(/\r?\n/g, ' ↵ ').trim();
  }

  private static truncate(value: string, max: number): string {
    if (max <= 0 || value.length <= max) {
      return value;
    }
    return `${value.substring(0, max)}…(${value.length})`;
  }

  private static safeTag(tag: string): string {
    const t: string = tag.trim();
    return t === '' ? 'Dashiell' : t;
  }

  private static tagWithScope(record: LogRecord): string {
    const tag: string = LogFormatter.safeTag(record.tag);
    return record.scope === '' ? tag : `${tag}:${record.scope}`;
  }

  private static dateText(d: Date): string {
    return `${d.getFullYear()}-${LogFormatter.pad2(d.getMonth() + 1)}-${LogFormatter.pad2(d.getDate())}`;
  }

  private static zoneText(d: Date): string {
    const offset: number = -d.getTimezoneOffset();
    const sign: string = offset >= 0 ? '+' : '-';
    const abs: number = Math.abs(offset);
    return `${sign}${LogFormatter.pad2(Math.floor(abs / 60))}:${LogFormatter.pad2(abs % 60)}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  private static padLeft(value: string, width: number, ch: string): string {
    let out: string = value;
    while (out.length < width) {
      out = `${ch}${out}`;
    }
    return out;
  }
}
