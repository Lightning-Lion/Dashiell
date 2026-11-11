import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logTag } from '../../common/printLog';
import { DouYinLoopMode, DouYinMenuLayer, DouYinPlayerUi } from './DouYinPlayerUi';

const PLAYER_TAG = '🎬抖音播放器';
const VOLUME_TAG = '👑抖音表冠';
const CROWN_VOLUME_SCALE = 0.02;

const DOUYIN_HEADERS: Record<string, string> = {
  'accept': '*/*',
  'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  'sec-ch-ua': '"Microsoft Edge";v="129", "Not=A?Brand";v="8", "Chromium";v="129"',
  'sec-ch-ua-mobile': '?0',
  'sec-ch-ua-platform': '"macOS"',
  'sec-fetch-dest': 'video',
  'sec-fetch-mode': 'no-cors',
  'sec-fetch-site': 'cross-site',
  'Referer': 'https://www.douyin.com/',
  'Referrer-Policy': 'strict-origin-when-cross-origin'
};

export interface DouYinPlaybackItem {
  awemeID: string;
  urls: string[];
  description: string;
}

/**
 * 音量控制器：表冠转角度 → 系统媒体音量。
 * BEGIN 重读系统值，浮点累计、整数取整、串行写入；HUD 在停转 1s 后隐藏。
 */
@ObservedV2
export class DouYinVolumeController {
  @Trace level: number = 0;
  @Trace minimum: number = 0;
  @Trace maximum: number = 15;
  @Trace ready: boolean = false;
  @Trace showBar: boolean = false;

  private busy: boolean = false;
  private pendingDegrees: number = 0;
  private lastWritten: number = -1;
  private hideTimer: number | null = null;
  private lastEventMs: number = 0;

  async handleCrown(event: CrownEvent): Promise<void> {
    const now = Date.now();
    // API 24 之后 BEGIN 可能不再派发：超过 800ms 没有事件就当作新会话，重新读音量。
    if (now - this.lastEventMs > 800) {
      this.ready = false;
    }
    this.lastEventMs = now;

    if (event.action === CrownAction.BEGIN || !this.showBar) {
      this.showBar = true;
      if (this.hideTimer !== null) {
        clearTimeout(this.hideTimer);
        this.hideTimer = null;
      }
    }
    if (event.action === CrownAction.BEGIN) {
      this.ready = false;
    }

    this.pendingDegrees += event.degree;
    if (this.busy) { return; }
    this.busy = true;
    try {
      const manager = audio.getAudioManager();
      if (!this.ready) {
        const group = await manager.getVolumeManager().getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
        this.level = await group.getVolume(audio.AudioVolumeType.MEDIA);
        this.minimum = await manager.getMinVolume(audio.AudioVolumeType.MEDIA);
        this.maximum = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA);
        this.lastWritten = Math.round(this.level);
        this.ready = true;
        console.info(VOLUME_TAG, `[读音量] 当前=${this.level} 范围[${this.minimum},${this.maximum}]`);
      }
      while (this.pendingDegrees !== 0) {
        const degrees = this.pendingDegrees;
        this.pendingDegrees = 0;
        // 表冠上转为负，取负号让“上转=变大”。
        const wanted = this.level - degrees * CROWN_VOLUME_SCALE;
        const clamped = Math.min(this.maximum, Math.max(this.minimum, wanted));
        this.level = clamped;
        const next = Math.round(this.level);
        if (next !== this.lastWritten) {
          await manager.setVolume(audio.AudioVolumeType.MEDIA, next);
          this.lastWritten = next;
          console.info(VOLUME_TAG, `[写音量] ${next}`);
        }
      }
    } catch (error) {
      this.pendingDegrees = 0;
      this.ready = false;
      console.warn(VOLUME_TAG, '音量处理失败: ' + (error as Error).message);
      throw error as Error;
    } finally {
      this.busy = false;
    }

