# Tally 记账

<img src="docs/icon-preview.png" width="96" align="right" alt="Tally icon">

原生 iOS 个人记账 App（V3）：SwiftUI + SwiftData + Swift Charts，资产优先的五个标签页（资产 / 流水 / 统计 / 预算 / 设置），支持资产与负债、转账手续费、退款、拆分、信用卡还款、余额调整、周期交易、多币种历史汇率、周 / 月 / 年 / 自定义统计与预算、CSV 与 JSON 备份、Face ID 锁定，简体中文 / 繁體中文 / English，完全离线。

- **最低系统**：iOS 17.0（iPhone，竖屏）
- **工程**：`Tally.xcodeproj`（Xcode 16+，文件夹同步组格式；新增 Swift 文件放进 `Tally/` 任意子目录即可自动加入目标）
- **依赖**：无第三方依赖，全部使用 Apple 系统框架
- **Bundle Identifier**：`com.ganhoo.tally`（测试目标 `com.ganhoo.tallyTests`）
- 架构：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · 财务规则：[docs/FINANCE_RULES.md](docs/FINANCE_RULES.md) · 构建与测试记录、已知问题：[docs/DELIVERY.md](docs/DELIVERY.md)

---

## 功能

| 模块 | 内容 |
|---|---|
| 资产（默认页） | 净资产、总资产、总负债，本位币一键切换，隐藏金额；账户类型：现金、日常卡、储蓄、电子钱包、多币种、投资、其他资产、信用卡、负债；按类型 / 币种 / 自定义分组，拖动排序，归档；初始余额 + 初始余额日期、备注、是否计入净资产；无汇率的账户标记「待折算」，不按 1:1 计入 |
| 账户详情 | 当前余额、已核对余额、账户信息、该账户交易；记一笔、转账、对账（生成可审计的余额调整）、信用卡还款、编辑、归档 |
| 快速记账 | 底部 Sheet；支出（默认）/ 收入 / 转账；计算器键盘（`+` `−`，按币种小数位）；分类、账户、日期时间、备注、标签、收付款方；拆分（合计必须等于总额，第一项自动填入剩余）；支出的折扣与手续费（实付 = 原价 − 折扣 + 手续费）；转账手续费（计入「手续费」分类支出）与两端不同金额；记住上次选择；保存成功后才关闭，触感 + Toast；有改动时下滑关闭会二次确认 |
| 流水 | 月份切换 / 自定义区间；搜索（备注、收付款方、分类、账户、标签、金额）；按账户、分类、类型、标签、金额筛选；左滑编辑 / 删除，复制；退款关联原交易；周期计划管理 |
| 统计 | 周 / 月 / 年 / 自定义；收入、支出、净收支与上期同口径对比；分类环形图 + 排行，点分类跳到筛选好的流水；每日支出、月度收支、月度净收支；显示汇率口径与待换算笔数；转账、还款、余额调整不计入收支 |
| 预算 | 总预算与分类预算；月 / 周 / 年 / 自定义周期，月度起始日可设；已用、剩余、百分比、剩余天数、每日可用；超支显示超出金额；结转；排除分类；退款冲减；跨币种预算按汇率换算；预算多时自动紧凑列表；超过阈值 App 内提醒（每期每级一次） |
| 设置 | 外观（经典 / 液态玻璃主题、浅色 / 深色 / 跟随系统、强调色、金额格式、语言）；财务（本位币、汇率、账户入口、默认账户、分类、标签、周期计划、预算月起始日）；数据（CSV 导入导出、JSON 备份与恢复、数据完整性检查、变更记录、演示数据、清除数据）；隐私（Face ID 锁、自动锁定、多任务遮罩、隐藏金额、隐私说明）；关于（版本、更新说明、致谢、反馈诊断信息） |
| 多币种 | 每笔交易保存原币金额、币种、日期、账户、类型和当日汇率快照；没有汇率时标记「待换算」，**绝不假设 1:1**；补录汇率后自动补齐；手动汇率与历史汇率表；离线可用 |
| 数据安全 | 所有写入原子提交、失败回滚；删除 / 编辑 / 调整 / 导入 / 恢复记入变更记录；备份带格式版本与 SHA-256 校验，恢复前预览、合并时按 ID 去重 |

演示数据：首次启动可选「使用演示数据体验」，生成约 100 天的记录（含澳元账户、跨币种转账与手续费、拆分 + 退款、信用卡、贷款、每月房租周期计划）。所有演示对象带 `isDemo` 标记，可在资产页或设置 › 数据中一键移除，不影响自己的记录。

