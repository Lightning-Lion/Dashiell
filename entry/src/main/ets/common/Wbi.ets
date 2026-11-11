import { it } from '@ohos/hypium';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, url } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { logTag } from './printLog';
import { BusinessError } from '@kit.BasicServicesKit';
import { BiliResponseDecoder } from './bili/BiliResponseDecoder';
import { JsonDecodeError } from './jsonschema/JsonDecode';


const mixinKeyEncTab = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
  61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
  36, 20, 34, 44, 52
]

@ObservedV2
class MD5Error extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

const md5 = async (content:string) => {
  try {
    let md = cryptoFramework.createMd('MD5');
    await md.update({ data: new Uint8Array(buffer.from(content, 'utf-8').buffer) })
    const digestOutput = await md.digest()
    //转换为16进制字符串并输出
    const result = Array.from(digestOutput.data).map(byte => byte.toString(16)).join('')
    return result
  } catch (error) {
    throw new MD5Error("ArkTS无法正常完成MD5计算")
  }
}

// 对 imgKey 和 subKey 进行字符顺序打乱编码
const getMixinKey = (orig: string) =>
mixinKeyEncTab
  .map((n) => orig[n])
  .join("")
  .slice(0, 32);
interface DictionaryItem {
  key: string;
  value: string;
}

@ObservedV2
class EncWbiError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

async function encWbi (
  params: DictionaryItem[],
  img_key: string,
  sub_key: string
) {
  try {
    const mixin_key = getMixinKey(img_key + sub_key),
      curr_time = Math.round(Date.now() / 1000),
      chr_filter = /[!'()*]/g;

    // 把 wts 作为一个新的 DictionaryItem 加进去
    const extendedParams: DictionaryItem[] = [
      ...params,
      { key: "wts", value: curr_time.toString() }
    ];

    // 按 key 排序，然后处理每一个 {key, value}
    const query = extendedParams
      .sort((a, b) => a.key.localeCompare(b.key)) // 根据 key 排序
      .map((item:DictionaryItem) => {
        const key:string = item.key
        const value:string = item.value
        const filteredValue = value.replace(chr_filter, "");
        return `${encodeURIComponent(key)}=${encodeURIComponent(filteredValue)}`;
      })
      .join("&");

    const wbi_sign = await md5(query + mixin_key); // 计算 w_rid

    return query + "&w_rid=" + wbi_sign;
  } catch (error) {
    if (error instanceof MD5Error) {
      const typedError:MD5Error = error as MD5Error
      console.debug(logTag,"encWbi遇到了MD5Error")
      throw new EncWbiError(typedError.message)
    } else {
      try {
        const businessError = error as BusinessError
        const businessErrorDescription: string =
          "Error name: " + businessError.name + "\n" + "Error message:" + businessError.message + "\n" +
            "Error stack:" + businessError.stack + "\n" + "Error code:" + businessError.code + "\n" +
            "Error data:" + businessError.data
        console.debug(logTag,
          "encWbi时出现了BusinessError：\n" + businessErrorDescription)
        throw new EncWbiError("请求签名失败，无法完成wbi签名：\n"+businessErrorDescription)
      } catch (_) {
        console.debug(logTag,
          "encWbi时出现了Error：\n" + error.message ?? JSON.stringify(error, null, 2))
        throw new EncWbiError("请求签名失败，无法完成wbi签名：\n"+error.message ?? JSON.stringify(error,null,2))
      }
    }
  }
}

export interface GetWbiKeysResponse {
  data:GetWbiKeysResponseData
}
export interface GetWbiKeysResponseData {
  wbi_img:GetWbiKeysResponseWbiImg
}
export interface GetWbiKeysResponseWbiImg {
  img_url: string
  sub_url: string
}


// 获取最新的 img_key 和 sub_key
interface GetWbiKeysResult {
  img_key: string;
  sub_key: string;
}

@ObservedV2
class GetWbiKeysError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}