    if (event.action === CrownAction.END) {
      if (this.hideTimer !== null) { clearTimeout(this.hideTimer); }
      this.hideTimer = setTimeout(() => {
        this.showBar = false;
        this.hideTimer = null;
      }, 1000);
    }
  }

  async ensureReady(): Promise<void> {
    if (this.ready) { return; }
    try {
      const manager = audio.getAudioManager();
      const group = await manager.getVolumeManager().getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
      this.level = await group.getVolume(audio.AudioVolumeType.MEDIA);
      this.minimum = await manager.getMinVolume(audio.AudioVolumeType.MEDIA);
      this.maximum = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA);
      this.lastWritten = Math.round(this.level);
      this.ready = true;
      console.info(VOLUME_TAG, `[初始化] 当前=${this.level} 范围[${this.minimum},${this.maximum}]`);
    } catch (error) {
      console.warn(VOLUME_TAG, 'ensureReady failed: ' + (error as Error).message);
    }
  }

  async setLevel(next: number): Promise<void> {
    try {
      const manager = audio.getAudioManager();
      if (!this.ready) {
        const group = await manager.getVolumeManager().getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
        this.level = await group.getVolume(audio.AudioVolumeType.MEDIA);
        this.minimum = await manager.getMinVolume(audio.AudioVolumeType.MEDIA);
        this.maximum = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA);
        this.ready = true;
      }
      const clamped = Math.round(Math.min(this.maximum, Math.max(this.minimum, next)));
      this.level = clamped;
      if (clamped !== this.lastWritten) {
        await manager.setVolume(audio.AudioVolumeType.MEDIA, clamped);
        this.lastWritten = clamped;
      }
    } catch (error) {
      console.warn(VOLUME_TAG, 'setLevel failed: ' + (error as Error).message);
    }
  }

  release(): void {
    if (this.hideTimer !== null) {
      clearTimeout(this.hideTimer);
      this.hideTimer = null;
    }
  }
}

/**
 * 播放会话：整个播放器只有一个 AVPlayer、一个 surface。
 * 切卡片只换媒体源；内页只是把视频节点迁到另一个槽位。
 */
@ObservedV2
export class DouYinPlayerSession {
  @Trace loading: boolean = false;
  @Trace playing: boolean = false;
  @Trace positionMs: number = 0;
  @Trace durationMs: number = 0;
  @Trace videoW: number = 0;
  @Trace videoH: number = 0;
  @Trace speed: number = 1;
  @Trace loopMode: DouYinLoopMode = DouYinLoopMode.Single;
  @Trace currentAwemeID: string = '';
  @Trace currentDescription: string = '';
  @Trace errorMessage: string = '';

  readonly ui: DouYinPlayerUi = new DouYinPlayerUi();
  readonly volume: DouYinVolumeController = new DouYinVolumeController();

  onCompleted: (() => void) | null = null;
  onImmersiveRequest: ((want: boolean) => void) | null = null;
  onLoopModeChanged: ((mode: DouYinLoopMode) => void) | null = null;
  onLayerChanged: ((layer: DouYinMenuLayer) => void) | null = null;
  onBusyChanged: (() => void) | null = null;
  onFullscreenChanged: ((on: boolean) => void) | null = null;

  private player: media.AVPlayer | null = null;
  private surfaceId: string = '';
  private urls: string[] = [];
  private urlIndex: number = 0;
  private generation: number = 0;
  private pendingItem: DouYinPlaybackItem | null = null;
  private pendingSeekMs: number = -1;
  private active: boolean = true;
  private resumeOnActive: boolean = false;

  bindSurface(surfaceId: string): void {
    if (this.surfaceId === surfaceId) { return; }
    this.surfaceId = surfaceId;
    console.info(PLAYER_TAG, 'bind surface=' + surfaceId);
    if (this.player !== null) {
      try {
        this.player.surfaceId = surfaceId;
      } catch (error) {
        console.warn(PLAYER_TAG, 'rebind surface failed: ' + (error as Error).message);
      }
      return;
    }
    if (this.pendingItem !== null) {
      this.startCurrent();
    }
  }

