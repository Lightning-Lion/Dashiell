/** A segment keeps its own alternatives and duration; backups are not subsequent segments. */
export class PlaybackPart {
  urls: string[];
  duration: number;
  constructor(urls: string[], duration: number) {
    this.urls = urls.slice();
    this.duration = duration;
  }
}

export class PlaybackSeek {
  changedPart: boolean;
  localTime: number;
  constructor(changedPart: boolean, localTime: number) {
    this.changedPart = changedPart;
    this.localTime = localTime;
  }
}

/** Pure timeline logic, independent of ArkUI and native decoder callbacks. Durations are seconds. */
export class BiliPlaybackQueue {
  private parts: PlaybackPart[] = [];
  partIndex: number = 0;
  private urlIndex: number = 0;
  position: number = 0;
  completed: boolean = false;

  configure(parts: PlaybackPart[]): void {
    if (parts.length === 0 || parts.some((part: PlaybackPart) => part.urls.length === 0 ||
      part.urls.some((address: string) => address.trim().length === 0) || !Number.isFinite(part.duration) || part.duration < 0)) {
      throw new Error('视频分段信息不完整，请重新获取播放地址');
    }
    this.parts = parts.map((part: PlaybackPart) => new PlaybackPart(part.urls, part.duration));
    this.restart();
  }

  get url(): string { return this.parts[this.partIndex]?.urls[this.urlIndex] ?? ''; }
  get duration(): number {
    if (this.parts.some((part: PlaybackPart) => part.duration <= 0)) { return 0; }
    return this.parts.reduce((total: number, part: PlaybackPart) => total + part.duration, 0);
  }
  get offset(): number {
    let result = 0;
    for (let index = 0; index < this.partIndex; index++) { result += this.parts[index].duration; }
    return result;
  }
  get localTime(): number { return Math.max(0, this.position - this.offset); }

  prepared(duration: number): void {
    if (this.parts.length === 0 || !Number.isFinite(duration) || duration <= 0) { return; }
    const local = this.localTime;
    this.parts[this.partIndex].duration = duration;
    this.position = this.offset + Math.min(local, duration);
  }

  update(localTime: number): void {
    if (this.completed || !Number.isFinite(localTime) || localTime < 0) { return; }
    const duration = this.parts[this.partIndex]?.duration ?? 0;
    this.position = this.offset + (duration > 0 ? Math.min(localTime, duration) : localTime);
  }

  seek(target: number): PlaybackSeek {
    const duration = this.duration;
    if (!Number.isFinite(target) || duration <= 0) { throw new Error('视频分段时长尚未就绪'); }
    const position = Math.min(Math.max(0, target), Math.max(0, duration - 0.05));
    let local = position;
    let index = 0;
    while (index < this.parts.length - 1 && local >= this.parts[index].duration) {
      local -= this.parts[index].duration;
      index++;
    }
    const changed = index !== this.partIndex;
    if (changed) { this.urlIndex = 0; }
    this.partIndex = index;
    this.position = position;
    this.completed = false;
    return new PlaybackSeek(changed, local);
  }

  next(): boolean {
    if (this.partIndex + 1 >= this.parts.length) {
      this.position = this.duration || this.position;
      this.completed = true;
      return false;
    }
    this.partIndex++;
    this.urlIndex = 0;
    this.position = this.offset;
    this.completed = false;
    return true;
  }

  fallback(): boolean {
    if (this.urlIndex + 1 >= (this.parts[this.partIndex]?.urls.length ?? 0)) { return false; }
    this.urlIndex++;
    return true;
  }

  retry(): void {
    this.urlIndex = 0;
    this.completed = false;
  }

  restart(): void {
    this.partIndex = 0;
    this.urlIndex = 0;
    this.position = 0;
    this.completed = false;
  }
}