async function getWbiKeys(cookieString:string,ua:string,referer:string) {
  try {
    // 发起请求
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(
      'https://api.bilibili.com/x/web-interface/nav',
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': ua,
          'Referer': referer,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': cookieString,
        }
      }
    )
    if (response.responseCode === 200) {
      const responseText = BiliResponseDecoder.responseText(response.result);
      const data = BiliResponseDecoder.parseWbi(responseText);
      const img_url = data.data.wbi_img.img_url
      const sub_url = data.data.wbi_img.sub_url
      return ({
        img_key: img_url.slice(img_url.lastIndexOf('/') + 1, img_url.lastIndexOf('.')),
        sub_key: sub_url.slice(sub_url.lastIndexOf('/') + 1, sub_url.lastIndexOf('.'))
      } as GetWbiKeysResult)
    } else {
      throw new GetWbiKeysError("获取WbiKeys出错，响应状态码："+response.responseCode)
    }
  } catch (error) {
    if (error instanceof JsonDecodeError) {
      throw error;
    } else if (error instanceof GetWbiKeysError) {
      console.log(logTag,"getWbiKeys遇到了GetWbiKeysError")
      throw error
    } else {
      try {
        const businessError = error as BusinessError
        const businessErrorDescription: string =
          "Error name: " + businessError.name + "\n" + "Error message:" + businessError.message + "\n" +
            "Error stack:" + businessError.stack + "\n" + "Error code:" + businessError.code + "\n" +
            "Error data:" + businessError.data
        console.log(logTag,"getWbiKeys遇到了BusinessError")
        throw new GetWbiKeysError("获取WbiKeys出错：\n"+businessErrorDescription)
      } catch (_) {
        console.log(logTag,"getWbiKeys遇到了Error")
        throw new GetWbiKeysError("获取WbiKeys出错：\n"+error.message ?? JSON.stringify(error,null,2))
      }
    }
  }
}

export async function spaceWbiArcSearchQuery(params: DictionaryItem[],cookieString:string,ua:string,referer:string) {
  const web_keys = await getWbiKeys(cookieString,ua,referer)
  const img_key = web_keys.img_key
  const sub_key = web_keys.sub_key
  const query:string = await encWbi(params, img_key, sub_key)
  return query
}

// Retired unused all/v2 JSON passthrough. Active UI search is typed by
// BilibiliService.requestSearch and its generated SearchResponse decoder.

export const getUPsVideos = async (mid:string,pn:string,cookieString:string,ua:string,referer:string) => {
  const params: DictionaryItem[] = [{
    key:"mid",
    value:mid
  },{
    key:"order",
    value:"pubdate"
  },{
    key:"pn",
    value:pn
  },{
    key:"ps",
    value:"40"
  }]
  const query = await spaceWbiArcSearchQuery(params,cookieString,ua,referer)
  try {
    // 发起请求
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(
      "https://api.bilibili.com/x/space/wbi/arc/search?"+query,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': ua,
          'Referer': referer,
          'Origin': 'https://www.bilibili.com',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
          'Cookie': cookieString,
        }
      }
    )
    const responseText = BiliResponseDecoder.responseText(response.result);
    if (response.responseCode === 200) {
      const data = BiliResponseDecoder.parseUPVideos(responseText);
      // An empty list is a valid successful page, not a malformed response.
      return data.data.list.vlist
    } else {
      throw new GetUPsVideosError("获取UP主视频出错，响应状态码："+response.responseCode)
    }
  } catch (error) {
    if (error instanceof GetUPsVideosError) {
      console.log(logTag,"getUPsVideos遇到了GetUPsVideosError")
      throw error
    } else if (error instanceof GetWbiKeysError) {
      console.log(logTag,"getUPsVideos遇到了GetWbiKeysError")
      const typedError:GetWbiKeysError = error as GetWbiKeysError
      throw new GetUPsVideosError("获取UP主视频出错：\n"+typedError.message)
    } else if (error instanceof EncWbiError) {
      console.log(logTag,"getUPsVideos遇到了EncWbiError")
      const typedError:EncWbiError = error as EncWbiError
      throw new GetUPsVideosError("获取UP主视频出错：\n"+typedError.message)
    } else if (error instanceof JsonDecodeError) {
      throw error;
    } else {
      try {
        const businessError = error as BusinessError
        const businessErrorDescription: string =
          "Error name: " + businessError.name + "\n" + "Error message:" + businessError.message + "\n" +
            "Error stack:" + businessError.stack + "\n" + "Error code:" + businessError.code + "\n" +
            "Error data:" + businessError.data
        console.log(logTag,"getUPsVideos遇到了BusinessError")
        throw new GetUPsVideosError("获取UP主视频出错：\n"+businessErrorDescription)
      } catch (_) {
        console.log(logTag,"getUPsVideos遇到了Error")
        throw new GetUPsVideosError("获取UP主视频出错：\n"+error.message ?? JSON.stringify(error,null,2))
      }
    }
  }
}

export interface GetUPsVideosResponse {
  "code": number
  "message": string
  "data": GetUPsVideosResponseData
}

interface GetUPsVideosErrorResponse {
    "code": number,
    "message": string
}


export interface GetUPsVideosResponseData {
  list:GetUPsVideosResponseDataList
}

export interface GetUPsVideosResponseDataList {
  vlist:GetUPsVideosResponseDataListVlistItem[]
}

export interface GetUPsVideosResponseDataListVlistItem {
  aid:number
  bvid:string
  title:string
  pic:string
  author:string
}

@ObservedV2
export class GetUPsVideosError extends Error {
  @Trace
  message: string

  constructor(message: string) {
    super(message)
    this.message = message
  }
}