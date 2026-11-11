/**
 * Article image loading.
 *
 * ArkUI's Image component sends a fixed `libcurl-agent/1.0` user agent and cannot set
 * Referer headers — the bundled feeds' CDNs (img.3dmgame.com, pic*.zhimg.com) reject that UA
 * with 403/567 challenge pages. So every article image is downloaded over http with a
 * browser UA + matching Referer, decoded to a PixelMap with a bounded desired size (a watch
 * never needs the 907 KB original), and served from a shared LRU plus a disk cache.
 */

import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const BROWSER_UA = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/120.0 Mobile Safari/537.36';

export class RemoteImageResult {
  ok: boolean = false;
  pixelMap: image.PixelMap | null = null;
  width: number = 0;
  height: number = 0;
  fromCache: boolean = false;
  /** Why the load failed; empty when ok. Callers log this next to the URL. */
  reason: string = '';

  constructor(ok: boolean, pixelMap: image.PixelMap | null, width: number, height: number,
    fromCache: boolean, reason: string) {
    this.ok = ok;
    this.pixelMap = pixelMap;
    this.width = width;
    this.height = height;
    this.fromCache = fromCache;
    this.reason = reason;
  }

  static failed(reason: string): RemoteImageResult {
    return new RemoteImageResult(false, null, 0, 0, false, reason);
  }
}

/** download() has to report a cause as well as bytes, so it resolves this instead of a bare buffer. */
class DownloadResult {
  bytes: ArrayBuffer | null = null;
  reason: string = '';

  constructor(bytes: ArrayBuffer | null, reason: string) {
    this.bytes = bytes;
    this.reason = reason;
  }
}

class MemoryEntry {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
  weight: number;

  constructor(pixelMap: image.PixelMap, width: number, height: number) {
    this.pixelMap = pixelMap;
    this.width = width;
    this.height = height;
    this.weight = width * height * 4;
  }
}

/** Shared across pages; eviction releases the PixelMap so decoding work is never wasted twice. */
export class ImageMemoryCache {
  private entries: Map<string, MemoryEntry> = new Map<string, MemoryEntry>();
  private weight: number = 0;
  private readonly maxEntries: number = 40;
  private readonly maxWeight: number = 20 * 1024 * 1024;

  get(key: string): MemoryEntry | undefined {
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      this.entries.delete(key);
      this.entries.set(key, entry);
    }
    return entry;
  }

  put(key: string, entry: MemoryEntry): void {
    const previous = this.entries.get(key);
    if (previous !== undefined) { this.weight -= previous.weight; }
    this.entries.set(key, entry);
    this.weight += entry.weight;
    while (this.entries.size > this.maxEntries || this.weight > this.maxWeight) {
      const oldestKey = this.entries.keys().next().value as string;
      const oldest = this.entries.get(oldestKey);
      if (oldest !== undefined) {
        this.weight -= oldest.weight;
        this.entries.delete(oldestKey);
        oldest.pixelMap.release().catch(() => {});
      }
    }
  }
}

export const sharedImageCache: ImageMemoryCache = new ImageMemoryCache();

export function refererForImageURL(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/.exec(url);
  const host = match !== null ? match[1].toLowerCase() : '';
  if (host.endsWith('zhimg.com')) { return 'https://www.zhihu.com/'; }
  if (host.endsWith('3dmgame.com')) { return 'https://www.3dmgame.com/'; }
  if (host.endsWith('ithome.com')) { return 'https://www.ithome.com/'; }
  if (host.endsWith('360buyimg.com')) { return 'https://www.jd.com/'; }
  return host.length > 0 ? 'https://' + host + '/' : '';
}

/** FNV-1a (two seeds) hex digest; long enough for a cache key, no crypto import needed. */
function hashText(text: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = (Math.imul(h1 ^ c, 0x01000193) >>> 0);
    h2 = (Math.imul(h2 ^ c, 0x85ebca6b) >>> 0);
  }
  const pad = (value: number): string => {
    const hex = value.toString(16);
    return '00000000'.substring(hex.length) + hex;
  };
  return pad(h1) + pad(h2);
}

/** ArkTS catch variables are untyped; pull a readable message out of whatever landed there. */
function formatError(error: Error): string {
  const message = error.message;
  return (message !== undefined && message.length > 0) ? message : String(error);
}

