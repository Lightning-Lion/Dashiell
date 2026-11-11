import { DeviceMgr } from '../common/AlwaysOn';
import { playbackLifecycle } from '../common/PlaybackLifecycle';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want, bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WifiManager } from '../common/WiFiManager';
import { DouyinCookieDebugImport } from '../common/douyin/DouyinCookieDebugImport';
import { RssSubscriptionDebugProbe } from '../common/dev/RssSubscriptionDebugProbe';
import { DevFlags } from '../common/dev/DevFlags';
import { AppDatabase } from '../common/storage/AppDatabase';
import { DATABASE_VERSION } from '../common/storage/DatabaseSchema';
import { LogEvents } from '../utils/log/LogEvents.generated';
import { Logger } from '../utils/log/Logger';
import { L } from '../utils/log/LogCore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let version: string = '';
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      version = `${info.versionName}(${info.versionCode})`;
    } catch (_) {
      version = '';
    }
    try {
      Logger.init({ debug: DevFlags.isDebugBuild, appVersion: version });
      Logger.getConfig().extraMaskKeys = [
        'sessdata', 'bili_jct', 'dedeuserid', 'ttwid', 'odin_tt', 'ms_token',
        'passport_csrf_token',
      ];
      const env = Logger.getEnv();
      LogEvents.appCreate({
        version: env.appVersion,
        debug: env.debug,
        device: env.device,
        api: env.apiVersion,
        session: env.sessionId,
      });
    } catch (error) {
      // 日志初始化失败不能阻断启动。
      hilog.error(DOMAIN, 'testTag', 'Logger init failed: %{public}s', String(error));
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      LogEvents.colorModeFailed(error);
    }
    // Debug-only explicit action; release builds ignore it. See docs/debug-config.md.
    DouyinCookieDebugImport.handle(this.context, want.action, want.parameters, 'onCreate');
    // Debug-only: --ps probe rss-add|rss-list|rss-clear 读写订阅表，验证「添加 RSS 源」持久化链路。
    RssSubscriptionDebugProbe.handle(this.context, want.parameters, 'onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Warm start (app already running) receives the import Want here instead of onCreate.
    DouyinCookieDebugImport.handle(this.context, want.action, want.parameters, 'onNewWant');
    RssSubscriptionDebugProbe.handle(this.context, want.parameters, 'onNewWant');
    Logger.info('App', L('应用接收到新的 Want', 'app received new want'));
  }

  onDestroy(): void {
    playbackLifecycle.foreground = false;
    DeviceMgr.Ins().setForeground(false);
    LogEvents.appDestroy();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    LogEvents.windowStageCreate();

    DeviceMgr.Ins().bindWindow(windowStage.getMainWindowSync());
    const entryPage: string = 'pages/Index';
    // 首次启动/升级：先打开 RDB 并完成一次性迁移，再上屏；失败也继续上屏，由各读取点回退默认值。
    (async () => {
      try {
        await AppDatabase.open(this.context);
        LogEvents.dbOpenOk({ version: DATABASE_VERSION });
      } catch (error) {
        LogEvents.dbOpenFailed(error);
      }
      windowStage.loadContent(entryPage, (err) => {
        if (err.code) {
          LogEvents.loadContentFailed({ page: entryPage }, err);
          return;
        }
        LogEvents.loadContentOk({ page: entryPage });
      });
    })();
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    LogEvents.windowStageDestroy();
  }

  onForeground(): void {
    playbackLifecycle.foreground = true;
    DeviceMgr.Ins().setForeground(true);
    // Ability has brought to foreground
    WifiManager.getInstance().startListenNetChange();
    LogEvents.appForeground();
  }

  onBackground(): void {
    playbackLifecycle.foreground = false;
    DeviceMgr.Ins().setForeground(false);
    // Ability has back to background
    LogEvents.appBackground();
  }
}
