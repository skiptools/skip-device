// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
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
}
