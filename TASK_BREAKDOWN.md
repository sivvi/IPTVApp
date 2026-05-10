# IPTVApp 任务分解

## 项目概览

**核心功能**：播放 IPTV 流媒体频道，支持节目指南（EPG），通过 DLNA + AirPlay 2 投屏到电视设备
**平台**：iOS 15+（预留 tvOS 兼容空间）
**架构**：MVVM + Protocol-Oriented Programming
**UI**：UIKit + SnapKit（AutoLayout），关键列表用 UICollectionViewCompositionalLayout
**依赖管理**：SPM（Swift Package Manager）

---

## 阶段一：项目基础设施（预计 2-3 天）

### 1.1 仓库和工程初始化
- [ ] `git init`，创建 `.gitignore`（Xcode、CocoaPods、SPM、macOS 系统文件）
- [ ] 用 Xcode 创建空 iOS 项目，选择 UIKit App Delegate 生命周期
- [ ] 清理模板代码（删除默认 ViewController、Storyboard 引用）
- [ ] Info.plist 初始配置：Bundle display name、版本号、Deployment target 设为 iOS 15.0
- [ ] 确认项目用纯代码启动（删除 `Main.storyboard`，在 `SceneDelegate` 中手动设 rootViewController）

### 1.2 SPM 依赖集成
- [ ] 添加 MobileVLCKit（通过 SPM，仓库地址：https://code.videolan.org/videolan/VLCKit.git，锁定具体版本）
- [ ] 添加 SnapKit（https://github.com/SnapKit/SnapKit.git）
- [ ] 添加 Kingfisher（https://github.com/onevcat/Kingfisher.git，频道 logo 加载与缓存）
- [ ] 可选：添加 GRDB.swift 替代 SQLite.swift（类型安全更好）
- [ ] 可选：添加 CocoaAsyncSocket（https://github.com/robbiehanson/CocoaAsyncSocket.git），用于 DLNA SSDP 设备发现
- [ ] 验证所有依赖编译通过，无警告

### 1.3 项目文件结构
- [ ] 创建目录分组（在 Xcode 中与文件系统一致）：
  ```
  IPTVApp/
  ├── App/           # AppDelegate, SceneDelegate, Info.plist
  ├── Models/        # 数据模型
  ├── Services/      # 业务逻辑、解析器、播放器封装
  ├── ViewModels/    # MVVM ViewModel 层
  ├── Views/         # UI 层
  │   ├── Live/      直播 Tab
  │   ├── EPG/       节目指南 Tab
  │   ├── Favorites/ 收藏 Tab
  │   ├── Settings/  设置 Tab
  │   └── Common/    复用组件（播放控制条、空状态、加载指示器等）
  ├── Extensions/   # UIKit/Foundation 扩展
  ├── Protocols/    # 协议定义
  ├── Utilities/    # 工具类（常量、辅助函数）
  └── Resources/    # Assets, LaunchScreen, 字体
  ```
- [ ] 创建 `Constants.swift`：API 超时、缓存过期时间、默认画质等

### 1.4 基础架构搭建
- [ ] 定义 `Coordinator` 协议（简单的页面路由，避免 ViewController 之间直接耦合）
- [ ] 创建 `AppCoordinator`，负责初始化 TabBarController 和四个 Tab 的 NavigationController
- [ ] 创建 `TabBarController`，配置四个 Tab 的基础 VC 占位
- [ ] 创建 `BaseViewController` 基类（通用 loading/error/empty 状态处理）
- [ ] 创建 `BaseViewModel` 基类（持有通用的 `isLoading`、`errorMessage` 等状态）

---

## 阶段二：数据模型与解析器（预计 2-3 天）

### 2.1 核心数据模型
- [ ] `Channel` 模型（Codable）：
  - id, name, url, logoUrl, group, epgId, isFavorite, sortOrder
- [ ] `Program` 模型（Codable）：
  - id, channelId, title, description, startTime, endTime, category
- [ ] `Playlist` 模型（Codable）：
  - id, name, sourceUrl, channels: [Channel], lastUpdated, isDefault
