// swift-tools-version:5.9
// Claude Notch — the notch as a status light for Claude Code sessions.
//
//   swift build            debug binary in .build/debug/ClaudeNotch
//   swift test             the unit tests
//   make app               release build wrapped as build/ClaudeNotch.app
//   open Package.swift     the same targets inside Xcode
//
// Layout: ClaudeNotchKit holds everything testable without a window; the
// ClaudeNotch executable is the AppKit/SwiftUI shell.
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeNotch", targets: ["ClaudeNotch"]),
        .library(name: "ClaudeNotchKit", targets: ["ClaudeNotchKit"]),
    ],
    targets: [
        .target(
            name: "ClaudeNotchKit",
            path: "ClaudeNotch/Kit"
        ),
        .executableTarget(
            name: "ClaudeNotch",
            dependencies: ["ClaudeNotchKit"],
            path: "ClaudeNotch/App"
        ),
        .testTarget(
            name: "ClaudeNotchTests",
            dependencies: ["ClaudeNotchKit"],
            path: "ClaudeNotch/Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
