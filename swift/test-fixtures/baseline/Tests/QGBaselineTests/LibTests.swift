import XCTest

@testable import QGBaseline

final class LibTests: XCTestCase {
  func testAddPositive() {
    XCTAssertEqual(qgAdd(2, 3), 5)
  }

  func testAddNegative() {
    XCTAssertEqual(qgAdd(-1, -1), -2)
  }

  func testMultiplyPositive() {
    XCTAssertEqual(qgMultiply(3, 4), 12)
  }

  func testMultiplyZero() {
    XCTAssertEqual(qgMultiply(0, 5), 0)
  }
}
