import SwiftUI
import SwiftData

/// 单条打卡记录详情：原始时间与时区、验证信息、备注编辑与删除。
struct CheckInDetailView: View {
    @Bindable var checkIn: CheckIn
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        // 删除过程中不再读取模型属性，避免访问已删除对象。
        if isDeleting || checkIn.isDeleted {
            Color(.systemGroupedBackground)
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(checkIn.place?.name ?? String(localized: "未知地点"))
                        .font(.title3.bold())
                    if let cityCountry = checkIn.place?.cityCountryText {
                        Text(cityCountry)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let place = checkIn.place {
                    NavigationLink(value: PlaceCandidate(place: place)) {
                        Label("查看景点", systemImage: "mappin.circle")
                    }
                }
            }

            Section {
                LabeledContent("当地时间", value: checkIn.localDateTimeText)
                LabeledContent("时区", value: checkIn.timeZoneText)
                LabeledContent("UTC 时间", value: CheckInDateFormatter.utcText(for: checkIn.visitedAt))
            } header: {
                Text("到访时间")
            } footer: {
                Text("时间按打卡地当地时区保存与展示，跨国旅行也不会出现日期错位。")
            }

            Section("验证信息") {
                LabeledContent("打卡方式") {
                    MethodBadge(method: checkIn.method)
                }
                if let coordinate = checkIn.gpsCoordinate {
                    LabeledContent("GPS 坐标", value: CoordinateFormatting.text(coordinate))
                }
                if let accuracy = checkIn.gpsHorizontalAccuracy {
                    LabeledContent("定位精度", value: "±" + DistanceFormatting.text(for: accuracy))
                }
                if let distance = checkIn.distanceFromPlace {
                    LabeledContent("与景点距离", value: DistanceFormatting.text(for: distance))
                }
                if checkIn.method == .manual {
                    Text("此记录为手动补录，未经过 GPS 位置验证。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("备注") {
                TextField("添加备注", text: $checkIn.note, axis: .vertical)
                    .lineLimit(2...10)
            }

            Section {
                Button("删除这条记录", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } footer: {
                Text("记录创建于 \(CheckInDateFormatter.dateTimeText(for: checkIn.createdAt, timeZone: .current))")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("打卡记录")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: checkIn.note) {
            checkIn.updatedAt = .now
        }
        .onDisappear {
            guard !isDeleting else { return }
            try? modelContext.save()
        }
        .confirmationDialog("删除这条打卡记录？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: delete)
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func delete() {
        isDeleting = true
        do {
            try CheckInStore(context: modelContext).delete(checkIn)
            dismiss()
        } catch {
            isDeleting = false
            errorMessage = error.localizedDescription
        }
    }
}
