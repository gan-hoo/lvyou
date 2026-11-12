# Tally — 设计与架构

## 1. 设计系统（`DesignSystem/`）

| Token | 定义 | 说明 |
|---|---|---|
| 颜色 `DS.Colors` | accent `#3E7BFA / #5B8DFF`，income `#16A06A / #3DD68C`，warning、danger、transfer；背景与卡片使用系统分组背景色 | 浅 / 深色动态色；支出用主文字色而非红色，避免焦虑感 |
| 调色板 `DS.Palette` | 18 个低饱和色板 | 分类、账户、标签共用，深浅模式下都清晰 |
| 字体 `DS.Typography` | SF Pro；金额使用 SF Pro Rounded + 等宽数字 | 全部基于 Dynamic Type 文本样式（记账键盘大号金额除外） |
| 间距 `DS.Spacing` | 2 / 4 / 8 / 12 / 16 / 20 / 28 | 页面左右边距 16 |
| 圆角 `DS.Radius` | 卡片 22、内层 14、控件 12、键盘 16 | 全部 `.continuous` 连续曲率 |
| 动画 `DS.Motion` | spring(0.42, 0.86)、snappy、gentle | `withMotion {}` 与 `DS.Motion.adaptive` 在「减弱动态效果」开启时改为短淡入淡出 |
| 材质 `glass(in:)` | iOS 26 SDK 编译时使用系统 `glassEffect`（Liquid Glass），否则 `ultraThinMaterial` + 0.6pt 高光描边 | 仅用于浮动按钮、Toast 等浮层；内容卡片用纯色卡片，不滥用模糊和阴影 |
| 触感 `Haptics` | tap / selection / success / warning / error | 设置中可关闭 |

通用组件：`SymbolBadge`（分类 / 账户图标）、`AmountText`（`numericText` 数字过渡）、`CapsuleProgress`、`RingProgress`、`Chip`、`MetricView`、`FloatingAddButton`、`PressableStyle`、`Toast`、`FlowLayout`、`SymbolPickerGrid`、`ColorSwatchPicker`、`SettingsLabel`。

## 2. 导航

```
RootView ─┬─ OnboardingView（首次启动：主币种、开始使用 / 演示数据）
          ├─ MainTabView（TabView）
          │   ├─ 首页 Dashboard ── push: 账户列表 / 账户详情 / 交易详情
          │   ├─ 流水 Transactions ── sheet: 筛选；push: 交易详情 / 账户详情
          │   ├─ 统计 Statistics ── push: 分类明细 → 交易详情
          │   ├─ 预算 Budget ── sheet: 预算编辑
          │   └─ 设置 Settings ── push: 账户 / 分类 / 标签 / 汇率 / 导入导出
          │   sheet（全局）: QuickEntrySheet ← AppRouter.entryRequest
          ├─ LockScreenView（启用应用锁且已锁定）
          └─ PrivacyCoverView（App 不在前台时遮盖内容）
```

快速记账由 `AppRouter`（`@Observable`，经 Environment 注入）统一弹出：首页 / 流水的悬浮按钮、账户详情的「记一笔 / 转账」、各处的「编辑」都只是设置 `entryRequest`。

## 3. 架构（MVVM + 服务层）

```
Views (SwiftUI)          @Query 订阅数据变化 → 保存后各页面自动刷新
   │
ViewModels               QuickEntryViewModel（@Observable）、AmountExpression、TransactionFilter
   │
Services                 LedgerStore（唯一写入入口：校验 + 汇率快照）
                         LedgerMath（余额、汇总、分类构成、时间序列，纯函数）
                         CurrencyConverter（历史汇率查找：二分 + 反向 + 交叉）
                         BudgetEvaluator / BudgetNotifier
                         LedgerCSVExporter / LedgerCSVImporter
                         AppLockManager（LocalAuthentication）+ KeychainStore
                         ExchangeRateFetcher（async/await，可选）
   │
Models (SwiftData)       Account, LedgerEntry, LedgerCategory, Tag, Budget, ExchangeRate
```

## 4. 数据模型

- **金额精度**：所有金额是 `Decimal`，以 POSIX 十进制字符串持久化（`DecimalCodec`），避免存储层把 Decimal 转成浮点。计算全程 Decimal，仅在绘图时转 Double。
- **余额从不存储**：`余额 = 期初余额 + 收入 − 支出 − 转出 + 转入（转入币种金额）`，由 `LedgerMath.balances` 每次从交易计算。
- **多币种**：
  - `LedgerEntry.amount + currencyCode`：原币金额（= 账户币种）。
  - `baseCurrencyCode + rateToBase + baseAmount`：保存时按「交易日期当天生效的最新汇率」生成的折算快照。
  - 统计使用快照；若之后更改了主币种，则用历史汇率表按交易日期重新换算（快照保留不动）。
  - 只改备注 / 分类等不会重算快照；改金额、日期或币种时按当日汇率重算。
  - 跨币种转账单独保存 `toAmount`（目标币种实际到账金额），可手动填写。
- **ExchangeRate**：`1 base = rate quote`，带 `effectiveDate` 与来源（参考 / 手动 / 欧洲央行 / 导入）。默认参考汇率生效日期为 2000-01-01，仅用于开箱即用。
- **预算**：每月循环；`category == nil` 为总预算；金额以创建时主币种保存，评估时换算。
- **演示数据**：`isDemo` 标记，`LedgerStore.deleteDemoData()` 精确清除。
- **CloudKit 兼容**：所有属性有默认值、关系均为可选、无唯一约束，后续可直接打开 `cloudKitDatabase` 做 iCloud 同步。

## 5. 安全

- `AppLockManager` 使用 `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`：优先 Face ID / Touch ID，失败回落设备密码。
- 开 / 关应用锁都需要先验证；锁定开关、宽限时间、隐私遮罩保存在钥匙串（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随备份迁移）。
- 进入后台记录时间，回到前台超过宽限时间即锁定；App 切换器中显示模糊遮罩。
- 「清除所有数据」需要身份验证。

## 6. 性能

- 每个页面一次性把 `@Query` 结果计算成快照结构（`DashboardSnapshot`、`StatisticsSnapshot`），子视图只读快照。
- 汇率查找按币种对预排序后二分查找；分组、汇总均为单次遍历。
- 动画只作用于状态变化的局部（数字、进度、选中态），图表使用系统 Charts 渲染。

## 7. 无障碍

- Dynamic Type、VoiceOver 标签（键盘按键、图表扇区、进度、金额组合朗读）、`isSelected` 特征、「减弱动态效果」、浅深色对比。
