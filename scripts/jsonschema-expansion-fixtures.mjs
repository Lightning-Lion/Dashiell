// Test fixture emission only; production ArkTS generation remains entirely Rust.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
export function expansionFixtures(root, update) {
  const cases = JSON.parse(fs.readFileSync(path.join(root, 'tests/jsonschema/expansion-cases.json'), 'utf8'));
  const methods = {
    wbi:'parseWbi',upVideos:'parseUPVideos',favFolders:'parseFavoriteFolders',favContents:'parseFavoriteContents',favFolder:'parseFavoriteFolder',favoriteState:'parseFavoriteState',history:'parseHistory',mid:'parseMid',session:'parseSession',action:'parseActionResponse',likeState:'parseLikeStateResponse',coinState:'parseCoinStateResponse',insertCoin:'parseInsertCoinResponse',userStat:'parseUserStatResponse',userCard:'parseUserCardResponse',userCoin:'parseUserCoinResponse',following:'parseFollowingResponse'
  };
  const mediaMethods = { home:'parseHome', videoSearch:'parseSearch', cid:'parseCid', videoDetail:'parseDetail', playback:'parsePlayback', nav:'parseNav' };
  let source = `// GENERATED from tests/jsonschema/expansion-cases.json.\nimport { describe, it, expect } from '@ohos/hypium';\nimport { DecodeIssue, JsonDecodeError } from '../main/ets/common/jsonschema/JsonDecode';\nimport { BiliResponseDecoder } from '../main/ets/common/bili/BiliResponseDecoder';\nimport { BiliMediaDecoder } from '../main/ets/common/bili/BiliMediaDecoder';\nimport { DouyinResponseDecoder } from '../main/ets/common/douyin/DouyinResponseDecoder';\nimport { LocalDataDecoder } from '../main/ets/common/local/LocalDataDecoder';\nimport { jsReturnValueToString, jsReturnValueToNumber, jsReturnValueToBoolean } from '../main/ets/common/WebViewExtension';\nexport default function jsonSchemaExpansionFixturesTest() {\n  describe('JsonSchemaExpansionFixtures', () => {\n`;
  for (const c of cases) {
    const arg = JSON.stringify(c.text ?? JSON.stringify(c.input));
    const call = mediaMethods[c.endpoint] ? `BiliMediaDecoder.${mediaMethods[c.endpoint]}(${arg}${['cid','videoDetail'].includes(c.endpoint) ? ', \"BV1\"' : ''})` : c.endpoint === 'webFeed' ? `DouyinResponseDecoder.parseWebFeed(${arg})` : c.endpoint === 'rss' ? `LocalDataDecoder.parseRSSSourceIds(${arg})` : c.endpoint.startsWith('script') ? `jsReturnValueTo${c.endpoint.slice(6)}(${arg})` : `BiliResponseDecoder.${methods[c.endpoint]}(${arg})`;
    assert(!call.includes('undefined('));
    source += `    it(${JSON.stringify(c.name)}, 0, () => {\n      let issue: DecodeIssue | undefined = undefined;\n      try {\n        const result = ${call};\n`;
    if (c.ok) source += Object.hasOwn(c,'value') ? `        expect(result).assertEqual(${JSON.stringify(c.value)});\n` : `        expect(result !== undefined).assertTrue();\n`;
    source += `      } catch (error) {\n        if (!(error instanceof JsonDecodeError)) {\n          if (error instanceof Error) { throw error; }\n          throw new Error('Unexpected non-Error failure');\n        }\n        issue = error.issues[0];\n      }\n`;
    if (c.ok) source += `      expect(issue === undefined).assertTrue();\n`;
    else source += `      expect(issue !== undefined).assertTrue();\n      expect(issue?.code).assertEqual(${JSON.stringify(c.code)});\n      expect(issue?.pathText()).assertEqual(${JSON.stringify(c.path)});\n`;
    source += '    });\n';
  }
  source += '  });\n}\n';
  const file = path.join(root,'entry/src/test/JsonSchemaExpansionFixtures.generated.ets');
  if (update) fs.writeFileSync(file,source); else assert.equal(fs.readFileSync(file,'utf8'),source,'Expansion fixtures stale');
  return cases.length;
}
