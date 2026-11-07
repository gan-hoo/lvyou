import Foundation
import CoreLocation

enum DistanceFormatting {
    /// 按用户地区习惯格式化距离（如「850 米」「1.2 公里」）。
    static func text(for meters: CLLocationDistance, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: max(0, meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(locale))
    }
}

enum CoordinateFormatting {
    /// 例如「33.85678° S, 151.21530° E」。
    static func text(latitude: Double, longitude: Double) -> String {
        let lat = abs(latitude).formatted(.number.precision(.fractionLength(5)))
        let lon = abs(longitude).formatted(.number.precision(.fractionLength(5)))
        return "\(lat)° \(latitude >= 0 ? "N" : "S"), \(lon)° \(longitude >= 0 ? "E" : "W")"
    }

    static func text(_ coordinate: CLLocationCoordinate2D) -> String {
        text(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

enum LocationText {
    /// 例如「悉尼 · 澳大利亚」。无城市时退回省 / 州。
    static func cityCountry(locality: String?, administrativeArea: String?, country: String?) -> String? {
        let city = locality?.nilIfBlank ?? administrativeArea?.nilIfBlank
        var parts = [city, country?.nilIfBlank].compactMap { $0 }
        if parts.count == 2, parts[0] == parts[1] { parts.removeLast() }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension String {
    /// 去除首尾空白后为空则返回 nil。
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
