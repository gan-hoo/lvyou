import SwiftUI
import MapKit

/// 轻量的静态地图预览（MKMapSnapshotter），用于列表，避免在每一行创建可交互地图。
struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    var spanMeters: CLLocationDistance = 1_500

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Rectangle().fill(.quaternary)
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key(for: proxy.size)) {
                guard proxy.size.width > 0, proxy.size.height > 0 else { return }
                let snapshot = await MapSnapshotProvider.shared.snapshot(for: key(for: proxy.size))
                withAnimation(.easeOut(duration: 0.2)) { image = snapshot }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func key(for size: CGSize) -> MapSnapshotKey {
        MapSnapshotKey(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            spanMeters: spanMeters,
            width: size.width.rounded(),
            height: size.height.rounded(),
            scale: displayScale,
            isDark: colorScheme == .dark
        )
    }
}

struct MapSnapshotKey: Hashable {
    let latitude: Double
    let longitude: Double
    let spanMeters: Double
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let isDark: Bool

    var cacheKey: String {
        "\(latitude),\(longitude),\(spanMeters),\(width)x\(height)@\(scale),\(isDark)"
    }
}

/// 带内存缓存的地图快照生成器。
@MainActor
final class MapSnapshotProvider {
    static let shared = MapSnapshotProvider()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
    }

    func snapshot(for key: MapSnapshotKey) async -> UIImage? {
        let cacheKey = key.cacheKey as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: key.latitude, longitude: key.longitude),
            latitudinalMeters: key.spanMeters,
            longitudinalMeters: key.spanMeters
        )
        options.size = CGSize(width: key.width, height: key.height)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = key.isDark ? .dark : .light
            traits.displayScale = key.scale
        }

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            cache.setObject(snapshot.image, forKey: cacheKey)
            return snapshot.image
        } catch {
            return nil
        }
    }
}
