/**
 * 日志脱敏 / Log masking.
 *
 * 只按字段名判断敏感字段;不扫描整条文案。动态值一律走 F(...) 字段,
 * 不要把 token/手机号拼进双语文案。
 */
export class LogMask {
  private static readonly DEFAULT_KEYS: string[] = [
    'token', 'accesstoken', 'refreshtoken', 'authorization', 'password', 'passwd',
    'secret', 'cookie', 'credential', 'smscode', 'verifycode', 'authcode',
    'captcha', 'phone', 'mobile', 'idcard', 'bankcard',
  ];

  /** 键名是否敏感 / sensitive key check. */
  static isSensitive(key: string, extra: string[]): boolean {
    const k: string = LogMask.normalizeKey(key);
    if (k === '') {
      return false;
    }
    for (let i = 0; i < LogMask.DEFAULT_KEYS.length; i++) {
      const p: string = LogMask.DEFAULT_KEYS[i];
      if (k === p || k.endsWith(p) || k.indexOf(p) >= 0) {
        return true;
      }
    }
    for (let i = 0; i < extra.length; i++) {
      const p: string = LogMask.normalizeKey(extra[i]);
      if (p !== '' && k.indexOf(p) >= 0) {
        return true;
      }
    }
    return false;
  }

  /** 按字段名脱敏;非敏感返回空串表示“原样输出”。 */
  static mask(key: string, value: string, extra: string[]): string {
    if (!LogMask.isSensitive(key, extra)) {
      return '';
    }
    const k: string = LogMask.normalizeKey(key);
    if (k.indexOf('phone') >= 0 || k.indexOf('mobile') >= 0) {
      return LogMask.phone(value);
    }
    if (k.indexOf('authorization') >= 0 || k.indexOf('cookie') >= 0) {
      if (value.startsWith('Bearer ')) {
        return 'Bearer ***';
      }
      return '***';
    }
    if (k.indexOf('token') >= 0 || k.indexOf('secret') >= 0 ||
      k.indexOf('password') >= 0 || k.indexOf('passwd') >= 0 ||
      k.indexOf('credential') >= 0) {
      return LogMask.token(value);
    }
    return '***';
  }

  /** 手机号:138****1234 / phone mask. */
  static phone(value: string): string {
    const v: string = value.trim();
    if (v.length === 11 && /^\d+$/.test(v)) {
      return `${v.substring(0, 3)}****${v.substring(7)}`;
    }
    if (v.length >= 7) {
      return `${v.substring(0, 2)}***${v.substring(v.length - 2)}`;
    }
    return '***';
  }

  /** token:abcd…wxyz(len=32) / token mask. */
  static token(value: string): string {
    const v: string = value.trim();
    if (v.length > 16) {
      return `${v.substring(0, 4)}…${v.substring(v.length - 4)}(len=${v.length})`;
    }
    return '***';
  }

  /** 邮箱:a***@b.com / email mask. */
  static email(value: string): string {
    const at: number = value.indexOf('@');
    if (at <= 0) {
      return '***';
    }
    const head: string = value.substring(0, at);
    const tail: string = value.substring(at);
    if (head.length <= 1) {
      return `*${tail}`;
    }
    return `${head.substring(0, 1)}***${tail}`;
  }

  private static normalizeKey(key: string): string {
    let k: string = key.toLowerCase();
    k = k.replace(/_/g, '').replace(/-/g, '').replace(/\./g, '').replace(/\[/g, '').replace(/\]/g, '');
    return k.trim();
  }
}
