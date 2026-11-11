import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
// In the utility class, retrieve the Context from the Entry Ability and save it to AppStore, then use AppStore to retrieve it in the utility class

export const getStringFromRawfile = async (fileName:string) => {
  let context = getContext()
  try {
    const rawFile:Uint8Array = await context.resourceManager.getRawFileContent(fileName)
    const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM : true });
    const rawFileString = textDecoder.decodeToString( rawFile , {stream: false});
    return rawFileString
  } catch (error) {
    const code = (error as BusinessError).code;
    const message = (error as BusinessError).message;
    console.error(`callback getRawFileContent failed, error code: ${code}, message: ${message}.`);
    throw new Error("加载rawfile中的字符串失败")
  }
}

// 用法
// const html:string = await getStringFromRawfile("DouYin.html")