import SwiftUI

/// 点击地图标记后弹出的景点摘要：名称、到访日期与历史记录。
struct PlaceSummarySheet: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name)
                            .font(.title2.bold())
                        if let cityCountry = place.cityCountryText {
                            Text(cityCountry)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if let latest = place.latestVisit {
                        LabeledContent("最近到访", value: latest.localDateTimeText)
                    }
                    LabeledContent("到访次数") {
                        Text("\(place.visitCount) 次")
                    }

                    NavigationLink(value: PlaceCandidate(place: place)) {
                        Label("景点详情与打卡", systemImage: "mappin.circle")
                    }
                }

                Section("到访记录") {
                    ForEach(place.visits) { checkIn in
                        NavigationLink(value: checkIn) {
                            CheckInRow(checkIn: checkIn, showsPlace: false)
                        }
                    }
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .travelDestinations()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
