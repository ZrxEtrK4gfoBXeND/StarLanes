// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "starlanes",
    products: [ .executable(name: "starlanes", targets: ["starlanes"])],
    targets: [
        // The game engine and console front end, built as a library so it can be tested.
        .target(name: "StarLanesKit", dependencies: [], path: "Sources/StarLanesKit"),
        // The command line entry point.
        .target(name: "starlanes", dependencies: ["StarLanesKit"], path: "Sources/starlanes"),
        .testTarget(name: "StarLanesKitTests", dependencies: ["StarLanesKit"], path: "Tests/StarLanesKitTests")
    ]
)
