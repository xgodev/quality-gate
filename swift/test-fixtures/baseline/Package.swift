// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "QGBaseline",
  targets: [
    .target(name: "QGBaseline", path: "Sources/QGBaseline"),
    .testTarget(name: "QGBaselineTests", dependencies: ["QGBaseline"], path: "Tests/QGBaselineTests"),
  ]
)
