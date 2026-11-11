#!/usr/bin/env python3
"""Regenerate synthetic webSign vectors by executing the pinned upstream pure-stdlib module.
Never imports the upstream server or reads real Cookies. The audited source hash must match.
"""
import argparse,hashlib,importlib.util,json,random
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--reference',required=True);args=p.parse_args()
source=Path(args.reference)/'src/dtk/signing/native/websign.py'
EXPECTED_SHA='b31e1809de52e43f8098cbc903746d342b2128d56907542ca118af56d9c6010b'
if hashlib.sha256(source.read_bytes()).hexdigest()!=EXPECTED_SHA:
 raise SystemExit('Reference differs from the audited revision; inspect it before updating vectors')
spec=importlib.util.spec_from_file_location('audited_websign_reference',source)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
uid='aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff0011'
cases=[
 ('upstream-sdk-basic',[('device_platform','webapp'),('aid','6383'),('aweme_id','123')],uid,1788848841,'6090b6162b96aeb107b51ab69140c764'),
 ('upstream-sdk-unicode-space',[('q','中'),('z','a b'),('e','/')],'AAAA1111',1788848901,'a79dcd330ecba4d98016189c3ca313cd'),
 ('upstream-sdk-empty',[],'AAAA1111',1788848901,'0479f3eb2297110d45bfbd96ccccb292'),
 ('upstream-sdk-existing-visitor',[('uifid','ZZZ'),('t','1')],'ZZZ',1788848901,'df59a6887d4647239b9079d7d16ad784'),
 ('duplicate-business-keys',[('a','1'),('a','2'),('empty','')],uid,0,None),
 ('punctuation',[('q'," ~!*'()=+%/&?:#\x00"),('空 键','😀')],uid,4294967300,None),
 ('signature-encoded',[('aid','6383'),('a_bogus','abc/def-=='),('msToken','fixture+/%=')],uid,1788848901,None),
 ('long-query',[('q','中😀 abc+'*1000)],uid,1788848901,None),
]
rng=random.Random(20261012);alphabet='aZ09 -._~!*()\'=+/%&中😀é'
for i in range(80):
 pairs=[('p'+str(j),''.join(rng.choice(alphabet) for _ in range(rng.randrange(0,40)))) for j in range(rng.randrange(0,8))]
 cases.append(('python-reference-'+str(i),pairs,'synthetic-visitor-'+str(i),1788848000+i,None))
vectors=[]
for name,pairs,visitor,stamp,known in cases:
 query,signature,headers=module.sign(pairs,visitor,timestamp=stamp)
 if known is not None and signature!=known:raise SystemExit('Upstream SDK vector disagrees with upstream code')
 vectors.append({'name':name,'pairs':[{'name':k,'value':v} for k,v in pairs],'uifid':visitor,'timestamp':stamp,'expectedQuery':query,'expectedSignature':signature,'expectedHeaders':headers})
out=Path(__file__).resolve().parent.parent/'tests/douyin/websign-vectors.json'
out.write_text(json.dumps({'referenceRepository':'Evil0ctal/Douyin_TikTok_Download_API','referenceRevision':'4f0bed8483c35a980315d9c7b3a1d4a1119ad2b2','referenceFile':'src/dtk/signing/native/websign.py','referenceSha256':EXPECTED_SHA,'syntheticOnly':True,'vectors':vectors},ensure_ascii=False,indent=2)+'\n')
print('Generated',len(vectors),'synthetic vectors, including 4 upstream SDK oracle vectors')
