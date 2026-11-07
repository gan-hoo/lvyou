import SwiftUI

/// 已打卡景点在地图上的标记。
struct PlaceMarkerView: View {
    let visitCount: Int
    var isSelected = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if visitCount > 1 {
                    Text(visitCount, format: .number)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(.white, in: Capsule())
                        .offset(x: 7, y: -6)
                }
            }

            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
                .offset(y: -2)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
        .scaleEffect(isSelected ? 1.25 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("已打卡 \(visitCount) 次"))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HStack(spacing: 30) {
        PlaceMarkerView(visitCount: 1)
        PlaceMarkerView(visitCount: 3, isSelected: true)
    }
    .padding(40)
    .background(Color(.systemGroupedBackground))
}
