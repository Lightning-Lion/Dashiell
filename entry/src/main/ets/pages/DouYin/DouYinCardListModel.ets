import { shuffled } from "../../common/ArrayExtension"
import { logTag } from "../../common/printLog"
import { AppDatabase } from "../../common/storage/AppDatabase"
import { StorageKeys, StorageNamespaces } from "../../common/storage/StorageKeys"
import { StorageTime } from "../../common/storage/StorageTime"
import { DouYinAwemeCard, DouYinVideoCard } from "./DouYinJingxuanPage"
import { DouYinRecommandAwemeData, DouYinRecommandAwemeItem, DouYinRecommandVideoPlayAddr } from "./DouYinWebView"
import { common } from "@kit.AbilityKit"
import fs from '@ohos.file.fs';
import { util } from "@kit.ArkTS"

// 在WebView和CardListView之间共享视频
@ObservedV2
export class DouYinCardListModel {
  // 和抖音的数据结构解耦
  @Trace
  cardList:Array<DouYinAwemeCard> | null = null

  // 手表只需要少量分页视频；保留过多视频会同时持有标题、URL和播放器状态，
  // 让内存和 WebView 请求量持续增长。
  @Computed
  get showWebView():boolean {
    if (this.cardList !== null) {
      // 因为在禁用CSS后WebView会持续请求更多视频，如果实际解析成功可播放的视频达到36条，就不再继续加载
      if (this.cardList.length >= 12) {
        console.debug(logTag,"销毁了WebView")
        return false
      }
    }
    console.debug(logTag,"显示WebView")
    return true
  }
  // 需要保证：
  // 1.先前视频不再变动，比如移动、删除，改变索引会影响播放，DouVideoPlayer预期已产生的索引是稳定的
  // 2.传入的总是视频卡片，DouVideoPlayer预期只有视频卡片
  // 3.视频的videoURLList不应该为空，DouVideoPlayer预期总是至少能取到一个URL
  appendVideoList(newVideos:DouYinRecommandAwemeData) {
    const newCardList:Array<DouYinAwemeCard>= []
    newVideos.aweme_list.forEach((item) => {
      try {
        // sortedVideoURLList会抛错，如果item不是视频
        const card = new DouYinAwemeCard(item.aweme_id,new DouYinVideoCard(item.preview_title || item.desc || '抖音视频',this.sortedVideoURLList(item)))
        if (!newCardList.some((existing: DouYinAwemeCard) => existing.awemeID === card.awemeID)) {
          newCardList.push(card)
        }
      } catch (error) {
        if (error instanceof NotVideoError) {
          // 跳过这一条
          console.debug(logTag,"跳过一条不是视频的")
        } else {
          console.debug(logTag,"appendVideoList抛出错误："+error.message ?? JSON.stringify(error,null,2))
          throw error as Error
        }
      }
    })
    this.appendVideoListL0(newCardList)
  }

  refreshVideo(item: DouYinRecommandAwemeItem): void {
    const urls = this.sortedVideoURLList(item);
    const card = this.cardList?.find((c: DouYinAwemeCard) => c.awemeID === item.aweme_id);
    if (card?.videoInfo) { card.videoInfo.videoURLList = urls; }
  }

  appendVideoListA(newCardList:Array<DouYinAwemeCard>) {
    this.appendVideoListL0(newCardList)
  }

  private appendVideoListL0(newCardList:Array<DouYinAwemeCard>) {
    if (newCardList.length === 0) { return; }
    const merged = this.cardList?.slice() ?? [];
    const ids = new Set(merged.map((card: DouYinAwemeCard) => card.awemeID));
    for (const card of newCardList) {
      if (!ids.has(card.awemeID)) { ids.add(card.awemeID); merged.push(card); }
    }
    if (merged.length !== (this.cardList?.length ?? 0)) {
      // Replacing the array signals lazy-list append without changing existing card identities/indices.
      this.cardList = merged;
    }
  }

  /**
   * 从抖音推荐视频数据中提取有效播放URL
   * @param data 抖音推荐视频根数据
   * @returns 按优先级筛选后的URL数组（无有效URL的视频项会被过滤）
   */
  private sortedVideoURLList(awemeItem:DouYinRecommandAwemeItem): string[] {
    if (!awemeItem.video) { throw new NotVideoError('不是视频'); }
    const urlArray:Array<string> = []
    // Prefer compatible AVC before HEVC, and retain alternatives for playback errors.
    const priorityPlayAddrs: DouYinRecommandVideoPlayAddr[] = [
      awemeItem.video.play_addr_h264,
      awemeItem.video.play_addr,
      awemeItem.video.play_addr_lowbr,
      awemeItem.video.play_addr_265
    ];
    for (const playAddr of priorityPlayAddrs) {
      for (const url of playAddr?.url_list ?? []) {
        if (url && url.trim() && !urlArray.includes(url.trim())) {
          urlArray.push(url.trim());
        }
      }
    }

    // 不是视频就抛错，不混脏数据
    if (urlArray.length === 0) {
      console.debug(logTag,"抛出NotVideoError")
      throw new NotVideoError("不是视频")
    }
    return urlArray;
  }
}

