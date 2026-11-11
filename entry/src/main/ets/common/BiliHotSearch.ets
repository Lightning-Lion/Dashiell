import { BiliResponseDecoder } from './bili/BiliResponseDecoder';
import { LogEvents } from '../utils/log/LogEvents.generated';

export interface BiliHotSearchItem {
  keyword: string;
  show_name?: string;
}

export function parseBiliHotSearch(text: string): BiliHotSearchItem[] {
  const report = BiliResponseDecoder.parseHotSearchReport(text);
  if (report.issues.length > 0 || report.skipped > 0) {
    const first = report.issues.length > 0 ? report.issues[0] : undefined;
    LogEvents.biliHotSearchSkipped({
      received: report.received,
      skipped: report.skipped,
      firstCode: first === undefined ? '' : first.code,
      firstPath: first === undefined ? '' : first.pathText(),
    });
  }
  return report.items;
}
