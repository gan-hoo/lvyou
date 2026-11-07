import SwiftUI

/// 搜索结果行：名称、类别、地址、城市与国家、经纬度和地图预览。
struct SearchResultRow: View {
    let candidate: PlaceCandidate
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 68

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MapSnapshotView(coordinate: candidate.coordinate)
                .frame(width: thumbnailSize, height: thumbnailSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.headline)
                    .lineLimit(2)
                if let category = candidate.categoryDisplayName {
                    Text(category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if let address = candidate.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let cityCountry = candidate.cityCountryText {
                    Label(cityCountry, systemImage: "globe")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(candidate.coordinateText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