- [ ] `EPGData` 模型（Codable）：
  - sourceUrl, channels: [EPGChannel], programs: [Program], lastUpdated

### 2.2 m3u/m3u8 解析器
- [ ] `PlaylistParser` 协议定义：`func parse(content: String) throws -> [Channel]`
- [ ] 实现 `M3UParser`：
  - 按行解析，识别 `#EXTINF` 标签
  - 提取属性：`tvg-name`, `tvg-id`, `tvg-logo`, `group-title`
  - 提取紧跟 `#EXTINF` 的 URL 行
  - 处理编码问题（m3u 文件可能用各种编码）
- [ ] 单元测试：正常 m3u、空 m3u、损坏 m3u、含特殊字符的 m3u
- [ ] 支持远程 URL 加载（`URLSession` 下载 m3u 内容后解析）
- [ ] 支持本地文件导入（`UIDocumentPickerViewController`，后阶段实现 UI）

### 2.3 XMLTV (EPG) 解析器
- [ ] `EPGParser` 协议定义：`func parse(xml: Data) throws -> EPGData`
- [ ] 实现 `XMLTVParser`（使用 `XMLParser`）：
  - 解析 `<channel>` 元素（频道 ID 和显示名映射）
  - 解析 `<programme>` 元素（起止时间、标题、描述、分类）
  - 处理日期格式（XMLTV 多种日期格式兼容）
- [ ] 单元测试：正常 XMLTV、含时区的、缺字段的、空文件的

### 2.4 数据持久化
- [ ] 选择方案：GRDB.swift 或 SQLite.swift，建 `DatabaseManager` 单例
- [ ] 建表/迁移逻辑：channels 表、programs 表、playlists 表
- [ ] CRUD 操作：
  - 频道：批量插入/更新、按分组查询、按收藏查询、搜索
  - 节目：按频道+时间范围查询、清理过期节目
  - 播放列表：增删改查、设为默认源
- [ ] 编写基础集成测试，验证增删改查

---

## 阶段三：频道管理（预计 3-4 天）

### 3.1 频道列表 ViewModel
- [ ] `ChannelListViewModel`：
  - `channels: [Channel]` 按分组整理
  - `groupedChannels: [(group: String, channels: [Channel])]` 供列表使用
  - `searchQuery` 搜索过滤逻辑
  - `loadPlaylist(from url: URL)` 下载+解析+入库流程
  - 加载状态、错误状态管理
  - 收藏/取消收藏操作

### 3.2 频道列表 UI
- [ ] `ChannelListViewController`：
  - 左侧分组列表 + 右侧频道列表（iPad 用 UISplitViewController，iPhone 用 TableView section）
  - 每个 Cell 显示：频道号、logo 图片、频道名、当前节目名（小字）
  - 搜索栏（UISearchController）
  - 下拉刷新
  - 长按弹出操作菜单（收藏、分享）
- [ ] 频道 logo 异步加载（用 `URLSession` + 内存/磁盘缓存，不依赖第三方图片库）

### 3.3 添加播放源
- [ ] `AddPlaylistViewController`：
  - URL 输入框 + 名称输入框
  - "添加"按钮，触发下载+解析流程
  - 解析成功 → 入库 → 刷新列表
  - 解析失败 → 显示具体错误（网络不可达/格式不支持/URL 无效）
- [ ] 本地文件导入：`UIDocumentPickerViewController` 选 .m3u / .m3u8 文件
- [ ] 内置一个示例 m3u URL 模板（占位，审核时移除或隐藏）

### 3.4 分组和收藏管理
- [ ] 收藏频道独立列表（从 `isFavorite` 过滤）
- [ ] 收藏操作：频道 Cell 左滑或长按 → "收藏/取消收藏"
- [ ] 收藏列表支持手动排序（拖拽重排）

---

## 阶段四：视频播放器（预计 5-7 天）⚠️ 核心模块