// 给sortedVideoURLList用的错误
class NotVideoError extends Error {
  constructor(message: string) {
    super(message)
  }
}

// 视频播放链接的有效期是一小时，在一小时内重新进入可以复用之前加载出来了的视频
@ObservedV2
export class DouYinCardListModelCache {
  saveCache(responseText: string, context: common.UIAbilityContext): void {
    // 在后台缓存：先落文件，再写 RDB 元数据；元数据失败时最多多读一次旧文件，不会丢文件。
    (async () => {
      const manager = new DouYinResponseTextFileCacheManager(context)
      try {
        await manager.save(responseText)
        const db = await AppDatabase.open(context)
        await db.values.setString(StorageKeys.DOUYIN_FEED_CACHE_LAST_REFRESH,
          StorageNamespaces.STATE, StorageTime.nowIso())
        console.debug(logTag, "持久化写入成功")
      } catch (error) {
        console.debug(logTag, "写入缓存失败: " + DouYinCardListModelCache.describe(error))
      }
    })()
  }

  async readCache(context: common.UIAbilityContext): Promise<string | null> {
    try {
      const db = await AppDatabase.open(context)
      const lastRefresh = await db.values.getString(StorageKeys.DOUYIN_FEED_CACHE_LAST_REFRESH, '')
      if (!this.isWithinLastHour(lastRefresh)) {
        console.debug(logTag, "没有上次持久化或缓存过期")
        return null
      }
      console.debug(logTag, "缓存有效，尝试读取")
      const manager = new DouYinResponseTextFileCacheManager(context)
      const responseText = await manager.read()
      console.debug(logTag, "缓存读取成功")
      return responseText
    } catch (error) {
      console.debug(logTag, "读取上次持久化数据出错: " + DouYinCardListModelCache.describe(error))
      return null
    }
  }

  // 缓存有效期一小时
  private isWithinLastHour(iso: string): boolean {
    if (!StorageTime.isCanonicalIso(iso)) {
      return false;
    }
    const timestamp = Date.parse(iso);
    const oneHourAgo = Date.now() - 60 * 60 * 1000;
    return timestamp >= oneHourAgo;
  }

  private static describe(error: Object): string {
    const message = (error as Error).message;
    return message === undefined ? 'unknown' : message;
  }
}

// 自定义错误类
class DouYinResponseTextFileCacheError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NovelSaveError';
  }
}

// 响应正文可能很大，继续放文件；RDB 只保存“上次成功刷新时间”。旧文件路径保持不变，迁移后可继续复用。
class DouYinResponseTextFileCacheManager {
  private context: common.UIAbilityContext;
  private readonly CACHE_DIR = 'DouYinCache';
  private readonly FIXED_FILENAME = 'e7522eb67645488cb21c.json';

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async save(content: string): Promise<string> {
    try {
      // 1. 获取应用文件目录路径
      const filesDir:string = this.context.filesDir;

      // 2. 构建目录和文件路径
      const dirPath = `${filesDir}/${this.CACHE_DIR}`;
      const filePath = `${dirPath}/${this.FIXED_FILENAME}`;

      console.log(logTag,`准备保存文件到: ${filePath}`);

      // 3. 确保目录存在
      await this.ensureDirectoryExists(dirPath);

      // 4. 写入文件（覆盖模式）
      await this.writeFileWithOverwrite(filePath, content);

      console.log(logTag,`文件保存成功: ${filePath}`);
      return filePath;

    } catch (error) {
      console.error(logTag,'保存ResponseText失败:', error);
      throw new DouYinResponseTextFileCacheError(error.message);
    }
  }

