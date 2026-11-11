import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { process } from '@kit.ArkTS';
import {
  F,
  L,
  LogConfig,
  LogEnv,
  LogField,
  LogFormat,
  LogLanguage,
  LogLevel,
  LogMessage,
  LogRecord,
  LogSite,
  LogText,
  LogTimerEntry,
  LoggerOptions,
  logLevelName,
} from './LogCore';
import { LogAppConfig } from './LogAppConfig';
import { LogErrorCapture } from './LogErrorCapture';
import { LogFormatter } from './LogFormatter';
import { LogSourceLocator } from './LogSourceLocator';

const DEFAULT_TAG: string = LogAppConfig.defaultTag;
const MAX_HILOG_TAG: number = 31;

/**
 * 全局日志入口 / Global logging entry.
 *
 * 两种用法:
 *  1. 构建期生成事件(推荐,精确文件/行/列/类/方法,零抓栈):
 *       LogEvents.appStart({ version: '1.0.0', debug: true });
 *  2. 手写兜底(运行时抓栈):
 *       Logger.info('Api', L('请求失败', 'request failed'), [F('status', 500)], err);
 *
 * 手写日志的调用点由 LogSourceLocator 解析;生成事件直接传 LogSite。
 */
export class Logger {
  private static config: LogConfig = new LogConfig();
  private static env: LogEnv = new LogEnv();
  private static seq: number = 0;
  private static traceId: string = '';
  private static emitting: boolean = false;
  private static initialized: boolean = false;

  private static memory: string[] = [];
  private static memoryStart: number = 0;
  private static memoryCount: number = 0;
  private static timers: Map<string, LogTimerEntry> = new Map<string, LogTimerEntry>();

  /** 初始化环境与默认配置 / init runtime environment. */
  static init(options?: LoggerOptions): void {
    if (options !== undefined) {
      if (options.debug !== undefined) {
        Logger.env.debug = options.debug;
      }
      if (options.appVersion !== undefined) {
        Logger.env.appVersion = options.appVersion;
      }
      if (options.buildMode !== undefined) {
        Logger.env.buildMode = options.buildMode;
      }
    }
    Logger.env.buildMode = Logger.env.buildMode === ''
      ? (Logger.env.debug ? 'debug' : 'release') : Logger.env.buildMode;
    Logger.env.device = Logger.safeDeviceModel();
    Logger.env.osVersion = Logger.safeOsVersion();
    Logger.env.apiVersion = Logger.safeApiVersion();
    Logger.env.pid = Logger.safePid();
    if (Logger.env.sessionId === '') {
      Logger.env.sessionId = Logger.newSessionId();
    }
    Logger.config.debug = Logger.env.debug;
    Logger.config.format = options !== undefined && options.format !== undefined
      ? options.format : (Logger.env.debug ? LogFormat.PRETTY : LogFormat.COMPACT);
    Logger.config.minLevel = options !== undefined && options.minLevel !== undefined
      ? options.minLevel : (Logger.env.debug ? LogLevel.DEBUG : LogLevel.INFO);
    Logger.config.language = options !== undefined && options.language !== undefined
      ? options.language : LogLanguage.BOTH;
    if (options !== undefined && options.includeMeta !== undefined) {
      Logger.config.includeMeta = options.includeMeta;
    }
    if (options !== undefined && options.memoryCapacity !== undefined) {
      Logger.setMemoryCapacity(options.memoryCapacity);
    }
    Logger.initialized = true;
  }

  /** 是否已初始化 / init state. */
  static isInitialized(): boolean {
    return Logger.initialized;
  }

  /** 是否输出该级别 / level gate. */
  static isEnabled(level: LogLevel): boolean {
    return level >= Logger.config.minLevel;
  }

  /**
   * 构建期事件入口 / generated-event entry.
   * site 由 log-gen 写入;不抓栈。
   */
  static logAt(level: LogLevel, tag: string, site: LogSite, message: LogMessage,
    fields?: LogField[], error?: Object): void {
    if (!Logger.isEnabled(level)) {
      return;
    }
    let useSite: LogSite = site;
    if (!useSite.valid() && Logger.config.includeSource) {
      useSite = LogSourceLocator.capture();
    }
    Logger.emit(level, tag, useSite, message, fields, error, '');
  }