### 4.1 播放器服务封装
- [ ] `PlayerService` 协议：
  - `func play(url: URL)`
  - `func pause()` / `func resume()` / `func stop()`
  - `func seek(to: TimeInterval)`
  - `var state: PlayerState`（idle, loading, playing, paused, failed, stopped）
  - `var currentTime: TimeInterval`, `var duration: TimeInterval`
  - `var isBuffering: Bool`
  - 回调/Combine publisher：`stateDidChange`, `timeDidChange`, `bufferingDidChange`
- [ ] `VLCPlayerService` 实现（基于 MobileVLCKit 的 `VLCMediaPlayer`）：
  - 初始化 VLC 播放器实例
  - 配置默认参数：超时时间、缓冲大小、硬件解码、网络缓存（3000ms）
  - 状态机映射：VLC 状态 → 自定义 PlayerState
  - 时间回调（每秒更新 currentTime）
  - 缓冲状态回调

### 4.2 播放器 UI — 基础层
- [ ] `PlayerView`（UIView 子类，持有 `VLCVideoView` 作为渲染层）
- [ ] 单击切换控制条显示/隐藏
- [ ] 双击切换全屏/小窗
- [ ] 手势：左右滑动快进/快退，上下滑动左侧调亮度、右侧调音量

### 4.3 播放器 UI — 控制条
- [ ] `PlayerControlBar`（自定义 UIView）：
  - 播放/暂停按钮
  - 进度条（UISlider，显示缓冲进度 + 播放进度）
  - 当前时间 / 总时长 Label
  - 全屏/小窗切换按钮
  - 投屏按钮（AVRoutePickerView）
  - 画幅切换按钮（fit / fill / 原生）
- [ ] 控制条自动隐藏逻辑（播放中 3 秒无操作自动隐藏）
- [ ] 横竖屏适配：竖屏控制条在下方，横屏控制条在底部居中

### 4.4 全屏播放
- [ ] 强制横屏（`supportedInterfaceOrientations` 动态切换）
- [ ] 全屏时隐藏状态栏
- [ ] 全屏时 TabBar 和 NavigationBar 隐藏
- [ ] 旋转动画平滑过渡（UIView.animate + 手动布局 vs AutoLayout）
- [ ] 安全区域适配（iPhone X+ 的刘海区域）

### 4.5 画中画 (PiP)
- [ ] 配置 Background Modes：Audio, AirPlay, and Picture in Picture
- [ ] 用 `AVPictureInPictureController` 或 VLCKit 自带的 PiP 支持初始化
- [ ] PiP 启动/停止回调处理
- [ ] PiP 中点击"返回"按钮回到 App 的处理
- [ ] 注意：如果 VLCKit 版本不支持原生 PiP，回退方案用 AVPlayer 播放 HLS 流时启用 PiP

### 4.6 锁屏 & 控制中心
- [ ] 配置 `MPNowPlayingInfoCenter`：
  - 标题（频道名）、艺术家（当前节目名）、封面图（频道 logo）、时长、播放进度
  - 播放速率
- [ ] 配置 `MPRemoteCommandCenter`：
  - 播放、暂停、下一频道、上一频道、快进、快退
  - 在 AppDelegate 中注册远程命令，通过通知或 Combine 转发到当前播放器
- [ ] 测试：锁屏状态、控制中心、AirPods 双击（全部触发对应 remote command）

### 4.7 错误处理与重连
- [ ] 播放失败自动重试（最多 3 次，指数退避：1s → 2s → 4s）
- [ ] 缓冲超时处理（缓冲超过 15s → 显示"加载中"，超过 60s → 提示"信号异常"并提供重试按钮）
- [ ] 错误分级展示：
  - 轻微（短暂缓冲）：不弹窗，控制条显示加载指示器
  - 中等（超时）：Toast 提示"加载超时，正在重试"
  - 严重（无法连接）：全屏错误页 + 重试按钮 + 切换备用源选项
- [ ] 网络切换时的处理（NWPathMonitor 监听，WiFi→蜂窝时弹提示，蜂窝→WiFi 时静默）

### 4.8 后台播放
- [ ] Capabilities 中启用 Background Modes → Audio
- [ ] 配置 AVAudioSession（`.playback` category）
- [ ] 处理后台音频中断（来电、闹钟→暂停；结束后→恢复播放）

