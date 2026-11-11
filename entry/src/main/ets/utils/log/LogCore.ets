/**
 * 日志核心类型 / Core log types.
 *
 * 设计约束:
 *  - 纯 ArkTS,无 any、无动态属性访问;
 *  - 日志事件由 tools/log-gen 在构建期生成,调用点直接带 LogSite;
 *  - 手写日志仍可走 Logger.info(...),由 LogSourceLocator 抓取调用位置。
 */

/** 日志级别 / Log level. 数值越大越严重,可直接比较。 */
export enum LogLevel {
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5,
}

/** 输出格式 / Output format. */
export enum LogFormat {
  /** 单行,适合 hilog 过滤 / one line, grep-friendly */
  COMPACT = 0,
  /** 多行详情,适合 DevEco Log / multi-line detail for DevEco */
  PRETTY = 1,
  /** 每行一个 JSON,适合采集 / one JSON object per line */
  JSON = 2,
}

/** 中英展示策略 / Bilingual display policy. */
export enum LogLanguage {
  /** 中文 / English */
  BOTH = 0,
  /** 仅中文 / Chinese only */
  ZH = 1,
  /** 仅英文 / English only */
  EN = 2,
}

/** 双语文案 / Bilingual text. 中文与英文应描述同一件事。 */
export interface LogText {
  zh: string;
  en: string;
}

/** 兼容手写字符串;字符串按单语输出,不重复。 */
export type LogMessage = string | LogText;

/** 字段值联合类型;对象/数组由格式化器安全序列化。 */
export type LogValue = string | number | boolean | bigint | Object | null | undefined;

/** 构造双语文案 / Build bilingual text. */
export function L(zh: string, en: string): LogText {
  return { zh: zh, en: en };
}

/** 仅中文 / Chinese-only text. */
export function Lz(zh: string): LogText {
  return { zh: zh, en: '' };
}

/** 仅英文 / English-only text. */
export function Le(en: string): LogText {
  return { zh: '', en: en };
}

/**
 * 一个结构化字段 / One structured field.
 * 键名用于敏感字段脱敏;值保持原始类型,JSON 输出时可保留数字/布尔。
 */
export class LogField {
  key: string;
  value: LogValue;

  constructor(key: string, value: LogValue) {
    this.key = key;
    this.value = value;
  }
}

/** 字段简写 / Field helper. */
export function F(key: string, value: LogValue): LogField {
  return new LogField(key, value);
}

/**
 * 调用点 / Call site.
 *
 * 由 log-gen 在构建期写入 file/line/column/class/method/event,
 * 运行时零抓栈。手写日志由 LogSourceLocator 生成同结构对象。
 */
export class LogSite {
  file: string;
  line: number;
  column: number;
  className: string;
  methodName: string;
  eventName: string;

  constructor(file: string, line: number, column: number, className: string,
    methodName: string, eventName: string) {
    this.file = file;
    this.line = line;
    this.column = column;
    this.className = className;
    this.methodName = methodName;
    this.eventName = eventName;
  }

  /** 文件与行有效 / file+line valid. */
  valid(): boolean {
    return this.file !== '' && this.line > 0;
  }

  /** entry/src/main/ets/...:line:col */
  location(): string {
    if (!this.valid()) {
      return 'unknown:0:0';
    }
    return `${this.file}:${this.line}:${this.column}`;
  }

  /** Class.method(若扫描不到则为空) */
  symbol(): string {
    if (this.className !== '' && this.methodName !== '') {
      return `${this.className}.${this.methodName}`;
    }
    return this.methodName;
  }

  /** 稳定键,用于聚合/去重 / stable key. */
  key(): string {
    return `${this.file}:${this.line}:${this.column}`;
  }
}

/** 错误快照 / Error snapshot. 脱离原始对象,避免日志持有业务引用。 */
export class LogErrorSnapshot {
  name: string = 'Error';
  message: string = '';
  /** 常见业务错误字段 / common business fields */
  code: string = '';
  httpStatus: number = -1;
  /** 原始 stack 行,已做路径归一化 / normalized stack lines */
  stack: string[] = [];
  /** 自定义可枚举属性 / custom enumerable props */
  props: LogField[] = [];
  cause: LogErrorSnapshot | undefined = undefined;
}

