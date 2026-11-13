import SwiftUI
import UIKit

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
    /// Optional button in the toast, e.g. "Undo".
    var actionTitle: String? = nil
    var action: (@MainActor () -> Void)? = nil
    /// Set by `ToastCenter` for toasts with an action: drives the countdown ring.
    var deadline: Date? = nil
    var totalSeconds: Double = 0

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

@Observable
@MainActor
final class ToastCenter {
    var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: ToastMessage, duration: Duration = .seconds(2.6)) {
        var message = message
        if message.action != nil {
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            message.totalSeconds = seconds
            message.deadline = Date().addingTimeInterval(seconds)
        }
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

/// Capsule bar above the tab bar (modelled on Telegram's undo bar): icon or countdown
/// ring, message, and an optional light-blue action such as "Undo".
struct ToastView: View {
    var message: ToastMessage
    var onAction: () -> Void = {}

    static let actionBlue = Color(red: 0.43, green: 0.77, blue: 0.96)
    /// Medium-dark grey, the same in Light and Dark Mode.
    static let barColor = Color(red: 82 / 255, green: 82 / 255, blue: 82 / 255)
    static let height: CGFloat = 50

    private var iconTint: Color {
        switch message.style {
        case .success: Color(red: 0.42, green: 0.88, blue: 0.58)
        case .info: .white
        case .warning: Color(red: 1.0, green: 0.74, blue: 0.38)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            leading
            Text(message.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = message.actionTitle, let action = message.action {
                Button {
                    action()
                    onAction()
                } label: {
                    Text(verbatim: title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Self.actionBlue)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 22)
        .frame(height: Self.height)
        .background(Capsule(style: .continuous).fill(Self.barColor))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .accessibilityElement(children: message.action == nil ? .combine : .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var leading: some View {
        if let deadline = message.deadline, message.totalSeconds > 0 {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                CountdownRing(fraction: remaining / message.totalSeconds, seconds: Int(remaining.rounded(.up)))
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: message.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 28, height: 28)
        }
    }
}

private struct CountdownRing: View {
    var fraction: Double
    var seconds: Int

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: String(seconds))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    /// Clearance for the tab bar, so the toast sits just above it.
    private let tabBarClearance: CGFloat = 74

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = toasts.current {
                ToastView(message: message) { toasts.dismiss() }
                    .padding(.bottom, tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { toasts.dismiss() }
                    .id(message.id)
            }
        }
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

// MARK: - Keyboard

extension View {
    /// Number pads have no Return key. Adds a Done button above the keyboard and lets a
    /// downward drag dismiss it. Apply once per screen, inside its NavigationStack.
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButton())
    }
}

private struct KeyboardDoneButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
    }
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Tab root titles

extension View {
    /// Main tab pages show no title text (the tab bar already says where you are).
    /// The title is still set, so back buttons on sub-pages and VoiceOver use it.
    func tabRootTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
    }
}
