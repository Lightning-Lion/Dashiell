import { vibrator } from '@kit.SensorServiceKit';
import { logTag } from './printLog';

const HAPTIC_TAG = '👑抖音触感';

/**
 * 表冠推卡的触感：
 * - 齿感用 haptic.effect.hard（“硬”，近似 Rigid），每 80ms 最多一次；
 * - 落位用 haptic.effect.sharp（脆），每次落位一次；
 * - 到头用 sharp，300ms 内不重复。
 * 设备不支持时静默降级，绝不影响表冠逻辑。
 */
export class Haptic {
  private static hardSupported: boolean | null = null;
  private static sharpSupported: boolean | null = null;
  private static lastTickMs: number = 0;
  private static lastCommitMs: number = 0;
  private static lastEdgeMs: number = 0;

  static tick(): void {
    const now = Date.now();
    if (now - Haptic.lastTickMs < 80) { return; }
    Haptic.lastTickMs = now;
    Haptic.play(vibrator.HapticFeedback.EFFECT_HARD, 12);
  }

  static commit(): void {
    const now = Date.now();
    if (now - Haptic.lastCommitMs < 120) { return; }
    Haptic.lastCommitMs = now;
    Haptic.play(vibrator.HapticFeedback.EFFECT_SHARP, 22);
  }

  static edge(): void {
    const now = Date.now();
    if (now - Haptic.lastEdgeMs < 300) { return; }
    Haptic.lastEdgeMs = now;
    Haptic.play(vibrator.HapticFeedback.EFFECT_SHARP, 18);
  }

  private static play(effectId: string, duration: number): void {
    if (!Haptic.supports(effectId)) {
      Haptic.timeVibrate(duration);
      return;
    }
    try {
      vibrator.startVibration({ type: 'preset', effectId: effectId }, { usage: 'touch' })
        .catch((error: Error) => {
          console.debug(HAPTIC_TAG, 'preset vibration rejected: ' + error.message);
        });
    } catch (error) {
      console.debug(HAPTIC_TAG, 'preset vibration threw: ' + error.message);
      Haptic.timeVibrate(duration);
    }
  }

  private static timeVibrate(duration: number): void {
    try {
      vibrator.startVibration({ type: 'time', duration: duration }, { usage: 'touch' })
        .catch((error: Error) => {
          console.debug(HAPTIC_TAG, 'time vibration rejected: ' + error.message);
        });
    } catch (error) {
      console.debug(HAPTIC_TAG, 'time vibration threw: ' + error.message);
    }
  }

  private static supports(effectId: string): boolean {
    if (effectId === vibrator.HapticFeedback.EFFECT_HARD) {
      if (Haptic.hardSupported === null) {
        Haptic.hardSupported = Haptic.query(effectId);
      }
      return Haptic.hardSupported;
    }
    if (effectId === vibrator.HapticFeedback.EFFECT_SHARP) {
      if (Haptic.sharpSupported === null) {
        Haptic.sharpSupported = Haptic.query(effectId);
      }
      return Haptic.sharpSupported;
    }
    return Haptic.query(effectId);
  }

  private static query(effectId: string): boolean {
    try {
      return vibrator.isSupportEffectSync(effectId);
    } catch (error) {
      console.debug(logTag, HAPTIC_TAG + ' support query failed: ' + error.message);
      return false;
    }
  }
}
