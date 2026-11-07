import SwiftUI
import SwiftData
import MapKit

/// 首页：Apple Maps 风格的全屏地图，展示用户位置与已打卡景点。
struct MapHomeView: View {
    private enum ActiveSheet: Identifiable {
        case search
        case place(Place)

        var id: String {
            switch self {
            case .search: "search"
            case .place(let place): place.id.uuidString
            }
        }
    }

    @Environment(LocationService.self) private var locationService
    @Environment(\.openURL) private var openURL
    @Query(sort: \Place.createdAt) private var places: [Place]

    @State private var position: MapCameraPosition = .automatic
    @State private var activeSheet: ActiveSheet?
    @State private var showsLocationDeniedAlert = false

    private var visitedPlaces: [Place] {
        places.filter { $0.visitCount > 0 }
    }

    private var selectedPlaceID: UUID? {
        if case .place(let place) = activeSheet { return place.id }
        return nil
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(visitedPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    PlaceMarkerView(visitCount: place.visitCount, isSelected: selectedPlaceID == place.id)
                        .onTapGesture { activeSheet = .place(place) }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .safeAreaInset(edge: .top) {
            topBar
        }
        .overlay(alignment: .bottom) {
            if visitedPlaces.isEmpty {
                emptyHint
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .search:
                SearchView()
                    .environment(locationService)
            case .place(let place):
                PlaceSummarySheet(place: place)
                    .environment(locationService)
            }
        }
        .alert("无法显示你的位置", isPresented: $showsLocationDeniedAlert) {
            Button("前往设置") { openSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("定位权限未开启。你仍然可以浏览地图和历史记录；如需显示位置或 GPS 打卡，请在「设置」中允许访问位置。")
        }
        .sensoryFeedback(.selection, trigger: selectedPlaceID)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .search
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("搜索景点、城市或地址")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索景点")

            Button(action: showUserLocation) {
                Image(systemName: locationService.isAuthorized ? "location.fill" : "location")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("显示我的位置")
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var emptyHint: some View {
        Label("搜索一个景点，完成你的第一次打卡", systemImage: "mappin.and.ellipse")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
            .onTapGesture { activeSheet = .search }
    }

    // MARK: - Actions

    private func showUserLocation() {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            showsLocationDeniedAlert = true
        case .notDetermined:
            Task {
                let status = await locationService.requestAuthorizationIfNeeded()
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    focusOnUser()
                }
            }
        default:
            focusOnUser()
        }
    }

    private func focusOnUser() {
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .userLocation(fallback: .automatic)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

#if DEBUG
#Preview {
    MapHomeView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
