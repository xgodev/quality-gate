// REGRESSION fmt: indentation with 4 spaces (config wants 2).
public func qgAdd(_ a: Int, _ b: Int) -> Int {
    return a + b
}

public func qgMultiply(_ a: Int, _ b: Int) -> Int {
  return a * b
}

// REGRESSION lint: forca de unwrap (swiftlint force_unwrapping rule).
public func qgForceUnwrap(_ s: String?) -> Int {
  return s!.count
}

// REGRESSION coverage: public function without a test.
public func qgUncovered() -> Int {
  return 99
}
