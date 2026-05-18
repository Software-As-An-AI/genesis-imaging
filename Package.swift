// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GenesisImaging",
    platforms: [
        // Phase A.4 (v0.6.0.0): macOS 14 → 15 (Sequoia) for flux-2-swift-mlx
        // (MLX-Swift requires macOS 15+). v0.5.x stays on .v14 for users not
        // ready to upgrade.
        .macOS(.v15),
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
        // min macOS .v13 (we ship .v15, compatible). Swift 5.8 toolchain.
        .package(url: "https://github.com/apple/ml-stable-diffusion", from: "1.1.1"),
        // Phase A.4 (v0.6.0.0): FLUX.2 Klein 4B native Swift MLX engine.
        // VincentGourbin/flux-2-swift-mlx — single-maintainer (bus-factor-1)
        // but very active (PR #85 merged 2026-05-17). Provides Flux2Core,
        // FluxTextEncoders, Flux2Chains library products. Brings transitive
        // mlx-swift + swift-transformers 1.1.6+ (POTENTIAL CONFLICT with
        // Apple ml-stable-diffusion's swift-transformers 0.1.8 exact pin —
        // resolve at build).
        // min macOS .v15 (matches our bump). Apache-MIT mixed license stack.
        .package(url: "https://github.com/VincentGourbin/flux-2-swift-mlx", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "ImagingCore",
            dependencies: [],
            swiftSettings: legacySwiftSettings
        ),
        .target(
            name: "NcnnEngine",
            dependencies: ["ImagingCore"],
            swiftSettings: legacySwiftSettings
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
            ],
            swiftSettings: legacySwiftSettings
        ),
        .testTarget(
            name: "ImagingCoreTests",
            dependencies: ["ImagingCore"],
            swiftSettings: legacySwiftSettings
        ),
        .testTarget(
            name: "NcnnEngineTests",
            dependencies: ["NcnnEngine"],
            resources: [.process("Resources")],
            swiftSettings: legacySwiftSettings
        ),
        .testTarget(
            name: "CoreMLEngineTests",
            dependencies: ["CoreMLEngine", "ImagingCore"],
            resources: [.process("Resources")],
            swiftSettings: legacySwiftSettings
        ),
    ]
)

// Swift 6.0 tools-version is required by flux-2-swift-mlx, but our existing
// code (Phase A.1-A.3) was written under Swift 5 concurrency. Force Swift 5
// language mode for our pre-FLUX targets so the strict concurrency checker
// doesn't gate ship on a sweeping refactor. New FLUX engine target (added
// later in Phase A.4) opts into Swift 6 concurrency explicitly.
//
// Tracked as technical debt: incremental migration to Swift 6 concurrency
// per-file when each file is next touched. CoreMLEngine kept on default
// (compiler picks per source) — already MainActor-clean for StableDiffusionXLEngine.
private var legacySwiftSettings: [SwiftSetting] {
    [.swiftLanguageMode(.v5)]
}
