import { DouyinFeedResponse } from './schema/DouyinModels.generated';
import { DouyinListSource } from './DouyinRequestBuilder';

export class DouyinNextPage {
  cursor: string;
  hasMore: boolean;
  constructor(cursor: string, hasMore: boolean) { this.cursor = cursor; this.hasMore = hasMore; }
}

/** Preserve 64-bit decimal cursor strings; never turn them into imprecise JS numbers. */
export class DouyinPagination {
  static next(data: DouyinFeedResponse, previous: string, source: DouyinListSource): DouyinNextPage {
    const max = String(data.maxCursor ?? '').trim();
    const next = max.length > 0 && max !== '0' ? max : String(data.cursor ?? '').trim();
    if (next.length > 0 && !/^\d+$/.test(next)) { throw new Error('Invalid response cursor'); }
    if (data.hasMore === 0 || data.hasMore === false) { return new DouyinNextPage(next, false); }
    if (next.length > 0) {
      const progresses = next !== previous && next !== '0';
      const advertisedMore = data.hasMore === true || (typeof data.hasMore === 'number' && data.hasMore > 0);
      if (!progresses && advertisedMore && source !== 'recommended') {
        throw new Error('Personal list cursor did not advance');
      }
      return new DouyinNextPage(next, progresses);
    }
    if (source === 'recommended') { return new DouyinNextPage('', data.items.length > 0); }
    if (data.hasMore === true || (typeof data.hasMore === 'number' && data.hasMore > 0)) {
      throw new Error('Personal list advertised another page without a cursor');
    }
    return new DouyinNextPage('', false);
  }
}
