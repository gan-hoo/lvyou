# 旅行足迹（Travel Footprints）— 产品与技术设计

> 记录去过的每一个地方，珍藏每一段旅程。

## 1. 产品功能结构

```
旅行足迹
├── 地图（首页）
│   ├── 全屏交互式地图（Apple MapKit，写实高程）
│   ├── 用户当前位置（仅授权后显示，按需申请权限）
│   ├── 已打卡景点标记（多次到访显示次数角标）
│   ├── 点击标记 → 景点摘要面板（名称 / 最近到访 / 次数 / 历史）
│   └── 顶部搜索入口 + 定位按钮
├── 全球景点搜索
│   ├── 输入联想（MKLocalSearchCompleter）
│   ├── 完整搜索（MKLocalSearch）：名称、类别、地址、城市·国家、经纬度、地图预览
│   └── 无结果 / 网络错误 / 频率限制 / 重复搜索取消
├── 景点详情
│   ├── 地图 + 打卡范围圆圈
│   ├── 地址、城市·国家、坐标
│   ├── 与用户的距离（已授权时自动刷新）
│   ├── GPS 打卡（核心）
│   ├── 手动补录过去的旅行（明确标记「手动记录」）
│   └── 历史到访记录
├── GPS 打卡
│   ├── 按需请求定位权限 → 必要时请求临时精确位置
│   ├── 单次定位（15 秒超时，不持续定位）
│   ├── 验证：精度 ≤ 100 m、定位时效 ≤ 60 s、距离 ≤ 打卡半径（默认 200 m）
│   ├── 保存：UTC 时间、时区标识、UTC 偏移、GPS 坐标、精度、距离
│   └── 成功反馈（动画 + 触觉）/ 明确的失败原因与下一步
├── 足迹
│   ├── 全部去过的景点地图
│   ├── 打卡次数 / 景点数 / 城市数
│   ├── 按国家、城市筛选
│   └── 按最近到访时间排序的景点列表
├── 时间线
│   ├── 按当地月份分组、时间倒序
│   ├── 记录详情：当地时间、时区、UTC、验证信息、备注编辑
│   └── 删除记录（滑动删除 / 详情页删除，均需确认）
└── 我的
    ├── 旅行统计：国家、城市、景点、打卡次数、最近一次旅行、每年打卡数
    ├── 隐私与权限：定位权限状态、跳转系统设置
    └── 关于
```

## 2. 页面导航结构

```
TabView（RootTabView）
├── 地图 MapHomeView
│   ├── sheet: SearchView ─ NavigationStack
│   │   └── push: PlaceDetailView
│   │       ├── sheet: CheckInSuccessView
│   │       ├── sheet: ManualCheckInView
│   │       └── push: CheckInDetailView
│   └── sheet: PlaceSummarySheet ─ NavigationStack（medium / large 档位）
│       ├── push: PlaceDetailView
│       └── push: CheckInDetailView
├── 足迹 FootprintsView ─ NavigationStack
│   └── push: PlaceDetailView → CheckInDetailView
├── 时间线 TravelTimelineView ─ NavigationStack
│   └── push: CheckInDetailView → PlaceDetailView
└── 我的 ProfileView ─ NavigationStack
    └── push: CheckInDetailView
```

导航全部采用基于值的 `NavigationLink(value:)`，每个 `NavigationStack` 根视图通过
`.travelDestinations()` 统一注册 `PlaceCandidate` 与 `CheckIn` 两种目的地。

## 3. 技术架构

```
┌──────────────────────────── Views (SwiftUI) ────────────────────────────┐
│ MapHomeView  SearchView  PlaceDetailView  FootprintsView  Timeline ...  │
└──────────────┬───────────────────────────────────────────┬──────────────┘
               │ @State / @Bindable / @Query                │
┌──────────────▼───────── ViewModels (@Observable) ─────────▼──────────────┐
│ SearchViewModel  PlaceDetailViewModel  FootprintsViewModel  Timeline    │
└──────────────┬───────────────────────────────────────────┬──────────────┘
               │                                            │
┌──────────────▼──────────────── Services ──────────────────▼──────────────┐
│ LocationService (Core Location, 单次定位)                                │
│ SearchCompleter / PlaceSearchService (MapKit)                            │
│ CheckInValidator (纯逻辑)  CheckInStore (SwiftData 仓库)                 │
│ TravelStatistics (纯逻辑)  MapItemAdapter (MKMapItem → PlaceCandidate)  │
└──────────────┬───────────────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────── Models (SwiftData) ───────────────────────┐
│ Place 1 ── * CheckIn          PlaceCandidate（值类型，搜索结果 / 导航）   │
└──────────────────────────────────────────────────────────────────────────┘
```

