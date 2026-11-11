import { describe, it, expect } from '@ohos/hypium';
import jsonSchemaExpansionFixturesTest from './JsonSchemaExpansionFixtures.generated';
import { BiliResponseDecoder } from '../main/ets/common/bili/BiliResponseDecoder';
import { BiliFavoriteMapping } from '../main/ets/common/bili/BiliFavoriteMapping';
import { DouyinResponseDecoder } from '../main/ets/common/douyin/DouyinResponseDecoder';
import { DouyinFeedMapping } from '../main/ets/common/douyin/DouyinFeedMapping';
import { LocalDataDecoder } from '../main/ets/common/local/LocalDataDecoder';
import { JsonDecodeError } from '../main/ets/common/jsonschema/JsonDecode';
import { validateAwemeData, validGetUPsVideosResponse } from '../main/ets/common/TypeValid';
import { jsReturnValueToString, jsReturnValueToBoolean } from '../main/ets/common/WebViewExtension';

export default function jsonSchemaExpansionTest() {
  jsonSchemaExpansionFixturesTest();
  describe('JsonSchemaExpansion', () => {
    it('hotSearchExplicitTolerancePreservesOriginalOrder', 0, () => {
      const report = BiliResponseDecoder.parseHotSearchReport('{"code":0,"data":{"trending":{"list":[null,{}, {"keyword":" "},{"keyword":123},{"keyword":" valid ","show_name":42},{"keyword":" second ","show_name":" name "}]}}}');
      expect(report.received).assertEqual(6);
      expect(report.skipped).assertEqual(4);
      expect(report.items.length).assertEqual(2);
      expect(report.items[0].keyword).assertEqual('valid');
      expect(report.items[0].show_name).assertEqual('valid');
      expect(report.items[1].show_name).assertEqual('name');
      expect(report.issues.length).assertEqual(4);
      expect(report.issues[0].pathText()).assertEqual('$.data.trending.list[0]');
      expect(report.issues[3].pathText()).assertEqual('$.data.trending.list[4].show_name');
    });
    it('hotSearchRejectsEntirelyBrokenList', 0, () => {
      let failed = false;
      try { BiliResponseDecoder.parseHotSearchReport('{"code":0,"data":{"trending":{"list":[{"keyword":false},null]}}}'); }
      catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
    });
    it('hotSearchStillAcceptsLegitimateEmptyRanking', 0, () => {
      const report = BiliResponseDecoder.parseHotSearchReport('{"code":0,"data":{"trending":{"list":[]}}}');
      expect(report.items.length).assertEqual(0);
      expect(report.issues.length).assertEqual(0);
    });
    it('hotSearchCapsWarningCollectionWithoutDroppingGoodRows', 0, () => {
      const rows: string[] = [];
      for (let i = 0; i < 60; i++) { rows.push('{}'); }
      rows.push('{"keyword":"last"}');
      const report = BiliResponseDecoder.parseHotSearchReport('{"code":0,"data":{"trending":{"list":[' + rows.join(',') + ']}}}');
      expect(report.issues.length).assertEqual(32);
      expect(report.skipped).assertEqual(60);
      expect(report.items[0].keyword).assertEqual('last');
    });
    it('rssFailureDoesNotReplacePreviousState', 0, () => {
      let ids: string[] = ['previous'];
      try { ids = LocalDataDecoder.parseRSSSourceIds('["new",false]'); } catch (_) { }
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual('previous');
    });
    it('rssRejectsNonTextPreferencesValue', 0, () => {
      let failed = false;
      try { LocalDataDecoder.parseRSSSourceIds(17); } catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
    });
    it('scriptNullIsNotAParseFailure', 0, () => {
      expect(jsReturnValueToString('null') === null).assertTrue();
      expect(jsReturnValueToBoolean('false')).assertFalse();
      let failed = false;
      try { jsReturnValueToBoolean('"false"'); } catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
    });
    it('webAndLegacyCacheShareSameMapping', 0, () => {
      const text = '{"aweme_list":[{"aweme_id":"1","desc":"fallback","video":{"play_addr":{"url_list":["https://example.com/v"]}}}]}';
      const model = DouyinResponseDecoder.parseWebFeed(text);
      const mapped = DouyinFeedMapping.items(model.items);
      expect(mapped.aweme_list[0].video.play_addr.url_list.length).assertEqual(1);
      expect(mapped.aweme_list[0].video.play_addr_h264.url_list.length).assertEqual(0);
      expect(mapped.aweme_list[0].desc).assertEqual('fallback');
    });
    it('legacyValidatorNoLongerAcceptsTypedAssignmentOnly', 0, () => {
      let failed = false;
      try { validGetUPsVideosResponse(null); } catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
      failed = false;
      try { validateAwemeData(null); } catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
    });
    it('badSessionDataDoesNotOverwriteLoggedInState', 0, () => {
      let loggedIn = true;
      try { loggedIn = BiliResponseDecoder.parseSession('{"code":0,"data":{"isLogin":123}}'); } catch (_) { }
      expect(loggedIn).assertTrue();
    });
    it('wbiGuestPayloadDoesNotGrantAuthenticatedSession', 0, () => {
      const text = '{"code":-101,"data":{"wbi_img":{"img_url":"https://example.com/a.png","sub_url":"https://example.com/b.png"}}}';
      expect(BiliResponseDecoder.parseWbi(text).data.wbi_img.img_url).assertEqual('https://example.com/a.png');
      expect(BiliResponseDecoder.parseSession(text)).assertFalse();
    });
    it('favoriteNullListNormalizationOnlyAfterValidation', 0, () => {
      const model = BiliResponseDecoder.parseFavoriteFolders('{"code":0,"data":{"count":0,"list":null}}');
      expect(model.data?.list === null).assertTrue();
      expect(BiliFavoriteMapping.folders(model).data.list?.length).assertEqual(0);
    });
    it('favoriteMappingPreservesMediaAndFolderMetadata', 0, () => {
      const model = BiliResponseDecoder.parseFavoriteContents('{"code":0,"data":{"info":{"id":1,"title":"folder","attr":0,"media_count":1,"intro":"intro","cover":"cover"},"medias":[{"id":2,"type":2,"title":"video","cover":"pic","attr":0,"duration":4,"bv_id":"BV1","upper":{"name":"up"},"cnt_info":{"play":7}}],"has_more":false}}');
      const mapped = BiliFavoriteMapping.contents(model);
      expect(mapped.data.info.intro).assertEqual('intro');
      expect(mapped.data.info.cover).assertEqual('cover');
      expect(mapped.data.medias?.[0].upper?.name).assertEqual('up');
      expect(mapped.data.medias?.[0].cnt_info?.play).assertEqual(7);
      expect(mapped.data.medias?.[0].bv_id).assertEqual('BV1');
      expect(mapped.data.medias?.[0].type).assertEqual(2);
    });
    it('httpBoundaryRejectsNonTextInsteadOfCasting', 0, () => {
      let failed = false;
      try { BiliResponseDecoder.responseText(9); } catch (error) { failed = error instanceof JsonDecodeError; }
      expect(failed).assertTrue();
    });
  });
}
