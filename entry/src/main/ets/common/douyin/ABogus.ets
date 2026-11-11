import { SM3 } from './SM3';

/** Compatibility port of Android_Dashiell's Kotlin ABogus, not a browser SDK. */
export class ABogus {
  private readonly clock: () => number;
  private readonly random: () => number;
  private static readonly BROWSER: string = '1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|MacIntel';
  private static readonly TABLE: string = 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe';

  constructor(clock: () => number = () => Date.now(), random: () => number = () => Math.random()) {
    this.clock = clock;
    this.random = random;
  }

  /** Java URLEncoder UTF-8 semantics, including '?' for unpaired surrogates. */
  static formEncode(value: string): string {
    let normalized = '';
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) { normalized += value[i] + value[++i]; }
        else { normalized += '?'; }
      } else { normalized += code >= 0xdc00 && code <= 0xdfff ? '?' : value[i]; }
    }
    return encodeURIComponent(normalized).replace(/%20/g, '+').replace(/[!'()~]/g,
      (ch: string): string => '%' + ch.charCodeAt(0).toString(16).toUpperCase());
  }

  static serialize(params: Map<string, string>): string {
    const parts: string[] = [];
    params.forEach((value: string, key: string) => {
      parts.push(ABogus.formEncode(key) + '=' + ABogus.formEncode(value));
    });
    return parts.join('&');
  }

  private sample(): number {
    const value = this.random();
    if (!Number.isFinite(value) || value < 0 || value >= 1) { throw new Error('Random value must be in [0, 1)'); }
    return value;
  }

  getValue(params: Map<string, string>): string {
    if (params.has('a_bogus')) { throw new Error('Remove the existing a_bogus before signing'); }
    const prefix: number[] = [];
    for (let group = 0; group < 3; group++) {
      const r = Math.floor(this.sample() * 10000);
      prefix.push((r & 170) | 1, (r & 85) | (group === 0 ? 2 : 0),
        ((r >> 8) & 170) | (group === 1 ? 0 : 5), ((r >> 8) & 85) | (group === 0 ? 40 : 0));
    }
    const start = this.clock();
    if (!Number.isSafeInteger(start) || start < 0) { throw new Error('Clock must return nonnegative integer milliseconds'); }
    const end = start + 4 + Math.floor(this.sample() * 5);
    if (!Number.isSafeInteger(end)) { throw new Error('Timestamp overflow'); }
    // Form encoding makes the digest input ASCII; hash raw digest bytes on the second pass.
    const text = ABogus.serialize(params) + 'cus';
    const input: number[] = [];
    for (let i = 0; i < text.length; i++) { input.push(text.charCodeAt(i)); }
    const hash = SM3.digest(SM3.digest(input));
    const a: number[] = [44, (end >>> 24) & 255, 0, 0, 0, 0, 24, hash[21], 251, 0,
      40, (end >>> 16) & 255, 0, 0, 0, 1, 0, 239, hash[22], 167, 49, (end >>> 8) & 255,
      0, 0, 0, 0, end & 255, 0, 0, 14, (start >>> 24) & 255, (start >>> 16) & 255,
      0, (start >>> 8) & 255, start & 255, 3, Math.floor(end / 4294967296) | 0, 1,
      Math.floor(start / 4294967296) | 0, 1, 67, 0, 0, 0];
    let check = 0;
    for (let i = 0; i < a.length; i++) { check ^= a[i]; }
    for (let i = 0; i < ABogus.BROWSER.length; i++) { a.push(ABogus.BROWSER.charCodeAt(i)); }
    a.push(check);
    // Kotlin toChar truncates to 16 bits, NOT to 8 bits. Preserve this through RC4/Base64.
    const s: number[] = [];
    for (let i = 0; i < 256; i++) { s.push(i); }
    let j = 0;
    for (let i = 0; i < 256; i++) {
      j = (j + s[i] + 121) & 255;
      const temp = s[i]; s[i] = s[j]; s[j] = temp;
    }
    let i = 0; j = 0;
    for (let k = 0; k < a.length; k++) {
      i = (i + 1) & 255; j = (j + s[i]) & 255;
      const temp = s[i]; s[i] = s[j]; s[j] = temp;
      prefix.push((a[k] & 65535) ^ s[(s[i] + s[j]) & 255]);
    }
    let result = '';
    for (let k = 0; k < prefix.length; k += 3) {
      const n = (prefix[k] << 16) | (k + 1 < prefix.length ? prefix[k + 1] << 8 : 0) |
        (k + 2 < prefix.length ? prefix[k + 2] : 0);
      result += ABogus.TABLE[(n >>> 18) & 63] + ABogus.TABLE[(n >>> 12) & 63];
      result += k + 1 < prefix.length ? ABogus.TABLE[(n >>> 6) & 63] : '=';
      result += k + 2 < prefix.length ? ABogus.TABLE[n & 63] : '=';
    }
    return result;
  }

  /** Use this exact query on the wire to avoid signature/request encoding divergence. */
  signedQuery(params: Map<string, string>): string {
    const signature = this.getValue(params);
    const query = ABogus.serialize(params);
    return (query.length > 0 ? query + '&' : '') + 'a_bogus=' + ABogus.formEncode(signature);
  }
}
