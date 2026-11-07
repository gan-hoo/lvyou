import SwiftUI
import SwiftData
import CoreLocation

/// 我的：旅行统计、隐私与权限、关于。
struct ProfileView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.openURL) private var openURL
    @Query private var checkIns: [CheckIn]

    var body: some View {
        let stats = TravelStatistics(checkIns: checkIns)

        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(value: stats.countryCount, title: "国家/地区", systemImage: "globe.asia.australia")
                        StatTile(value: stats.cityCount, title: "城市", systemImage: "building.2")
                        StatTile(value: stats.placeCount, title: "景点", systemImage: "mappin.and.ellipse")
                        StatTile(value: stats.checkInCount, title: "打卡次数", systemImage: "checkmark.seal")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("旅行统计")
                }

                Section("最近一次旅行") {
                    if let latest = stats.latestCheckIn {
                        NavigationLink(value: latest) {
                            CheckInRow(checkIn: latest)
                        }
                    } else {
                        Text("暂无记录")
                            .foregroundStyle(.secondary)
                    }
                }

                if !stats.yearlyCounts.isEmpty {
                    Section("每年打卡") {
                        let maxCount = stats.yearlyCounts.map(\.count).max() ?? 1
                        ForEach(stats.yearlyCounts) { item in
                            YearCountRow(year: item.year, count: item.count, maxCount: maxCount)
                        }
                    }
                }

                Section {
                    LabeledContent("定位权限", value: locationStatusText)
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                } header: {
                    Text("隐私与权限")
                } footer: {
                    Text("旅行足迹仅在你主动打卡、查看距离或定位时使用位置，不会在后台持续定位，也不会记录你的移动轨迹。所有数据默认只保存在本设备上。")
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                }
            }
            .navigationTitle("我的")
            .travelDestinations()
        }
    }

    private var locationStatusText: String {
        let status: String
        switch locationService.authorizationStatus {
        case .notDetermined: status = String(localized: "尚未请求")
        case .denied: status = String(localized: "已拒绝")
        case .restricted: status = String(localized: "受限制")
        case .authorizedWhenInUse: status = String(localized: "使用 App 期间")
        case .authorizedAlways: status = String(localized: "始终")
        @unknown default: status = String(localized: "未知")
        }
        if locationService.isAuthorized, locationService.accuracyAuthorization == .reducedAccuracy {
            return status + String(localized: " · 大致位置")
        }
        return status
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct YearCountRow: View {
    let year: Int
    let count: Int
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: String(year))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Text("\(count) 次")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(6, proxy.size.width * CGFloat(count) / CGFloat(max(maxCount, 1))))
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    ProfileView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
