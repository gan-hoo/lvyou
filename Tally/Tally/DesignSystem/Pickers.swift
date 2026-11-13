import SwiftUI

enum SymbolLibrary {
    static let categories: [String] = [
        "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass", "birthday.cake", "carrot",
        "cart", "basket", "bag", "handbag", "tshirt", "shoe",
        "house", "sofa", "lightbulb", "bolt", "drop", "flame",
        "wifi", "phone", "tv", "gamecontroller", "headphones", "music.note",
        "film", "ticket", "book", "graduationcap", "pencil.and.ruler", "paintbrush",
        "tram", "bus", "car", "fuelpump", "bicycle", "airplane",
        "suitcase", "map", "tent", "beach.umbrella", "figure.run", "dumbbell",
        "cross.case", "pills", "heart", "stethoscope", "pawprint", "leaf",
        "gift", "party.popper", "sparkles", "scissors", "comb", "camera",
        "laptopcomputer", "iphone", "wrench.and.screwdriver", "hammer", "shippingbox", "doc.text",
        "briefcase", "building.2", "banknote", "creditcard", "chart.line.uptrend.xyaxis", "percent",
        "arrow.uturn.backward", "repeat", "star", "person.2", "figure.and.child.holdinghands", "ellipsis.circle",
    ]

    static let accounts: [String] = [
        "banknote", "creditcard", "creditcard.and.123", "building.columns", "iphone.gen3", "wallet.pass",
        "dollarsign.circle", "yensign.circle", "eurosign.circle", "sterlingsign.circle", "bitcoinsign.circle", "chart.line.uptrend.xyaxis",
        "lock.shield", "house", "car", "briefcase", "gift", "globe.asia.australia",
    ]
}

struct SymbolPickerGrid: View {
    var symbols: [String]
    @Binding var selection: String
    var colorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                let selected = symbol == selection
                Button {
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { selection = symbol }
                } label: {
                    SymbolBadge(symbol: symbol, colorHex: selected ? colorHex : "8E8E93", size: 42, style: selected ? .solid : .soft)
                        .scaleEffect(selected ? 1.06 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(symbol))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 9)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(DS.Palette.swatches, id: \.self) { hex in
                let selected = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { selection = hex }
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Color(hex: hex) : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Color"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