- **UI**：SwiftUI，iOS 17+，系统字体、SF Symbols、系统材质，支持浅色 / 深色与 Dynamic Type。
- **状态**：Observation 框架（`@Observable`），所有 ViewModel 与服务均为 `@MainActor`。
- **并发**：Swift Concurrency。定位与授权使用 `CheckedContinuation` 桥接代理回调，
  搜索使用 `MKLocalSearch.start()` async，新搜索会取消旧搜索。
- **持久化**：SwiftData。列表视图直接用 `@Query` 观察数据，写操作统一经过 `CheckInStore`。
- **依赖**：仅系统框架（SwiftUI、SwiftData、MapKit、Core Location、Contacts）。
- **国际化**：开发语言为简体中文（`zh-Hans`），界面字符串通过 `LocalizedStringKey` /
  `String(localized:)` 编写，Xcode 构建时自动提取到 `Localizable.xcstrings`，后续直接在
  String Catalog 中添加 English 即可。

## 4. Xcode 项目目录树

```
lvyou/
├── TravelFootprints.xcodeproj           # Xcode 16+ 项目（文件夹同步组，无需手动添加文件）
│   └── xcshareddata/xcschemes/TravelFootprints.xcscheme
├── TravelFootprints/
│   ├── Info.plist                       # 定位 / 照片权限说明
│   ├── App/
│   │   ├── TravelFootprintsApp.swift    # @main，创建 ModelContainer 与 LocationService
│   │   ├── RootTabView.swift            # 四个 Tab
│   │   └── PreviewSampleData.swift      # 仅 DEBUG 预览数据
│   ├── Models/
│   │   ├── Place.swift                  # @Model 景点
│   │   ├── CheckIn.swift                # @Model 打卡记录
│   │   ├── CheckInMethod.swift          # GPS 验证 / 手动记录
│   │   ├── PlaceCandidate.swift         # 值类型地点（搜索结果 / 导航）
│   │   └── PersistenceController.swift  # ModelContainer 工厂（预留 CloudKit）
│   ├── Services/
│   │   ├── LocationService.swift        # 按需单次定位、权限、精确位置
│   │   ├── CheckInValidator.swift       # 打卡验证规则与半径规则
│   │   ├── CheckInStore.swift           # SwiftData 读写、景点匹配与清理
│   │   ├── SearchCompleter.swift        # MKLocalSearchCompleter 封装
│   │   ├── PlaceSearchService.swift     # MKLocalSearch 封装与错误映射
│   │   ├── MapItemAdapter.swift         # MKMapItem → PlaceCandidate
│   │   └── TravelStatistics.swift       # 统计计算
│   ├── ViewModels/
│   │   ├── SearchViewModel.swift
│   │   ├── PlaceDetailViewModel.swift   # 打卡流程状态机 + CheckInFailure
│   │   ├── FootprintsViewModel.swift    # 筛选与汇总
│   │   └── TimelineViewModel.swift      # 按当地月份分组
│   ├── Views/
│   │   ├── Map/          MapHomeView, PlaceMarkerView, PlaceSummarySheet
│   │   ├── Search/       SearchView, SearchResultRow, MapSnapshotView
│   │   ├── PlaceDetail/  PlaceDetailView, CheckInSuccessView, ManualCheckInView, CheckInFailureCard
│   │   ├── Footprints/   FootprintsView
│   │   ├── Timeline/     TravelTimelineView, CheckInDetailView
│   │   ├── Profile/      ProfileView
│   │   └── Components/   Components.swift（卡片、标签、统计块、记录行、导航目的地）
│   ├── Utilities/
│   │   ├── CheckInDateFormatter.swift   # 时区感知的日期展示
│   │   └── Formatting.swift             # 距离、坐标、城市·国家文本
│   └── Resources/
│       ├── Assets.xcassets              # AppIcon、AccentColor（浅 / 深色）
│       └── Localizable.xcstrings        # String Catalog
├── TravelFootprintsTests/               # Swift Testing 单元测试
├── SimulatorLocations/                  # 模拟器测试用 GPX 坐标
└── docs/ARCHITECTURE.md
```

## 5. SwiftData 数据模型设计