/** 一条日志记录 / One log record. */
export class LogRecord {
  seq: number = 0;
  time: number = 0;
  level: LogLevel = LogLevel.INFO;
  tag: string = '';
  scope: string = '';
  message: LogText = { zh: '', en: '' };
  fields: LogField[] = [];
  site: LogSite = new LogSite('', 0, 0, '', '', '');
  error: LogErrorSnapshot | undefined = undefined;
  traceId: string = '';
  pid: number = 0;
  tid: number = 0;
  sessionId: string = '';
  appVersion: string = '';
  buildMode: string = '';
  device: string = '';
  osVersion: string = '';
  apiVersion: number = 0;
}

/** 运行环境 / Runtime environment, init 时采集一次。 */
export class LogEnv {
  debug: boolean = true;
  appVersion: string = '';
  buildMode: string = '';
  device: string = '';
  osVersion: string = '';
  apiVersion: number = 0;
  pid: number = 0;
  sessionId: string = '';
}

/** 运行配置 / Runtime config. */
export class LogConfig {
  minLevel: LogLevel = LogLevel.DEBUG;
  format: LogFormat = LogFormat.PRETTY;
  language: LogLanguage = LogLanguage.BOTH;
  /** hilog domain, 0x0..0xFFFF */
  domain: number = 0x0101;
  includeSource: boolean = true;
  includeFields: boolean = true;
  includeThread: boolean = true;
  includeSequence: boolean = true;
  includeMeta: boolean = false;
  fullTimestamp: boolean = false;
  maxValueLength: number = 512;
  maxMessageLength: number = 2000;
  maxStackFrames: number = 12;
  memoryCapacity: number = 300;
  maskSensitive: boolean = true;
  /** 额外敏感 key(小写) / extra sensitive keys */
  extraMaskKeys: string[] = [];
  debug: boolean = true;
}

/** init 的可选项 / Optional init overrides. */
export interface LoggerOptions {
  debug?: boolean;
  appVersion?: string;
  buildMode?: string;
  minLevel?: LogLevel;
  format?: LogFormat;
  language?: LogLanguage;
  includeMeta?: boolean;
  memoryCapacity?: number;
}

/** 计时器 / Timer entry. */
export class LogTimerEntry {
  label: string;
  start: number;
  site: LogSite;
  message: LogText;

  constructor(label: string, start: number, site: LogSite, message: LogText) {
    this.label = label;
    this.start = start;
    this.site = site;
    this.message = message;
  }
}

/** 级别短名 / short level name. */
export function logLevelShort(level: LogLevel): string {
  switch (level) {
    case LogLevel.TRACE:
      return 'T';
    case LogLevel.DEBUG:
      return 'D';
    case LogLevel.INFO:
      return 'I';
    case LogLevel.WARN:
      return 'W';
    case LogLevel.ERROR:
      return 'E';
    case LogLevel.FATAL:
      return 'F';
    default:
      return '?';
  }
}

/** 级别全名 / full level name. */
export function logLevelName(level: LogLevel): string {
  switch (level) {
    case LogLevel.TRACE:
      return 'TRACE';
    case LogLevel.DEBUG:
      return 'DEBUG';
    case LogLevel.INFO:
      return 'INFO';
    case LogLevel.WARN:
      return 'WARN';
    case LogLevel.ERROR:
      return 'ERROR';
    case LogLevel.FATAL:
      return 'FATAL';
    default:
      return 'INFO';
  }
}

/** 级别中文名 / Chinese level name. */
export function logLevelZh(level: LogLevel): string {
  switch (level) {
    case LogLevel.TRACE:
      return '跟踪';
    case LogLevel.DEBUG:
      return '调试';
    case LogLevel.INFO:
      return '信息';
    case LogLevel.WARN:
      return '警告';
    case LogLevel.ERROR:
      return '错误';
    case LogLevel.FATAL:
      return '致命';
    default:
      return '信息';
  }
}

/** 解析配置中的级别名 / parse level name. */
export function parseLogLevel(raw: string): LogLevel {
  switch (raw.trim().toUpperCase()) {
    case 'TRACE':
      return LogLevel.TRACE;
    case 'DEBUG':
      return LogLevel.DEBUG;
    case 'INFO':
      return LogLevel.INFO;
    case 'WARN':
      return LogLevel.WARN;
    case 'ERROR':
      return LogLevel.ERROR;
    case 'FATAL':
      return LogLevel.FATAL;
    default:
      return LogLevel.INFO;
  }
}
