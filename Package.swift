// swift-tools-version:5.9
// Lightswitch — the notch as a status light for Claude Code sessions.
//
//   swift build            debug binary in .build/debug/Lightswitch
//   swift test             the unit tests
//   make app               release build wrapped as build/Lightswitch.app
//   open Package.swift     the same targets inside Xcode
//
// Layout: LightswitchKit holds everything testable without a window; the
// Lightswitch executable is the AppKit/SwiftUI shell.
import PackageDescription

let package = Package(
    name: "Lightswitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lightswitch", targets: ["Lightswitch"]),
        .library(name: "LightswitchKit", targets: ["LightswitchKit"]),
    ],
    targets: [
        .target(
            name: "LightswitchKit",
            path: "Lightswitch/Kit"
        ),
        .executableTarget(
            name: "Lightswitch",
            dependencies: ["LightswitchKit"],
            path: "Lightswitch/App"
        ),
        .testTarget(
            name: "LightswitchTests",
            dependencies: ["LightswitchKit"],
            path: "Lightswitch/Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
