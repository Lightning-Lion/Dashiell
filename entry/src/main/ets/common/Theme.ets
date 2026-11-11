// 深色主题颜色

// 页面顶部的淡雅渐变。
// 取色规律：色相呼应进入该页面的入口卡片（见 BiliStackWidgetPage 的「更多」菜单），
// 收尾统一落在 navDestDefaultBackground 上，
// 于是每个页面顶部各具特色，页面下半部分又彼此一致。
interface PageTopGradientInterface {
  // 近似红：搜索、首页这些 App 自己的核心页面
  brand: Array<[ResourceColor, number]>;
  // 蓝：哔哩哔哩首页
  biliHome: Array<[ResourceColor, number]>;
  // 玫紫：我的
  mine: Array<[ResourceColor, number]>;
  // 橙黄：收藏
  favorite: Array<[ResourceColor, number]>;
  // 青蓝：历史
  history: Array<[ResourceColor, number]>;
  // 蓝：知乎日报 / 知乎热榜
  zhihu: Array<[ResourceColor, number]>;
  // 红：IT之家
  ithome: Array<[ResourceColor, number]>;
  // 绿：3DM
  threeDM: Array<[ResourceColor, number]>;
  // 玫红：抖音精选子页（菜单/标题复制/指引），色相取抖音红 #FE2C55，按其余项规律压暗后收尾到 navDestDefaultBackground
  douyin: Array<[ResourceColor, number]>;
}

// 加载态这类前景元素用的强调色，键名与 PageTopGradientInterface 逐字对应。
// 渐变是同一色相的「背景档」，故意压暗（S=30%/L=36%），直接当文字色只有 ~3.4:1，手表上读不清；
// 这里是同一色相的「前景档」。
// 取色规律：色相不变，按相对亮度等值化到 ~7:1（#121212 上），
// 于是各模块读起来一样亮，不会绿色比蓝色刺眼。
interface AccentInterface {
  // 近似红：搜索、首页这些 App 自己的核心页面
  brand: string;
  // 蓝：哔哩哔哩首页
  biliHome: string;
  // 玫紫：我的
  mine: string;
  // 橙黄：收藏
  favorite: string;
  // 青蓝：历史
  history: string;
  // 蓝：知乎日报 / 知乎热榜
  zhihu: string;
  // 红：IT之家
  ithome: string;
  // 绿：3DM
  threeDM: string;
  // 抖音。它是唯一不做等亮度处理的强调色——抖音红 #FE2C55 的色相 348° 与品牌红 353° 只差 5°，
  // 等亮度化后会算成 #E38A88，和 brand 的 #E38793 肉眼分不开，
  // 保留原值的高饱和度才分得开，代价是它比其余键暗一档（5.09:1，仍过 AA）。
  douyin: string;
}

interface DarkThemeInterface {
  // 贯穿整个 App 的强调色，取自 App 图标上的近似红。
  // 按钮、链接、进度条这类 App 级 UI 用它。
  primary: string;
  // 哔哩哔哩品牌语境里的粉色，只留给点赞/投币/收藏/播放/分享、
  // 账号等级徽章这些「哔哩哔哩自己的东西」。
  biliPink: string;
  background: string;
  navDestDefaultBackground: string;
  textFieldBackground: string;
  prominentButton:string;
  disabledButton: string;
  cardBackground: string;
  // 列表卡片一镜到底展开成全屏时的表面色。
  // 起点必须等于 cardBackground，否则点击的瞬间卡片会跳色。
  heroSurface: Array<[ResourceColor, number]>;
  textPrimary: string;
  textSecondary: string;
  divider: string;
  loadingBackground: string;
  errorColor: string;
  destructiveColor: string;
  pageTopGradients: PageTopGradientInterface;
  accents: AccentInterface;
}

export
const DarkTheme: DarkThemeInterface = {
  primary: '#FF4C63', // 取色自 App 图标上的近似红
  biliPink: '#EA7A99', // 与 App 内 bili_color 资源同一个值，改用主题变量方便统一调整
  background: '#121212', // 深色背景
  navDestDefaultBackground: "#18181A", // 取色自鸿蒙的NavDestination()没有放置任何内容时的默认背景色
  textFieldBackground:"#262626", // 取色自鸿蒙系统设置里添加WiFi的输入框
  prominentButton:"#2071FF", // Button("按钮")蓝色按钮默认的颜色
  disabledButton:"#666666", // 取色自鸿蒙系统设置里Toggle的关闭状态的底色
  cardBackground: '#1E1E1E', // 卡片背景
  // 从卡片色过渡到 NavDestination 默认底色，展开过程中不出现第二种色相
  heroSurface: [['#FF1E1E1E', 0], ['#FF18181A', 1]],
  textPrimary: '#FFFFFF', // 主要文字颜色
  textSecondary: '#AAAAAA', // 次要文字颜色
  divider: '#2A2A2A', // 分割线颜色
  loadingBackground: '#2A2A2A', // 加载中状态背景
  errorColor: '#FF6B6B', // 错误提示颜色
  destructiveColor: "#EB534E", // 取色自苹果的iMessage侧滑删除
  pageTopGradients: {
    // 基准色相 352° 就是 App 图标红；饱和度/亮度沿用搜索页调好的那组，
    // 所以在搜索页上几乎看不出变化，只是色相从偏粉挪到了偏红。
    brand: [['#FF6E454A', 0], ['#18181A', 0.6]],
    // 其余页面把饱和度提到 30%，否则在手表上几个色相会糊成一片、看不出「各具特色」。
    biliHome: [['#FF406D77', 0], ['#18181A', 0.6]],
    mine: [['#FF774067', 0], ['#18181A', 0.6]],
    favorite: [['#FF775F40', 0], ['#18181A', 0.6]],
    history: [['#FF407766', 0], ['#18181A', 0.6]],
    zhihu: [['#FF405C77', 0], ['#18181A', 0.6]],
    ithome: [['#FF774040', 0], ['#18181A', 0.6]],
    threeDM: [['#FF407749', 0], ['#18181A', 0.6]],
    // 抖音红 #FE2C55 压暗一档得到的玫红，色相比 brand 更偏粉一点，好在手表上区分开
    douyin: [['#FF7A3046', 0], ['#18181A', 0.6]]
  },
  accents: {
    brand: '#E38793',
    biliHome: '#30AFCC',
    mine: '#E282C6',
    favorite: '#D39646',
    history: '#2BB78B',
    zhihu: '#6EA6DD',
    ithome: '#E38888',
    threeDM: '#2CB943',
    douyin: '#FE2C55'
  }
}
