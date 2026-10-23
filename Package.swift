// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

// PestoCore is the UI-free engine: pasteboard watching, storage (SwiftData models and the storage actor), sync, paste,
// predicate.
// It builds and tests independently of Xcode — useful for CI and fast local iteration. Swift 6 language mode
// (tools 6.0) already checks concurrency strictly in every target, so no StrictConcurrency flag is set.
// The full Pesto.app target (in Pesto.yml / Pesto.xcodeproj) depends on this package.

let package = Package(
    name: "PestoCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PestoCore", targets: ["PestoCore"])
    ],
    dependencies: [
        // No third-party deps in Core. Sparkle and snapshot-testing live in the Xcode-side targets.
    ],
    targets: [
        .target(
            name: "PestoCore",
            path: "Sources/Core",
            exclude: [
                "AI/CLAUDE.md", "Backup/CLAUDE.md", "Paste/CLAUDE.md", "Pasteboard/CLAUDE.md", "Storage/CLAUDE.md",
                "Sync/CLAUDE.md"
            ],
            // The SwiftData @Model files (Storage/Models) need Xcode's macro plugin, which is the toolchain every
            // supported build already uses (CommandLineTools cannot build this package at all, see AGENTS.md).
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "PestoCLI",
            dependencies: ["PestoCore"],
            path: "Sources/CLI",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "PestoCoreTests",
            dependencies: ["PestoCore"],
            path: "Tests/PestoCoreTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "PestoRegressionTests",
            dependencies: ["PestoCore"],
            path: "Tests/PestoRegressionTests"
        )
    ]
)
