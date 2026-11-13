import SwiftUI

struct LockScreenView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var returnedFromBackground = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            DS.Colors.background.opacity(0.4).ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                Spacer()
                AppGlyph(size: 76)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 6) {
                    Text("Tally is Locked")
                        .font(.title2.weight(.semibold))
                    Text("Your ledger is protected with \(lock.biometry.title).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DS.Colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxl)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometry.title)", systemImage: lock.biometry.symbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(lock.isAuthenticating)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .task {
            withMotion(DS.Motion.gentle) { appeared = true }
            await lock.unlock()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                returnedFromBackground = true
            } else if phase == .active && returnedFromBackground {
                returnedFromBackground = false
                Task { await lock.unlock() }
            }
        }
    }
}