---

## 阶段五：节目指南 EPG（预计 4-5 天）

### 5.1 EPG 数据管理
- [ ] `EPGService`：
  - `func fetchEPG(from url: URL) async throws -> EPGData`
  - `func loadCachedEPG() -> EPGData?`（本地 3 天缓存）
  - `func refreshIfNeeded()` 自动刷新逻辑
  - 支持多个 EPG 数据源（用户可添加备选 URL）
  - 数据合并策略：同一频道多个源有冲突时，取时间戳最新的
- [ ] 后台刷新：`BGTaskScheduler` 每天凌晨刷新一次 EPG

### 5.2 EPG ViewModel
- [ ] `EPGViewModel`：
  - `currentPrograms: [String: Program]`（channelId → 当前节目）
  - `programs(for channelId: String, date: Date) -> [Program]`
  - `programsForTimeSlot(start: Date, end: Date) -> [(channel: Channel, programs: [Program])]`
  - 时间轴数据：按小时分桶

### 5.3 EPG UI — 频道网格视图（主视图）
- [ ] `EPGChannelGridViewController`：
  - 左侧固定宽度的频道名列表（垂直滚动）
  - 右侧可左右滚动的时间轴（水平滚动），每列 = 30 分钟
  - 节目块按开始时间和时长绘制在对应位置
  - 当前时间红线指示器
  - 点击节目块 → 弹出节目详情 Card
  - 双指缩放调整时间粒度（30min / 15min / 5min）

### 5.4 EPG UI — 时间轴实现细节
- [ ] 用 `UICollectionView` + `UICollectionViewCompositionalLayout` 或自定义 `UIScrollView`
- [ ] 同步左侧频道列表和右侧时间轴的垂直滚动
- [ ] 性能优化：只绘制可视区域内的节目块（Cell 复用 + 预计算 frame）
- [ ] 支持左右滑动切换日期

### 5.5 "正在播出"浮层
- [ ] 在播放器上方或频道列表底部展示：当前频道正在播出的节目名 + 下一个节目名
- [ ] 进度条显示当前节目剩余时间

---

## 阶段六：投屏功能（预计 4-5 天）

### 6.1 DLNA 设备发现
- [ ] `DLNADiscoveryService`：基于 SSDP（Simple Service Discovery Protocol）发现局域网内 DLNA 渲染设备
  - 通过 UDP 多播（239.255.255.250:1900）发送 M-SEARCH 请求
  - 解析设备响应，获取 LOCATION URL → 拉取设备描述 XML → 提取设备名、图标、控制 URL（AVTransport / RenderingControl）
  - `func discoverDevices(timeout: TimeInterval) async throws -> [DLNADevice]`
  - 持续监听（设备上线/下线通知）
- [ ] `DLNADevice` 模型：uuid, friendlyName, manufacturer, iconUrl, avTransportURL, renderingControlURL
- [ ] 设备缓存：记住上次连接的设备（uuid + IP），下次启动优先直连，跳过扫描
- [ ] `DLNADevicePickerViewController`：设备列表 UI，显示设备名 + 图标 + 信号强度，支持手动刷新，点击连接

### 6.2 DLNA 投屏控制
- [ ] `DLNACastingService`：
  - 通过 SOAP 协议向设备 AVTransport 端点发送控制命令
  - `func play(url: URL)` — SetAVTransportURI + Play
  - `func pause()` / `func resume()` / `func stop()`
  - `func seek(to: TimeInterval)`
  - `func setVolume(_ volume: Float)` — 通过 RenderingControl 端点
  - `func getPlaybackInfo()` — 查询 GetPositionInfo / GetTransportInfo 轮询状态
  - 心跳检测（每隔 10s 查询设备状态，确认连接存活）
- [ ] 状态机：.idle, .discovering, .connecting, .connected, .playing, .paused, .disconnected
- [ ] `Combine` publisher：`stateDidChange`, `playbackDidUpdate` 供 UI 层订阅
- [ ] 注意：DLNA 设备端直接拉流 URL，不经过 iPhone 中转