```
Place                                   CheckIn
──────────────────────────────          ─────────────────────────────────
id: UUID                                id: UUID
name: String                            place: Place?            ← 多对一
address: String?                        createdAt: Date          记录写入时间
locality: String?          城市          visitedAt: Date          实际到访时间（绝对时间 = UTC）
administrativeArea: String? 省/州        timeZoneIdentifier: String  IANA，如 Asia/Tokyo
country: String?                        utcOffsetSeconds: Int    打卡时 UTC 偏移（兜底）
countryCode: String?       ISO 代码      methodRawValue: String   "gps" | "manual"
latitude / longitude: Double            gpsLatitude / gpsLongitude: Double?
mapItemIdentifier: String? MapKit 标识   gpsHorizontalAccuracy: Double?
pointOfInterestCategory: String?        distanceFromPlace: Double?
timeZoneIdentifier: String?             note: String
checkInRadius: Double = 200             photoFileNames: [String]  沙盒相对路径（第二阶段）
createdAt: Date                         updatedAt: Date
checkIns: [CheckIn]?  ── cascade ──▶
```

设计要点：

- **一对多**：`Place.checkIns` 删除规则为 `cascade`；`CheckIn.place` 为可选反向关系。
  同一景点多次打卡各自独立成记录。
- **景点匹配**：优先 `mapItemIdentifier`（iOS 18+），否则按名称 + 100 米内坐标匹配，避免重复创建。
- **时间**：`visitedAt` 是绝对时间点；展示始终使用记录自身的 `timeZoneIdentifier`，
  即使用户回国后查看东京的记录，显示的仍是东京当地日期时间。
- **验证方式不可伪造**：`methodRawValue` 默认值为 `manual`，只有通过 `CheckInValidator`
  验证后的 `recordGPSCheckIn` 才会写入 `gps`。
- **CloudKit 预留**：无唯一约束、全部属性可选或有默认值、关系可选；容器创建处显式
  `cloudKitDatabase: .none`，开启同步只需改一处并添加 iCloud 能力。
- **导出预留**：所有字段均为基础类型（UUID / String / Double / Date），可直接映射为 JSON / CSV / GPX。
- **照片**：只保存文件名，图片文件存放在 App 沙盒（第二阶段实现），避免数据库膨胀，也便于导出。

## 6. 第一阶段 MVP 实施顺序

| # | 模块 | 主要文件 | 验证方式 |
|---|------|---------|---------|
| 1 | 项目结构、Info.plist、资源 | `TravelFootprints.xcodeproj`、`Info.plist` | ⌘B 构建成功 |
| 2 | 数据模型与持久化 | `Models/*` | `CheckInStoreTests` |
| 3 | 时间与格式化工具 | `Utilities/*` | `CheckInDateFormatterTests` |
| 4 | 底部导航 | `RootTabView` | 运行，切换四个 Tab |
| 5 | MapKit 首页 | `MapHomeView`、`PlaceMarkerView` | 地图显示；定位按钮请求权限 |
| 6 | 景点搜索 | `SearchCompleter`、`PlaceSearchService`、`SearchViewModel`、`SearchView` | 搜索 “Sydney Opera House” |
| 7 | 景点详情 | `PlaceDetailView`、`PlaceDetailViewModel` | 查看地图、地址、距离 |
| 8 | GPS 验证打卡 | `LocationService`、`CheckInValidator`、`CheckInStore` | 模拟器设置景点坐标后打卡；`CheckInValidatorTests` |
| 9 | 自动记录时间 + 本地保存 | `CheckIn`、`CheckInStore` | 打卡成功页显示时间与时区 |
| 10 | 地图足迹 | `MapHomeView`、`FootprintsView` | 打卡后地图出现标记 |
| 11 | 基础历史记录 | `TravelTimelineView`、`CheckInDetailView` | 时间线列表、删除记录 |

第一阶段额外完成了：手动补录、备注编辑、按国家 / 城市筛选与基础统计（这些逻辑简单且与 MVP 数据结构直接相关）。

## 后续阶段

**第二阶段**：照片（PhotosPicker → 沙盒存储 → `photoFileNames`）、时间线搜索与筛选、
统计图表（Swift Charts）、更丰富的动画与过渡。

**第三阶段**：iCloud 同步（`cloudKitDatabase: .private(...)`）、旅行年度报告、
导出（JSON / CSV / GPX，`ShareLink`）、到达景点提醒（`CLMonitor` 地理围栏，需单独的权限说明）、
更多地图可视化（国家着色、热力图）。
