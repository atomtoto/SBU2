import Foundation
import Testing
@testable import SBU2

@Suite("BMS reading freshness")
struct BMSReadingFreshnessTests {
    private let receivedAt = Date(timeIntervalSince1970: 1_000)

    @Test("No basic-information frame cannot authorize a MOSFET change")
    func missingReading() {
        #expect(!BMSConnection.readingIsFresh(lastBasicInfoAt: nil, now: receivedAt))
    }

    @Test("A recent basic-information frame remains usable")
    func recentReading() {
        let now = receivedAt.addingTimeInterval(BMSConnection.readingStaleAfter - 0.1)
        #expect(BMSConnection.readingIsFresh(lastBasicInfoAt: receivedAt, now: now))
    }

    @Test("An old frame cannot authorize a MOSFET change")
    func oldReading() {
        let now = receivedAt.addingTimeInterval(BMSConnection.readingStaleAfter + 0.1)
        #expect(!BMSConnection.readingIsFresh(lastBasicInfoAt: receivedAt, now: now))
    }

    @Test("A clock change backwards does not make an old frame look fresh")
    func clockMovedBackwards() {
        let now = receivedAt.addingTimeInterval(-1)
        #expect(!BMSConnection.readingIsFresh(lastBasicInfoAt: receivedAt, now: now))
    }
}
