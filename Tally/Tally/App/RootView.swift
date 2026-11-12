import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var onboarded = false

    var body: some View {
        ZStack {
            if onboarded {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }

            if lock.isEnabled && lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if scenePhase != .active && (lock.privacyCover || lock.isEnabled) {
                PrivacyCoverView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(DS.Motion.adaptive(DS.Motion.gentle), value: onboarded)
        .animation(DS.Motion.adaptive(.easeInOut(duration: 0.2)), value: lock.isLocked)
        .onChange(of: scenePhase) { old, new in
            switch new {
            case .background:
                lock.didEnterBackground()
            case .inactive, .active:
                if old == .background { lock.willEnterForeground() }
                if new == .active {
                    // Book recurring occurrences that fell due while the app was closed.
                    RecurringService(context: context).postDueOccurrences()
                }
            @unknown default:
                break
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            AssetsView()
                .tabItem { Label("Assets", systemImage: "wallet.pass") }
                .tag(AppTab.assets)
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.pie") }
                .tag(AppTab.analytics)
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(AppTab.budgets)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .sheet(item: $router.entryRequest) { request in
            QuickEntrySheet(request: request)
        }
        .toastOverlay()
        .onChange(of: router.selectedTab) { _, _ in Haptics.selection() }
    }
}

/// Shown in the app switcher so balances are never visible in snapshots.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            AppGlyph(size: 72)
        }
        .accessibilityHidden(true)
    }
}

/// The app's mark, drawn in SwiftUI (also used on lock and onboarding screens).
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(DS.Colors.accent)
            VStack(alignment: .leading, spacing: size * 0.08) {
                Capsule().fill(.white).frame(width: size * 0.46, height: size * 0.09)
                Capsule().fill(.white.opacity(0.75)).frame(width: size * 0.32, height: size * 0.09)
                Capsule().fill(.white.opacity(0.5)).frame(width: size * 0.2, height: size * 0.09)
            }
            .frame(width: size * 0.5, alignment: .leading)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
