import { UIContext } from '@kit.ArkUI';

export function requestFocusWithRetry(_context: UIContext, _id: string): void {
  // The list may not be attached yet from onShown/onAppear. Request once now
  // and once after the first render so the crown is usable immediately.
  const request = (): void => {
    try {
      _context.getFocusController().requestFocus(_id);
    } catch (error) {
      const failure = error as Error;
      console.debug(`[WatchListFocus] requestFocus failed: ${failure.message || String(error)}`);
    }
  };
  request();
  setTimeout(request, 100);
}

export function focusWatchList(context: UIContext, id: string): void {
  requestFocusWithRetry(context, id);
}
