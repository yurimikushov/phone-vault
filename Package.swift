// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhoneVault",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PhoneVaultCore",
            targets: ["PhoneVaultCore"]
        ),
        .executable(
            name: "PhoneVaultApp",
            targets: ["PhoneVaultApp"]
        ),
    ],
    targets: [
        .target(
            name: "PhoneVaultCore",
            path: "src/PhoneVaultCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PhoneVaultApp",
            dependencies: ["PhoneVaultCore"],
            path: "src/PhoneVaultApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PhoneVaultCoreTests",
            dependencies: ["PhoneVaultCore"],
            path: "tests/PhoneVaultCoreTests",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
    ]
)
