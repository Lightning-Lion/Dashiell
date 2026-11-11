// API reference: pskdje/bilibili-API-collect, docs/fav/{info,list,action}.md (master).
export interface FavoriteFolder {
  id: number;
  title: string;
  attr: number;
  media_count: number;
  fav_state?: number;
  intro?: string;
  cover?: string;
}

export interface FavoriteFoldersResponse {
  code: number;
  message: string;
  data: FavoriteFoldersData;
}

export interface FavoriteFoldersData {
  count: number;
  list: FavoriteFolder[] | null;
}

export interface FavoriteMedia {
  id: number;
  type: number;
  title: string;
  cover: string;
  attr: number;
  bvid?: string;
  bv_id?: string;
  duration: number;
  upper?: FavoriteUpper;
  cnt_info?: FavoriteCounts;
}

export interface FavoriteCounts {
  play: number;
}

export interface FavoriteUpper {
  name: string;
}

export interface FavoriteContentsResponse {
  code: number;
  message: string;
  data: FavoriteContentsData;
}

export interface FavoriteContentsData {
  info: FavoriteFolder;
  medias: FavoriteMedia[] | null;
  has_more: boolean;
}

export interface FavoriteFolderResponse {
  code: number;
  message: string;
  data: FavoriteFolder;
}

export interface FavoriteResponse {
  code: number;
  message: string;
}

export interface FavoriteChanges {
  add: number[];
  remove: number[];
}

export function getFavoriteChanges(original: number[], selected: number[]): FavoriteChanges {
  return {
    add: selected.filter(id => !original.includes(id)),
    remove: original.filter(id => !selected.includes(id))
  };
}

export function favoriteVideoId(media: FavoriteMedia): string {
  return media.bvid || media.bv_id || '';
}

export function canPlayFavorite(media: FavoriteMedia): boolean {
  return media.type === 2 && (media.attr & 1) === 0 && favoriteVideoId(media).length > 0;
}
