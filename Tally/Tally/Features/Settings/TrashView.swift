import SwiftUI
import SwiftData

/// Shared "delete" for transactions: moves them to the trash and offers Undo in a toast.
@MainActor
enum TrashActions {
    static func moveToTrash(_ entries: [LedgerEntry], context: ModelContext, toasts: ToastCenter) {
        let ids = entries.map(\.id)
        do {
            try TrashService(context: context).trash(entries)
            Haptics.success()
            toasts.show(ToastMessage(
                symbol: "trash",
                text: String(localized: "Moved to Trash"),
                actionTitle: String(localized: "Undo"),
                action: {
                    do {
                        try TrashService(context: context).restore(ids: ids)
                        Haptics.success()
                    } catch {
                        Haptics.error()
                        toasts.show(ToastMessage(symbol: "exclamationmark.triangle", text: error.localizedDescription, style: .warning))
                    }
                }
            ), duration: .seconds(5))
        } catch {
            Haptics.error()
            toasts.show(ToastMessage(symbol: "exclamationmark.triangle", text: error.localizedDescription, style: .warning))
        }
    }
}

/// Settings › Data › Trash: deleted transactions, restorable for 30 days.
struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \TrashedEntry.deletedAt, order: .reverse) private var items: [TrashedEntry]

    @State private var pendingPurge: [TrashedEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        TrashRow(item: item)
                            .swipeActions(edge: .leading) {
                                Button { restore([item]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                    .tint(DS.Colors.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingPurge = [item] } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button { restore([item]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                Button(role: .destructive) { pendingPurge = [item] } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("Deleted transactions stay here for \(TrashService.retentionDays) days, then are removed for good. Restoring puts a transaction back exactly as it was, and balances, analytics and budgets count it again. Swipe right to restore, left to delete permanently.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Trash Is Empty", systemImage: "trash")
                } description: {
                    Text("Deleted transactions appear here for \(TrashService.retentionDays) days and can be restored.")
                }
            }
        }
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { restore(items) } label: { Label("Restore All", systemImage: "arrow.uturn.backward") }
                        Button(role: .destructive) { pendingPurge = items } label: { Label("Empty Trash", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
        }
        .alert(
            pendingPurge.count > 1 ? Text("Delete \(pendingPurge.count) transactions permanently?") : Text("Delete permanently?"),
            isPresented: Binding(get: { !pendingPurge.isEmpty }, set: { if !$0 { pendingPurge = [] } })
        ) {
            Button("Delete Permanently", role: .destructive) { purge(pendingPurge) }
            Button("Cancel", role: .cancel) { pendingPurge = [] }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't Restore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { TrashService(context: context).purgeExpired() }
    }

    private func restore(_ list: [TrashedEntry]) {
        do {
            let count = try withMotion { try TrashService(context: context).restore(list) }
            Haptics.success()
            toasts.show(ToastMessage(symbol: "arrow.uturn.backward.circle.fill",
                                     text: String(localized: "Restored \(count) transactions"), style: .success))
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    private func purge(_ list: [TrashedEntry]) {
        do {
            try withMotion { try TrashService(context: context).purge(list) }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingPurge = []
    }
}

private struct TrashRow: View {
    let item: TrashedEntry

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: item.symbolName, colorHex: item.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.s)
            VStack(alignment: .trailing, spacing: 3) {
                Text(MoneyFormat.signed(item.paidAmount, code: item.currencyCode, kind: item.kind))
                    .font(DS.Typography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.amount(for: item.kind))
                Text("\(TrashService.daysLeft(item)) days left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [item.date.shortDateText]
        if !item.accountName.isEmpty { parts.append(item.accountName) }
        parts.append(String(localized: "Deleted") + " " + item.deletedAt.text(.dateTime.month(.abbreviated).day()))
        return parts.joined(separator: " · ")
    }
}