/** Keeps the disk-stage cause when the network/decode stage fails too; either side may be empty. */
function joinReason(fromDisk: string, fromNetwork: string): string {
  if (fromDisk.length === 0) { return fromNetwork; }
  if (fromNetwork.length === 0) { return fromDisk; }
  return '磁盘缓存: ' + fromDisk + '；网络: ' + fromNetwork;
}

/** Page-owned loader; call cancel() on dispose. Decoded results stay in the shared cache. */
export class RemoteImage {
  private context: common.UIAbilityContext;
  private clients: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  private inflight: Map<string, Promise<RemoteImageResult>> = new Map<string, Promise<RemoteImageResult>>();
  private cancelled: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  cancel(): void {
    this.cancelled = true;
    for (const client of Array.from(this.clients)) {
      try { client.destroy(); } catch (_) {}
    }
    this.clients.clear();
    this.inflight.clear();
  }

  private static normalizeURL(url: string): string {
    let address = url.trim();
    if (address.startsWith('//')) { address = 'https:' + address; }
    address = address.split(' ').join('%20');
    return address;
  }

  private cacheKey(url: string): string {
    return hashText(RemoteImage.normalizeURL(url));
  }

  private diskPath(url: string): string {
    return this.context.cacheDir + '/article-images/' + this.cacheKey(url) + '.img';
  }

  /** Only absolute http(s) reaches the network; `data:`/`blob:` inline payloads cannot. */
  private static isFetchable(address: string): boolean {
    return address.startsWith('http://') || address.startsWith('https://');
  }

  async load(url: string, maxWidth: number): Promise<RemoteImageResult> {
    const address = RemoteImage.normalizeURL(url);
    if (address.length === 0) { return RemoteImageResult.failed('URL 为空'); }
    if (!RemoteImage.isFetchable(address)) {
      // Feed markup carries inline placeholders (Zhihu's lazy images are an empty SVG); the
      // request would fail with a URL-format error that says nothing about the real cause.
      return RemoteImageResult.failed('不支持的图片地址（非 http/https）');
    }
    const key = this.cacheKey(address);

    const memory = sharedImageCache.get(key);
    if (memory !== undefined) {
      return new RemoteImageResult(true, memory.pixelMap, memory.width, memory.height, true, '');
    }
    const pending = this.inflight.get(key);
    if (pending !== undefined) { return pending; }

    const task = this.loadFromDiskOrNetwork(address, key, maxWidth);
    this.inflight.set(key, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(key);
    }
  }

  /**
   * 同步取已解码的 PixelMap，不发起任何请求。
   * 起飞动画在点击那一拍就要拿到同一张图：走 load() 虽然会命中内存 LRU，但 Promise
   * 至少晚一帧，那一帧会露出空白，图看起来是先闪一下再飞。
   */
  peek(url: string): image.PixelMap | null {
    const memory = sharedImageCache.get(this.cacheKey(url));
    return memory === undefined ? null : memory.pixelMap;
  }

  private async loadFromDiskOrNetwork(address: string, key: string,
    maxWidth: number): Promise<RemoteImageResult> {
    // Disk first: survives app restarts and costs no network round trip.
    let diskReason = '';
    try {
      const path = this.diskPath(address);
      if (fs.accessSync(path)) {
        const bytes = this.readFileBytes(path);
        if (bytes !== null && bytes.byteLength > 0) {
          const decoded = await this.decode(bytes, maxWidth);
          if (decoded.ok && decoded.pixelMap !== null) {
            sharedImageCache.put(key,
              new MemoryEntry(decoded.pixelMap, decoded.width, decoded.height));
            return decoded;
          }
          diskReason = decoded.reason;
        } else {
          diskReason = '缓存文件不可读或为空';
        }
      }
    } catch (error) {
      diskReason = '读取缓存失败: ' + formatError(error);
    }
    if (this.cancelled) { return RemoteImageResult.failed('页面已释放，请求取消'); }
    try {
      const downloaded = await this.download(address);
      if (downloaded.bytes === null) {
        return RemoteImageResult.failed(joinReason(diskReason, downloaded.reason));
      }
      const decoded = await this.decode(downloaded.bytes, maxWidth);
      if (decoded.ok && decoded.pixelMap !== null) {
        sharedImageCache.put(key, new MemoryEntry(decoded.pixelMap, decoded.width, decoded.height));
        this.persistDisk(address, downloaded.bytes);
      } else {
        decoded.reason = joinReason(diskReason, decoded.reason);
      }
      return decoded;
    } catch (error) {
      return RemoteImageResult.failed(joinReason(diskReason, '加载异常: ' + formatError(error)));
    }
  }