  play(item: DouYinPlaybackItem): void {
    if (item.urls.length === 0) {
      this.errorMessage = '没有可播放的地址';
      return;
    }
    this.currentAwemeID = item.awemeID;
    this.currentDescription = item.description;
    this.urls = item.urls;
    this.urlIndex = 0;
    this.pendingItem = item;
    this.pendingSeekMs = -1;
    this.errorMessage = '';
    if (this.surfaceId.length > 0) {
      this.startCurrent();
    }
  }

  playOrPause(): void {
    const player = this.player;
    if (player === null) { return; }
    const state = player.state;
    if (state === 'playing') {
      player.pause();
    } else if (state === 'paused' || state === 'prepared' || state === 'completed') {
      if (state === 'completed') { this.positionMs = 0; }
      player.play();
    }
  }

  seekTo(ms: number): void {
    const player = this.player;
    if (player === null) { return; }
    const state = player.state;
    if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
      const target = Math.max(0, Math.min(ms, this.durationMs > 0 ? this.durationMs : ms));
      this.positionMs = target;
      player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
    }
  }

  setSpeed(speed: number): void {
    const player = this.player;
    if (player === null) { return; }
    const state = player.state;
    if (state !== 'playing' && state !== 'paused') { return; }
    const target = speed >= 2 ? media.PlaybackSpeed.SPEED_FORWARD_2_00_X : media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    try {
      player.setSpeed(target);
      this.speed = speed >= 2 ? 2 : 1;
      console.info(PLAYER_TAG, 'speed=' + this.speed);
    } catch (error) {
      console.warn(PLAYER_TAG, 'setSpeed failed: ' + (error as Error).message);
      this.speed = 1;
    }
  }

  setLoopMode(mode: DouYinLoopMode): void {
    if (this.loopMode === mode) { return; }
    this.loopMode = mode;
    if (this.player !== null) {
      this.player.loop = mode === DouYinLoopMode.Single;
    }
    if (this.onLoopModeChanged !== null) {
      this.onLoopModeChanged(mode);
    }
  }

  setLayer(layer: DouYinMenuLayer): void {
    if (this.ui.layer === layer) { return; }
    this.ui.layer = layer;
    if (this.onLayerChanged !== null) {
      this.onLayerChanged(layer);
    }
  }

  setFullscreen(on: boolean): void {
    this.ui.fullscreen = on;
    if (!on) {
      this.ui.dragX = 0;
      this.ui.dragY = 0;
    }
    this.applyScaleType();
    console.info(PLAYER_TAG, 'fullscreen=' + on);
    if (this.onFullscreenChanged !== null) {
      this.onFullscreenChanged(on);
    }
  }

  setActive(active: boolean): void {
    if (this.active === active) { return; }
    this.active = active;
    const player = this.player;
    if (player === null) {
      // 页面在后台时挂载播放器：先记住待播项，回到前台再起播。
      if (active && this.pendingItem !== null && this.surfaceId.length > 0) {
        this.startCurrent();
      }
      return;
    }
    if (!active) {
      this.resumeOnActive = player.state === 'playing';
      if (this.resumeOnActive) { player.pause(); }
    } else if (this.resumeOnActive) {
      this.resumeOnActive = false;
      if (player.state === 'paused') { player.play(); }
    }
  }

  requestImmersive(want: boolean): void {
    if (this.ui.immersive === want) { return; }
    if (this.onImmersiveRequest !== null) {
      this.onImmersiveRequest(want);
      return;
    }
    this.ui.immersive = want;
  }

  release(): void {
    this.generation++;
    this.destroyPlayer();
    this.volume.release();
    this.pendingItem = null;
    this.pendingSeekMs = -1;
  }

  private notifyBusy(): void {
    if (this.onBusyChanged !== null) {
      this.onBusyChanged();
    }
  }

  private startCurrent(): void {
    if (this.urls.length === 0) { return; }
    this.generation++;
    const generation = this.generation;
    this.destroyPlayer();
    this.loading = true;
    this.playing = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.errorMessage = '';
    this.notifyBusy();
    if (!this.active) {
      this.loading = false;
      return;
    }
    (async () => {
      try {
        const player = await media.createAVPlayer();
        if (generation !== this.generation) {
          await player.release();
          return;
        }
        this.player = player;
        this.bindPlayer(player);
        const strategy: media.PlaybackStrategy = {
          preferredBufferDurationForPlaying: 0.3,
          preferredBufferDuration: 5,
          showFirstFrameOnPrepare: true
        };
        const source = media.createMediaSourceWithUrl(this.urls[this.urlIndex], DOUYIN_HEADERS);
        player.setMediaSource(source, strategy);
        console.info(PLAYER_TAG, `load index=${this.urlIndex} aweme=${this.currentAwemeID}`);
      } catch (error) {
        console.warn(PLAYER_TAG, 'create player failed: ' + (error as Error).message);
        this.handleUrlError();
      }
    })();
  }

  private bindPlayer(player: media.AVPlayer): void {
    player.on('error', (error: BusinessError) => {
      if (this.player !== player) { return; }
      console.warn(PLAYER_TAG, 'player error: ' + error.code + ' ' + error.message);
      this.handleUrlError();
    });
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (this.player !== player) { return; }
      if (state === 'initialized') {
        player.surfaceId = this.surfaceId;
        player.prepare();
      } else if (state === 'prepared') {
        player.loop = this.loopMode === DouYinLoopMode.Single;
        this.applyScaleType();
        player.play();
        if (this.pendingSeekMs > 0) {
          const resumeMs = this.pendingSeekMs;
          this.pendingSeekMs = -1;
          this.positionMs = resumeMs;
          player.seek(resumeMs, media.SeekMode.SEEK_PREV_SYNC);
          console.info(PLAYER_TAG, 'resume after fallback at ' + resumeMs + 'ms');
        }
      } else if (state === 'playing') {
        this.loading = false;
        this.playing = true;
        this.notifyBusy();
      } else if (state === 'paused') {
        this.playing = false;
        this.notifyBusy();
      } else if (state === 'completed') {
        this.playing = false;
        this.notifyBusy();
        if (this.loopMode === DouYinLoopMode.Sequence && this.onCompleted !== null) {
          this.onCompleted();
        }
      } else if (state === 'error') {
        this.handleUrlError();
      }
    });
    player.on('timeUpdate', (time: number) => {
      if (this.player !== player) { return; }
      this.positionMs = time;
    });
    player.on('durationUpdate', (duration: number) => {
      if (this.player !== player) { return; }
      this.durationMs = duration;
    });
    player.on('videoSizeChange', (width: number, height: number) => {
      if (this.player !== player) { return; }
      this.videoW = width;
      this.videoH = height;
    });
  }

  private handleUrlError(): void {
    // 换源前记住位置：新 URL 起播后 seek 回来，别让用户从头看。
    if (this.positionMs > 0) {
      this.pendingSeekMs = this.positionMs;
    }
    if (this.player !== null) {
      this.destroyPlayer();
    }
    if (this.urlIndex + 1 < this.urls.length) {
      this.urlIndex++;
      this.startCurrent();
      return;
    }
    this.loading = false;
    this.playing = false;
    this.errorMessage = '所有视频源均尝试失败，请重试';
    this.notifyBusy();
  }

  private applyScaleType(): void {
    const player = this.player;
    if (player === null) { return; }
    player.videoScaleType = this.ui.fullscreen
      ? media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP
      : media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
  }

  private destroyPlayer(): void {
    const player = this.player;
    this.player = null;
    if (player === null) { return; }
    try {
      player.off('stateChange');
      player.off('timeUpdate');
      player.off('durationUpdate');
      player.off('videoSizeChange');
      player.off('error');
    } catch (error) {
      console.debug(logTag, 'player listener cleanup failed');
    }
    player.release().catch(() => {
      console.debug(logTag, 'player release failed');
    });
  }
}
