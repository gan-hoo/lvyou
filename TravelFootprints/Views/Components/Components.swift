import SwiftUI

// MARK: - Card

/// Apple 原生风格的分组卡片背景。
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }
}

// MARK: - Method

extension CheckInMethod {
    var tint: Color {
        switch self {
        case .gpsVerified: .green
        case .manual: .orange
        }
    }
}

/// 打卡方式标签：「GPS 验证」/「手动记录」。
struct MethodBadge: View {
    let method: CheckInMethod

    var body: some View {
        Label(method.displayName, systemImage: method.systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(method.tint)
            .background(method.tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: Int
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value, format: .number)
                .font(.title.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Check-in row

/// 打卡记录行，用于时间线、景点历史等列表。
struct CheckInRow: View {
    let checkIn: CheckIn
    var showsPlace = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: checkIn.method.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(checkIn.method.tint)
                .frame(width: 32, height: 32)
                .background(checkIn.method.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if showsPlace {
                    Text(checkIn.place?.name ?? String(localized: "未知地点"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let cityCountry = checkIn.place?.cityCountryText {
                        Text(cityCountry)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(checkIn.localDateTimeText)
                    .font(showsPlace ? .footnote : .body)
                    .foregroundStyle(showsPlace ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                if !showsPlace {
                    Text(checkIn.method.displayName)
                        .font(.footnote)
                        .foregroundStyle(checkIn.method.tint)
                }
                if !checkIn.note.isEmpty {
                    Text(checkIn.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsPlace, checkIn.method == .manual {
                Text("手动")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.orange)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Navigation

extension View {
    /// 在每个 NavigationStack 根视图注册一次的统一导航目的地。
    func travelDestinations() -> some View {
        self
            .navigationDestination(for: PlaceCandidate.self) { candidate in
                PlaceDetailView(candidate: candidate)
            }
            .navigationDestination(for: CheckIn.self) { checkIn in
                CheckInDetailView(checkIn: checkIn)
            }
    }
}