  /** 手写日志 / manual log with runtime caller capture. */
  static trace(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.TRACE, tag, message, fields, error, '');
  }

  static debug(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.DEBUG, tag, message, fields, error, '');
  }

  static info(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.INFO, tag, message, fields, error, '');
  }

  static warn(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.WARN, tag, message, fields, error, '');
  }

  static error(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.ERROR, tag, message, fields, error, '');
  }

  static fatal(tag: string, message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.write(LogLevel.FATAL, tag, message, fields, error, '');
  }

  /** 作用域日志 / scoped logger with sticky fields. */
  static scope(tag: string, name: string = '', fields?: LogField[]): LogScope {
    return new LogScope(tag, name, fields === undefined ? [] : fields);
  }

  /**
   * 计时开始 / start a named timer.
   * 结束用 timeEnd(label),耗时写入 elapsedMs。
   */
  static time(label: string, message?: LogText): void {
    const site: LogSite = LogSourceLocator.capture();
    const text: LogText = message === undefined ? L('计时结束', 'timer end') : message;
    Logger.timers.set(label, new LogTimerEntry(label, Date.now(), site, text));
  }

  /** 计时结束并输出 / end timer and log elapsed. */
  static timeEnd(label: string, level: LogLevel = LogLevel.INFO, fields?: LogField[]): number {
    const entry: LogTimerEntry | undefined = Logger.timers.get(label);
    const end: number = Date.now();
    if (entry === undefined) {
      Logger.warn(DEFAULT_TAG, L('计时器不存在', 'timer not found'), [F('timer', label)]);
      return 0;
    }
    Logger.timers.delete(label);
    const elapsed: number = end - entry.start;
    const all: LogField[] = [];
    if (fields !== undefined) {
      for (let i = 0; i < fields.length; i++) {
        all.push(fields[i]);
      }
    }
    all.push(F('timer', label));
    all.push(F('elapsedMs', elapsed));
    all.push(F('startedAt', LogFormatter.timeText(entry.start, Logger.config)));
    if (entry.site.valid()) {
      all.push(F('startSrc', entry.site.location()));
    }
    Logger.write(level, DEFAULT_TAG, entry.message, all, undefined, '');
    return elapsed;
  }

  /** 读取耗时但不结束 / measure without ending. */
  static measure(label: string): number {
    const entry: LogTimerEntry | undefined = Logger.timers.get(label);
    return entry === undefined ? 0 : Date.now() - entry.start;
  }

  /** 取消计时 / cancel a timer. */
  static cancelTime(label: string): void {
    Logger.timers.delete(label);
  }

  /** 最近日志 / recent rendered records. */
  static recent(limit: number = 0): string[] {
    if (Logger.memoryCount === 0) {
      return [];
    }
    const cap: number = Logger.memory.length;
    const want: number = limit <= 0 || limit > Logger.memoryCount ? Logger.memoryCount : limit;
    const out: string[] = [];
    const start: number = (Logger.memoryStart + Logger.memoryCount - want) % cap;
    for (let i = 0; i < want; i++) {
      const index: number = (start + i) % cap;
      const item: string = Logger.memory[index];
      if (item !== undefined) {
        out.push(item);
      }
    }
    return out;
  }

  /** 导出内存日志 / export in-memory logs. */
  static exportText(): string {
    const head: string[] = [];
    head.push(`# ${LogAppConfig.appName} logs session=${Logger.env.sessionId} app=${Logger.env.appVersion}`);
    head.push(`# device=${Logger.env.device} os=${Logger.env.osVersion} api=${Logger.env.apiVersion}`);
    head.push(`# exportedAt=${LogFormatter.isoTime(Date.now())} config=${logLevelName(Logger.config.minLevel)}/${Logger.config.format}`);
    const body: string[] = Logger.recent(0);
    for (let i = 0; i < body.length; i++) {
      head.push(body[i]);
    }
    return head.join('\n');
  }

  static clearMemory(): void {
    Logger.memory = [];
    Logger.memoryStart = 0;
    Logger.memoryCount = 0;
  }

  static setMemoryCapacity(capacity: number): void {
    Logger.config.memoryCapacity = capacity < 0 ? 0 : capacity;
    Logger.clearMemory();
  }

  static setMinLevel(level: LogLevel): void {
    Logger.config.minLevel = level;
  }

  static setFormat(format: LogFormat): void {
    Logger.config.format = format;
  }

  static setLanguage(language: LogLanguage): void {
    Logger.config.language = language;
  }

  static setSourceEnabled(enabled: boolean): void {
    Logger.config.includeSource = enabled;
  }

  static setMetaEnabled(enabled: boolean): void {
    Logger.config.includeMeta = enabled;
  }

  static setTraceId(traceId: string): void {
    Logger.traceId = traceId;
  }

  /** 生成并设置新的 traceId / new trace id. */
  static newTraceId(): string {
    const id: string = Logger.newSessionId();
    Logger.traceId = id;
    return id;
  }

  static getTraceId(): string {
    return Logger.traceId;
  }

  static getConfig(): LogConfig {
    return Logger.config;
  }

  static getEnv(): LogEnv {
    return Logger.env;
  }

  static sessionId(): string {
    return Logger.env.sessionId;
  }

  /**
   * 作用域写入 / scoped write.
   * 公开仅给 LogScope 使用,业务请用 Logger.info(...)/LogEvents。
   */
  static writeScoped(level: LogLevel, tag: string, scope: string, message: LogMessage,
    fields?: LogField[], error?: Object): void {
    if (!Logger.isEnabled(level)) {
      return;
    }
    const site: LogSite = LogSourceLocator.capture();
    Logger.emit(level, tag, site, message, fields, error, scope);
  }

  private static write(level: LogLevel, tag: string, message: LogMessage,
    fields?: LogField[], error?: Object, scope: string = ''): void {
    if (!Logger.isEnabled(level)) {
      return;
    }
    const site: LogSite = LogSourceLocator.capture();
    Logger.emit(level, tag, site, message, fields, error, scope);
  }

  private static emit(level: LogLevel, tag: string, site: LogSite, message: LogMessage,
    fields?: LogField[], error?: Object, scope: string = ''): void {
    if (Logger.emitting) {
      return;
    }
    Logger.emitting = true;
    try {
      const record: LogRecord = new LogRecord();
      record.seq = ++Logger.seq;
      record.time = Date.now();
      record.level = level;
      record.tag = tag.trim() === '' ? DEFAULT_TAG : tag.trim();
      record.scope = scope;
      record.message = Logger.toText(message);
      record.fields = fields === undefined ? [] : fields;
      record.site = site;
      record.error = LogErrorCapture.capture(error);
      record.traceId = Logger.traceId;
      record.pid = Logger.env.pid;
      record.tid = Logger.safeTid();
      record.sessionId = Logger.env.sessionId;
      record.appVersion = Logger.env.appVersion;
      record.buildMode = Logger.env.buildMode;
      record.device = Logger.env.device;
      record.osVersion = Logger.env.osVersion;
      record.apiVersion = Logger.env.apiVersion;

      let lines: string[] = [];
      try {
        lines = LogFormatter.format(record, Logger.config);
      } catch (err) {
        lines = [`${logLevelName(level)}/${record.tag} ${Logger.toText(message).zh} <format failed>`];
      }
      if (lines.length === 0) {
        lines = [`${logLevelName(level)}/${record.tag} <empty log>`];
      }
      Logger.writeHilog(record, lines);
      Logger.writeMemory(lines);
    } finally {
      Logger.emitting = false;
    }
  }

  private static writeHilog(record: LogRecord, lines: string[]): void {
    const tag: string = Logger.safeHilogTag(record.tag);
    const domain: number = Logger.safeDomain(Logger.config.domain);
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      try {
        switch (record.level) {
          case LogLevel.TRACE:
          case LogLevel.DEBUG:
            hilog.debug(domain, tag, '%{public}s', line);
            break;
          case LogLevel.INFO:
            hilog.info(domain, tag, '%{public}s', line);
            break;
          case LogLevel.WARN:
            hilog.warn(domain, tag, '%{public}s', line);
            break;
          case LogLevel.ERROR:
            hilog.error(domain, tag, '%{public}s', line);
            break;
          case LogLevel.FATAL:
            hilog.fatal(domain, tag, '%{public}s', line);
            break;
          default:
            hilog.info(domain, tag, '%{public}s', line);
            break;
        }
      } catch (err) {
        // hilog 失败不能反过来打断业务
      }
    }
  }

  private static writeMemory(lines: string[]): void {
    const cap: number = Logger.config.memoryCapacity;
    if (cap <= 0) {
      return;
    }
    if (Logger.memory.length !== cap) {
      Logger.memory = [];
      Logger.memoryStart = 0;
      Logger.memoryCount = 0;
      for (let i = 0; i < cap; i++) {
        Logger.memory.push('');
      }
    }
    const text: string = lines.join('\n');
    if (Logger.memoryCount < cap) {
      const index: number = (Logger.memoryStart + Logger.memoryCount) % cap;
      Logger.memory[index] = text;
      Logger.memoryCount++;
    } else {
      Logger.memory[Logger.memoryStart] = text;
      Logger.memoryStart = (Logger.memoryStart + 1) % cap;
    }
  }

  private static toText(message: LogMessage): LogText {
    if (typeof message === 'string') {
      return L(message, '');
    }
    return message;
  }

  private static safeHilogTag(tag: string): string {
    let t: string = tag.trim();
    if (t === '') {
      t = DEFAULT_TAG;
    }
    if (t.length > MAX_HILOG_TAG) {
      t = t.substring(0, MAX_HILOG_TAG);
    }
    return t;
  }

  private static safeDomain(domain: number): number {
    if (domain < 0) {
      return 0;
    }
    if (domain > 0xFFFF) {
      return 0xFFFF;
    }
    return Math.floor(domain);
  }

  private static safePid(): number {
    try {
      return process.pid;
    } catch (err) {
      return 0;
    }
  }

  private static safeTid(): number {
    try {
      return process.tid;
    } catch (err) {
      return Logger.env.pid;
    }
  }

  private static safeDeviceModel(): string {
    try {
      return deviceInfo.productModel;
    } catch (err) {
      return '';
    }
  }

  private static safeOsVersion(): string {
    try {
      return deviceInfo.osFullName;
    } catch (err) {
      return '';
    }
  }

  private static safeApiVersion(): number {
    try {
      return deviceInfo.sdkApiVersion;
    } catch (err) {
      return 0;
    }
  }

  private static newSessionId(): string {
    const time: string = Date.now().toString(36);
    const rand: string = Math.floor(Math.random() * 0xFFFFFF).toString(36);
    return `${time}-${rand}`;
  }
}

