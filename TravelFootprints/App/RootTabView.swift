import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case map
    case footprints
    case timeline
    case profile
}

/// 底部四个 Tab：地图 / 足迹 / 时间线 / 我的。
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection: AppTab = .map

    var body: some View {
        TabView(selection: $selection) {
            MapHomeView()
                .tabItem { Label("地图", systemImage: "map") }
                .tag(AppTab.map)

            FootprintsView()
                .tabItem { Label("足迹", systemImage: "shoeprints.fill") }
                .tag(AppTab.footprints)

            TravelTimelineView()
                .tabItem { Label("时间线", systemImage: "clock") }
                .tag(AppTab.timeline)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .task {
            // 清理已无打卡记录的景点，不保留多余的位置信息。
            try? CheckInStore(context: modelContext).purgeOrphanPlaces()
        }
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
