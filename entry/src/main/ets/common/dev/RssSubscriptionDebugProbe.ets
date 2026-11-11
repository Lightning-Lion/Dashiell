import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logTag } from '../printLog';
import { DevFlags } from './DevFlags';
import { AppDatabase } from '../storage/AppDatabase';

/**
 * 调试用 Want：不点界面就能读写 RSS 订阅表，用来验证「添加 RSS 源」的持久化链路。
 *
 * 只在 debug 构建生效；release 构建收到同一参数也只记一条忽略日志。
 * 这里刻意用 @ObservedV2 + @Trace 的代理数组调用 `replaceOrder`，
 * 复现界面里 `enabledRSSItemsId` 的真实入参形状（曾导致 RDB 绑定参数变 0、整条事务回滚）。
 * 结果写到私有 result 文件，供 hdc 直接 cat；命令见 docs/debug-config.md。
 */

export const RSS_DEBUG_PROBE_KEY: string = 'probe';
export const RSS_DEBUG_STABLE_ID_KEY: string = 'stableId';
export const RSS_DEBUG_MODE_ADD: string = 'rss-add';
export const RSS_DEBUG_MODE_LIST: string = 'rss-list';
export const RSS_DEBUG_MODE_CLEAR: string = 'rss-clear';
export const RSS_DEBUG_RESULT_FILE: string = 'rss-debug-result.json';
// 知乎热榜：HomePageRSSList 的 insertableURLs 里真实存在的 stableId，添加后界面能正常显示。
export const RSS_DEBUG_DEFAULT_STABLE_ID: string = '0e229179-64a1-416f-811d-3ddf22b91b2d';

export interface RssDebugResult {
  ok: boolean;
  mode: string;
  origin: string;
  requested: string;
  before: string[];
  after: string[];
  reason: string;
  timestamp: string;
}

/** 复现界面入参：ArkUI V2 里 @Trace 数组是代理对象，不能直接交给 relationalStore。 */
@ObservedV2
class TrackedStableIds {
  @Trace ids: string[] = [];
}

export class RssSubscriptionDebugProbe {
  /** EntryAbility 的 onCreate/onNewWant 调用；不抛异常，失败只记 result 文件。 */
  static handle(context: common.Context, parameters: Record<string, Object> | undefined,
    origin: string): void {
    const mode = RssSubscriptionDebugProbe.stringParam(parameters, RSS_DEBUG_PROBE_KEY);
    if (mode === undefined || !mode.startsWith('rss-')) {
      return;
    }
    if (!DevFlags.isDebugBuild) {
      console.debug(logTag, 'rss debug probe ignored: release build');
      return;
    }
    const stableId = RssSubscriptionDebugProbe.stringParam(parameters, RSS_DEBUG_STABLE_ID_KEY);
    RssSubscriptionDebugProbe.run(context, mode, stableId === undefined ? '' : stableId, origin)
      .catch((error: Object): void => {
        console.debug(logTag, 'rss debug probe failed: ' + RssSubscriptionDebugProbe.describe(error));
      });
  }

  private static async run(context: common.Context, mode: string, stableId: string,
    origin: string): Promise<RssDebugResult> {
    let result: RssDebugResult = {
      ok: false, mode: mode, origin: origin, requested: stableId,
      before: [], after: [], reason: '', timestamp: new Date().toISOString()
    };
    try {
      const db = await AppDatabase.open(context);
      const before = await db.rssSubscriptions.getAll();
      result.before = before;
      if (mode === RSS_DEBUG_MODE_ADD) {
        const target = stableId.length > 0 ? stableId : RSS_DEBUG_DEFAULT_STABLE_ID;
        result.requested = target;
        const tracked = new TrackedStableIds();
        for (const id of before) {
          tracked.ids.push(id);
        }
        if (tracked.ids.indexOf(target) < 0) {
          tracked.ids.unshift(target);
        }
        // 真实入口：与界面点「添加」走同一条 repository/DAO/bind 链路。
        await db.rssSubscriptions.replaceOrder(tracked.ids);
      } else if (mode === RSS_DEBUG_MODE_CLEAR) {
        await db.rssSubscriptions.replaceOrder([]);
      } else if (mode !== RSS_DEBUG_MODE_LIST) {
        result.reason = 'unknown mode';
        RssSubscriptionDebugProbe.publish(context, result);
        return result;
      }
      result.after = await db.rssSubscriptions.getAll();
      result.ok = true;
    } catch (error) {
      result.reason = RssSubscriptionDebugProbe.describe(error);
    }
    RssSubscriptionDebugProbe.publish(context, result);
    return result;
  }

  private static publish(context: common.Context, result: RssDebugResult): void {
    console.debug(logTag, 'rss debug ' + JSON.stringify(result));
    try {
      const path = RssSubscriptionDebugProbe.appFilesDir(context) + '/' + RSS_DEBUG_RESULT_FILE;
      RssSubscriptionDebugProbe.writeAtomic(path, JSON.stringify(result, null, 2));
    } catch (_) {
      // 诊断文件写失败不能影响启动流程。
    }
  }

  private static writeAtomic(path: string, text: string): void {
    const temporary = path + '.tmp';
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    try {
      fs.renameSync(temporary, path);
    } catch (_) {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      fs.renameSync(temporary, path);
    }
  }

  private static appFilesDir(context: common.Context): string {
    try {
      return context.getApplicationContext().filesDir;
    } catch (_) {
      return context.filesDir;
    }
  }

  private static stringParam(parameters: Record<string, Object> | undefined, key: string): string | undefined {
    if (parameters === undefined) {
      return undefined;
    }
    const value = parameters[key];
    return typeof value === 'string' ? value as string : undefined;
  }

  private static describe(error: Object): string {
    const typed = error as Error;
    return typed.message === undefined ? JSON.stringify(error) : typed.message;
  }
}