/**
 * 作用域日志 / scoped logger.
 * 适合一个类/一个流程复用 tag+字段;不替代构建期事件。
 */
export class LogScope {
  private scopeTag: string;
  private scopeName: string;
  private scopeFields: LogField[];

  constructor(tag: string, name: string = '', fields: LogField[] = []) {
    this.scopeTag = tag;
    this.scopeName = name;
    this.scopeFields = fields;
  }

  child(name: string, fields?: LogField[]): LogScope {
    const merged: LogField[] = LogScope.merge(this.scopeFields, fields === undefined ? [] : fields);
    return new LogScope(this.scopeTag, name, merged);
  }

  debug(message: LogMessage, fields?: LogField[]): void {
    Logger.writeScoped(LogLevel.DEBUG, this.scopeTag, this.scopeName, message,
      this.merge(fields), undefined);
  }

  info(message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.writeScoped(LogLevel.INFO, this.scopeTag, this.scopeName, message,
      this.merge(fields), error);
  }

  warn(message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.writeScoped(LogLevel.WARN, this.scopeTag, this.scopeName, message,
      this.merge(fields), error);
  }

  error(message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.writeScoped(LogLevel.ERROR, this.scopeTag, this.scopeName, message,
      this.merge(fields), error);
  }

  fatal(message: LogMessage, fields?: LogField[], error?: Object): void {
    Logger.writeScoped(LogLevel.FATAL, this.scopeTag, this.scopeName, message,
      this.merge(fields), error);
  }

  private merge(fields?: LogField[]): LogField[] {
    return LogScope.merge(this.scopeFields, fields === undefined ? [] : fields);
  }

  private static merge(base: LogField[], extra: LogField[]): LogField[] {
    const out: LogField[] = [];
    for (let i = 0; i < base.length; i++) {
      out.push(base[i]);
    }
    for (let i = 0; i < extra.length; i++) {
      const key: string = extra[i].key;
      let replaced: boolean = false;
      for (let j = 0; j < out.length; j++) {
        if (out[j].key === key) {
          out[j] = extra[i];
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        out.push(extra[i]);
      }
    }
    return out;
  }
}
