import { LogSite } from './LogCore';

/**
 * 运行时调用点定位 / Runtime caller-site locator.
 *
 * 仅用于手写 Logger.info(...) 兜底;构建期生成的 LogEvents 直接携带 LogSite,
 * 不走这里。栈格式在 HarmonyOS/Panda 上可能是:
 *   at Foo.bar (entry|entry|1.0.0|src/main/ets/pages/Foo.ets:12:5)
 *   at Foo.bar (entry/src/main/ets/pages/Foo.ets:12:5)
 *   at anonymous (ets/pages/Foo.ets:12:5)
 *   at entry/src/main/ets/pages/Foo.ets:12:5
 * 解析器兼容这些形态,并按文件路径跳过日志库自身帧。
 */
export class LogSourceLocator {
  private static readonly WITH_FUNC: RegExp = /^\s*at\s+(.+?)\s+\((.+):(\d+):(\d+)\)\s*$/;
  private static readonly NO_FUNC: RegExp = /^\s*at\s+(.+):(\d+):(\d+)\s*$/;
  private static readonly BARE: RegExp = /^\s*(.+):(\d+):(\d+)\s*$/;
  private static readonly INTERNAL_DIR: string = 'entry/src/main/ets/utils/log/';
  private static readonly INTERNAL_FACADE: string = 'entry/src/main/ets/utils/Logger.ets';
  private static readonly INTERNAL_POS: string = 'entry/src/main/ets/utils/PosLog.ets';

