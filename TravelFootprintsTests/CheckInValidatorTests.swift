import Testing
import Foundation
import CoreLocation
@testable import TravelFootprints

struct CheckInValidatorTests {
    let validator = CheckInValidator()

    @Test func withinRadiusIsVerified() {
        let result = validator.evaluate(distance: 120, horizontalAccuracy: 10, locationAge: 2, radius: 200)
        #expect(result == .verified(distance: 120))
    }

    @Test func exactlyAtRadiusIsVerified() {
        let result = validator.evaluate(distance: 200, horizontalAccuracy: 10, locationAge: 2, radius: 200)
        #expect(result.isVerified)
    }

    @Test func beyondRadiusIsRejected() {
        let result = validator.evaluate(distance: 200.5, horizontalAccuracy: 10, locationAge: 2, radius: 200)
        #expect(result == .tooFar(distance: 200.5, radius: 200))
    }

    @Test func poorAccuracyIsRejectedEvenWhenClose() {
        let result = validator.evaluate(distance: 20, horizontalAccuracy: 350, locationAge: 2, radius: 200)
        #expect(result == .inaccurate(horizontalAccuracy: 350))
    }

    @Test func invalidAccuracyIsRejected() {
        let result = validator.evaluate(distance: 20, horizontalAccuracy: -1, locationAge: 2, radius: 200)
        #expect(result == .inaccurate(horizontalAccuracy: -1))
    }

    @Test func staleLocationIsRejected() {
        let result = validator.evaluate(distance: 20, horizontalAccuracy: 10, locationAge: 300, radius: 200)
        #expect(result == .stale(age: 300))
    }

    @Test func realCoordinatesNearSydneyOperaHouse() {
        let now = Date()
        let target = CLLocationCoordinate2D(latitude: -33.856784, longitude: 151.215297)
        // 约 80 米外。
        let nearby = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.857500, longitude: 151.215000),
            altitude: 0, horizontalAccuracy: 8, verticalAccuracy: 8, timestamp: now
        )
        #expect(validator.validate(location: nearby, target: target, radius: 200, now: now).isVerified)

        // 东京塔，远超打卡范围。
        let tokyo = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.658581, longitude: 139.745433),
            altitude: 0, horizontalAccuracy: 8, verticalAccuracy: 8, timestamp: now
        )
        let result = validator.validate(location: tokyo, target: target, radius: 200, now: now)
        guard case .tooFar(let distance, let radius) = result else {
            Issue.record("Expected tooFar, got \(result)")
            return
        }
        #expect(distance > 7_000_000)
        #expect(radius == 200)
    }

    @Test func defaultRadiusIs200Meters() {
        #expect(CheckInPolicy.defaultRadius == 200)
        #expect(CheckInRadiusRule.standard.radius(forCategory: nil) == 200)
        #expect(CheckInRadiusRule.standard.radius(forCategory: "MKPOICategoryMuseum") == 200)
    }

    @Test func categoryOverrideExtendsRadius() {
        let rule = CheckInRadiusRule(categoryOverrides: ["MKPOICategoryNationalPark": 3_000])
        #expect(rule.radius(forCategory: "MKPOICategoryNationalPark") == 3_000)
        #expect(rule.radius(forCategory: "MKPOICategoryMuseum") == 200)
    }
}