### 6.3 AirPlay 2（辅助通道）
- [ ] 在设备选择列表底部添加 `AVRoutePickerView` 作为备选方式
- [ ] 监听路由变化（`AVAudioSession.routeChangeNotification`）
- [ ] DLNA 和 AirPlay 互斥：同一时间只能使用一种；若正在 DLNA 投屏时启动 AirPlay，先断开 DLNA
- [ ] AirPlay 时隐藏部分本地播放控件（如画幅切换）

### 6.4 投屏状态管理与 UI
- [ ] `CastingState` 枚举（与 6.2 统一）：.idle, .discovering, .connecting, .connected, .playing, .paused, .disconnected
- [ ] `CastingControlBar`（自定义 UIView）：
  - 设备选择按钮 → 弹出设备选择器（DLNA 列表 + AirPlay AVRoutePickerView）
  - 投屏中显示"正在投屏到 [设备名]" + 设备图标
  - 播放/暂停/停止投屏按钮
  - 音量滑块
- [ ] 投屏时本地播放器静音（避免双重声音）
- [ ] 投屏断开时自动切回本地播放（带渐入过渡）

### 6.5 DLNA 兼容性处理
- [ ] 不同品牌电视的 SOAP 响应差异处理（小米、海信、TCL、创维、索尼等）
- [ ] 部分设备不支持 SetAVTransportURI 时的回退方案（尝试 DLNA MediaRenderer 1.0 兼容模式）
- [ ] 流格式兼容：HLS (.m3u8) 国内电视普遍支持，MPEG-TS 次之，RTSP 多数不支持
- [ ] 设备超时与重连策略（10s 无心跳 → 标记断开，自动重连最多 3 次）

---

## 阶段七：设置与偏好（预计 2 天）

### 7.1 设置 ViewModel
- [ ] `SettingsViewModel`：
  - 播放设置：默认画质（自动/高/中/低）、硬件解码开关、缓冲时长
  - EPG 设置：数据刷新频率、缓存天数
  - 外观：深色/浅色/跟随系统
  - 关于：版本号、开源许可、隐私政策链接

### 7.2 设置 UI
- [ ] `SettingsViewController`（UITableViewController, grouped style）：
  - Section: 播放 / EPG / 外观 / 缓存 / 关于
  - 缓存清理入口 → 显示缓存大小 → 确认弹窗 → 清理
- [ ] 播放源管理：列表展示已添加的 m3u/EPG 源，支持删除、设为默认

### 7.3 数据管理
- [ ] 缓存大小计算（EPG 数据库 + 频道 logo 图片缓存）
- [ ] 一键清理缓存
- [ ] 导出/导入用户数据（收藏列表、播放源列表）为 JSON

---

## 阶段八：细节打磨（预计 3-4 天）

### 8.1 空状态与错误状态
- [ ] 统一空状态组件 `EmptyStateView`（图标 + 提示文字 + 操作按钮）
- [ ] 频道列表为空 → "还没有频道，去添加播放源吧" + 添加按钮
- [ ] EPG 为空 → "暂无节目数据，下拉刷新试试"
- [ ] 收藏为空 → "长按频道可收藏" 引导

### 8.2 启动体验
- [ ] LaunchScreen 设计（App 图标 + 名称居中，简洁）
- [ ] 首次启动引导（2-3 页引导页，介绍核心功能）
- [ ] 恢复上次播放状态（退出时记录正在播放的频道和进度，下次启动恢复）

### 8.3 国际化
- [ ] 所有用户可见文字用 `NSLocalizedString`
- [ ] 初始支持中文 + 英文
- [ ] 导出 Localizable.strings

### 8.4 无障碍
- [ ] 所有按钮添加 `accessibilityLabel`
- [ ] 播放控制条支持 VoiceOver 操作
- [ ] 频道列表支持 VoiceOver 导航

### 8.5 错误日志
- [ ] 集成 OSLog（`os.Logger`），关键路径打点：
  - 播放开始/失败/重试
  - m3u 解析成功/失败
  - EPG 刷新成功/失败
  - 投屏连接/断开
