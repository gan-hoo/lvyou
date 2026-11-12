import Foundation
import SwiftData
import OSLog

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        Account.self, LedgerEntry.self, LedgerCategory.self, Tag.self, Budget.self, ExchangeRate.self,
    ]

    static var schema: Schema { Schema(models) }

    private static let log = Logger(subsystem: "com.ganhoo.tally", category: "persistence")

    /// On-device SQLite store. All models use optional relationships and default
    /// values (no unique constraints) so the schema stays CloudKit-compatible
    /// for a future iCloud sync option.
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let configuration = ModelConfiguration(
            "Tally",
            schema: schema,
            isStoredInMemoryOnly: inMemory || isTesting,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            log.error("Failed to open store: \(error.localizedDescription, privacy: .public)")
            let fallback = ModelConfiguration("TallyRecovery", schema: schema, isStoredInMemoryOnly: true)
            // An in-memory store keeps the app usable; the original file is left untouched.
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    /// In-memory container filled with demo data, for SwiftUI previews.
    @MainActor
    static let preview: ModelContainer = {
        let container = makeContainer(inMemory: true)
        DefaultData.ensureSeeded(in: container.mainContext)
        DemoData.load(into: container.mainContext, base: "CNY")
        return container
    }()
}
