import SwiftUI

/// GPS 打卡成功反馈。
struct CheckInSuccessView: View {
    @Bindable var checkIn: CheckIn
    @Environment(\.dismiss) private var dismiss
    @State private var animate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: animate)
                        .padding(.top, 12)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("打卡成功")
                            .font(.title.bold())
                        Text(checkIn.place?.name ?? "")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        LabeledContent("到访时间", value: checkIn.localDateTimeText)
                        LabeledContent("时区", value: checkIn.timeZoneText)
                        if let distance = checkIn.distanceFromPlace {
                            LabeledContent("与景点距离", value: DistanceFormatting.text(for: distance))
                        }
                        if let accuracy = checkIn.gpsHorizontalAccuracy {
                            LabeledContent("定位精度", value: "±" + DistanceFormatting.text(for: accuracy))
                        }
                        LabeledContent("验证方式") {
                            MethodBadge(method: checkIn.method)
                        }
                    }
                    .font(.subheadline)
                    .card()

                    TextField("添加备注（可选）", text: $checkIn.note, axis: .vertical)
                        .lineLimit(3...6)
                        .card()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { animate = true }
            .onDisappear {
                checkIn.updatedAt = .now
                try? checkIn.modelContext?.save()
            }
        }
        .presentationDragIndicator(.visible)
    }
}
