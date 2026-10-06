// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "BirthdaysCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "BirthdaysCore", targets: ["BirthdaysCore"])],
  targets: [
    .target(name: "BirthdaysCore", path: "ios/Core", resources: [.copy("Resources/life-enrollment.js")]),
    .testTarget(name: "BirthdaysCoreTests", dependencies: ["BirthdaysCore"], path: "ios/CoreTests"),
  ]
)
