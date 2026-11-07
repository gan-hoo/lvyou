import Foundation
import SwiftData
import CoreLocation

enum CheckInStoreError: LocalizedError, Equatable {
    case visitDateInFuture

    var errorDescription: String? {
        switch self {
        case .visitDateInFuture: String(localized: "到访时间不能晚于现在。")
        }
    }
}

/// 打卡记录的持久化仓库，封装所有 SwiftData 读写。
@MainActor
struct CheckInStore {
    let context: ModelContext

    /// 认为是「同一个景点」的最大坐标偏差。
    static let samePlaceDistance: CLLocationDistance = 100

    // MARK: - Places

    /// 查找与候选地点对应的已保存景点：优先使用 MapKit 标识，其次按名称 + 坐标邻近匹配。
    func existingPlace(matching candidate: PlaceCandidate) throws -> Place? {
        if let identifier = candidate.mapItemIdentifier {
            let target: String? = identifier
            let descriptor = FetchDescriptor<Place>(predicate: #Predicate<Place> { place in
                place.mapItemIdentifier == target
            })
            if let place = try context.fetch(descriptor).first {
                return place
            }
        }

        let name = candidate.name
        let descriptor = FetchDescriptor<Place>(predicate: #Predicate<Place> { place in
            place.name == name
        })
        let target = candidate.location
        return try context.fetch(descriptor).first { place in
            CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: target)
                <= Self.samePlaceDistance
        }
    }

    func findOrCreatePlace(for candidate: PlaceCandidate, radius: CLLocationDistance? = nil) throws -> Place {
        if let place = try existingPlace(matching: candidate) {
            // 补全旧记录中缺失的信息。
            if place.mapItemIdentifier == nil { place.mapItemIdentifier = candidate.mapItemIdentifier }
            if place.timeZoneIdentifier == nil { place.timeZoneIdentifier = candidate.timeZoneIdentifier }
            if place.countryCode == nil { place.countryCode = candidate.countryCode }
            if place.pointOfInterestCategory == nil { place.pointOfInterestCategory = candidate.pointOfInterestCategory }
            return place
        }

        let place = Place(
            name: candidate.name,
            address: candidate.address,
            locality: candidate.locality,
            administrativeArea: candidate.administrativeArea,
            country: candidate.country,
            countryCode: candidate.countryCode,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            mapItemIdentifier: candidate.mapItemIdentifier,
            pointOfInterestCategory: candidate.pointOfInterestCategory,
            timeZoneIdentifier: candidate.timeZoneIdentifier,
            checkInRadius: radius ?? CheckInRadiusRule.standard.radius(forCategory: candidate.pointOfInterestCategory)
        )
        context.insert(place)
        return place
    }

    // MARK: - Check-ins

    /// 保存一条已通过 GPS 验证的打卡。调用方必须先通过 `CheckInValidator` 验证。
    @discardableResult
    func recordGPSCheckIn(
        for candidate: PlaceCandidate,
        location: CLLocation,
        distance: CLLocationDistance,
        radius: CLLocationDistance? = nil,
        at date: Date = .now
    ) throws -> CheckIn {
        let place = try findOrCreatePlace(for: candidate, radius: radius)
        let checkIn = CheckIn(
            visitedAt: date,
            timeZone: Self.timeZone(for: place),
            method: .gpsVerified,
            gpsLatitude: location.coordinate.latitude,
            gpsLongitude: location.coordinate.longitude,
            gpsHorizontalAccuracy: location.horizontalAccuracy,
            distanceFromPlace: distance,
            createdAt: date
        )
        return try insert(checkIn, into: place)
    }

    /// 保存一条手动补录。该记录永远不会被标记为 GPS 验证。
    @discardableResult
    func recordManualCheckIn(
        for candidate: PlaceCandidate,
        visitedAt: Date,
        timeZone: TimeZone,
        note: String = "",
        now: Date = .now
    ) throws -> CheckIn {
        // 允许 1 分钟误差，防止 DatePicker 精度问题。
        guard visitedAt <= now.addingTimeInterval(60) else {
            throw CheckInStoreError.visitDateInFuture
        }
        let place = try findOrCreatePlace(for: candidate)
        let checkIn = CheckIn(
            visitedAt: visitedAt,
            timeZone: timeZone,
            method: .manual,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now
        )
        return try insert(checkIn, into: place)
    }

    func delete(_ checkIn: CheckIn) throws {
        context.delete(checkIn)
        try context.save()
    }

    /// 删除已经没有任何打卡记录的景点，避免残留位置信息。
    func purgeOrphanPlaces() throws {
        let places = try context.fetch(FetchDescriptor<Place>())
        var didDelete = false
        for place in places where place.visitCount == 0 {
            context.delete(place)
            didDelete = true
        }
        if didDelete {
            try context.save()
        }
    }

    // MARK: - Private

    private func insert(_ checkIn: CheckIn, into place: Place) throws -> CheckIn {
        context.insert(checkIn)
        checkIn.place = place
        try context.save()
        return checkIn
    }

    /// 打卡时区：优先使用景点所在时区（MapKit 提供），否则使用设备当前时区。
    static func timeZone(for place: Place) -> TimeZone {
        place.timeZone ?? .current
    }
}
