// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VersionGateKit",
    platforms: [.iOS(.v16), .macOS(.v14), .tvOS(.v16)],
    products: [
        .library(name: "VersionGateKit", targets: ["VersionGateKit"])
    ],
    targets: [
        .target(name: "VersionGateKit"),
        .testTarget(name: "VersionGateKitTests", dependencies: ["VersionGateKit"])
    ]
)
