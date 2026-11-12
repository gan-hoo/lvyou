# Tally V3 — 交付记录

本文件只记录实际发生的构建与测试结果；没有完成的部分明确写出。

## 1. 构建记录

构建全部在 GitHub Actions 的 macOS 15 runner 上完成（本仓库所在的开发环境是 Linux，无法运行 Xcode）。

| 项目 | 结果 |
|---|---|
| Release Archive（Xcode 26.3，iOS 26.2 SDK，`generic/platform=iOS`，未签名） | _待 CI 结果_ |
| 未签名 IPA 打包（`Payload/Tally.app` → `Tally-unsigned.ipa`） | _待 CI 结果_ |
| Xcode 16（iOS 18 SDK，非 Liquid Glass 编译分支）Release 编译 | _待 CI 结果_ |
| 单元测试（iPhone 模拟器） | _待 CI 结果_ |
| 模拟器截图 + OCR 文本校验 | _待 CI 结果_ |

## 2. 单元测试清单

_待 CI 结果_

## 3. 签名与 IPA

- CI 产出的是 **未签名 IPA**（`release/Tally-unsigned.ipa`）。它 **不能直接安装** 到 iPhone，需要用你自己的 Apple 开发者身份重新签名（Xcode、Sideloadly、AltStore 等），或在仓库中配置签名证书 Secrets 后运行 `Tally signed IPA` 工作流导出已签名 IPA。步骤见 README「签名与导出 IPA」「iPhone 真机安装」。
- 本次交付没有可用的签名证书与描述文件，因此 **没有** 导出已签名 IPA，也 **没有** 在真机上安装验证。

## 4. 已知问题与限制

1. IPA 未签名（见上）；没有在真机上验证过 Face ID、触感反馈和性能，只在模拟器上运行过。
2. 数据只保存在本机，没有 iCloud 同步（模型已按 CloudKit 要求设计，但未开启）。
3. 汇率不会自动更新：需要手动添加，或在「汇率」页手动下载欧洲央行参考汇率。早于最早一条汇率的日期使用最早的汇率；完全没有汇率的币种保持「待换算」。
4. 预算提醒是 App 内提示（Toast），不发送系统推送通知。
5. 周期交易在 App 启动和回到前台时入账，不在后台运行；自定义周期为「每 N 天 / 周 / 月 / 年」。
6. 切换语言需要重新打开 App（iOS 对单个 App 语言的限制）。
7. Liquid Glass 主题只有在 iOS 26 且用 Xcode 26 编译时才使用系统玻璃材质；更早系统使用半透明材质替代。系统列表行保持系统样式。
8. 切换主题、强调色、金额格式或「隐藏金额」会重建界面，当前页面的导航层级会回到根页面。
9. 备份与 CSV 导出文件未加密，需要自行妥善保存。
10. CSV 导入时，没有可用汇率的外币行不会被导入（会在结果中列出行号和原因）。