  /** This SDK's fs has no readFile; assemble the buffer from statSync + readSync. */
  private readFileBytes(path: string): ArrayBuffer | null {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(file.fd).size;
      if (size <= 0 || size > 8 * 1024 * 1024) { return null; }
      const buffer = new ArrayBuffer(size);
      const readCount = fs.readSync(file.fd, buffer);
      if (readCount <= 0) { return null; }
      return buffer;
    } catch (_) {
      return null;
    } finally {
      try { fs.closeSync(file); } catch (_) {}
    }
  }

  private persistDisk(address: string, bytes: ArrayBuffer): void {
    try {
      const directory = this.context.cacheDir + '/article-images';
      if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
      const file = fs.openSync(this.diskPath(address),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        try { fs.closeSync(file); } catch (_) {}
      }
    } catch (_) {
      // Cache writes are best-effort only.
    }
  }

  private download(address: string): Promise<DownloadResult> {
    return new Promise<DownloadResult>((resolve) => {
      if (this.cancelled) { resolve(new DownloadResult(null, '页面已释放，请求取消')); return; }
      const client = http.createHttp();
      this.clients.add(client);
      client.request(address, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': BROWSER_UA,
          'Referer': refererForImageURL(address),
          'Accept': 'image/avif,image/webp,image/png,image/jpeg,*/*'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: 8 * 1024 * 1024,
        connectTimeout: 6000,
        readTimeout: 15000
      }).then((response: http.HttpResponse) => {
        this.clients.delete(client);
        try { client.destroy(); } catch (_) {}
        if (response.responseCode !== 200) {
          resolve(new DownloadResult(null, 'HTTP ' + response.responseCode));
          return;
        }
        const buffer = response.result as ArrayBuffer;
        if (buffer.byteLength === 0) {
          resolve(new DownloadResult(null, 'HTTP 200 但响应体为空'));
          return;
        }
        resolve(new DownloadResult(buffer, ''));
      }).catch((error: BusinessError) => {
        this.clients.delete(client);
        try { client.destroy(); } catch (_) {}
        resolve(new DownloadResult(null,
          '网络请求失败: ' + formatError(error) + ' (code ' + error.code + ')'));
      });
    });
  }

  private decode(bytes: ArrayBuffer, maxWidth: number): Promise<RemoteImageResult> {
    return new Promise<RemoteImageResult>((resolve) => {
      const fail = (reason: string): void => { resolve(RemoteImageResult.failed(reason)); };
      let created: image.ImageSource | null = null;
      try {
        created = image.createImageSource(bytes);
      } catch (error) {
        fail('无法识别图片数据（' + bytes.byteLength + ' 字节）: ' + formatError(error));
        return;
      }
      if (created === null) {
        fail('无法识别图片数据（' + bytes.byteLength + ' 字节）');
        return;
      }
      // Const capture keeps the non-null narrowing alive inside the promise closures below.
      const source: image.ImageSource = created;
      const releaseSource = (): void => { source.release().catch(() => {}); };
      source.getImageInfo().then((info: image.ImageInfo) => {
        const intrinsicWidth = info.size.width;
        const intrinsicHeight = info.size.height;
        if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
          releaseSource();
          fail('图片尺寸无效: ' + intrinsicWidth + 'x' + intrinsicHeight);
          return;
        }
        const targetWidth = Math.min(intrinsicWidth, Math.max(1, maxWidth));
        const targetHeight = Math.max(1, Math.round(targetWidth * intrinsicHeight / intrinsicWidth));
        const options: image.DecodingOptions = {
          desiredSize: { width: targetWidth, height: targetHeight }
        };
        source.createPixelMap(options).then((pixelMap: image.PixelMap) => {
          releaseSource();
          resolve(new RemoteImageResult(true, pixelMap, targetWidth, targetHeight, false, ''));
        }).catch((error: BusinessError) => {
          releaseSource();
          fail('像素图解码失败: ' + formatError(error));
        });
      }).catch((error: BusinessError) => {
        releaseSource();
        fail('读取图片信息失败: ' + formatError(error));
      });
    });
  }
}
