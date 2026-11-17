// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CopyT",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CopyT",
            path: "Sources/CopyT",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "CopyTTests",
            dependencies: ["CopyT"],
            path: "Tests/CopyTTests"
        ),
    ]
)
