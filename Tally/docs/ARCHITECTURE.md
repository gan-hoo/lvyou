# Tally V3 — 设计与架构

财务计算规则见 [FINANCE_RULES.md](FINANCE_RULES.md)。优先级：财务数据正确性 > 核心功能可用性 > 操作效率 > UI 一致性 > 视觉特效。

## 1. 分层（MVVM + Repository + Service）

```
Views (SwiftUI, Features/*)        只负责展示与交互；读 @Query（模型列表）和 LedgerCache（计算结果）
   │
ViewModels                          QuickEntryViewModel（@Observable，草稿状态 + 校验）、AmountExpression（计算器）、TransactionFilter
   │
Services                            TransactionService   交易的唯一写入入口：校验 → 汇率快照 → 原子提交 → 审计
                                    LedgerRepository     读取、提交（失败回滚）、审计、账户/分类/预算/汇率/演示数据
                                    RecurringService     到期周期交易入账（按规则 ID + 日期去重）
                                    BackupService        JSON 备份（格式名、版本号、SHA-256 校验）与合并 / 替换恢复
                                    IntegrityService     数据完整性检查与安全修复
                                    LedgerCSVExporter / LedgerCSVImporter、BudgetNotifier、AppLockManager、KeychainStore、ExchangeRateFetcher
                                    LedgerCache          @Observable 计算缓存：存储保存后重建快照，重计算放后台线程，按版本记忆
   │
Domain（纯值类型，Sendable）         LedgerSnapshot（AccountValue / EntryValue / BudgetValue / RatePoint）
                                    FinanceEngine（余额、净资产、收支报表、分类构成、日 / 月趋势）
                                    BudgetEngine（周期、已用、结转、提醒级别、每日可用）
                                    Recurrence（周期日期计算）、CurrencyConverter（历史汇率查找）
   │
Models (SwiftData)                  Account, LedgerEntry, TransactionSplit, LedgerCategory, Tag, Budget,
                                    RecurringRule, ExchangeRate, AuditRecord；偏好设置在 UserDefaults（AppSettings），安全设置在钥匙串
```

- Domain 层不依赖 SwiftData / SwiftUI，单元测试直接构造值对象验证财务规则。
- 所有写操作经过 `LedgerRepository.commit()`：保存失败即 `rollback()`，不会留下半条记录。交易保存前先完成全部校验与跨币种金额解析，再插入模型。
- 删除、编辑、余额调整、导入、恢复、预算增删都会写一条 `AuditRecord`，设置 › 数据 › 变更记录可查看。

## 2. 导航

```
RootView ─┬─ OnboardingView（首次：本位币、开始使用 / 演示数据）
          ├─ MainTabView（TabView，默认「资产」）
          │   ├─ 资产 Assets ── push: 账户详情（余额、已核对余额、信息、交易、转账 / 对账 / 编辑 / 归档）
          │   ├─ 流水 Transactions ── 月份切换 / 自定义区间、搜索、筛选；push: 交易详情；周期计划
          │   ├─ 统计 Analytics ── 周 / 月 / 年 / 自定义；点分类 → 跳到流水并带筛选
          │   ├─ 预算 Budgets ── sheet: 预算编辑；点预算 → 跳到流水并带筛选
          │   └─ 设置 Settings ── 外观 / 财务 / 数据 / 隐私 / 关于
          │   sheet（全局）: QuickEntrySheet ← AppRouter.entryRequest
          ├─ LockScreenView（启用应用锁且已锁定）
          └─ PrivacyCoverView（App 不在前台时遮盖）
```

`AppRouter`（`@Observable`）统一负责：选中标签、弹出快速记账（新建 / 编辑 / 退款）、跨页跳转到带筛选条件的流水（`TransactionQuery`）。

## 3. 设计系统（`DesignSystem/`）

| Token | 内容 |
|---|---|
| `DS.Colors` | 强调色可在设置中选择（8 种）；收入绿、警告橙、危险红、转账蓝灰；支出用主文字色 |
| `DS.Typography` | SF Pro / SF Pro Rounded，金额等宽数字，全部基于 Dynamic Type |
| `DS.Spacing` / `DS.Radius` | 2–28 间距；卡片 22、内层 14、控件 12，连续曲率 |
| `DS.Motion` | spring / snappy / gentle；「减弱动态效果」时改为短淡入淡出 |
| `FinanceCard` / `PageBackground` | 经典主题：不透明分组卡片；液态玻璃主题：iOS 26 系统 `glassEffect`，早期系统用半透明材质 + 高光描边 |

两种主题共用同一套页面与组件，只替换卡片表面与页面背景。主题、强调色、金额格式、隐藏金额改变时根视图重建，保证全部页面一致。

通用组件：`SymbolBadge`、`AmountText`（数字过渡）、`CapsuleProgress`、`RingProgress`、`Chip`、`Toast`、`AddMenuButton`、`SettingsLabel`、`SymbolPickerGrid`、`ColorSwatchPicker`。

## 4. 性能

- `LedgerCache` 在 `ModelContext.didSave` 后（80 ms 合并）重建一次只读快照；统计、预算等计算在 `Task.detached` 后台执行，结果按「快照版本 + 参数」缓存，切换页面不会重复计算。
- 汇率按币种对排序后二分查找；报表、分类、预算均为单次遍历。
- 列表使用 `List` / `LazyVStack`，图表用 Swift Charts。

## 5. 安全与隐私

- `AppLockManager`：`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`，Face ID 失败可用设备密码；开关、自动锁定时间、多任务遮罩存钥匙串（仅本机）。
- 「隐藏金额」在所有页面把金额显示为 `••••`，输入框除外。
- 「替换恢复」与「清除全部数据」前需要身份验证。
- 唯一的网络请求：用户手动点击「下载今日汇率」。

## 6. 数据兼容

- 所有 SwiftData 属性都有默认值、关系可选、无唯一约束（轻量迁移；可开启 CloudKit）。V1/V2 的数据在 V3 首次启动时直接可用：旧账户的初始余额日期为「最早」，旧交易没有快照时按历史汇率计算。
- 备份文件 `schemaVersion = 3`；更新版本的备份会被拒绝，校验值不符会被拒绝。
