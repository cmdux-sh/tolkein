// swift-tools-version: 6.2
import Foundation
import PackageDescription

let sweetCookieKitPath = "../SweetCookieKit"
let useLocalSweetCookieKit =
    ProcessInfo.processInfo.environment["CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT"] == "1"
let sweetCookieKitDependency: Package.Dependency =
    useLocalSweetCookieKit && FileManager.default.fileExists(atPath: sweetCookieKitPath)
    ? .package(path: sweetCookieKitPath)
    : .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.5.11")

/// The shared Mac UI package is private; macOS CI reads it with a read-only deploy key.
let macOSOnlyDependencies: [Package.Dependency] = {
    #if os(macOS)
    [.package(url: "https://github.com/cmdux-sh/internal-ui.git", from: "0.12.0")]
    #else
    []
    #endif
}()

let package = Package(
    name: "CodexBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: {
        var products: [Product] = [
            .library(name: "CodexBarCore", targets: ["CodexBarCore"]),
            .executable(name: "CodexBarCLI", targets: ["CodexBarCLI"]),
        ]

        #if os(macOS)
        products.append(contentsOf: [
            .executable(name: "CodexBar", targets: ["CodexBar"]),
            .executable(name: "CodexBarClaudeWatchdog", targets: ["CodexBarClaudeWatchdog"]),
            .executable(name: "CodexBarWidget", targets: ["CodexBarWidget"]),
            .executable(name: "CodexBarClaudeWebProbe", targets: ["CodexBarClaudeWebProbe"]),
        ])
        #endif

        return products
    }(),
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
        .package(url: "https://github.com/steipete/Commander", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "4.5.2"..<"6.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.16.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/zats/Vortex", revision: "ef5392088d4aeb255c4eee83157dbdafcd31bf07"),
        sweetCookieKitDependency,
    ] + macOSOnlyDependencies,
    targets: {
        var targets: [Target] = [
            .target(
                name: "CQuickJS",
                path: "Sources/CQuickJS",
                exclude: ["README.md", "LICENSE"],
                publicHeadersPath: "include",
                cSettings: [
                    .define("_GNU_SOURCE"),
                ]),
            .target(
                name: "CodexBarCore",
                dependencies: [
                    "CQuickJS",
                    .product(name: "Crypto", package: "swift-crypto"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ],
                linkerSettings: [
                    .linkedFramework("JavaScriptCore", .when(platforms: [.macOS])),
                ]),
            .executableTarget(
                name: "CodexBarCLI",
                dependencies: [
                    "CodexBarCore",
                    .product(name: "Commander", package: "Commander"),
                    .product(name: "Crypto", package: "swift-crypto"),
                ],
                path: "Sources/CodexBarCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            // Crash-test subprocess: tests SIGKILL it mid-save to prove the cost store's
            // save cycle is atomic. Not shipped; built only as a test dependency.
            .executableTarget(
                name: "CodexBarCostStoreCrashProbe",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarCostStoreCrashProbe",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            // Sole owner of the adaptive refresh decision table, package-internal.
            .target(
                name: "AdaptiveRefreshCore",
                dependencies: [],
                path: "Sources/AdaptiveRefreshCore",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .testTarget(
                name: "CodexBarPluginTests",
                dependencies: ["CodexBarCore"],
                path: "TestsPlugin",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "CodexBarCoreTests",
                dependencies: [
                    "CodexBarCore",
                    "CodexBarCLI",
                ],
                path: "TestsCore",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
        ]

        #if os(macOS)
        targets.append(contentsOf: [
            .executableTarget(
                name: "CodexBarClaudeWatchdog",
                dependencies: [],
                path: "Sources/CodexBarClaudeWatchdog",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBar",
                dependencies: [
                    .product(name: "Sparkle", package: "Sparkle"),
                    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                    .product(name: "Vortex", package: "Vortex"),
                    .product(name: "InternalUI", package: "internal-ui"),
                    "AdaptiveRefreshCore",
                    "CodexBarCore",
                ],
                path: "Sources/CodexBar",
                // Agent instructions for this target's UI (see Sources/CodexBar/AGENTS.md).
                exclude: ["AGENTS.md", "CLAUDE.md"],
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    // Opt into Swift 6 strict concurrency (approachable migration path).
                    .enableUpcomingFeature("StrictConcurrency"),
                    .define("ENABLE_SPARKLE"),
                ]),
            .executableTarget(
                name: "CodexBarWidget",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarWidget",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBarClaudeWebProbe",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarClaudeWebProbe",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
        ])

        targets.append(.testTarget(
            name: "CodexBarTests",
            dependencies: [
                "CodexBar", "CodexBarCore", "CodexBarCLI", "CodexBarCostStoreCrashProbe", "CodexBarWidget",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Tests",
            exclude: [
                "CodexBarTests/ProviderPluginDetailsParityTests.swift",
                "CodexBarTests/ProviderPluginExtensionParityTests.swift",
                "CodexBarTests/ProviderPluginParityTests.swift",
                "CodexBarTests/ProviderPluginRuntimeTests.swift",
                "CodexBarTests/Sub2APIPluginGoldenTests.swift",
            ],
            resources: [
                .copy("CodexBarTests/Fixtures"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ],
            linkerSettings: [
                // XCTest's executable is three directories below its sibling framework products.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."]),
            ]))
        #endif

        return targets
    }())