- [ ] 可选：集成 Firebase Crashlytics 用于线上崩溃监控

---

## 阶段九：测试（预计 3-4 天）

### 9.1 单元测试
- [ ] `M3UParserTests`：正常/空/损坏/特殊字符 m3u 的解析测试
- [ ] `XMLTVParserTests`：正常/缺字段/时区/编码的解析测试
- [ ] `ChannelListViewModelTests`：搜索过滤、分组逻辑、收藏操作
- [ ] `EPGViewModelTests`：时间范围查询、数据合并
- [ ] `PlayerServiceTests`：状态机转换逻辑

### 9.2 UI 测试
- [ ] 频道列表：搜索过滤、分组切换
- [ ] 播放器：播放/暂停、全屏切换、进度拖拽
- [ ] EPG：时间轴滚动、节目点击

### 9.3 集成测试
- [ ] 播放源添加 → 解析 → 入库 → 列表显示（端到端）
- [ ] 播放 → 锁屏控制 → 解锁（状态一致）
- [ ] 投屏 → 断开 → 回到本地播放（平滑过渡）

---

## 阶段十：发布准备（预计 2 天）

### 10.1 App Store 合规
- [ ] PrivacyInfo.xcprivacy：声明网络访问、相册访问（如果需要）、Crashlytics（如果使用）
- [ ] 截图和预览视频
- [ ] 应用描述和关键词
- [ ] 审核说明：强调本 App 是"播放器工具"，不内置任何频道，由用户自行提供播放源

### 10.2 CI/CD
- [ ] GitHub Actions：每次 push 执行单元测试 + UI 测试
- [ ] 配置 TestFlight 自动上传（Fastlane 或 Xcode Cloud）
- [ ] 版本号自动化

---

## 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| VLCKit 在 iOS 新版上崩溃 | 中 | 高 | 保持 VLCKit 版本更新；准备 AVPlayer 回退方案用于 HLS 流 |
| DLNA 不同品牌电视 SOAP 兼容性差异大 | 高 | 中 | 主流品牌（小米/海信/TCL/创维/索尼）逐一适配测试；提供兼容模式回退；App 描述注明已适配品牌列表 |
| App Store 以 IPTV 为由拒绝 | 中 | 高 | 定位为"播放器工具"而非"电视应用"；不内置任何频道；审核时提供测试 m3u 文件 |
| EPG 数据源不稳定 | 高 | 中 | 本地缓存 3 天数据；支持多源切换；离线时显示缓存数据 |
| m3u 源格式多样导致解析失败 | 高 | 中 | 广泛测试真实世界的 m3u 文件；提供错误提示帮助用户判断是否是格式问题 |

---

## 总时间估算

| 阶段 | 预计工期 |
|------|----------|
| 一、项目基础设施 | 2-3 天 |
| 二、数据模型与解析器 | 2-3 天 |
| 三、频道管理 | 3-4 天 |
| 四、视频播放器 | 5-7 天 |
| 五、节目指南 EPG | 4-5 天 |
| 六、投屏功能 | 4-5 天 |
| 七、设置与偏好 | 2 天 |
| 八、细节打磨 | 3-4 天 |
| 九、测试 | 3-4 天 |
| 十、发布准备 | 2 天 |
| **合计** | **30-42 天**（单人全职） |

---

## 依赖关系（简化）

```
阶段一 ──► 阶段二 ──► 阶段三 ──► 阶段四 ──► 阶段六
                              │              │
                              └── 阶段五 ◄──┘
                                    │
                        阶段七 ◄────┘
                                    │
                              阶段八 ◄── 阶段九（可与八并行）
                                    │
                              阶段十 ◄── 阶段八、九完成
```

阶段三（频道管理）必须在阶段四（播放器）之前完成，否则没有可点击播放的频道。
阶段五（EPG）依赖阶段三的频道数据模型。
阶段六（投屏）依赖阶段四的播放器核心功能稳定。
阶段七、八、九可以在核心功能完成后并行推进。
