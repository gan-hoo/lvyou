# Tally 记账

<img src="docs/icon-preview.png" width="96" align="right" alt="Tally icon">

原生 iOS 个人记账 App：SwiftUI + SwiftData + Swift Charts，支持收入 / 支出 / 转账、多账户、多币种与历史汇率、月度与分类预算、CSV 导入导出、Face ID 锁定，中英双语，完全离线。

- **最低系统**：iOS 17.0（iPhone，竖屏）
- **工程**：`Tally.xcodeproj`（Xcode 16+，文件夹同步组格式；新增 Swift 文件放进 `Tally/` 任意子目录即可自动加入目标）
- **依赖**：无第三方依赖，全部使用 Apple 系统框架
- **Bundle Identifier**：`com.ganhoo.tally`（测试目标 `com.ganhoo.tallyTests`）
- 设计与架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## 功能

| 模块 | 内容 |
|---|---|
| 首页 | 本月结余（数字过渡动画）、收入 / 支出、环比变化、总预算进度与每日可用、总资产与各账户余额、本月累计支出趋势（与上月对比，可拖动查看）、预算温和提醒、最近交易。标题下拉菜单切换月份，左右滑动结余卡片也可切换 |
| 快速记账 | 底部 Sheet；支出 / 收入 / 转账；计算器键盘（`+` `−`，Decimal 精度）；分类网格（记住上次分类）；账户、日期时间、标签、备注；跨币种显示折算与汇率；跨币种转账可手填实际到账金额；保存后首页即时刷新 |
| 流水 | 按日分组 + 每日收支小计；搜索（备注、分类、账户、标签、金额）；筛选（类型、日期范围、金额区间、账户、分类、标签）；排序（时间 / 金额）；左滑编辑 / 删除，右滑复制到今天；长按菜单；详情页显示原币金额与记账汇率 |
| 统计 | 月 / 年切换；总额、日均 / 月均、环比、笔数；分类环形图（点击扇区或图例查看明细）；月视图每日柱状图，年视图收支折线；近 6 个月 / 近 4 年收支对比；分类排行，点进看该分类全部交易 |
| 预算 | 月度总预算（圆环）+ 分类预算（进度条）；剩余 / 超出、每日可用；提醒阈值 50%–100%；每项预算每月每个级别只提醒一次，App 内安静提示，不推送；可一键使用近 3 个月平均值 |
| 账户 | 现金、储蓄卡、信用卡、储蓄、电子钱包、投资；任意币种；余额 = 期初余额 + 全部交易实时计算（从不硬编码）；排序、归档、设为默认；删除时说明影响的交易数 |
| 汇率 | 汇率历史（每条有生效日期）；每笔交易按「交易日期当天生效的最新汇率」折算；原币金额与折算快照分开存储，新增或修改汇率不会改动历史账目；可选一键下载欧洲央行参考汇率 |
| 数据 | CSV 导出（UTF-8 BOM，Excel / Numbers 直接打开中文）；CSV 导入（识别中英文表头、多种日期格式、GB18030 编码、预览与错误行、自动建账户 / 分类、重复记录自动跳过，重复导入同一文件不会产生重复）；演示数据一键加载 / 移除；清除全部数据（需身份验证） |
| 安全 | Face ID / Touch ID / Optic ID 解锁，失败可用设备密码；锁定设置存于钥匙串（仅本机）；后台锁定延时；多任务界面隐藏内容 |
| 语言 | 简体中文 / 繁體中文 / English；默认跟随 iPhone 系统语言，也可在欢迎页右上角或「设置 › 语言」单独指定（重新打开 App 后生效）；内置分类、默认账户和演示数据的名称会随语言自动切换，你改过名的不受影响 |
| 外观 | 浅色 / 深色 / 跟随系统；SF Pro + SF Symbols；轻量玻璃材质（iOS 26 上自动使用系统 Liquid Glass）；弹簧动画与触感反馈，全部尊重「减弱动态效果」 |

演示数据：首次启动可选「使用演示数据体验」，生成约 100 天的真实感记录（含澳元旅行卡与跨币种转账）。所有演示对象都带 `isDemo` 标记，首页顶部有横幅提示，可随时一键移除且不影响自己的记录。

---

## 在 Xcode 中运行

1. 用 Xcode 16 或更高版本打开 `Tally/Tally.xcodeproj`。
2. 选择 Scheme **Tally** 和一台 iPhone 模拟器，⌘R。
3. ⌘U 运行单元测试（Swift Testing：计算器、Decimal 编解码、历史汇率换算、余额与转账、快照不漂移、预算级别、CSV 往返与幂等导入、演示数据清理）。

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

> 调试截图模式仅存在于 Debug 构建：启动参数 `-TallyScreenshotMode`（首次自动加载演示数据并跳过引导）、`-TallyTab statistics`、`-TallyOpenEntry`。

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
│   ├── App/            入口、根视图（Tab + 锁屏 + 隐私遮罩）、路由、持久化、设置项
│   ├── DesignSystem/   颜色 / 字体 / 间距 / 圆角 / 动画、玻璃材质、通用组件、触感
│   ├── Models/         SwiftData 模型（Account、LedgerEntry、LedgerCategory、Tag、Budget、ExchangeRate）
│   ├── Services/       LedgerStore、LedgerMath、CurrencyConverter、BudgetEvaluator、CSV、AppLock、Keychain、演示数据
│   ├── ViewModels/     QuickEntryViewModel、AmountExpression（计算器）、TransactionFilter
│   ├── Features/       Dashboard、QuickEntry、Transactions、Statistics、Budget、Accounts、Settings、Lock、Onboarding
│   ├── Utilities/      Decimal 存储与解析、日期周期、格式化
│   └── Resources/      Assets（App 图标浅色 / 深色 / 着色）、Localizable.xcstrings、InfoPlist.xcstrings
├── TallyTests/         Swift Testing 单元测试
├── ExportOptions/      导出 IPA 的 plist 模板
├── scripts/            build_ipa.sh、本地化提取脚本与中文翻译表
└── docs/
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

导出列：`Date, Type, Amount, Currency, Account, To Account, To Amount, To Currency, Category, Tags, Note, Base Currency, Rate To Base, Base Amount, ID`。
导入时只需要 `Date`（日期）和 `Amount`（金额）两列；`Type` 缺失时按金额正负判断收支；标签用 `;` 分隔。

## 隐私

数据只保存在本机（SwiftData / SQLite），不使用任何分析或网络服务。唯一的网络请求是你在「汇率」页手动点击「下载今日汇率」时访问 frankfurter.app（欧洲央行参考汇率）。
