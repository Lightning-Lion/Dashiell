/** RFC 1321 MD5 for wire-protocol compatibility only, not password storage or security design. */
export class MD5 {
  private static readonly K: number[] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  ];
  private static readonly SHIFTS: number[] = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];

  static hex(text: string): string {
    // encodeURIComponent supplies strict UTF-8 and rejects malformed UTF-16.
    const encoded = encodeURIComponent(text);
    const bytes: number[] = [];
    for (let i = 0; i < encoded.length; i++) {
      if (encoded[i] === '%') { bytes.push(parseInt(encoded.substring(i + 1, i + 3), 16)); i += 2; }
      else { bytes.push(encoded.charCodeAt(i)); }
    }
    const bitLength = bytes.length * 8;
    bytes.push(128);
    while (bytes.length % 64 !== 56) { bytes.push(0); }
    for (let i = 0; i < 8; i++) { bytes.push(Math.floor(bitLength / Math.pow(256, i)) & 255); }
    const state: number[] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
    for (let offset = 0; offset < bytes.length; offset += 64) {
      const words: number[] = [];
      for (let i = 0; i < 16; i++) {
        const n = offset + i * 4;
        words.push(bytes[n] | (bytes[n + 1] << 8) | (bytes[n + 2] << 16) | (bytes[n + 3] << 24));
      }
      let a = state[0]; let b = state[1]; let c = state[2]; let d = state[3];
      for (let step = 0; step < 64; step++) {
        let f: number; let index: number;
        if (step < 16) { f = (b & c) | (~b & d); index = step; }
        else if (step < 32) { f = (d & b) | (~d & c); index = (5 * step + 1) % 16; }
        else if (step < 48) { f = b ^ c ^ d; index = (3 * step + 5) % 16; }
        else { f = c ^ (b | ~d); index = (7 * step) % 16; }
        const sum = (a + f + MD5.K[step] + words[index]) | 0;
        const shift = MD5.SHIFTS[Math.floor(step / 16) * 4 + step % 4];
        const next = (b + ((sum << shift) | (sum >>> (32 - shift)))) | 0;
        a = d; d = c; c = b; b = next;
      }
      state[0] = (state[0] + a) | 0; state[1] = (state[1] + b) | 0;
      state[2] = (state[2] + c) | 0; state[3] = (state[3] + d) | 0;
    }
    let result = '';
    for (const word of state) {
      for (let i = 0; i < 4; i++) { result += ((word >>> (8 * i)) & 255).toString(16).padStart(2, '0'); }
    }
    return result;
  }
}
