import SwiftUI

enum KeypadKey: Hashable {
    case digit(Int)
    case decimal
    case op(AmountExpression.Operator)
    case backspace
    case clear
    case commit
}

/// Calculator keypad: 7-8-9-⌫ / 4-5-6-+ / 1-2-3-− / .-0-[Save].
struct CalculatorKeypad: View {
    var commitTitle: LocalizedStringKey
    var showsEquals: Bool
    var commitEnabled: Bool
    var tint: Color
    var onKey: (KeypadKey) -> Void

    private let spacing: CGFloat = 8

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            GridRow {
                digit(7); digit(8); digit(9)
                KeyButton(kind: .function, longPress: { onKey(.clear) }, action: { onKey(.backspace) }) {
                    Image(systemName: "delete.left")
                }
                .accessibilityLabel(Text("Delete"))
                .accessibilityHint(Text("Long press to clear"))
            }
            GridRow {
                digit(4); digit(5); digit(6)
                KeyButton(kind: .function, action: { onKey(.op(.plus)) }) { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Plus"))
            }
            GridRow {
                digit(1); digit(2); digit(3)
                KeyButton(kind: .function, action: { onKey(.op(.minus)) }) { Image(systemName: "minus") }
                    .accessibilityLabel(Text("Minus"))
            }
            GridRow {
                KeyButton(kind: .digit, action: { onKey(.decimal) }) { Text(verbatim: AppLocale.current.decimalSeparator ?? ".") }
                    .accessibilityLabel(Text("Decimal point"))
                digit(0)
                KeyButton(kind: .commit(tint), isEnabled: commitEnabled || showsEquals, action: { onKey(.commit) }) {
                    if showsEquals {
                        Image(systemName: "equal")
                    } else {
                        Text(commitTitle).font(.headline)
                    }
                }
                .gridCellColumns(2)
                .accessibilityLabel(showsEquals ? Text("Equals") : Text(commitTitle))
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        KeyButton(kind: .digit, action: { onKey(.digit(n)) }) {
            Text(verbatim: "\(n)")
        }
    }
}

private struct KeyButton<Label: View>: View {
    enum Kind {
        case digit
        case function
        case commit(Color)
    }

    var kind: Kind
    var isEnabled: Bool = true
    var longPress: (() -> Void)? = nil
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
                .font(DS.Typography.keypad)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 58)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.key, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.key, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .disabled(!isEnabled)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard let longPress else { return }
                Haptics.press()
                longPress()
            }
        )
    }

    private var foreground: Color {
        switch kind {
        case .digit: .primary
        case .function: .secondary
        case .commit: isEnabled ? .white : Color(uiColor: .tertiaryLabel)
        }
    }

    private var background: Color {
        switch kind {
        case .digit: DS.Colors.card
        case .function: DS.Colors.fill
        case .commit(let tint): isEnabled ? tint : DS.Colors.fill
        }
    }
}
