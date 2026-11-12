import SwiftUI

// MARK: - Category / account icon

struct SymbolBadge: View {
    enum Style { case soft, solid }

    var symbol: String
    var colorHex: String
    var size: CGFloat = 36
    var style: Style = .soft

    var body: some View {
        let color = Color(hex: colorHex)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(style == .solid ? Color.white : color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(style == .solid ? color : color.opacity(0.15))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Animated amount

/// Currency amount with a native numeric content transition.
struct AmountText: View {
    var value: Decimal
    var code: String
    var font: Font = DS.Typography.rowAmount
    var color: Color = .primary
    var showPlusSign = false

    var body: some View {
        Text(MoneyFormat.string(value, code: code, showPlusSign: showPlusSign))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value.doubleValue))
            .animation(DS.Motion.adaptive(DS.Motion.spring), value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, DS.Spacing.xs)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Progress

struct CapsuleProgress: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 6

    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.Colors.fill)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, shown))))
                    .opacity(shown > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear { withMotion(DS.Motion.gentle) { shown = fraction } }
        .onChange(of: fraction) { _, newValue in withMotion(DS.Motion.gentle) { shown = newValue } }
        .accessibilityElement()
        .accessibilityValue(MoneyFormat.percent(fraction))
    }
}

struct RingProgress: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 10

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(DS.Colors.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, shown)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withMotion(DS.Motion.gentle) { shown = fraction } }
        .onChange(of: fraction) { _, newValue in withMotion(DS.Motion.gentle) { shown = newValue } }
        .accessibilityElement()
        .accessibilityValue(MoneyFormat.percent(fraction))
    }
}

// MARK: - Buttons

/// Subtle press-down scale used on cards and custom controls.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.adaptive(DS.Motion.snappy), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Floating "add" button with a glass rim. Long-press offers a kind menu.
struct FloatingAddButton: View {
    var onSelectKind: ((TransactionKind) -> Void)? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.press()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(DS.Colors.accent, in: Circle())
                .padding(4)
                .glass(in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .contextMenu {
            if let onSelectKind {
                ForEach(TransactionKind.allCases) { kind in
                    Button {
                        onSelectKind(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Add Transaction"))
        .accessibilityHint(Text("Opens quick entry"))
    }
}

/// Selectable capsule chip.
struct Chip: View {
    var title: String
    var symbol: String?
    var isSelected: Bool = false
    var tint: Color = DS.Colors.accent

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.semibold))
            }
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            Capsule(style: .continuous).fill(isSelected ? tint : DS.Colors.fill)
        )
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Metric

struct MetricView: View {
    var title: LocalizedStringKey
    var value: Decimal
    var code: String
    var color: Color = .primary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.caption2.weight(.bold))
                }
                Text(title)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            AmountText(value: value, code: code, font: DS.Typography.metric, color: color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    enum Style { case success, info, warning }
    let id = UUID()
    var symbol: String
    var text: String
    var style: Style = .info
}

@Observable
@MainActor
final class ToastCenter {
    var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: ToastMessage, duration: Duration = .seconds(2.6)) {
        withMotion(DS.Motion.spring) { current = message }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withMotion(DS.Motion.spring) { self?.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withMotion(DS.Motion.spring) { current = nil }
    }
}

struct ToastView: View {
    var message: ToastMessage

    private var tint: Color {
        switch message.style {
        case .success: DS.Colors.income
        case .info: DS.Colors.accent
        case .warning: DS.Colors.warning
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassCapsule()
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = toasts.current {
                ToastView(message: message)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { toasts.dismiss() }
                    .id(message.id)
            }
        }
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
