/** Shared foreground state; a hidden watch app must not continue decoding video. */
@ObservedV2
export class PlaybackLifecycle {
  @Trace foreground: boolean = true;
}
export const playbackLifecycle: PlaybackLifecycle = new PlaybackLifecycle();
