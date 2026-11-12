import Foundation
import SwiftData
import Observation

/// Single source of computed money for the UI. Holds an immutable snapshot of the
/// ledger, rebuilds it whenever the store saves, and runs heavier calculations off
/// the main thread with results memoised per snapshot version.
@Observable
@MainActor
final class LedgerCache {
    private(set) var snapshot = LedgerSnapshot()
    private(set) var converter = CurrencyConverter(points: [])
    /// Native-currency balance per account.
    private(set) var balances: [UUID: Decimal] = [:]
    /// Increments on every reload; use it as a `.task(id:)` key.
    private(set) var version = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var memo: [String: Any] = [:]

    init(context: ModelContext) {
        self.context = context
        reload()
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    /// Coalesces bursts of saves into one rebuild.
    func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        let snap = LedgerSnapshot.load(from: context)
        snapshot = snap
        converter = snap.converter
        memo.removeAll()
        let engine = FinanceEngine(base: AppSettings.baseCurrency, converter: converter)
        balances = engine.balances(accounts: snap.accounts, entries: snap.entries)
        version += 1
    }

    func engine(base: String = AppSettings.baseCurrency) -> FinanceEngine {
        FinanceEngine(base: base, converter: converter)
    }

    func netWorth(base: String = AppSettings.baseCurrency) -> NetWorth {
        engine(base: base).netWorth(accounts: snapshot.accounts, balances: balances)
    }

    func balance(of id: UUID) -> Decimal { balances[id] ?? 0 }

    /// Runs `work` on a background thread with the current snapshot, memoised by `key`
    /// until the next reload.
    func compute<T: Sendable>(_ key: String, _ work: @escaping @Sendable (LedgerSnapshot, CurrencyConverter) -> T) async -> T {
        let fullKey = "\(version)|\(key)"
        if let cached = memo[fullKey] as? T { return cached }
        let snap = snapshot
        let conv = converter
        let result = await Task.detached(priority: .userInitiated) { work(snap, conv) }.value
        memo[fullKey] = result
        return result
    }
}
