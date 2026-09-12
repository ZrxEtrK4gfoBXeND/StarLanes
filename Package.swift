// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "starlanes",
    products: [
        .executable(name: "starlanes", targets: ["starlanes"]),
        // The game engine, exported so other packages can depend on it.
        .library(name: "StarLanesKit", targets: ["StarLanesKit"])
    ],
    targets: [
        // The game engine and console front end, built as a library so it can be tested.
        .target(name: "StarLanesKit", dependencies: [], path: "Sources/StarLanesKit"),
        // The command line entry point.
        .executableTarget(name: "starlanes", dependencies: ["StarLanesKit"], path: "Sources/starlanes"),
        .testTarget(name: "StarLanesKitTests", dependencies: ["StarLanesKit"], path: "Tests/StarLanesKitTests")
    ]
)
