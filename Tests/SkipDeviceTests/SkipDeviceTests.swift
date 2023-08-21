import XCTest
import OSLog
import Foundation

let logger: Logger = Logger(subsystem: "SkipDevice", category: "Tests")

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
final class SkipDeviceTests: XCTestCase {
    func testSkipDevice() throws {
        XCTAssertEqual(1 + 2, 3, "basic test")
    }
}
