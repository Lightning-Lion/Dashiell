/** Dependency-free SM3. Input and output contain unsigned bytes. */
export class SM3 {
  private static rot(x: number, n: number): number {
    return (x << (n & 31)) | (x >>> ((32 - n) & 31));
  }

  static digest(input: number[]): number[] {
    const bytes: number[] = input.slice();
    const bits = bytes.length * 8;
    bytes.push(128);
    while (bytes.length % 64 !== 56) { bytes.push(0); }
    for (let i = 7; i >= 0; i--) { bytes.push(Math.floor(bits / Math.pow(256, i)) & 255); }
    const state: number[] = [0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
      0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e];
    for (let offset = 0; offset < bytes.length; offset += 64) {
      const w: number[] = [];
      for (let j = 0; j < 16; j++) {
        const k = offset + j * 4;
        w.push((bytes[k] << 24) | (bytes[k + 1] << 16) | (bytes[k + 2] << 8) | bytes[k + 3]);
      }
      for (let j = 16; j < 68; j++) {
        const x = w[j - 16] ^ w[j - 9] ^ SM3.rot(w[j - 3], 15);
        w.push(x ^ SM3.rot(x, 15) ^ SM3.rot(x, 23) ^ SM3.rot(w[j - 13], 7) ^ w[j - 6]);
      }
      let a = state[0]; let b = state[1]; let c = state[2]; let d = state[3];
      let e = state[4]; let f = state[5]; let g = state[6]; let h = state[7];
      for (let j = 0; j < 64; j++) {
        const ar = SM3.rot(a, 12);
        const ss1 = SM3.rot((ar + e + SM3.rot(j < 16 ? 0x79cc4519 : 0x7a879d8a, j)) | 0, 7);
        const ss2 = ss1 ^ ar;
        const ff = j < 16 ? a ^ b ^ c : (a & b) | (a & c) | (b & c);
        const gg = j < 16 ? e ^ f ^ g : (e & f) | (~e & g);
        const tt1 = (ff + d + ss2 + (w[j] ^ w[j + 4])) | 0;
        const tt2 = (gg + h + ss1 + w[j]) | 0;
        d = c; c = SM3.rot(b, 9); b = a; a = tt1;
        h = g; g = SM3.rot(f, 19); f = e;
        e = tt2 ^ SM3.rot(tt2, 9) ^ SM3.rot(tt2, 17);
      }
      const result: number[] = [a, b, c, d, e, f, g, h];
      for (let j = 0; j < 8; j++) { state[j] ^= result[j]; }
    }
    const output: number[] = [];
    for (let j = 0; j < 8; j++) {
      for (let shift = 24; shift >= 0; shift -= 8) { output.push((state[j] >>> shift) & 255); }
    }
    return output;
  }
}
