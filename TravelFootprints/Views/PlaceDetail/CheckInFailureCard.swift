import SwiftUI

/// 打卡失败提示。清晰说明原因，并提供可行的下一步。
struct CheckInFailureCard: View {
    let failure: CheckInFailure
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onManualEntry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(failure.title, systemImage: failure.systemImage)
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭提示")
            }

            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if failure.canOpenSettings {
                    Button("前往设置", action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                }
                if failure.canRetry {
                    Button("重试", action: onRetry)
                        .buttonStyle(.bordered)
                }
                Button("改为手动补录", action: onManualEntry)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}
