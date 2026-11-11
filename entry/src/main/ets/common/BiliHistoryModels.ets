export interface BiliHistoryCursor {
  max: number;
  viewAt: number;
  business?: string;
}

export interface BiliHistoryListResponse {
  code: number;
  message: string;
  ttl: number;
  data?: BiliHistoryData;
}

export interface BiliHistoryData {
  cursor?: BiliHistoryCursor;
  tab?: BiliHistoryTab[];
  list?: BiliHistoryItem[];
}

export interface BiliHistoryTab {
  type: string;
  name: string;
}

export interface BiliHistoryItem {
  title: string;
  long_title?: string;
  cover?: string;
  uri?: string;
  history?: BiliHistoryItemHistory;
  videos?: number;
  author_name?: string;
  author_face?: string;
  author_mid?: number;
  view_at?: number;
  progress?: number;
  badge?: string;
  show_title?: string;
  duration?: number;
  is_finish?: number;
  is_fav?: number;
  kid?: number;
  tag_name?: string;
  live_status?: number;
  business?: string;
}

export interface BiliHistoryItemHistory {
  oid?: number;
  epid?: number;
  bvid?: string;
  page?: number;
  cid?: number;
  part?: string;
  business?: string;
}

export interface BiliHistoryApiResponse {
  code: number;
  message: string;
  ttl: number;
  data?: BiliHistoryApiData;
}

export interface BiliHistoryApiData {
  cursor?: BiliHistoryApiCursor;
  tab?: BiliHistoryApiTab[];
  list?: BiliHistoryApiItem[];
}

export interface BiliHistoryApiCursor {
  max?: number;
  view_at?: number;
  business?: string;
}

export interface BiliHistoryApiTab {
  type?: string;
  name?: string;
}

export interface BiliHistoryApiItem {
  title?: string;
  long_title?: string;
  cover?: string;
  uri?: string;
  history?: BiliHistoryApiItemHistory;
  videos?: number;
  author_name?: string;
  author_face?: string;
  author_mid?: number;
  view_at?: number;
  progress?: number;
  badge?: string;
  show_title?: string;
  duration?: number;
  is_finish?: number;
  is_fav?: number;
  kid?: number;
  tag_name?: string;
  live_status?: number;
  business?: string;
}

export interface BiliHistoryApiItemHistory {
  oid?: number;
  epid?: number;
  bvid?: string;
  page?: number;
  cid?: number;
  part?: string;
  business?: string;
}
