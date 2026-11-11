import { ReadingSourcePagePushData } from '../../pages/RSS/NewsListPage';
import { logTag } from '../printLog';
import { DevFlags } from './DevFlags';

/**
 * 本地开发「启动直达」注册表。
 *
 * 只允许 pages/NavigationStack/NavigationStack.ets 引用本模块：common 反向被页面引用会立刻成环。
 * 接入新模块 = 加一个具名 push 函数 + 在 directEntryTargets 里加一行，
 * 再把 LocalDevConfig.ets 里的 DEV_DIRECT_ENTRY 设成对应的 key。
 * 带函数/类入参的路由不要登记：路由参数会被物化成普通对象，方法会丢失。
 */
export interface DirectEntryTarget {
  key: string
  title: string
  push: (stack: NavPathStack) => void
}

/** 资讯页目标：title 与 url 同 HomePageRSSList.dispatchNavigation 里的源表保持一致。 */
function pushReadingSource(stack: NavPathStack, displayTitle: string, sourceURL: string): void {
  const params: ReadingSourcePagePushData = { displayTitle: displayTitle, sourceURL: sourceURL }
  stack.pushPathByName('ReadingSourcePage', params)
}

function pushZhihuHot(stack: NavPathStack): void {
  pushReadingSource(stack, '知乎热榜 - 全站', 'https://rss.dashiell.cn/zhihu/hot')
}

function pushZhihuDaily(stack: NavPathStack): void {
  pushReadingSource(stack, '知乎日报', 'https://rss.dashiell.cn/zhihu/daily')
}

function pushITHome(stack: NavPathStack): void {
  pushReadingSource(stack, 'IT之家', 'https://www.ithome.com/rss/')
}

function push3DM(stack: NavPathStack): void {
  pushReadingSource(stack, '3DM - 新闻中心', 'https://rss.dashiell.cn/3dmgame/news')
}

/** 先压菜单再压精选页，直达的同时保留返回链路（与首页进入抖音的顺序一致）。 */
function pushDouyinJingxuan(stack: NavPathStack): void {
  stack.pushPathByName('DouYinMenu', undefined)
  stack.pushPathByName('DouYinJingxuanPage', undefined)
}

function pushDouyinCollected(stack: NavPathStack): void {
  stack.pushPathByName('DouYinMenu', undefined)
  stack.pushPathByName('DouyinCollectedPage', undefined)
}

function pushDouyinLiked(stack: NavPathStack): void {
  stack.pushPathByName('DouYinMenu', undefined)
  stack.pushPathByName('DouyinLikedPage', undefined)
}

function pushDouyinLogin(stack: NavPathStack): void {
  stack.pushPathByName('DouYinLoginPage', undefined)
}

function pushBiliHomeLoggedIn(stack: NavPathStack): void {
  stack.pushPathByName('BiliHomeFeedPageWithLogin', undefined)
}

function pushBiliHomeGuest(stack: NavPathStack): void {
  stack.pushPathByName('BiliHomeFeedPageWithoutLogin', undefined)
}

/** 与 pages/BiliLogin/BiliLoginRequiredPage 的 BiliLoginRequiredParam 字段一致；这里只传普通值。 */
interface BiliLoginRequiredPageParam {
  featureName: string
  accountName: string
}

/** 哔哩哔哩搜索的登录中间页；栈底保留免登录首页，取消后能回到一个真实页面。 */
function pushBiliLoginRequired(stack: NavPathStack): void {
  const param: BiliLoginRequiredPageParam = { featureName: '搜索', accountName: '哔哩哔哩' }
  stack.pushPathByName('BiliHomeFeedPageWithoutLogin', undefined)
  stack.pushPathByName('BiliLoginRequiredPage', param)
}

function pushSettings(stack: NavPathStack): void {
  stack.pushPathByName('PersonalizedSettingsPage', undefined)
}

/**
 * 卡片堆叠菜单：只压菜单本身。
 * `BiliStackWidgetPage` 的入参带 `BilibiliService` 实例，这里不传，页面会回退到
 * `getCurrentBiliService()`；未登录时只影响第 2 张卡的标题，卡片布局照常渲染。
 */
function pushBiliMenu(stack: NavPathStack): void {
  stack.pushPathByName('BiliStackWidgetPage', undefined)
}

function pushDouyinMenu(stack: NavPathStack): void {
  stack.pushPathByName('DouYinMenu', undefined)
}

export const directEntryTargets: DirectEntryTarget[] = [
  { key: 'zhihu-hot', title: '知乎热榜 - 全站', push: pushZhihuHot },
  { key: 'zhihu-daily', title: '知乎日报', push: pushZhihuDaily },
  { key: 'ithome', title: 'IT之家', push: pushITHome },
  { key: '3dmgame', title: '3DM - 新闻中心', push: push3DM },
  { key: 'douyin-jingxuan', title: '抖音精选', push: pushDouyinJingxuan },
  { key: 'douyin-collected', title: '抖音收藏', push: pushDouyinCollected },
  { key: 'douyin-liked', title: '抖音喜欢', push: pushDouyinLiked },
  { key: 'douyin-login', title: '抖音登录页', push: pushDouyinLogin },
  { key: 'bili-home-login', title: '哔哩哔哩首页（登录链路）', push: pushBiliHomeLoggedIn },
  { key: 'bili-home-guest', title: '哔哩哔哩首页（免登录）', push: pushBiliHomeGuest },
  { key: 'bili-login-required', title: '哔哩哔哩登录中间页', push: pushBiliLoginRequired },
  { key: 'settings', title: '个性化设置', push: pushSettings },
  { key: 'bili-menu', title: '哔哩哔哩卡片菜单', push: pushBiliMenu },
  { key: 'douyin-menu', title: '抖音卡片菜单', push: pushDouyinMenu },
]

/** 只在导航栈为空时调用；调用方负责这个前提。 */
export function applyDirectEntry(stack: NavPathStack): void {
  if (DevFlags.directEntry.length === 0) { return }
  const target = directEntryTargets.find((item: DirectEntryTarget) => item.key === DevFlags.directEntry)
  if (target === undefined) {
    console.warn(logTag, 'DEV_DIRECT_ENTRY unknown key=' + DevFlags.directEntry)
    return
  }
  console.debug(logTag, 'DEV_DIRECT_ENTRY key=' + target.key + ' title=' + target.title)
  target.push(stack)
}