---

## 在 Xcode 中运行

1. 用 Xcode 16 或更高版本打开 `Tally/Tally.xcodeproj`。
2. 选择 Scheme **Tally** 和一台 iPhone 模拟器，⌘R。
3. ⌘U 运行单元测试（Swift Testing，覆盖收支、转账与手续费、退款、信用卡消费与还款、负债、多币种与待换算、拆分、预算与结转、编辑删除、余额调整、舍入、周期交易去重、备份校验、CSV 往返等，清单见 docs/DELIVERY.md）。

命令行：

```bash
cd Tally
xcodebuild test -project Tally.xcodeproj -scheme Tally \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 签名与导出 IPA

> IPA 必须在 macOS + Xcode 上用有效的 Apple 签名导出。本仓库的 CI 会在每次推送时 **Archive 出未签名 IPA**；有签名证书时可用下面任一方式导出可直接安装的 IPA。

### 方式 A：本机 Xcode（推荐）

1. Xcode › Settings › Accounts 登录 Apple ID（免费账号即可真机调试；Ad Hoc / TestFlight 需要付费开发者账号）。
2. 打开工程 › TARGETS › **Tally** › Signing & Capabilities：勾选 *Automatically manage signing*，选择你的 Team。若提示 Bundle ID 已被占用，把 `com.ganhoo.tally` 改成你自己的，例如 `com.yourname.tally`。
3. 菜单 Product › Archive（Scheme 的 Archive 使用 **Release** 配置）。
4. Organizer › Distribute App：
   - **Debugging / Development**：安装到已在开发者账号中注册的设备；
   - **Release Testing（Ad Hoc）**：安装到描述文件中包含 UDID 的设备；
   - **App Store Connect**：上传 TestFlight。

### 方式 B：命令行脚本

```bash
cd Tally
./scripts/build_ipa.sh <TEAM_ID>                         # development
./scripts/build_ipa.sh <TEAM_ID> release-testing         # Ad Hoc
./scripts/build_ipa.sh <TEAM_ID> development com.you.tally
# 产物：Tally/build/export/Tally.ipa
```

脚本使用自动签名（`-allowProvisioningUpdates`），导出选项模板在 `ExportOptions/`。

### 方式 C：GitHub Actions 导出已签名 IPA

在仓库 Settings › Secrets and variables › Actions 添加：

| Secret | 内容 |
|---|---|
| `TALLY_CERT_P12_BASE64` | 开发或分发证书 `.p12` 的 base64（`base64 -i cert.p12 \| pbcopy`） |
| `TALLY_CERT_PASSWORD` | `.p12` 密码 |
| `TALLY_PROFILE_BASE64` | 对应描述文件 `.mobileprovision` 的 base64 |
| `TALLY_TEAM_ID` | 10 位 Team ID |

然后在 Actions › **Tally signed IPA** › Run workflow，选择导出方式与 Bundle ID（须与描述文件一致），完成后在运行页面下载 `Tally-signed-*` 产物。

### 未签名 IPA（CI 自动产出）

每次推送 `Tally/` 都会运行 **Tally iOS** 工作流（`.github/workflows/tally.yml`）：

1. **Archive & unsigned IPA**：默认 Xcode（当前为 Xcode 26 / iOS 26 SDK）Release Archive → 打包 `Tally-unsigned.ipa`，在运行页面 Artifacts 中下载；
2. **Unit tests**：在 iPhone 模拟器上跑全部单元测试；
3. **Xcode 16**：用 iOS 18 SDK 再编译一次，确保旧工具链（非 Liquid Glass 分支）也能编译；
4. **Simulator screenshots**：以调试截图模式启动 App 并截取各页面（Artifacts › `tally-screenshots`）。

未签名 IPA 不能直接安装，需要用你自己的 Apple ID 重新签名，例如 Sideloadly、AltStore，或 `codesign` + 描述文件手动重签。

> 调试截图模式仅存在于 Debug 构建：启动参数 `-TallyScreenshotMode`（首次自动加载演示数据并跳过引导）、`-TallyTab assets|transactions|analytics|budgets|settings`、`-TallyOpenEntry`。

---

## iPhone 真机安装

**用 Xcode 直接安装（最简单）**
1. 数据线连接 iPhone，信任这台电脑。
2. iPhone 设置 › 隐私与安全性 › 开启 **开发者模式**（iOS 16+，开启后重启）。
3. Xcode 顶部选择你的 iPhone，⌘R。
4. 免费 Apple ID 签名时，首次打开需在 设置 › 通用 › VPN与设备管理 中信任开发者证书；免费签名 7 天后需重新安装。

**安装导出的 .ipa**
- Development / Ad Hoc IPA：设备 UDID 必须在描述文件中。可用 Finder（macOS Catalina+）把 IPA 拖到 iPhone 的「通用」页、Apple Configurator 2，或 `xcrun devicectl device install app --device <UDID> Tally.ipa`。
- TestFlight：App Store Connect 上传后通过 TestFlight App 安装。
- 未签名 IPA：先用 Sideloadly / AltStore 以你的 Apple ID 签名再安装。

首次启动会询问 Face ID 权限（仅在你开启「使用面容 ID 锁定」时）。

---

## 目录结构

```
Tally/
├── Tally.xcodeproj
├── Tally/
│   ├── App/            入口、根视图（Tab + 锁屏 + 隐私遮罩）、路由、持久化、设置项、语言
│   ├── DesignSystem/   颜色 / 字体 / 间距 / 圆角 / 动画、主题表面（经典 / 液态玻璃）、通用组件、触感
│   ├── Domain/         纯值类型财务引擎：LedgerSnapshot、FinanceEngine、BudgetEngine、Recurrence
│   ├── Models/         SwiftData 模型：Account、LedgerEntry、TransactionSplit、LedgerCategory、Tag、Budget、RecurringRule、ExchangeRate、AuditRecord
│   ├── Services/       TransactionService、LedgerRepository、LedgerCache、RecurringService、BackupService、IntegrityService、CSV、BudgetNotifier、AppLock、Keychain、汇率、演示数据
│   ├── ViewModels/     QuickEntryViewModel、AmountExpression（计算器）、TransactionFilter
│   ├── Features/       Assets、Transactions、QuickEntry、Analytics、Budgets、Settings、Lock、Onboarding
│   ├── Utilities/      Decimal 存储与解析、统计周期、格式化
│   └── Resources/      Assets（App 图标）、Localizable.xcstrings、InfoPlist.xcstrings
├── TallyTests/         Swift Testing 单元测试
├── ExportOptions/      导出 IPA 的 plist 模板
├── scripts/            build_ipa.sh、本地化脚本与翻译表、OCR 校验脚本
├── release/            CI 生成的未签名 IPA
└── docs/               架构、财务规则、交付记录
```

## 本地化

源语言英文；简体中文翻译在 `scripts/translations_zh.json`，繁體中文由 `scripts/make_zh_hant.py`（OpenCC 转换 + 港台用语修正）生成到 `scripts/translations_zh_hant.json`。修改界面文案后运行：

```bash
pip install opencc-python-reimplemented
python3 Tally/scripts/make_zh_hant.py          # 由简体生成繁体
python3 Tally/scripts/l10n_extract.py          # 重新生成 Localizable.xcstrings
python3 Tally/scripts/l10n_extract.py --list   # 列出尚未翻译的候选文案
```

> iOS 只在 iPhone 系统语言为对应语言时才自动显示中文；手机是英文时，可在 App 内「设置 › 语言」选择简体中文。

## CSV 格式

导出列：`Date, Type, Amount, Currency, Account, To Account, To Amount, To Currency, Category, Splits, Payee, Fee, Discount, Tags, Note, Base Currency, Rate To Base, Base Amount, ID`。支出行的 Amount 为原价，实付 = Amount − Discount + Fee。
导入时只需要 `Date`（日期）和 `Amount`（金额）两列；`Type` 缺失时按金额正负判断收支；标签用 `;` 分隔；拆分写作 `分类=金额; 分类=金额`。外币行如果没有可用汇率，不会被导入（导入结果会列出这些行）。

## 备份

设置 › 数据 › 创建备份：生成一个 JSON 文件（`format = tally-backup`、`schemaVersion = 3`、SHA-256 校验），包含账户、分类、标签、交易（含拆分）、预算、周期计划和汇率。恢复时先显示文件内容，可选「合并」（按 ID 跳过已有记录）或「替换」（需身份验证）。

## 隐私

数据只保存在本机（SwiftData / SQLite），不使用任何分析或网络服务。唯一的网络请求是你在「汇率」页手动点击「下载今日汇率」时访问 frankfurter.app（欧洲央行参考汇率）。
