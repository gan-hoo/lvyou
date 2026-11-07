import SwiftUI

/// 手动补录过去的旅行。记录会被明确标记为「手动记录」，不会伪装成 GPS 验证。
struct ManualCheckInView: View {
    let candidate: PlaceCandidate
    let timeZone: TimeZone
    let onSave: (Date, TimeZone, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var visitedAt = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .font(.headline)
                        if let cityCountry = candidate.cityCountryText {
                            Text(cityCountry)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    DatePicker(
                        "日期与时间",
                        selection: $visitedAt,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    // 按景点当地时区选择时间，避免跨时区补录时日期错位。
                    .environment(\.timeZone, timeZone)

                    LabeledContent("时区", value: CheckInDateFormatter.timeZoneText(for: timeZone, at: visitedAt))
                } header: {
                    Text("到访时间")
                } footer: {
                    Text("请按景点当地时间填写。")
                }

                Section("备注") {
                    TextField("记录这次旅行的点滴（可选）", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Label("手动记录不经过 GPS 位置验证，将始终标记为「手动记录」，与 GPS 验证打卡区分。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("手动补录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            try onSave(visitedAt, timeZone, note)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
