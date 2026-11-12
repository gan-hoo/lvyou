import SwiftUI

/// Capsule segmented control with a sliding selection pill.
struct KindSwitcher: View {
    var selection: TransactionKind
    var onSelect: (TransactionKind) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TransactionKind.allCases) { kind in
                let selected = kind == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { onSelect(kind) }
                } label: {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(DS.Colors.card)
                                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(DS.Colors.fill, in: Capsule(style: .continuous))
    }
}

/// Category picker grid for expenses and income.
struct CategoryGrid: View {
    var categories: [LedgerCategory]
    var selection: LedgerCategory?
    var onSelect: (LedgerCategory) -> Void
    var onManage: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { category in
                let selected = category.id == selection?.id
                Button {
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { onSelect(category) }
                } label: {
                    VStack(spacing: 5) {
                        SymbolBadge(symbol: category.symbolName, colorHex: category.colorHex, size: 44, style: selected ? .solid : .soft)
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 44 * 0.3 + 3, style: .continuous)
                                        .strokeBorder(Color(hex: category.colorHex).opacity(0.35), lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                            .scaleEffect(selected ? 1.04 : 1)
                        Text(category.name)
                            .font(.caption2.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(Text(category.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button(action: onManage) {
                VStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 44 * 0.3, style: .continuous)
                                .strokeBorder(DS.Colors.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        )
                    Text("Edit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel(Text("Manage categories"))
        }
        .padding(.vertical, 6)
    }
}

/// From → To account selector for transfers.
struct TransferPanel: View {
    var accounts: [Account]
    var from: Account?
    var to: Account?
    var onSelectFrom: (Account) -> Void
    var onSelectTo: (Account) -> Void
    var onSwap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            accountMenu(title: "From", account: from, exclude: nil, onSelect: onSelectFrom)
            Button {
                Haptics.softTap()
                withMotion(DS.Motion.snappy) { onSwap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 34, height: 34)
                    .background(DS.Colors.fill, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text("Swap accounts"))
            accountMenu(title: "To", account: to, exclude: from, onSelect: onSelectTo)
        }
    }

    private func accountMenu(title: LocalizedStringKey, account: Account?, exclude: Account?, onSelect: @escaping (Account) -> Void) -> some View {
        Menu {
            ForEach(accounts.filter { $0.id != exclude?.id }) { a in
                Button {
                    Haptics.selection()
                    onSelect(a)
                } label: {
                    Label(a.name + " · " + a.currencyCode, systemImage: a.symbolName)
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.m) {
                if let account {
                    SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 34)
                } else {
                    Image(systemName: "questionmark")
                        .frame(width: 34, height: 34)
                        .background(DS.Colors.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(account?.name ?? String(localized: "Choose account"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if let account {
                    Text(account.currencyCode).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, 10)
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        }
    }
}