  /**
   * 抓取调用者。第一条非日志库帧即调用点。
   * 失败返回 invalid LogSite,绝不抛错。
   */
  static capture(): LogSite {
    try {
      const stack: string | undefined = new Error().stack;
      if (stack === undefined || stack.length === 0) {
        return new LogSite('', 0, 0, '', '', '');
      }
      const lines: string[] = stack.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const site: LogSite | undefined = LogSourceLocator.parseFrame(lines[i]);
        if (site === undefined) {
          continue;
        }
        if (LogSourceLocator.isInternal(site.file)) {
          continue;
        }
        return site;
      }
    } catch (err) {
      // 日志定位失败不能影响业务
    }
    return new LogSite('', 0, 0, '', '', '');
  }

  /** 解析一条 stack 帧 / parse one frame. */
  static parseFrame(line: string): LogSite | undefined {
    if (line === '' || line.indexOf(':') < 0) {
      return undefined;
    }
    let m: RegExpExecArray | null = LogSourceLocator.WITH_FUNC.exec(line);
    if (m !== null) {
      return LogSourceLocator.build(m[2], m[3], m[4], m[1]);
    }
    m = LogSourceLocator.NO_FUNC.exec(line);
    if (m !== null) {
      return LogSourceLocator.build(m[1], m[2], m[3], '');
    }
    m = LogSourceLocator.BARE.exec(line);
    if (m !== null && LogSourceLocator.looksLikeSource(m[1])) {
      return LogSourceLocator.build(m[1], m[2], m[3], '');
    }
    return undefined;
  }

  /** 归一化文件路径到 entry/src/main/ets/... / normalize project path. */
  static normalizeFile(raw: string): string {
    let f: string = raw.trim();
    if (f.startsWith('at ')) {
      f = f.substring(3).trim();
    }
    if (f.startsWith('file://')) {
      f = f.substring('file://'.length);
    }
    if (f.startsWith('webpack://')) {
      f = f.substring('webpack://'.length);
    }
    const query: number = f.indexOf('?');
    if (query >= 0) {
      f = f.substring(0, query);
    }
    const hash: number = f.indexOf('#');
    if (hash >= 0) {
      f = f.substring(0, hash);
    }
    f = f.replace(/\\/g, '/');
    while (f.startsWith('./')) {
      f = f.substring(2);
    }

    // HarmonyOS normalized module key: entry|entry|1.0.0|src/main/ets/...
    if (f.indexOf('|') >= 0) {
      const parts: string[] = f.split('|');
      if (parts.length >= 2) {
        const moduleName: string = parts[0] === '' ? 'entry' : parts[0];
        const tail: string = parts[parts.length - 1];
        if (tail.startsWith('src/main/')) {
          f = `${moduleName}/${tail}`;
        } else if (tail.startsWith('ets/')) {
          f = `${moduleName}/src/main/${tail}`;
        } else if (tail.startsWith('/src/main/')) {
          f = `${moduleName}${tail}`;
        }
      }
    }

    // @bundle:bundleName/module/ets/...
    if (f.startsWith('@bundle:')) {
      const body: string = f.substring('@bundle:'.length);
      const segs: string[] = body.split('/');
      for (let i = 0; i < segs.length; i++) {
        if (segs[i] === 'ets') {
          const moduleName: string = i > 0 ? segs[i - 1] : 'entry';
          const rest: string = segs.slice(i + 1).join('/');
          f = `${moduleName}/src/main/ets/${rest}`;
          break;
        }
      }
    }

    // Absolute path or entry/... path containing src/main/ets.
    const marker: string = '/src/main/ets/';
    const markerIdx: number = f.lastIndexOf(marker);
    if (markerIdx >= 0) {
      const before: string = f.substring(0, markerIdx);
      const slash: number = before.lastIndexOf('/');
      let moduleName: string = slash >= 0 ? before.substring(slash + 1) : before;
      if (moduleName === '') {
        moduleName = 'entry';
      }
      f = `${moduleName}/src/main/ets/${f.substring(markerIdx + marker.length)}`;
    } else if (f.startsWith('src/main/ets/')) {
      f = `entry/${f}`;
    } else if (f.startsWith('ets/')) {
      f = `entry/src/main/${f}`;
    } else if (f.startsWith('entry/ets/')) {
      f = `entry/src/main/${f.substring('entry/'.length)}`;
    }

    // ArkTS debug stacks may expose the intermediate .ts name.
    if (f.startsWith('entry/src/main/ets/') && f.endsWith('.ts')) {
      f = `${f.substring(0, f.length - 3)}.ets`;
    }
    // Missing extension in normalized module keys.
    if (f.indexOf('/src/main/ets/') >= 0 && !LogSourceLocator.hasExtension(f)) {
      f = `${f}.ets`;
    }
    return f;
  }

  /** 是否是日志库内部帧 / logger-internal frame. */
  static isInternal(file: string): boolean {
    const f: string = LogSourceLocator.normalizeFile(file);
    return f.startsWith(LogSourceLocator.INTERNAL_DIR) || f === LogSourceLocator.INTERNAL_FACADE ||
      f === LogSourceLocator.INTERNAL_POS;
  }

  /**
   * 归一化错误栈行 / normalize error stack.
   * 只保留 max 条,保留无法解析的原始行。
   */
  static normalizeStack(stack: string, max: number): string[] {
    const out: string[] = [];
    if (stack === '') {
      return out;
    }
    const lines: string[] = stack.split('\n');
    for (let i = 0; i < lines.length && out.length < max; i++) {
      const raw: string = lines[i];
      if (raw.trim() === '') {
        continue;
      }
      const site: LogSite | undefined = LogSourceLocator.parseFrame(raw);
      if (site === undefined) {
        // 第一行通常是 "Error: message",保留
        if (out.length === 0 || raw.trim().startsWith('Caused by')) {
          out.push(raw.trim());
        }
        continue;
      }
      const symbol: string = site.symbol();
      if (symbol === '') {
        out.push(`    at ${site.file}:${site.line}:${site.column}`);
      } else {
        out.push(`    at ${symbol} (${site.file}:${site.line}:${site.column})`);
      }
    }
    return out;
  }

  private static build(rawFile: string, rawLine: string, rawColumn: string, rawFunc: string): LogSite {
    const file: string = LogSourceLocator.normalizeFile(rawFile);
    const line: number = parseInt(rawLine, 10);
    const column: number = parseInt(rawColumn, 10);
    const func: string = LogSourceLocator.cleanFunction(rawFunc);
    let className: string = '';
    let methodName: string = func;
    const dot: number = func.lastIndexOf('.');
    if (dot > 0 && dot < func.length - 1) {
      className = func.substring(0, dot);
      methodName = func.substring(dot + 1);
    }
    return new LogSite(file, isNaN(line) ? 0 : line, isNaN(column) ? 0 : column,
      className, methodName, '');
  }

  private static cleanFunction(raw: string): string {
    let f: string = raw.trim();
    while (f.startsWith('async ')) {
      f = f.substring('async '.length).trim();
    }
    while (f.startsWith('new ')) {
      f = f.substring('new '.length).trim();
    }
    if (f.startsWith('get ')) {
      f = f.substring('get '.length).trim();
    } else if (f.startsWith('set ')) {
      f = f.substring('set '.length).trim();
    }
    // ArkTS 栈帧可能带模块名: "at pushPos entry (file:line:col)"
    const space: number = f.lastIndexOf(' ');
    if (space > 0) {
      const tail: string = f.substring(space + 1);
      if (tail === 'entry' || tail === 'entry_test' || tail === 'default') {
        f = f.substring(0, space).trim();
      }
    }
    if (f === 'anonymous' || f === '<anonymous>' || f === 'Object.<anonymous>') {
      return '';
    }
    return f;
  }

  private static looksLikeSource(raw: string): boolean {
    const f: string = raw.trim();
    return f.endsWith('.ets') || f.endsWith('.ts') || f.endsWith('.js') ||
      f.indexOf('/src/main/ets/') >= 0 || f.indexOf('|') >= 0;
  }

  private static hasExtension(file: string): boolean {
    const slash: number = file.lastIndexOf('/');
    const dot: number = file.lastIndexOf('.');
    return dot > slash;
  }
}
