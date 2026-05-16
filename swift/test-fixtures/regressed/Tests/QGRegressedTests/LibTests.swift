import XCTest

@testable import QGRegressed

final class LibTests: XCTestCase {
  // REGRESSION test: assertion errada de proposito.
  func testAddFailingOnPurpose() {
    XCTAssertEqual(qgAdd(2, 3), 999)
  }

  func testMultiplyPositive() {
    XCTAssertEqual(qgMultiply(3, 4), 12)
  }
}
