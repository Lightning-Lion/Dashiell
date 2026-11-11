// GENERATED from tests/jsonschema/expansion-cases.json.
import { describe, it, expect } from '@ohos/hypium';
import { DecodeIssue, JsonDecodeError } from '../main/ets/common/jsonschema/JsonDecode';
import { BiliResponseDecoder } from '../main/ets/common/bili/BiliResponseDecoder';
import { BiliMediaDecoder } from '../main/ets/common/bili/BiliMediaDecoder';
import { DouyinResponseDecoder } from '../main/ets/common/douyin/DouyinResponseDecoder';
import { LocalDataDecoder } from '../main/ets/common/local/LocalDataDecoder';
import { jsReturnValueToString, jsReturnValueToNumber, jsReturnValueToBoolean } from '../main/ets/common/WebViewExtension';
export default function jsonSchemaExpansionFixturesTest() {
  describe('JsonSchemaExpansionFixtures', () => {
    it("webFeedSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = DouyinResponseDecoder.parseWebFeed("{\"aweme_list\":[{\"aweme_id\":\"1\",\"video\":{\"play_addr\":{\"url_list\":[\"https://example.com/v\"]}}}]}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("wbiSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseWbi("{\"code\":0,\"data\":{\"wbi_img\":{\"img_url\":\"https://example.com/a.png\",\"sub_url\":\"https://example.com/b.png\"}}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("upVideosSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"code\":0,\"data\":{\"list\":{\"vlist\":[{\"aid\":1,\"bvid\":\"BV1\",\"title\":\"t\",\"pic\":\"p\",\"author\":\"a\"}]}}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("favFoldersSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("{\"code\":0,\"data\":{\"count\":1,\"list\":[{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1}]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("favContentsSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteContents("{\"code\":0,\"data\":{\"info\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1},\"medias\":[{\"id\":2,\"type\":2,\"title\":\"test\",\"cover\":\"https://example.com/c\",\"attr\":0,\"duration\":60,\"bvid\":\"BVtest\",\"upper\":{\"name\":\"u\"},\"cnt_info\":{\"play\":3}}],\"has_more\":false}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("favFolderSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolder("{\"code\":0,\"data\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("favoriteStateSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteState("{\"code\":0,\"data\":{\"favoured\":true}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("historySuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseHistory("{\"code\":0,\"data\":{\"cursor\":{\"max\":1,\"view_at\":2},\"tab\":[{\"type\":\"archive\",\"name\":\"video\"}],\"list\":[{\"title\":\"a\",\"history\":{\"bvid\":\"BV1\",\"cid\":1},\"progress\":-1}]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("midSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseMid("{\"code\":0,\"data\":{\"mid\":123}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("actionSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseActionResponse("{\"code\":0,\"message\":\"0\"}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("likeStateSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseLikeStateResponse("{\"code\":0,\"data\":1}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("coinStateSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseCoinStateResponse("{\"code\":0,\"data\":{\"multiply\":2}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("insertCoinSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseInsertCoinResponse("{\"code\":0,\"data\":{\"like\":false}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("userStatSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserStatResponse("{\"code\":0,\"data\":{\"following\":1,\"follower\":2,\"dynamic_count\":3}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("userCardSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserCardResponse("{\"code\":0,\"data\":{\"card\":{\"following\":1,\"follower\":2},\"following\":false,\"follower\":2}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("userCoinSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserCoinResponse("{\"code\":0,\"data\":{\"money\":3.5}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("followingSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFollowingResponse("{\"code\":0,\"data\":{\"list\":[{\"mid\":1,\"uname\":\"u\"}],\"total\":1}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("webNestedURL", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = DouyinResponseDecoder.parseWebFeed("{\"aweme_list\":[{\"aweme_id\":\"1\",\"video\":{\"play_addr\":{\"url_list\":[3]}}}]}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.aweme_list[0].video.play_addr.url_list[0]");
    });
    it("webBusinessFailureFirst", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = DouyinResponseDecoder.parseWebFeed("{\"status_code\":8}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.status_code");
    });
    it("webValidLegacyCache", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = DouyinResponseDecoder.parseWebFeed("{\"aweme_list\":[]}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("guestWbiKeysNotLoginVerdict", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseWbi("{\"code\":-101,\"data\":{\"wbi_img\":{\"img_url\":\"https://example.com/a.png\",\"sub_url\":\"https://example.com/b.png\"}}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("wbiWrongNestedURL", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseWbi("{\"code\":0,\"data\":{\"wbi_img\":{\"img_url\":42,\"sub_url\":\"https://example.com/b.png\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.wbi_img.img_url");
    });
    it("wbiMissingNestedURL", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseWbi("{\"code\":0,\"data\":{\"wbi_img\":{\"img_url\":\"https://example.com/a.png\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.wbi_img.sub_url");
    });
    it("wbiNullObject", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseWbi("{\"code\":0,\"data\":{\"wbi_img\":null}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NULL_NOT_ALLOWED");
      expect(issue?.pathText()).assertEqual("$.data.wbi_img");
    });
    it("upVideoWrongAid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"code\":0,\"data\":{\"list\":{\"vlist\":[{\"aid\":\"1\",\"bvid\":\"BV1\",\"title\":\"t\",\"pic\":\"p\",\"author\":\"a\"}]}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list.vlist[0].aid");
    });
    it("upVideoWrongList", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"code\":0,\"data\":{\"list\":{\"vlist\":{}}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list.vlist");
    });
    it("upEmptyPage", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"code\":0,\"data\":{\"list\":{\"vlist\":[]}}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("upBusinessFailure", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"code\":-403}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("missingCode", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUPVideos("{\"data\":{}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("folderWrongId", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("{\"code\":0,\"data\":{\"count\":1,\"list\":[{\"id\":\"1\",\"title\":\"test\",\"attr\":0,\"media_count\":1}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list[0].id");
    });
    it("folderWrongList", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("{\"code\":0,\"data\":{\"count\":1,\"list\":{}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list");
    });
    it("folderNullEmpty", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("{\"code\":0,\"data\":{\"count\":0,\"list\":null}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("folderAbsentData", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("{\"code\":0}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("mediaWrongAuthor", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteContents("{\"code\":0,\"data\":{\"info\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1},\"medias\":[{\"id\":2,\"type\":2,\"title\":\"test\",\"cover\":\"https://example.com/c\",\"attr\":0,\"duration\":60,\"bvid\":\"BVtest\",\"upper\":{\"name\":3},\"cnt_info\":{\"play\":3}}],\"has_more\":false}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.medias[0].upper.name");
    });
    it("mediaWrongCount", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteContents("{\"code\":0,\"data\":{\"info\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1},\"medias\":[{\"id\":2,\"type\":2,\"title\":\"test\",\"cover\":\"https://example.com/c\",\"attr\":0,\"duration\":60,\"bvid\":\"BVtest\",\"upper\":{\"name\":\"u\"},\"cnt_info\":{\"play\":\"3\"}}],\"has_more\":false}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.medias[0].cnt_info.play");
    });
    it("mediaWrongFlag", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteContents("{\"code\":0,\"data\":{\"info\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1},\"medias\":[{\"id\":2,\"type\":2,\"title\":\"test\",\"cover\":\"https://example.com/c\",\"attr\":0,\"duration\":60,\"bvid\":\"BVtest\",\"upper\":{\"name\":\"u\"},\"cnt_info\":{\"play\":3}}],\"has_more\":0}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.has_more");
    });
    it("mediaNullEmpty", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteContents("{\"code\":0,\"data\":{\"info\":{\"id\":1,\"title\":\"test\",\"attr\":0,\"media_count\":1},\"medias\":null,\"has_more\":false}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("infoWrongTitle", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolder("{\"code\":0,\"data\":{\"id\":1,\"title\":3,\"attr\":0,\"media_count\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.title");
    });
    it("favoriteWrongState", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteState("{\"code\":0,\"data\":{\"favoured\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.favoured");
    });
    it("historyDeepWrongCid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseHistory("{\"code\":0,\"data\":{\"cursor\":{\"max\":1,\"view_at\":2},\"tab\":[{\"type\":\"archive\",\"name\":\"video\"}],\"list\":[{\"title\":\"a\",\"history\":{\"bvid\":\"BV1\",\"cid\":\"1\"},\"progress\":-1}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list[0].history.cid");
    });
    it("historyWrongTab", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseHistory("{\"code\":0,\"data\":{\"cursor\":{\"max\":1,\"view_at\":2},\"tab\":{},\"list\":[{\"title\":\"a\",\"history\":{\"bvid\":\"BV1\",\"cid\":1},\"progress\":-1}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.tab");
    });
    it("historyUnsafeCursor", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseHistory("{\"code\":0,\"data\":{\"cursor\":{\"max\":9007199254740992,\"view_at\":2},\"tab\":[{\"type\":\"archive\",\"name\":\"video\"}],\"list\":[{\"title\":\"a\",\"history\":{\"bvid\":\"BV1\",\"cid\":1},\"progress\":-1}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("OUT_OF_RANGE");
      expect(issue?.pathText()).assertEqual("$.data.cursor.max");
    });
    it("historyNullData", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseHistory("{\"code\":0,\"data\":null}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("midWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseMid("{\"code\":0,\"data\":{\"mid\":\"123\"}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.mid");
    });
    it("likeWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseLikeStateResponse("{\"code\":0,\"data\":true}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data");
    });
    it("coinWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseCoinStateResponse("{\"code\":0,\"data\":{\"multiply\":\"2\"}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.multiply");
    });
    it("insertWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseInsertCoinResponse("{\"code\":0,\"data\":{\"like\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.like");
    });
    it("mutationBusinessFailure", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseInsertCoinResponse("{\"code\":-101}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("statWrongFollower", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserStatResponse("{\"code\":0,\"data\":{\"following\":1,\"follower\":\"2\",\"dynamic_count\":3}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.follower");
    });
    it("cardWrongNested", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserCardResponse("{\"code\":0,\"data\":{\"card\":{\"following\":false,\"follower\":2},\"following\":false,\"follower\":2}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.card.following");
    });
    it("coinWrongMoney", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseUserCoinResponse("{\"code\":0,\"data\":{\"money\":\"3.5\"}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.money");
    });
    it("followingWrongUid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFollowingResponse("{\"code\":0,\"data\":{\"list\":[{\"mid\":\"1\",\"uname\":\"u\"}],\"total\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list[0].mid");
    });
    it("followingWrongArray", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFollowingResponse("{\"code\":0,\"data\":{\"list\":{},\"total\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.list");
    });
    it("sessionLoggedIn", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseSession("{\"code\":0,\"data\":{\"isLogin\":true}}");
        expect(result).assertEqual(true);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("sessionExpired", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseSession("{\"code\":-101}");
        expect(result).assertEqual(false);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("sessionLoggedOut", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseSession("{\"code\":0,\"data\":{\"isLogin\":false}}");
        expect(result).assertEqual(false);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("sessionRiskNotLogout", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseSession("{\"code\":-412}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("sessionMalformedNotLogout", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseSession("{\"code\":0,\"data\":{\"isLogin\":\"false\"}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.isLogin");
    });
    it("rssStrings", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("[\"a\",\"b\"]");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("rssEmpty", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("[]");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("rssObject", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("{}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("rssBadStringItem", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("[\"a\",3]");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$[1]");
    });
    it("rssNullItem", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("[\"a\",null]");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NULL_NOT_ALLOWED");
      expect(issue?.pathText()).assertEqual("$[1]");
    });
    it("rssEmptyId", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = LocalDataDecoder.parseRSSSourceIds("[\"\"]");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("OUT_OF_RANGE");
      expect(issue?.pathText()).assertEqual("$[0]");
    });
    it("scriptStringValue", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToString("\"hello\\n\\\"世界\\\"\"");
        expect(result).assertEqual("hello\n\"世界\"");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptStringNull", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToString("null");
        expect(result).assertEqual(null);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptBooleanValue", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToBoolean("false");
        expect(result).assertEqual(false);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptBooleanNull", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToBoolean("null");
        expect(result).assertEqual(null);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptNumberValue", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToNumber("2.5");
        expect(result).assertEqual(2.5);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptNumberNull", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToNumber("null");
        expect(result).assertEqual(null);
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("scriptStringDoesNotStripNumber", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToString("123");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("scriptBooleanDoesNotCoerceString", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToBoolean("\"false\"");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("scriptNumberDoesNotCoerceString", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToNumber("\"5\"");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("scriptNumberRejectsEmpty", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToNumber("");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_JSON");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("scriptNumberRejectsNonFinite", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = jsReturnValueToNumber("1e999");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("OUT_OF_RANGE");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("badJSON", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliResponseDecoder.parseFavoriteFolders("<html>login required</html>");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_JSON");
      expect(issue?.pathText()).assertEqual("$");
    });
    it("homeCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("videoSearchCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":1,\"bvid\":\"BV1\",\"title\":\"<em>title</em>\",\"author\":\"owner\",\"duration\":\"1:23\",\"play\":1}],\"numResults\":1,\"page\":1}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("cidCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":0,\"data\":{\"cid\":2,\"bvid\":\"BV1\"}}", "BV1");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("videoDetailCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":9}}]}}", "BV1");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("playbackCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("navCoreSuccess", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":1,\"uname\":\"u\",\"face\":\"https://example.com/a\",\"money\":3.5,\"wallet\":{\"bcoin_balance\":2.5},\"level_info\":{\"current_level\":3,\"current_exp\":123,\"next_exp\":\"--\"}}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("homeBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":-403}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("videoSearchBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":-403}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("cidBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":-403}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("videoDetailBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":-403}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("playbackBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":-403}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("navBusinessErrorBeforePayload", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":-403}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("homeEmptyPage", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("homeMissingArray", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.item");
    });
    it("homeArrayWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":{}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.item");
    });
    it("homeObjectArrayItemWrong", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[[],{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.item[0]");
    });
    it("homeUnsafeNumericId", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":9007199254740992,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("OUT_OF_RANGE");
      expect(issue?.pathText()).assertEqual("$.data.item[0].id");
    });
    it("homeMissingVideoBvid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.item[0].bvid");
    });
    it("homeEmptyVideoBvid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_VALUE");
      expect(issue?.pathText()).assertEqual("$.data.item[0].bvid");
    });
    it("homeMissingVideoCid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.item[0].cid");
    });
    it("homeInvalidCidValue", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"cid\":\"abc\",\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_VALUE");
      expect(issue?.pathText()).assertEqual("$.data.item[0].cid");
    });
    it("homeNestedWrongCount", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":\"1\",\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.item[0].stat.view");
    });
    it("homeNestedWrongName", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":3,\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.item[0].owner.name");
    });
    it("homeNestedEmptyName", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"owner\":{\"name\":\"\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_VALUE");
      expect(issue?.pathText()).assertEqual("$.data.item[0].owner.name");
    });
    it("homePreservesLargeStringIds", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseHome("{\"code\":0,\"data\":{\"item\":[{\"id\":\"900719925474099312345\",\"bvid\":\"BV1\",\"cid\":\"900719925474099312345\",\"title\":\"title\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2}},{\"id\":0,\"goto\":\"login_card\"},{\"id\":\"0\",\"goto\":\"ad\",\"owner\":{\"name\":\"\"}}]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("searchEmptyPage", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("searchMissingResult", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.result");
    });
    it("searchWrongTitle", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":1,\"bvid\":\"BV1\",\"title\":false,\"author\":\"owner\",\"duration\":\"1:23\",\"play\":1}],\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.result[0].title");
    });
    it("searchWrongDuration", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":1,\"bvid\":\"BV1\",\"title\":\"<em>title</em>\",\"author\":\"owner\",\"duration\":{},\"play\":1}],\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("UNION_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.result[0].duration");
    });
    it("searchWrongCount", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":1,\"bvid\":\"BV1\",\"title\":\"<em>title</em>\",\"author\":\"owner\",\"duration\":\"1:23\",\"play\":\"1\"}],\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.result[0].play");
    });
    it("searchMissingBvid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":1,\"title\":\"<em>title</em>\",\"author\":\"owner\",\"duration\":\"1:23\",\"play\":1}],\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.result[0].bvid");
    });
    it("searchInvalidId", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseSearch("{\"code\":0,\"data\":{\"result\":[{\"id\":-1,\"bvid\":\"BV1\",\"title\":\"<em>title</em>\",\"author\":\"owner\",\"duration\":\"1:23\",\"play\":1}],\"numResults\":1,\"page\":1}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_VALUE");
      expect(issue?.pathText()).assertEqual("$.data.result[0].id");
    });
    it("cidMissingField", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":0,\"data\":{\"bvid\":\"BV1\"}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.cid");
    });
    it("cidWrongType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":0,\"data\":{\"cid\":false,\"bvid\":\"BV1\"}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("UNION_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.cid");
    });
    it("cidMismatch", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":0,\"data\":{\"cid\":2,\"bvid\":\"BVother\"}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("ID_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.bvid");
    });
    it("cidInvalidValue", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseCid("{\"code\":0,\"data\":{\"cid\":0,\"bvid\":\"BV1\"}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_VALUE");
      expect(issue?.pathText()).assertEqual("$.data.cid");
    });
    it("detailMissingView", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":9}}]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.View");
    });
    it("detailWrongOwner", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":null,\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":9}}]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NULL_NOT_ALLOWED");
      expect(issue?.pathText()).assertEqual("$.data.View.owner");
    });
    it("detailWrongStat", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":\"1\",\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":9}}]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.View.stat.coin");
    });
    it("detailWrongRelated", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":{}}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.Related");
    });
    it("detailRelatedNestedWrong", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":false},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":false},\"stat\":{\"view\":9}}]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.Related[0].owner.face");
    });
    it("detailRelatedNullItem", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[null]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NULL_NOT_ALLOWED");
      expect(issue?.pathText()).assertEqual("$.data.Related[0]");
    });
    it("detailMismatch", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BVother\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":[{\"title\":\"related\",\"bvid\":\"BV2\",\"pic\":\"pic\",\"duration\":30,\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":9}}]}}", "BV1");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("ID_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.View.bvid");
    });
    it("detailNullableRelated", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseDetail("{\"code\":0,\"data\":{\"View\":{\"aid\":1,\"bvid\":\"BV1\",\"cid\":2,\"title\":\"title\",\"desc\":\"desc\",\"owner\":{\"name\":\"owner\",\"face\":\"https://example.com/face\"},\"stat\":{\"view\":1,\"like\":2,\"coin\":3,\"favorite\":4,\"share\":5},\"pic\":\"https://example.com/pic\",\"pubdate\":1,\"duration\":60},\"Related\":null}}", "BV1");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("playMissingDurl", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.durl");
    });
    it("playWrongSegmentArray", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":{},\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.durl");
    });
    it("playWrongSegmentObject", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[false],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.durl[0]");
    });
    it("playWrongPrimary", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":1,\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.durl[0].url");
    });
    it("playWrongBackupArray", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":{}}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.durl[0].backup_url");
    });
    it("playWrongBackupItem", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[1]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.durl[0].backup_url[0]");
    });
    it("playWrongAcceptDescription", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[16],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.accept_description[0]");
    });
    it("playWrongAcceptQuality", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[\"16\"]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.accept_quality[0]");
    });
    it("playWrongFormatDescription", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":1234,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":1,\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.support_formats[0].display_desc");
    });
    it("playNegativeDuration", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":-1,\"durl\":[{\"url\":\"https://example.com/main\",\"backup_url\":[\"https://example.com/backup\"]}],\"support_formats\":[{\"display_desc\":\"流畅\",\"codecs\":null}],\"accept_description\":[\"流畅\"],\"accept_quality\":[16]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("OUT_OF_RANGE");
      expect(issue?.pathText()).assertEqual("$.data.timelength");
    });
    it("playEmptySegments", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":0,\"durl\":[]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NO_PLAYABLE_URL");
      expect(issue?.pathText()).assertEqual("$.data.durl");
    });
    it("playOnlyEmptyURLs", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":0,\"durl\":[{\"url\":\" \",\"backup_url\":[\"\",\" \"]}]}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("NO_PLAYABLE_URL");
      expect(issue?.pathText()).assertEqual("$.data.durl");
    });
    it("playBackupOnly", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":0,\"durl\":[{\"url\":null,\"backup_url\":[\"\",\"https://example.com/b\"]}]}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("playNullFormats", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("{\"code\":0,\"data\":{\"format\":\"mp4\",\"timelength\":0,\"durl\":[{\"url\":\"https://example.com/a\"}],\"support_formats\":null}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("navWrongLoginType", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":\"true\",\"mid\":1,\"uname\":\"u\",\"face\":\"https://example.com/a\",\"money\":3.5,\"wallet\":{\"bcoin_balance\":2.5},\"level_info\":{\"current_level\":3,\"current_exp\":123,\"next_exp\":\"--\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.isLogin");
    });
    it("navMissingAuthenticatedMid", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":true,\"uname\":\"u\",\"face\":\"https://example.com/a\",\"money\":3.5,\"wallet\":{\"bcoin_balance\":2.5},\"level_info\":{\"current_level\":3,\"current_exp\":123,\"next_exp\":\"--\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("MISSING_FIELD");
      expect(issue?.pathText()).assertEqual("$.data.mid");
    });
    it("navWrongWallet", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":1,\"uname\":\"u\",\"face\":\"https://example.com/a\",\"money\":3.5,\"wallet\":{\"bcoin_balance\":\"1\"},\"level_info\":{\"current_level\":3,\"current_exp\":123,\"next_exp\":\"--\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.wallet.bcoin_balance");
    });
    it("navWrongLevel", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":1,\"uname\":\"u\",\"face\":\"https://example.com/a\",\"money\":3.5,\"wallet\":{\"bcoin_balance\":2.5},\"level_info\":{\"current_level\":3,\"current_exp\":false,\"next_exp\":\"--\"}}}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("TYPE_MISMATCH");
      expect(issue?.pathText()).assertEqual("$.data.level_info.current_exp");
    });
    it("navFalseIsLogin", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":false}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("navNullWalletAndLevel", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":1,\"wallet\":null,\"level_info\":null}}");
        expect(result !== undefined).assertTrue();
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue === undefined).assertTrue();
    });
    it("navExpiredBusinessCode", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parseNav("{\"code\":-101}");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("BUSINESS_STATUS");
      expect(issue?.pathText()).assertEqual("$.code");
    });
    it("mediaInvalidJSON", 0, () => {
      let issue: DecodeIssue | undefined = undefined;
      try {
        const result = BiliMediaDecoder.parsePlayback("<html>blocked</html>");
      } catch (error) {
        if (!(error instanceof JsonDecodeError)) {
          if (error instanceof Error) { throw error; }
          throw new Error('Unexpected non-Error failure');
        }
        issue = error.issues[0];
      }
      expect(issue !== undefined).assertTrue();
      expect(issue?.code).assertEqual("INVALID_JSON");
      expect(issue?.pathText()).assertEqual("$");
    });
  });
}
