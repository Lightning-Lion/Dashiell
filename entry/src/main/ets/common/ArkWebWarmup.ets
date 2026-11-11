/**
 * ArkWeb cold-start warm-up.
 *
 * Creating the first Web component of a process is what loads the web engine — on a watch that
 * cost lands entirely inside the first page load, which is why a hidden challenge page can take
 * tens of seconds before it has anything to show. `initializeWebEngine` does that engine work up
 * front, but only while no Web component exists yet, so the useful place to call it is a page
 * that is shown *before* the first Web: the list the reader picks a link from.
 *
 * `prepareForPageLoad` additionally resolves DNS and opens TLS sockets for an origin the reader
 * is about to open, so the navigation itself starts on an established connection.
 */

import { webview } from '@kit.ArkWeb';

/** Sockets to preconnect. Two is enough for the navigation plus its first sub-resource. */
const PRECONNECT_SOCKETS = 2;

/** Only ever effective once per process; kept so a Web that already exists is not re-initialized. */
let engineInitialized: boolean = false;

/**
 * Prepares the web engine and one origin for a Web that the reader has not opened yet.
 * Safe to call on every appearance of a page; failures are non-fatal by design (a cold Web
 * still loads, just slower), so they are swallowed.
 */
export function warmUpArkWeb(preconnectURL: string): void {
  if (!engineInitialized) {
    try {
      webview.WebviewController.initializeWebEngine();
      engineInitialized = true;
    } catch (_) {
      // Engine already up (any existing Web component) or not on the UI thread: nothing to do.
    }
  }
  if (preconnectURL.length > 0) {
    try {
      webview.WebviewController.prepareForPageLoad(preconnectURL, true, PRECONNECT_SOCKETS);
    } catch (_) {
      // Invalid URL or socket count; the navigation still works without a warm connection.
    }
  }
}
