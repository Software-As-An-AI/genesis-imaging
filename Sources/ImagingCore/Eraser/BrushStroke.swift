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
    /// Grayscale fill value the stroke paints. Default 255 (pure white)
    /// preserves prior behavior. v0.3.5.4: editor samples the ambient
    /// background color at stroke-start so colored / sepia / parchment
    /// pages erase to the page color, not a hard white circle.
    public let fillColor: UInt8

    public init(points: [CGPoint], radius: CGFloat, fillColor: UInt8 = 255) {
        self.points = points
        self.radius = radius
        self.fillColor = fillColor
    }
}
