import { common } from '@kit.AbilityKit';
import { logTag } from '../printLog';
import { AppDatabase } from '../storage/AppDatabase';
import { StorageKeys, StorageNamespaces } from '../storage/StorageKeys';

const LOOP_MODE_SINGLE: string = 'single';
const LOOP_MODE_SEQUENCE: string = 'sequence';

/**
 * 抖音播放器设置：循环模式。存 RDB，重启后保留。
 */
export class DouYinPlaybackPrefs {
  static async loadLoopMode(context: common.UIAbilityContext): Promise<string> {
    try {
      const db = await AppDatabase.open(context);
      const value = await db.values.getString(StorageKeys.DOUYIN_LOOP_MODE, LOOP_MODE_SINGLE);
      return value === LOOP_MODE_SEQUENCE ? LOOP_MODE_SEQUENCE : LOOP_MODE_SINGLE;
    } catch (error) {
      console.debug(logTag, 'load douyin loop mode failed: ' + DouYinPlaybackPrefs.describe(error));
      return LOOP_MODE_SINGLE;
    }
  }

  static async saveLoopMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    if (mode !== LOOP_MODE_SINGLE && mode !== LOOP_MODE_SEQUENCE) {
      console.debug(logTag, 'ignore invalid douyin loop mode');
      return;
    }
    try {
      const db = await AppDatabase.open(context);
      await db.values.setString(StorageKeys.DOUYIN_LOOP_MODE, StorageNamespaces.SETTING, mode);
    } catch (error) {
      console.debug(logTag, 'save douyin loop mode failed: ' + DouYinPlaybackPrefs.describe(error));
    }
  }

  private static describe(error: Object): string {
    const message = (error as Error).message;
    return message === undefined ? 'unknown' : message;
  }
}
