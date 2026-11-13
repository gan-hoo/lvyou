import SwiftUI
import SwiftData

struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var draft = TransactionFilter()
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    FlowChips(items: TransactionKind.allCases, title: \.title, isSelected: { draft.kinds.contains($0) }) { kind in
                        draft.kinds.formSymmetricDifference([kind])
                    }
                }

                Section("Amount") {
                    HStack {
                        TextField("Min", text: $minText).keyboardType(.decimalPad)
                        Text(verbatim: "–").foregroundStyle(.secondary)
                        TextField("Max", text: $maxText).keyboardType(.decimalPad)
                    }
                }

                if !accounts.isEmpty {
                    Section("Accounts") {
                        FlowChips(items: accounts, title: \.name, isSelected: { draft.accountIDs.contains($0.id) }) { account in
                            draft.accountIDs.formSymmetricDifference([account.id])
                        }
                    }
                }

                ForEach(CategoryKind.allCases) { kind in
                    let list = categories.filter { $0.kind == kind }
                    if !list.isEmpty {
                        Section(kind == .expense ? String(localized: "Expense Categories") : String(localized: "Income Categories")) {
                            FlowChips(items: list, title: \.name, isSelected: { draft.categoryIDs.contains($0.id) }) { category in
                                draft.categoryIDs.formSymmetricDifference([category.id])
                            }
                        }
                    }
                }

                if !tags.isEmpty {
                    Section("Tags") {
                        FlowChips(items: tags, title: \.name, isSelected: { draft.tagIDs.contains($0.id) }) { tag in
                            draft.tagIDs.formSymmetricDifference([tag.id])
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withMotion {
                            draft.reset()
                            minText = ""
                            maxText = ""
                        }
                    }
                    .disabled(!draft.isActive && minText.isEmpty && maxText.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        draft.minAmount = DecimalCodec.parseLenient(minText)
                        draft.maxAmount = DecimalCodec.parseLenient(maxText)
                        withMotion { filter = draft }
                        Haptics.selection()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = filter
            minText = filter.minAmount.map { DecimalCodec.encode($0) } ?? ""
            maxText = filter.maxAmount.map { DecimalCodec.encode($0) } ?? ""
        }
    }
}

/// Wrapping chips (uses the iOS 16 Layout protocol).
struct FlowChips<Item: Identifiable>: View {
    var items: [Item]
    var title: KeyPath<Item, String>
    var isSelected: (Item) -> Bool
    var onToggle: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                Button {
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { onToggle(item) }
                } label: {
                    Chip(title: item[keyPath: title], isSelected: isSelected(item))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
