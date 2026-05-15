import SwiftUI

/// Compact icon-button style with hover affordance.
///
/// Default SwiftUI `.borderless` button on macOS gives zero hover feedback —
/// users can't tell which icon is interactive. This style adds:
///   - Subtle rounded background on hover (secondary 18% opacity)
///   - Slight press shrink (0.92×)
///   - Soft easing on both transitions
///
/// Cursor pointer change is intentionally omitted (macOS doesn't have a
/// reliable cross-version "link cursor" without AppKit gymnastics — the
/// hover background is the dominant signal anyway).
public struct IconHoverButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HoverableLabel(configuration: configuration)
    }

    /// Inner View struct so `@State` survives per-button (a `ButtonStyle`
    /// itself can't hold mutable state — its `makeBody` is called per render).
    private struct HoverableLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.secondary.opacity(0.18) : Color.clear)
                )
                .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

public extension ButtonStyle where Self == IconHoverButtonStyle {
    /// Sugar so call sites read `.buttonStyle(.iconHover)`.
    static var iconHover: IconHoverButtonStyle { IconHoverButtonStyle() }
}
