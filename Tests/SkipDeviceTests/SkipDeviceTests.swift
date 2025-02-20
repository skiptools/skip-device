// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import XCTest
import OSLog
import Foundation
@testable import SkipDevice

let logger: Logger = Logger(subsystem: "SkipDevice", category: "Tests")

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
final class SkipDeviceTests: XCTestCase {
    func testNetworkReachability() async throws {
        let isReachable = NetworkReachability.isNetworkReachable
        XCTAssertTrue(isReachable, "expected the network to be reachable")
    }

    func testLocationProvier() async throws {
        let lp = LocationProvider()

        throw XCTSkip("Skipping fetchCurrentLocation due to hang")

        let location = try await lp.fetchCurrentLocation()
        XCTAssertNotEqual(0.0, location.latitude)
    }

    func testLocationCalculation() {
        let l1 = Location(latitude: 42.21, longitude: 71.3) // Paris
        let l2 = Location(latitude: 35.6895, longitude: 139.6917) // Tokyo
        let distance = l1.distance(from: l2)
        XCTAssertEqual(5799.680063587996, distance)
    }
}
