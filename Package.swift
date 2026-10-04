// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "BirthdayCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "BirthdayCore", targets: ["BirthdayCore"])],
  targets: [
    .target(name: "BirthdayCore", path: "ios/Core"),
    .testTarget(name: "BirthdayCoreTests", dependencies: ["BirthdayCore"], path: "ios/CoreTests"),
  ]
)
