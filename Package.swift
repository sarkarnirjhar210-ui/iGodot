// swift-tools-version: 5.9
import PackageDescription
let macLibgodotTarget: Target = .binaryTarget(
    name: "mac_libgodot",
    url: "https://github.com/migueldeicaza/godot/releases/download/v4.7.3-rc-swiftgodotkit.1/libgodot-macos.xcframework.zip",
    checksum: "dda4992c4c5abc8de7af49c3a1465e966aed74b3c0599c48544a333b9a94589e"
)

let iosLibgodotTarget: Target = .binaryTarget(
    name: "ios_libgodot",
    url: "https://github.com/migueldeicaza/godot/releases/download/v4.7.3-rc-swiftgodotkit.1/libgodot-ios.xcframework.zip",
    checksum: "20610e7d5c52302481a51e9fc020fd68a6b113e9ad19e2c5e602ab5d1c330f37"
)

let package = Package(
    name: "SwiftGodotKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftGodotKit",
            targets: [.binaryTarget(
            name: "SwiftGodot",
            url: "https://github.com/migueldeicaza/SwiftGodot/releases/download/v0.99.2/SwiftGodot.xcframework.zip",
            checksum: "102bbfa42f4169d2f5959eb1f3f084cbd75da18b0acc51cf2ca43b285eb1dba4"
        ),
        .binaryTarget(
            name: "SwiftGodotRuntime",
            url: "https://github.com/migueldeicaza/SwiftGodot/releases/download/v0.99.2/SwiftGodotRuntime.xcframework.zip",
            checksum: "194c4792dcd0414138d7c004404791b202d5c8453967ea0f5e54035cb023658f"
        ),
        .binaryTarget(
            name: "GDExtension",
            url: "https://github.com/migueldeicaza/SwiftGodot/releases/download/v0.99.2/GDExtension.xcframework.zip",
            checksum: "d67e9bda1fa79067393f3f67777c6d09b991b9b5b86cbae7badb2f3a386044bd"
        ),
        .binaryTarget(
            name: "SwiftGodotMacroPlugin",
            url: "https://github.com/migueldeicaza/SwiftGodot/releases/download/v0.99.2/SwiftGodotMacroPlugin.xcframework.zip",
            checksum: "d4a46ed848ddf11888628421c0c07a2ad39c6a342cf2088647ff11235bb3ede6"
        ),
        "SwiftGodotKit"]),
        .executable(name: "TrivialSample", targets: ["TrivialSample"]),
    ],
    dependencies: [
        // Prebuilt SwiftGodot XCFrameworks, so clients do not compile SwiftGodot
        // or swift-syntax. Produced by SwiftGodot's binaries.yml release workflow.
        
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftGodotKit",
            dependencies: [
                "SwiftGodot",
                "libgodot",
                .target(name: "apple_plugin_stubs", condition: .when(platforms: [.iOS])),
                .target(name: "mac_libgodot", condition: .when(platforms: [.macOS])),
                .target(name: "ios_libgodot", condition: .when(platforms: [.iOS])),
            ]
        ),

        .executableTarget(
            name: "TrivialSample",
            dependencies: ["SwiftGodotKit"],
            resources: [
                .copy("main.pck"),
                .copy("AxolotlDemo-LICENSE.txt"),
                .copy("THIRD_PARTY.md"),
                .copy("Xolonium-OFL.txt"),
            ]
        ),

        .target(
            name: "apple_plugin_stubs",
            path: "Sources/apple_plugin_stubs",
            publicHeadersPath: "include"
        ),

        macLibgodotTarget,
        iosLibgodotTarget,
        .systemLibrary(
            name: "libgodot"
        ),
    ],
    swiftLanguageModes: [.v5]
)
