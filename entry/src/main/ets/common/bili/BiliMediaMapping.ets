import { PlaybackPart } from './BiliPlaybackQueue';
import { BiliHomeResponse, BiliHomeItem, BiliPlaybackResponse } from './schema/BiliModels.generated';
import { BiliHomeFeedApiResponse, BiliHomeFeedApiResponseData, BiliHomeFeedApiResponseItem,
  BiliHomeFeedApiResponseOwner, BiliHomeFeedApiResponseStat, PlaybackSelection } from './BiliMediaModels';

export class BiliMediaMapping {
  static isHomePlaceholder(item: BiliHomeItem): boolean {
    // Zero IDs alone do not identify placeholders: malformed videos must fail validation.
    return item.goto === 'ad' || item.goto === 'login_card';
  }

  // Called only after BiliMediaDecoder validates both schema and video-required fields.
  static home(model: BiliHomeResponse): BiliHomeFeedApiResponse {
    const response = new BiliHomeFeedApiResponse();
    response.code = model.code;
    response.message = model.message ?? '';
    const data = new BiliHomeFeedApiResponseData();
    for (const item of model.data.item) {
      if (BiliMediaMapping.isHomePlaceholder(item)) { continue; }
      const video = new BiliHomeFeedApiResponseItem();
      video.id = typeof item.id === 'string' ? item.id : String(item.id);
      video.bvid = item.bvid ?? '';
      video.cid = typeof item.cid === 'string' ? item.cid : String(item.cid);
      video.title = item.title || 'No Title';
      video.goto = item.goto;
      video.pic = item.pic ?? undefined;
      video.duration = item.duration;
      if (item.owner !== null && item.owner !== undefined) {
        const owner = new BiliHomeFeedApiResponseOwner();
        owner.name = item.owner.name ?? '';
        owner.face = item.owner.face ?? undefined;
        video.owner = owner;
      }
      if (item.stat !== null && item.stat !== undefined) {
        const stat = new BiliHomeFeedApiResponseStat();
        stat.view = item.stat.view ?? 0;
        stat.like = item.stat.like ?? 0;
        video.stat = stat;
      }
      data.item.push(video);
    }
    response.data = data;
    return response;
  }

  static playbackParts(model: BiliPlaybackResponse): PlaybackPart[] {
    const segments = model.data.durl.slice();
    const orders = segments.map((segment) => segment.order ?? 0);
    if (orders.every((order: number) => Number.isInteger(order) && order > 0) &&
      new Set(orders).size === segments.length) {
      segments.sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
    }
    return segments.map((segment): PlaybackPart => {
      const addresses: string[] = [];
      for (const value of [segment.url ?? '', ...segment.backup_url ?? []]) {
        const address = value.trim();
        if (address.length > 0 && !addresses.includes(address)) { addresses.push(address); }
      }
      const milliseconds = segment.length ?? (segments.length === 1 ? model.data.timelength : 0);
      return new PlaybackPart(addresses, milliseconds > 0 ? milliseconds / 1000 : 0);
    });
  }

  static playback(model: BiliPlaybackResponse): PlaybackSelection {
    const first = BiliMediaMapping.playbackParts(model)[0];
    return new PlaybackSelection(first?.urls[0] ?? '', first?.urls[1]);
  }
}
