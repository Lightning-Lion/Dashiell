import { BilibiliService } from './BiliService';

let currentService: BilibiliService | null = null;

export function setCurrentBiliService(service: BilibiliService): void {
  if (service.isReleased() || !service.isSessionCurrent()) { throw new Error('账号服务已失效，请重新验证登录'); }
  currentService = service;
}

export function getCurrentBiliService(): BilibiliService | null {
  if (currentService !== null && (currentService.isReleased() || !currentService.isSessionCurrent())) {
    currentService.releaseHttp();
    currentService = null;
  }
  return currentService;
}

/**
 * 路由参数可能被物化成普通对象而丢掉 BilibiliService 的方法，所以先验证候选对象，
 * 不可用时再回落到进程内当前登录服务。返回 null 表示当前没有可用的登录态。
 */
export function resolveAuthenticatedBiliService(candidate?: BilibiliService | null): BilibiliService | null {
  if (candidate instanceof BilibiliService && !candidate.isReleased() && candidate.isSessionCurrent()) {
    return candidate;
  }
  return getCurrentBiliService();
}

export function clearCurrentBiliService(): void {
  currentService?.releaseHttp();
  currentService = null;
}
