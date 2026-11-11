import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { logTag } from '../../common/printLog';

const SURFACE_TAG = '🎬抖音视频节点';

class VideoSurfaceParams {
  controller: XComponentController = new XComponentController();
  onReady: ((surfaceId: string) => void) | null = null;
}

@Builder
function douYinVideoSurfaceBuilder(params: VideoSurfaceParams) {
  XComponent({
    id: 'douyin-live-video-surface',
    type: XComponentType.SURFACE,
    controller: params.controller
  })
    .width('100%')
    .height('100%')
    .onLoad(() => {
      const id = params.controller.getXComponentSurfaceId();
      console.info(SURFACE_TAG, 'surface ready id=' + id);
      params.onReady?.(id);
    })
}

/**
 * 槽位控制器：NodeContainer 通过它挂载/卸载同一个视频节点。
 * 迁移时先源槽 attach(null)，再目标槽 attach(node)，节点本身不销毁。
 */
export class VideoSlotController extends NodeController {
  private node: FrameNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    return this.node;
  }

  attach(node: FrameNode | null): void {
    this.node = node;
    try {
      this.rebuild();
    } catch (error) {
      console.warn(SURFACE_TAG, 'slot rebuild failed: ' + error.message);
    }
  }
}

/**
 * 整个播放器只有一个视频节点、一个 surface。
 * 外页聚焦卡片、内页各自提供一个槽位，节点在两者之间迁移。
 */
export class DouYinVideoSurfaceHost {
  private builder: BuilderNode<[VideoSurfaceParams]> | null = null;
  private readonly params: VideoSurfaceParams = new VideoSurfaceParams();
  onSurface: ((surfaceId: string) => void) | null = null;

  build(ctx: UIContext): void {
    if (this.builder !== null) { return; }
    this.params.onReady = (surfaceId: string) => {
      this.onSurface?.(surfaceId);
    };
    const builder = new BuilderNode<[VideoSurfaceParams]>(ctx);
    builder.build(wrapBuilder(douYinVideoSurfaceBuilder), this.params);
    this.builder = builder;
    console.info(SURFACE_TAG, 'BuilderNode built');
  }

  frame(): FrameNode | null {
    return this.builder?.getFrameNode() ?? null;
  }

  dispose(): void {
    this.builder?.dispose();
    this.builder = null;
    console.info(logTag, SURFACE_TAG + ' disposed');
  }
}
