// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GenesisImaging",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ImagingCore", targets: ["ImagingCore"]),
        .library(name: "NcnnEngine", targets: ["NcnnEngine"]),
        .library(name: "CoreMLEngine", targets: ["CoreMLEngine"]),
        .executable(name: "GenesisImaging", targets: ["AppShell"]),
    ],
    targets: [
        .target(
            name: "ImagingCore",
            dependencies: []
        ),
        .target(
            name: "NcnnEngine",
            dependencies: ["ImagingCore"]
        ),
        .target(
            name: "CoreMLEngine",
            dependencies: ["ImagingCore"]
        ),
        .executableTarget(
            name: "AppShell",
            dependencies: ["ImagingCore", "NcnnEngine", "CoreMLEngine"]
        ),
        .testTarget(
            name: "ImagingCoreTests",
            dependencies: ["ImagingCore"]
        ),
        .testTarget(
            name: "NcnnEngineTests",
            dependencies: ["NcnnEngine"]
        ),
    ]
)
