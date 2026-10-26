// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Newton", platforms: [.macOS(.v14)],
    products: [.library(name: "NewtonCore", targets: ["NewtonCore"]),
               .executable(name: "Newton", targets: ["NewtonApp"]),
               .executable(name: "NewtonBench", targets: ["NewtonBench"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "NewtonCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "NewtonBench", dependencies: ["NewtonCore"], path: "Benchmarks"),
        .target(name: "NewtonWorkspace", dependencies: ["NewtonCore"]),
        .executableTarget(name: "NewtonApp", dependencies: ["NewtonCore", "NewtonWorkspace"]),
        .testTarget(name: "NewtonCoreTests", dependencies: ["NewtonCore", "CSQLite"]),
        .testTarget(name: "NewtonWorkspaceTests", dependencies: ["NewtonCore", "NewtonWorkspace"])
    ], swiftLanguageModes: [.v6]
)
