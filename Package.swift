// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Athena",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AthenaApp", targets: ["Athena"]),
        .executable(name: "athena", targets: ["athena-cli"]),
    ],
    targets: [
        // Everything that is not UI: persistence, scheduling, evaluation, Ollama, LeetCode.
        // Shared by the app and the terminal CLI so both read/write the same SQLite database.
        .target(
            name: "AthenaCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Athena",
            dependencies: ["AthenaCore"]
        ),
        .executableTarget(
            name: "athena-cli",
            dependencies: ["AthenaCore"]
        ),
        .testTarget(
            name: "AthenaCoreTests",
            dependencies: ["AthenaCore"]
        ),
    ]
)
