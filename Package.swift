// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GenesisImaging",
    platforms: [
        .macOS(.v14),
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
            dependencies: ["ImagingCore"],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Vision"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
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
            dependencies: ["NcnnEngine"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CoreMLEngineTests",
            dependencies: ["CoreMLEngine", "ImagingCore"],
            resources: [.process("Resources")]
        ),
    ]
)
