import SwiftUI
import SwiftData
import MapKit

/// 旅行足迹：所有去过的景点地图、数量汇总、按国家 / 城市筛选及按日期排序的列表。
struct FootprintsView: View {
    @Query(sort: \Place.createdAt) private var places: [Place]
    @State private var viewModel = FootprintsViewModel()
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.visitedPlaces(from: places).isEmpty {
                    ContentUnavailableView {
                        Label("还没有足迹", systemImage: "shoeprints.fill")
                    } description: {
                        Text("在地图页搜索景点并完成打卡，你去过的地方会出现在这里。")
                    }
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("足迹")
            .travelDestinations()
        }
    }

    private var content: some View {
        let visible = viewModel.visiblePlaces(from: places)
        let summary = FootprintSummary(places: visible)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                footprintMap(visible)

                if let selected = visible.first(where: { $0.id == viewModel.selectedPlaceID }) {
                    selectedPlaceCard(selected)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    StatTile(value: summary.checkInCount, title: "打卡次数", systemImage: "checkmark.seal")
                    StatTile(value: summary.placeCount, title: "景点", systemImage: "mappin.and.ellipse")
                    StatTile(value: summary.cityCount, title: "城市", systemImage: "building.2")
                }

                filterBar

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { place in
                        NavigationLink(value: PlaceCandidate(place: place)) {
                            FootprintPlaceRow(place: place)
                        }
                        .buttonStyle(.plain)
                        if place.id != visible.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                    if visible.isEmpty {
                        Text("没有符合筛选条件的足迹。")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: viewModel.selectedPlaceID)
        }
        .onChange(of: viewModel.filter) {
            withAnimation { position = .automatic }
        }
    }

    // MARK: - Map

    private func footprintMap(_ visible: [Place]) -> some View {
        Map(position: $position) {
            ForEach(visible) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    PlaceMarkerView(visitCount: place.visitCount, isSelected: viewModel.selectedPlaceID == place.id)
                        .onTapGesture {
                            viewModel.selectedPlaceID = viewModel.selectedPlaceID == place.id ? nil : place.id
                        }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
        .sensoryFeedback(.selection, trigger: viewModel.selectedPlaceID)
    }

    private func selectedPlaceCard(_ place: Place) -> some View {
        NavigationLink(value: PlaceCandidate(place: place)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                    if let latest = place.latestVisit {
                        Text("最近到访：\(latest.localDateTimeText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("共 \(place.visitCount) 次打卡")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("全部国家/地区") { viewModel.selectCountry(nil) }
                    ForEach(viewModel.countries(from: places), id: \.self) { country in
                        Button(country) { viewModel.selectCountry(country) }
                    }
                } label: {
                    FilterChip(
                        title: viewModel.filter.country ?? String(localized: "全部国家/地区"),
                        isActive: viewModel.filter.country != nil
                    )
                }

                Menu {
                    Button("全部城市") { viewModel.selectCity(nil) }
                    ForEach(viewModel.cities(from: places), id: \.self) { city in
                        Button(city) { viewModel.selectCity(city) }
                    }
                } label: {
                    FilterChip(
                        title: viewModel.filter.city ?? String(localized: "全部城市"),
                        isActive: viewModel.filter.city != nil
                    )
                }

                if viewModel.filter.isActive {
                    Button("清除") { viewModel.resetFilter() }
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        .background(
            isActive ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
    }
}

private struct FootprintPlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let cityCountry = place.cityCountryText {
                    Text(cityCountry)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let latest = place.latestVisit {
                    Text("\(place.visitCount) 次 · 最近 \(CheckInDateFormatter.dateText(for: latest.visitedAt, timeZone: latest.timeZone))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    FootprintsView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
