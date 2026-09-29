// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dustpan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dustpan", targets: ["Dustpan"]),
    ],
    targets: [
        // Pure logic: scanning, cleaning, rules. No UI, fully testable.
        .target(name: "DustpanCore"),
        // SwiftUI menu bar app.
        .executableTarget(name: "Dustpan", dependencies: ["DustpanCore"]),
        .testTarget(name: "DustpanCoreTests", dependencies: ["DustpanCore"]),
    ]
)
