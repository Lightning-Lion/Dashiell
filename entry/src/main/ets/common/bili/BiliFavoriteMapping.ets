import { BiliFavoriteFolder, BiliFavoriteMedia, BiliFavoriteFoldersResponse, BiliFavoriteContentsResponse } from './schema/BiliModels.generated';
import { FavoriteFolder, FavoriteMedia, FavoriteFoldersResponse, FavoriteContentsResponse, FavoriteUpper, FavoriteCounts } from '../BiliFavoriteModels';

/** Explicit UI mapping after schema success; empty-list normalization never hides invalid types. */
export class BiliFavoriteMapping {
  static folder(value: BiliFavoriteFolder): FavoriteFolder {
    return { id: value.id, title: value.title, attr: value.attr, media_count: value.media_count,
      fav_state: value.fav_state, intro: value.intro, cover: value.cover };
  }
  static media(value: BiliFavoriteMedia): FavoriteMedia {
    let upper: FavoriteUpper | undefined = undefined;
    let counts: FavoriteCounts | undefined = undefined;
    if (value.upper !== undefined) { upper = { name: value.upper.name }; }
    if (value.cnt_info !== undefined) { counts = { play: value.cnt_info.play }; }
    return { id: value.id, type: value.type, title: value.title, cover: value.cover, attr: value.attr,
      bvid: value.bvid, bv_id: value.bv_id, duration: value.duration, upper: upper, cnt_info: counts };
  }
  static folders(value: BiliFavoriteFoldersResponse): FavoriteFoldersResponse {
    return { code: value.code, message: value.message ?? '', data: {
      count: value.data?.count ?? 0,
      list: (value.data?.list ?? []).map((folder: BiliFavoriteFolder): FavoriteFolder => BiliFavoriteMapping.folder(folder))
    } };
  }
  static contents(value: BiliFavoriteContentsResponse): FavoriteContentsResponse {
    return { code: value.code, message: value.message ?? '', data: {
      info: BiliFavoriteMapping.folder(value.data.info),
      medias: (value.data.medias ?? []).map((media: BiliFavoriteMedia): FavoriteMedia => BiliFavoriteMapping.media(media)),
      has_more: value.data.has_more
    } };
  }
}
