// UI-normalized home-feed types, separated from ArkUI components and untrusted wire models.
export class BiliHomeFeedApiResponse {
  code: number = 0;
  message: string = '';
  data?: BiliHomeFeedApiResponseData;
}
export class BiliHomeFeedApiResponseData {
  item: BiliHomeFeedApiResponseItem[] = [];
}
export class BiliHomeFeedApiResponseItem {
  id: string = '';
  bvid: string = '';
  cid: string = '';
  title: string = '';
  goto?: string;
  pic?: string;
  owner?: BiliHomeFeedApiResponseOwner;
  stat?: BiliHomeFeedApiResponseStat;
  duration?: number;
}
export class BiliHomeFeedApiResponseOwner {
  name: string = '';
  face?: string;
}
export class BiliHomeFeedApiResponseStat {
  view: number = 0;
  like: number = 0;
}
export class PlaybackSelection {
  url: string;
  backupUrl: string | undefined;
  constructor(url: string, backupUrl: string | undefined) { this.url = url; this.backupUrl = backupUrl; }
}
