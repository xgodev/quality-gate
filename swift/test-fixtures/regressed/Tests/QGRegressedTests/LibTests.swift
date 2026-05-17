import XCTest

@testable import QGRegressed

final class LibTests: XCTestCase {
  // REGRESSION test: assertion wrong on purpose.
  func testAddFailingOnPurpose() {
    XCTAssertEqual(qgAdd(2, 3), 999)
  }

  func testMultiplyPositive() {
    XCTAssertEqual(qgMultiply(3, 4), 12)
  }
}
