import { BusinessError } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { logTag } from './printLog';

@ObservedV2
export class WifiManager {
  // Compatibility name: availability includes Bluetooth tethering, not only Wi-Fi/5G.
  @Trace wifiOr5GFirst: boolean = false;
  // 诊断用的原始数据，供“网络诊断”页展示，方便用户对照或反馈。
  @Trace defaultNetId: number = -1;
  @Trace defaultNetBearers: string = '未探测';
  @Trace allNetsSummary: string = '未探测';
  @Trace lastProbeMs: number = 0;
  @Trace lastProbeError: string = '';
  private static instance?: WifiManager;
  private observer?: connection.NetConnection;
  private refreshing: boolean = false;
  private refreshPending: boolean = false;

  public static getInstance(): WifiManager {
    if (!WifiManager.instance) {
      WifiManager.instance = new WifiManager();
    }
    return WifiManager.instance;
  }

  /** 供“网络诊断”页手动触发一次重新探测。 */
  public probe(): void {
    this.refreshNetwork();
  }

  public startListenNetChange(): void {
    this.refreshNetwork();
    if (this.observer !== undefined) {
      return;
    }
    // Follow the system default network, including phone Bluetooth sharing.
    // Never pin process sockets/DNS to a Wi-Fi handle which expires on screen-off.
    const observer = connection.createNetConnection();
    this.observer = observer;
    observer.on('netAvailable', () => this.refreshNetwork());
    observer.on('netLost', () => this.refreshNetwork());
    observer.on('netCapabilitiesChange', () => this.refreshNetwork());
    observer.register((error: BusinessError) => {
      if (error) {
        console.debug(logTag, `Network observer registration failed: ${error.code}`);
        // Allow registration to be retried on next foreground entry.
        this.observer = undefined;
      }
    });
  }

  private refreshNetwork(): void {
    this.refreshPending = true;
    if (!this.refreshing) {
      this.drainNetworkChanges();
    }
  }

  private async drainNetworkChanges(): Promise<void> {
    this.refreshing = true;
    try {
      // A change during an await must not be dropped: query the latest route again.
      while (this.refreshPending) {
        this.refreshPending = false;
        try {
          const network = await connection.getDefaultNet();
          const available = network !== undefined && network !== null && network.netId > 0;
          this.wifiOr5GFirst = available;
          this.lastProbeMs = Date.now();
          this.lastProbeError = '';
          if (available) {
            this.defaultNetId = network.netId;
            this.defaultNetBearers = WifiManager.bearerOf(network);
          } else {
            this.defaultNetId = -1;
            this.defaultNetBearers = '无默认网络';
          }
          try {
            const all = await connection.getAllNets();
            const list = all ?? [];
            this.allNetsSummary = list.length === 0
              ? '（无）'
              : list.map((n: connection.NetHandle): string =>
                  `netId ${n.netId}: ${WifiManager.bearerOf(n)}`).join('\n');
          } catch (inner) {
            this.allNetsSummary = '读取失败: ' + WifiManager.errText(inner);
          }
        } catch (error) {
          // A monitor failure does not prove that application requests cannot connect.
          this.lastProbeError = WifiManager.errText(error);
          console.debug(logTag, 'Unable to inspect default network');
        }
      }
    } finally {
      this.refreshing = false;
    }
  }

  /** 取某个网络句柄的 bearer 类型并转成人话；getNetCapabilitiesSync 失败时降级为“未知”。 */
  private static bearerOf(handle: connection.NetHandle): string {
    try {
      return WifiManager.bearerNames(connection.getNetCapabilitiesSync(handle).bearerTypes);
    } catch (error) {
      return '未知';
    }
  }

  /** 把 bearerTypes 枚举翻成人话；未知类型回落到数字，避免依赖不存在的枚举成员。 */
  private static bearerNames(bearers?: connection.NetBearType[]): string {
    if (bearers === undefined || bearers === null || bearers.length === 0) {
      return '未知';
    }
    return bearers.map((b: connection.NetBearType): string => {
      switch (b) {
        case connection.NetBearType.BEARER_CELLULAR: return '蜂窝';
        case connection.NetBearType.BEARER_WIFI: return 'Wi-Fi';
        case connection.NetBearType.BEARER_BLUETOOTH: return '蓝牙';
        case connection.NetBearType.BEARER_ETHERNET: return '以太网';
        case connection.NetBearType.BEARER_VPN: return 'VPN';
        default: return `类型${b}`;
      }
    }).join(' + ');
  }

  private static errText(error: Error): string {
    const e = error as BusinessError;
    return `${e.code ?? ''} ${e.message ?? ''}`.trim() || JSON.stringify(error);
  }
}
