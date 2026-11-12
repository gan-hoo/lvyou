# 旅行足迹 Travel Footprints

> 本仓库另含 **Tally 记账**（原生 SwiftUI 个人财务 App），工程、构建、签名与真机安装说明见 [Tally/README.md](Tally/README.md)。

原生 iOS 旅行打卡应用：搜索全球景点，到达后通过 GPS 验证打卡，自动记录到访时间与时区，并在地图上展示个人旅行足迹。

- Swift · SwiftUI · SwiftData · MapKit · Core Location
- iOS 17+，无第三方依赖，无服务器，数据仅保存在本机
- 设计与架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## 环境要求

- macOS + **Xcode 16 或更高版本**（项目使用 Xcode 16 的文件夹同步组格式）
- iOS 17.0+ 模拟器或真机

## 运行

1. 用 Xcode 打开 `TravelFootprints.xcodeproj`。
2. 选择 Scheme **TravelFootprints** 与一台 iPhone 模拟器（如 iPhone 16）。
3. ⌘R 运行。

**真机运行**：在 *TARGETS › TravelFootprints › Signing & Capabilities* 中选择你的 Team；
如 Bundle Identifier 冲突，把 `com.ganhoo.TravelFootprints` 改成你自己的标识。

> 新增 Swift 文件只需放进 `TravelFootprints/` 下任意子文件夹，Xcode 会自动加入目标，无需手动拖拽。

## 在模拟器中测试 GPS 打卡

模拟器没有真实 GPS，需要手动设定位置：

1. 运行 App，在地图页点搜索框，搜索 **Sydney Opera House**，进入详情页。
2. 设定模拟位置（任选其一）：
   - 模拟器菜单 **Features › Location › Custom Location…**，输入 `-33.8568`, `151.2153`；
   - 或 Xcode 菜单 **Debug › Simulate Location › Add GPX File to Project…**，选择 `SimulatorLocations/SydneyOperaHouse.gpx`。
3. 点击 **GPS 打卡**，首次会弹出定位授权，选择「使用 App 时允许」。
4. 成功后显示打卡成功页（当地时间、时区、距离、精度）；返回地图可看到新标记。
5. 把位置改为东京塔（`35.6586`, `139.7454`）再在悉尼歌剧院打卡，会提示「距离景点太远」。

其他值得测试的场景：

| 场景 | 操作 | 预期 |
|------|------|------|
| 拒绝定位 | 授权时选「不允许」 | 打卡显示「定位权限未开启」+「前往设置」；地图和历史仍可浏览 |
| 无定位 | Features › Location › None 后打卡 | 约 15 秒后提示定位超时或无法获取位置，不会打卡成功 |
| 大致位置 | 设置中关闭「精确位置」 | 打卡时请求临时精确位置，拒绝则提示「需要精确位置」 |
| 手动补录 | 详情页「手动补录过去的旅行」 | 记录标记为「手动记录」，无 GPS 坐标 |
| 搜索无结果 | 搜索一串乱码 | 显示系统「无结果」视图 |
| 断网 | 关闭 Mac 网络后搜索 | 显示「网络连接异常」及重试按钮 |
| 删除 | 时间线左滑或记录详情删除 | 确认后删除，地图标记同步更新 |

## 运行单元测试

⌘U，或命令行：

```bash
xcodebuild test \
  -project TravelFootprints.xcodeproj \
  -scheme TravelFootprints \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

测试使用 Swift Testing，覆盖：

- `CheckInValidatorTests` — 200 米边界、精度不足、定位过期、真实坐标距离、半径规则
- `CheckInDateFormatterTests` — 「2026年11月7日，16:30」格式、跨时区跨日 / 跨年、GMT 偏移
- `CheckInStoreTests` — 景点复用与匹配、GPS / 手动记录区分、未来日期拒绝、删除与清理
- `StatisticsAndFilterTests` — 国家 / 城市 / 景点 / 年度统计、筛选、时间线分组

## 隐私

- 只在用户主动操作（打卡、查看距离、定位按钮）时请求「使用 App 期间」定位权限
- 单次定位，不使用后台定位，不记录移动轨迹
- 数据默认只保存在本设备；删除最后一条打卡后，对应景点会在下次启动时清除
- 手动补录永远不会被标记为 GPS 验证
