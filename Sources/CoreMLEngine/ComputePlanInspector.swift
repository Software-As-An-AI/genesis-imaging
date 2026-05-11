import Foundation
import CoreML
import ImagingCore

/// Reports which compute devices (ANE / GPU / CPU) Core ML's planner would
/// prefer for each layer of a compiled `.mlmodelc`. Non-invasive — uses
/// `MLComputePlan` introspection, no actual inference or root access.
///
/// Available on macOS 14.4+. The bundled `RealESRGAN_x4plus.mlmodelc` is a
/// `neuralNetwork` model, so this inspector enumerates the neural-network
/// layers. ML Program / Pipeline structures aren't shipped in Faz 2.
@available(macOS 14.4, *)
public enum ComputePlanInspector {

    /// Per-layer compute-device preference distribution.
    public struct DeviceUsageSummary: Sendable, Equatable {
        public let totalLayers: Int
        /// Layers the planner prefers on the Apple Neural Engine.
        public let aneCount: Int
        /// Layers the planner prefers on the Metal GPU.
        public let gpuCount: Int
        /// Layers the planner prefers on the CPU.
        public let cpuCount: Int
        /// Layers whose preferred device couldn't be resolved (rare).
        public let unknownCount: Int

        public init(totalLayers: Int, aneCount: Int, gpuCount: Int, cpuCount: Int, unknownCount: Int) {
            self.totalLayers = totalLayers
            self.aneCount = aneCount
            self.gpuCount = gpuCount
            self.cpuCount = cpuCount
            self.unknownCount = unknownCount
        }

        /// Fraction of layers the planner prefers on the ANE.
        public var anePreferredRatio: Double {
            totalLayers > 0 ? Double(aneCount) / Double(totalLayers) : 0
        }

        /// Coarse verdict — useful for benchmark reports / UI badges.
        public var verdict: Verdict {
            if totalLayers == 0 { return .unsupported }
            if anePreferredRatio >= 0.5 { return .aneDominant }
            if Double(gpuCount) / Double(totalLayers) >= 0.5 { return .gpuDominant }
            return .mixed
        }

        public enum Verdict: String, Sendable, CaseIterable {
            case aneDominant = "ane-dominant"
            case gpuDominant = "gpu-dominant"
            case mixed = "mixed"
            case unsupported = "unsupported"
        }
    }

    /// Asynchronously load a compute plan + summarize device usage.
    /// - Parameters:
    ///   - modelURL: Path to a compiled `.mlmodelc` directory.
    ///   - configuration: Compute-unit configuration (default `.all`).
    public static func summarize(
        modelURL: URL,
        configuration: MLModelConfiguration? = nil
    ) async throws -> DeviceUsageSummary {
        let config: MLModelConfiguration
        if let provided = configuration {
            config = provided
        } else {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            config = cfg
        }

        let plan: MLComputePlan
        do {
            plan = try await MLComputePlan.load(contentsOf: modelURL, configuration: config)
        } catch {
            throw UpscaleError.ioError(
                message: "MLComputePlan.load failed for \(modelURL.path): \(error)"
            )
        }

        guard case .neuralNetwork(let nn) = plan.modelStructure else {
            // Future work: handle .program / .pipeline. For Faz 2 we only ship
            // a neuralNetwork model, so this is a real "not supported" path,
            // not a swallowed error.
            throw UpscaleError.notImplemented(
                reason: "ComputePlanInspector currently supports neuralNetwork models only"
            )
        }

        var ane = 0
        var gpu = 0
        var cpu = 0
        var unknown = 0

        for layer in nn.layers {
            guard let usage = plan.deviceUsage(for: layer) else {
                unknown += 1
                continue
            }
            switch usage.preferred {
            case .cpu:
                cpu += 1
            case .gpu:
                gpu += 1
            case .neuralEngine:
                ane += 1
            @unknown default:
                unknown += 1
            }
        }

        return DeviceUsageSummary(
            totalLayers: nn.layers.count,
            aneCount: ane,
            gpuCount: gpu,
            cpuCount: cpu,
            unknownCount: unknown
        )
    }

    /// Format a one-line summary for logs / report tables.
    /// Example: `"ANE 720 (70%) · GPU 280 (27%) · CPU 26 (3%) · unknown 0 [verdict: ane-dominant]"`
    public static func formatSummary(_ summary: DeviceUsageSummary) -> String {
        guard summary.totalLayers > 0 else {
            return "unsupported (0 layers)"
        }
        let total = Double(summary.totalLayers)
        let anePct = Int((Double(summary.aneCount) / total * 100).rounded())
        let gpuPct = Int((Double(summary.gpuCount) / total * 100).rounded())
        let cpuPct = Int((Double(summary.cpuCount) / total * 100).rounded())
        return "ANE \(summary.aneCount) (\(anePct)%) · GPU \(summary.gpuCount) (\(gpuPct)%) · CPU \(summary.cpuCount) (\(cpuPct)%) · unknown \(summary.unknownCount) [verdict: \(summary.verdict.rawValue)]"
    }
}
