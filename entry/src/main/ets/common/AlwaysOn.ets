import { window } from '@kit.ArkUI';
import { ScreenOnCoordinator } from './ScreenOnCoordinator';

export type ScreenOnReason = 'feedLoading' | 'videoPlayback' | 'loadingRSS' | 'loadingRawHTML' |
  'convertingToReadingModeHTML' | 'douYinLoadingWebPage' | 'douYinPlayback' | 'douYinLoginWebLoading' |
  'douYinLoginProgressing' | 'nativeArticle' | 'articleLinkWeb';

export class DeviceMgr {
  private static instance: DeviceMgr | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;
  private coordinator: ScreenOnCoordinator = new ScreenOnCoordinator(async (enabled: boolean): Promise<void> => {
    const target = this.mainWindow ?? await window.getLastWindow(getContext());
    await target.setWindowKeepScreenOn(enabled);
  });

  private constructor() {}
  public static Ins(): DeviceMgr {
    if (DeviceMgr.instance === undefined) { DeviceMgr.instance = new DeviceMgr(); }
    return DeviceMgr.instance;
  }

  public async bindWindow(target: window.Window): Promise<void> {
    this.mainWindow = target;
    try { await this.coordinator.resetWindow(true); }
    catch (error) { console.warn('SCREEN_ON window initialization failed'); }
  }
  public async setForeground(foreground: boolean): Promise<void> {
    try { await this.coordinator.setForeground(foreground); }
    catch (error) { console.warn('SCREEN_ON foreground update failed'); }
  }
  public async requestKeepScreenOn(reason: ScreenOnReason, enabled: boolean, owner?: string): Promise<void> {
    try { await this.coordinator.request(owner === undefined ? reason : reason + ':' + owner, enabled); }
    catch (error) { console.warn('SCREEN_ON request failed'); }
  }
  public getUserKeepScreenRequest(reason: ScreenOnReason): boolean { return this.coordinator.hasRequest(reason); }
  public hasKeepScreenRequests(): boolean { return this.coordinator.hasRequests(); }
  public async isKeepScreenOn(): Promise<boolean> {
    const target = this.mainWindow ?? await window.getLastWindow(getContext());
    return target.getWindowProperties().isKeepScreenOn;
  }
}
