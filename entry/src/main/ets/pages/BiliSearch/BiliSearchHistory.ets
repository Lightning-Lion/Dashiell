import { Context } from "@kit.AbilityKit";
import { logTag } from "../../common/printLog";
import { AppDatabase } from "../../common/storage/AppDatabase";

class LoadBiliSearchHistoryError extends Error {
  constructor(errorMessage: string) {
    super(errorMessage)
  }
}

@ObservedV2
export class BiliSearchHistory {
  @Trace
  histories: string[] = []
  private page: number = 0
  private static readonly perPageCount: number = 20
  private readonly context: Context

  constructor(context: Context) {
    this.context = context
  }

  // 使用get会导致响应式不更新，应该使用@Computed
  @Computed
  get length(): number {
    return this.histories.length
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async getHistories(): Promise<string[]> {
    try {
      const db = await AppDatabase.open(this.context)
      return await db.searchHistory.getAll()
    } catch (error) {
      console.debug(logTag, error)
      console.debug(logTag, "无法解读当前的历史记录数据：可能是数据结构变更后未适配旧数据")
      // 不能因为解析失败就丢弃用户的数据
      throw new LoadBiliSearchHistoryError("加载搜索历史记录出错了，请联系开发者。\n点此联系开发者。")
    }
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async add(keyword: string): Promise<void> {
    const db = await AppDatabase.open(this.context)
    await db.searchHistory.add(keyword)
    await this.refreshDisplay()
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async remove(keyword: string): Promise<void> {
    const db = await AppDatabase.open(this.context)
    await db.searchHistory.remove(keyword)
    this.histories = this.histories.filter(item => item !== keyword)
    this.page = 0
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async fetchNextPage(): Promise<void> {
    const histories = await this.getHistories()

    // 如果是第一页，先获取最新的历史记录
    if (this.page === 0) {
      this.histories = histories.slice(0, BiliSearchHistory.perPageCount)
      this.page++
      return
    }

    // 计算起始和结束位置
    const start = this.page * BiliSearchHistory.perPageCount
    const end = start + BiliSearchHistory.perPageCount
    // 获取当前页的数据
    const pageData = histories.slice(start, end)
    // 追加到 histories 数组
    this.histories = [...this.histories, ...pageData]

    // 增加页码
    this.page++
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async refresh(): Promise<void> {
    this.page = 0
    await this.fetchNextPage()
  }

  // 我可能抛出LoadBiliSearchHistoryError
  async clear(): Promise<void> {
    const db = await AppDatabase.open(this.context)
    await db.searchHistory.clear()
    this.histories = []
    this.page = 0
  }

  private async refreshDisplay(): Promise<void> {
    const allHistories = await this.getHistories()
    const pagesToShow = this.page === 0 ? 1 : this.page
    const itemsToShow = pagesToShow * BiliSearchHistory.perPageCount
    this.histories = allHistories.slice(0, itemsToShow)
  }
}
