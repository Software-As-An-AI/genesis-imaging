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
    dependencies: [
        // Sparkle 2.x — macOS auto-update framework. Hardened Runtime + EdDSA
        // baked in; no extra entitlements needed for sandboxed apps (we don't
        // sandbox). Cross-edition reuse seed: future Mac native edition'lar
        // aynı SPM dep'i kullanır.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
        // Apple ml-stable-diffusion — Phase A.2 SDXL inference pipeline.
        // Brings `StableDiffusionXLPipeline` (text encoder + UNet loop + VAE
        // decode) with progressHandler callback that bridges 1:1 to our
        // `GenerationProgress.step(current:total:)`. Transitive dep:
        // swift-transformers 0.1.8 exact-pinned upstream.
        // min macOS .v13 (we ship .v14, compatible). Swift 5.8 toolchain.
        .package(url: "https://github.com/apple/ml-stable-diffusion", from: "1.1.1"),
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
            dependencies: [
                "ImagingCore",
                .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
            ],
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
            dependencies: [
                "ImagingCore",
                "NcnnEngine",
                "CoreMLEngine",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
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
