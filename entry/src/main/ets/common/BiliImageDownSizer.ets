export class BiliImageDownsizer {
  /** Missing optional cover metadata must never throw from an ArkUI @Computed getter. */
  static transformBilibiliImageUrl(url: string, width: number, height: number): string {
    let address = url?.trim() ?? '';
    if (address.startsWith('//')) { address = 'https:' + address; }
    const match = /^https?:\/\/([^/?#]+)(?:[/?#]|$)/i.exec(address);
    if (match === null || match[1].includes('@')) { return ''; }
    // The @size suffix is specific to Bilibili's image CDN. Do not corrupt other URLs or query signatures.
    if (!/(^|\.)hdslb\.com$/i.test(match[1]) || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return address;
    }
    const query = address.search(/[?#]/);
    const path = query < 0 ? address : address.substring(0, query);
    const suffix = query < 0 ? '' : address.substring(query);
    return `${path.split('@')[0]}@${Math.round(width)}w_${Math.round(height)}h${suffix}`;
  }
}
