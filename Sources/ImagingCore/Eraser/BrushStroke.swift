import Foundation
import CoreGraphics

/// A single eraser brush stroke captured in **image-space coordinates**
/// (not display-space). Points are typically densified by Catmull-Rom
/// interpolation in the editor view before being rasterized.
///
/// `radius` is half-diameter in image pixels. Brush diameter slider in
/// UI shows the full diameter; this struct stores radius so circle
/// rasterization is direct.
public struct BrushStroke: Sendable, Equatable {
    public let points: [CGPoint]
    public let radius: CGFloat

    public init(points: [CGPoint], radius: CGFloat) {
        self.points = points
        self.radius = radius
    }
}
