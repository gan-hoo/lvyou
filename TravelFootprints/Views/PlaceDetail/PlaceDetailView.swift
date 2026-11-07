import SwiftUI
import SwiftData
import MapKit

/// 景点详情：地图、位置信息、与用户的距离、GPS 打卡及历史到访记录。
struct PlaceDetailView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var viewModel: PlaceDetailViewModel
    @State private var showsManualEntry = false

    init(candidate: PlaceCandidate) {
        _viewModel = State(initialValue: PlaceDetailViewModel(candidate: candidate))
    }

    private var candidate: PlaceCandidate { viewModel.candidate }
    private var store: CheckInStore { CheckInStore(context: modelContext) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapHeader
                infoCard
                distanceCard
                checkInCard
                if let failure = viewModel.failure {
                    CheckInFailureCard(
                        failure: failure,
                        onRetry: { checkIn() },
                        onOpenSettings: openSettings,
                        onManualEntry: { showsManualEntry = true },
                        onDismiss: { viewModel.dismissFailure() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                historyCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: viewModel.failure)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(candidate.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear(store: store, locationService: locationService)
        }
        .onAppear {
            // 从记录详情返回时重新匹配（记录可能已被删除）。
            viewModel.resolvePlace(using: store)
        }
        .sheet(item: $viewModel.completedCheckIn) { checkIn in
            CheckInSuccessView(checkIn: checkIn)
        }
        .sheet(isPresented: $showsManualEntry) {
            ManualCheckInView(candidate: candidate, timeZone: viewModel.defaultTimeZone) { date, timeZone, note in
                try viewModel.saveManualCheckIn(visitedAt: date, timeZone: timeZone, note: note, store: store)
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.successCount)
        .sensoryFeedback(.error, trigger: viewModel.failureCount)
    }

    // MARK: - Map

    private var mapHeader: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: candidate.coordinate,
            latitudinalMeters: max(1_200, viewModel.radius * 6),
            longitudinalMeters: max(1_200, viewModel.radius * 6)
        ))) {
            MapCircle(center: candidate.coordinate, radius: viewModel.radius)
                .foregroundStyle(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
            Marker(candidate.name, systemImage: "mappin", coordinate: candidate.coordinate)
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
        .accessibilityLabel(Text("\(candidate.name) 的地图"))
    }

    // MARK: - Info

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let category = candidate.categoryDisplayName {
                Text(category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(candidate.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                if let address = candidate.address {
                    Label(address, systemImage: "mappin.and.ellipse")
                }
                if let cityCountry = candidate.cityCountryText {
                    Label(cityCountry, systemImage: "globe")
                }
                Label(candidate.coordinateText, systemImage: "scope")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: - Distance

    private var distanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("与你的距离")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                distanceValue
            }

            Spacer(minLength: 0)

            if locationService.isAuthorized {
                Button {
                    Task { await viewModel.refreshDistance(using: locationService) }
                } label: {
                    if viewModel.isRefreshingDistance {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(viewModel.isRefreshingDistance)
                .accessibilityLabel("刷新距离")
            }
        }
        .card()
    }

    @ViewBuilder
    private var distanceValue: some View {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            Text("定位权限未开启")
                .font(.headline)
            Button("前往设置开启", action: openSettings)
                .font(.subheadline)
        case .notDetermined:
            Button("显示与我的距离") {
                Task { await viewModel.refreshDistance(using: locationService) }
            }
            .font(.headline)
        default:
            if let distance = viewModel.currentDistance {
                Text(DistanceFormatting.text(for: distance))
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                if viewModel.isWithinRange == true {
                    Label("已在打卡范围内", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Text("打卡范围：\(DistanceFormatting.text(for: viewModel.radius)) 以内")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isRefreshingDistance {
                Text("正在定位…")
                    .font(.headline)
            } else {
                Text("暂时无法获取")
                    .font(.headline)
            }
        }
    }

    // MARK: - Check-in

    private var checkInCard: some View {
        VStack(spacing: 12) {
            Button(action: checkIn) {
                HStack(spacing: 8) {
                    if viewModel.isCheckingIn {
                        ProgressView()
                            .tint(.white)
                        Text("正在验证位置…")
                    } else {
                        Image(systemName: "location.fill")
                        Text("GPS 打卡")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .disabled(viewModel.isCheckingIn)

            Text("需位于景点 \(DistanceFormatting.text(for: viewModel.radius)) 范围内，系统将记录真实的打卡时间与 GPS 坐标。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Button {
                showsManualEntry = true
            } label: {
                Label("手动补录过去的旅行", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
            }
        }
        .card()
    }

    // MARK: - History

    private var historyCard: some View {
        let visits = viewModel.visits
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("到访记录")
                    .font(.headline)
                Spacer()
                if !visits.isEmpty {
                    Text("\(visits.count) 次")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if visits.isEmpty {
                Text("还没有到访记录。到达景点后点击「GPS 打卡」即可记录这一次旅行。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visits) { visit in
                    NavigationLink(value: visit) {
                        HStack {
                            CheckInRow(checkIn: visit, showsPlace: false)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if visit.id != visits.last?.id {
                        Divider()
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Actions

    private func checkIn() {
        Task {
            await viewModel.performGPSCheckIn(store: store, locationService: locationService)
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
    NavigationStack {
        PlaceDetailView(candidate: PreviewSampleData.operaHouse)
            .travelDestinations()
    }
    .environment(LocationService())
    .modelContainer(PreviewSampleData.container)
}
#endif
