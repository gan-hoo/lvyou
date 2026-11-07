import Foundation
import SwiftData

/// SwiftData 容器的统一创建入口。
///
/// 当前数据只保存在本机（`cloudKitDatabase: .none`）。
/// 第三阶段接入 iCloud 时：
/// 1. 在 Signing & Capabilities 中开启 iCloud（CloudKit）与 Background Modes › Remote notifications；
/// 2. 将此处改为 `.private("iCloud.<bundle id>")`。
/// 模型已满足 CloudKit 约束（无唯一约束、属性可选或有默认值、关系可选）。
enum PersistenceController {
    static let schema = Schema([Place.self, CheckIn.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        // 内存容器使用唯一名称，确保测试 / 预览之间互不共享数据。
        let configuration = ModelConfiguration(
            inMemory ? "InMemory-\(UUID().uuidString)" : "TravelFootprints",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 数据库无法打开属于不可恢复的启动错误。
            fatalError("无法创建本地数据库：\(error)")
        }
    }
}