  async read(): Promise<string> {
    const filePath = this.getCacheFilePath();

    try {
      console.log(logTag,`准备读取文件: ${filePath}`);

      // 1. 检查文件是否存在
      const fileExists = await this.checkPathExists(filePath);
      if (!fileExists) {
        throw new DouYinResponseTextFileCacheError(`缓存文件不存在: ${filePath}`);
      }

      // 2. 打开文件（只读模式）
      let file = await fs.open(filePath, fs.OpenMode.READ_ONLY);

      try {
        // 3. 获取文件状态以确定文件大小
        const fileStat = await fs.stat(filePath);
        const fileSize = fileStat.size;
        console.log(logTag,`文件大小: ${fileSize} 字节`);

        if (fileSize === 0) {
          console.warn(logTag,`文件为空: ${filePath}`);
          return '';
        }

        // 4. 读取文件内容
        const buffer:ArrayBuffer = new ArrayBuffer(fileSize);

        const bytesRead = await fs.read(file.fd, buffer, {
          offset: 0,
          length: fileSize
        });
        console.log(logTag,`实际读取字节数: ${bytesRead}`);

        // 5. 将ArrayBuffer转换为字符串
        const uint8Array = new Uint8Array(buffer);
        const content:string = new util.TextDecoder().decodeToString(uint8Array , {stream: false});
        console.log(logTag,`文件读取成功，内容长度: ${content.length} 字符`);

        return content;

      } finally {
        // 确保文件被关闭
        await fs.close(file.fd);
        console.log(logTag,'读取文件已关闭');
      }

    } catch (error) {
      console.error(logTag,`读取文件失败: ${filePath}`, error);

      // 如果是自定义错误，直接抛出
      if (error instanceof DouYinResponseTextFileCacheError) {
        throw error;
      }

      // 其他错误包装后抛出
      throw new DouYinResponseTextFileCacheError(
        `Failed to read file: ${filePath}. Reason: ${error.message}`
      );
    }
  }

  /**
   * 确保目录存在，不存在则创建
   */
  private async ensureDirectoryExists(dirPath: string): Promise<void> {
    try {
      // 检查目录是否存在
      const dirExists = await this.checkPathExists(dirPath);

      if (!dirExists) {
        console.log(logTag,`目录不存在，创建目录: ${dirPath}`);
        // 创建目录（recursive: true 确保可以创建多层目录）
        await fs.mkdir(dirPath);
        console.log(logTag,`目录创建成功: ${dirPath}`);
      } else {
        console.log(logTag,`目录已存在: ${dirPath}`);
      }
    } catch (error) {
      console.error(logTag,`创建目录失败: ${dirPath}`, error);
      throw new DouYinResponseTextFileCacheError(
        `Failed to create directory: ${dirPath}`
      );
    }
  }

  /**
   * 检查路径是否存在
   */
  private async checkPathExists(path: string): Promise<boolean> {
    try {
      const exists:boolean = await fs.access(path);
      console.debug(logTag,"await fs.access(path)返回"+exists)
      return exists;
    } catch (error) {
      console.debug(logTag,"await fs.access(path)抛错")
      console.debug(logTag,error.message ?? JSON.stringify(error,null,2))
      // 文件不存在时返回false
      if (error?.code === 13900015) { // ENOENT: No such file or directory
        return false;
      }
      // 其他错误重新抛出
      throw error as Error;
    }
  }

  /**
   * 写入文件（覆盖模式）
   */
  private async writeFileWithOverwrite(filePath: string, content: string): Promise<void> {
    try {
      // 使用 CREATE 和 TRUNC 标志确保覆盖已存在的文件
      const openMode = fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;

      console.log(logTag,`打开文件进行写入: ${filePath}`);
      let file = await fs.open(filePath, openMode);

      try {
        console.log(logTag,`写入内容，长度: ${content.length} 字符`);
        // 写入内容
        await fs.write(file.fd, content);

        // 同步到磁盘确保数据持久化
        await fs.fsync(file.fd);
        console.log(logTag,'文件同步到磁盘完成');

      } finally {
        // 确保文件被关闭
        await fs.close(file.fd);
        console.log(logTag,'文件已关闭');
      }

    } catch (error) {
      console.error(logTag,`写入文件失败: ${filePath}`, error);
      throw new DouYinResponseTextFileCacheError(`Failed to write file: ${filePath}`);
    }
  }

  /**
   * 获取缓存文件路径（只读）
   */
  getCacheFilePath(): string {
    const filesDir = this.context.filesDir;
    return `${filesDir}/${this.CACHE_DIR}/${this.FIXED_FILENAME}`;
  }

  /**
   * 检查缓存文件是否存在
   */
  async cacheFileExists(): Promise<boolean> {
    try {
      const filePath = this.getCacheFilePath();
      return await this.checkPathExists(filePath);
    } catch (error) {
      console.error(logTag,'检查缓存文件失败:', error);
      return false;
    }
  }
}
