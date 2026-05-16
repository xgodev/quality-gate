// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "QGRegressed",
  targets: [
    .target(name: "QGRegressed", path: "Sources/QGRegressed"),
    .testTarget(name: "QGRegressedTests", dependencies: ["QGRegressed"], path: "Tests/QGRegressedTests")
  ]
)
