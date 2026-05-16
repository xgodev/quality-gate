// REGRESSION fmt: indentacao com 4 espacos (config quer 2).
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

// REGRESSION coverage: funcao publica sem teste.
public func qgUncovered() -> Int {
  return 99
}
