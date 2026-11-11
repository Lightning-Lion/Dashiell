import { DouyinAwemeItem, DouyinPlayAddress, DouyinFeedResponse } from './schema/DouyinModels.generated';
import { DouYinRecommandAwemeData, DouYinRecommandAwemeItem, DouYinRecommandVideoPlayAddr } from '../../pages/DouYin/DouYinWebView';

/** Temporary bridge to existing UI DTOs. Only validated models enter this boundary. */
export class DouyinFeedMapping {
  private static address(value: DouyinPlayAddress | null | undefined): DouYinRecommandVideoPlayAddr {
    // Absence of an alternate encoding is valid; an incorrectly typed encoding never reaches here.
    return { url_list: value === null || value === undefined ? [] : value.urls };
  }

  static item(value: DouyinAwemeItem): DouYinRecommandAwemeItem | undefined {
    const video = value.video;
    if (video === undefined || video === null) { return undefined; }
    return {
      aweme_id: value.id,
      preview_title: value.previewTitle ?? '',
      desc: value.desc,
      video: {
        play_addr_h264: DouyinFeedMapping.address(video.h264),
        play_addr: DouyinFeedMapping.address(video.standard),
        play_addr_lowbr: DouyinFeedMapping.address(video.lowBitrate),
        play_addr_265: DouyinFeedMapping.address(video.hevc)
      }
    };
  }

  static feed(value: DouyinFeedResponse): DouYinRecommandAwemeData {
    return DouyinFeedMapping.items(value.items);
  }

  static items(values: DouyinAwemeItem[]): DouYinRecommandAwemeData {
    const items: DouYinRecommandAwemeItem[] = [];
    for (const item of values) {
      const mapped = DouyinFeedMapping.item(item);
      if (mapped !== undefined) { items.push(mapped); }
    }
    console.info('DOUYIN_NATIVE mapping received=' + values.length + ' nonVideo=' + (values.length - items.length));
    return { aweme_list: items };
  }
}
