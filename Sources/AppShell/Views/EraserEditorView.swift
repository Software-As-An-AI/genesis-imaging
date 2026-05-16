import SwiftUI
import AppKit
import ImagingCore

/// Sheet-presented eraser editor. Decoded image fills the canvas; user
/// strokes with mouse drag fill image regions to pure white. Toolbar
/// surfaces brush size, undo/redo, save, cancel.
///
/// Coordinate spaces:
///   - **image-space:** original pixel coordinates of the source PNG
///     (e.g., 5016×5016). Strokes stored here.
///   - **view-space:** SwiftUI canvas points, scaled to fit a `fitRect`
///     determined by aspect-fit on the available frame. Mouse events arrive
///     in view-space; we transform to image-space before storing strokes.
@MainActor
struct EraserEditorView: View {
    @Bindable var session: EraserSession
    let onSaved: (URL) -> Void
    let onCancel: () -> Void

    @Environment(\.undoManager) private var undoManager

    /// In-progress (not yet committed) stroke points, image-space.
    @State private var inProgressPoints: [CGPoint] = []

    /// Current hover position (image-space) for brush preview circle.
    @State private var hoverPoint: CGPoint? = nil

    /// True when a save operation is running. Disables interaction.
    @State private var isSaving: Bool = false

    /// Error alert state.
    @State private var saveError: String? = nil

    /// Decoded NSImage cached for canvas drawing — proxy at ≤1.5K for
    /// interactive performance on 5K source images.
    @State private var proxyImage: NSImage? = nil

    /// Zoom factor (multiplies the aspect-fit rect). 1.0 = fit-to-window.
    /// Range clamped to [0.5, 8.0] — beyond 8× brush precision dominated
    /// by source resolution, panning becomes the bottleneck.
    @State private var zoom: CGFloat = 1.0

    /// Pan offset in view-space points (translates the displayed rect).
    @State private var pan: CGSize = .zero

    /// Pan baseline captured at drag start (so successive drags accumulate).
    @State private var panStart: CGSize = .zero

    /// Tool mode: `.eraser` (drag erases), `.pan` (drag pans the canvas).
    @State private var tool: Tool = .eraser

    enum Tool: String, CaseIterable, Identifiable {
        case eraser, pan
        var id: String { rawValue }
        var label: String { self == .eraser ? "Silgi" : "Kaydır" }
        var icon: String { self == .eraser ? "eraser" : "hand.draw" }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))
            Divider()
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear { renderProxy() }
        .alert("Kaydetme hatası", isPresented: errorPresented) {
            Button("Tamam", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Tool mode toggle (eraser vs pan)
            Picker("", selection: $tool) {
                ForEach(Tool.allCases) { t in
                    Image(systemName: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .labelsHidden()
            .help("Silgi (E) / Kaydır (H)")

            // Brush size (only meaningful in eraser mode)
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $session.brushDiameter, in: 10...400, step: 2)
                    .frame(width: 140)
                Text("\(Int(session.brushDiameter))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text("px")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .opacity(tool == .eraser ? 1.0 : 0.5)

            Divider().frame(height: 18)

            // Zoom controls
            HStack(spacing: 4) {
                Button { zoomBy(0.8) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Uzaklaş (⌘−)")
                .keyboardShortcut("-", modifiers: .command)

                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42)

                Button { zoomBy(1.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Yakınlaş (⌘+)")
                .keyboardShortcut("=", modifiers: .command)

                Button { resetView() } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .help("Sığdır (⌘0)")
                .keyboardShortcut("0", modifiers: .command)
            }

            Spacer()

            // Undo/redo
            HStack(spacing: 4) {
                Button {
                    undoManager?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Geri al (⌘Z)")
                .disabled(undoManager?.canUndo != true)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    undoManager?.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .help("Yinele (⌘⇧Z)")
                .disabled(undoManager?.canRedo != true)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Divider().frame(height: 18)

            Button("İptal", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await performSave() }
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Kaydet")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || session.strokes.isEmpty)
        }
    }

    // MARK: - Zoom helpers

    private func zoomBy(_ factor: CGFloat) {
        let next = (zoom * factor).clamped(to: 0.25...8.0)
        zoom = next
        if zoom == 1.0 { pan = .zero }
    }

    private func resetView() {
        zoom = 1.0
        pan = .zero
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let displayRect = currentDisplayRect(in: geo.size)
            Canvas { ctx, _ in
                drawCanvas(ctx: ctx, fitRect: displayRect)
            }
            .contentShape(Rectangle())
            .gesture(combinedGesture(fitRect: displayRect))
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    hoverPoint = imageCoord(view: p, fitRect: displayRect)
                case .ended:
                    hoverPoint = nil
                }
            }
        }
    }

    /// Current display rect = aspect-fit × zoom + pan offset. View-space.
    private func currentDisplayRect(in containerSize: CGSize) -> CGRect {
        let base = aspectFitRect(
            content: CGSize(width: session.imageWidth, height: session.imageHeight),
            in: containerSize
        )
        let zoomedSize = CGSize(width: base.width * zoom, height: base.height * zoom)
        let centerX = base.midX + pan.width
        let centerY = base.midY + pan.height
        return CGRect(
            x: centerX - zoomedSize.width / 2,
            y: centerY - zoomedSize.height / 2,
            width: zoomedSize.width,
            height: zoomedSize.height
        )
    }

    private func drawCanvas(ctx: GraphicsContext, fitRect: CGRect) {
        // 1. Background image at fit-rect.
        if let proxy = proxyImage,
           let cg = proxy.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let img = Image(decorative: cg, scale: 1.0, orientation: .up)
            ctx.draw(img, in: fitRect)
        } else {
            ctx.fill(Path(fitRect), with: .color(.gray.opacity(0.2)))
        }

        // 2. Committed strokes.
        let scale = fitRect.width / CGFloat(session.imageWidth)
        for stroke in session.stroke​Stamps() {
            drawStroke(stroke, ctx: ctx, fitRect: fitRect, scale: scale)
        }
        // 3. In-progress stroke (real-time during drag).
        if !inProgressPoints.isEmpty {
            let s = BrushStroke(points: inProgressPoints, radius: session.brushRadius)
            drawStroke(s, ctx: ctx, fitRect: fitRect, scale: scale)
        }
        // 4. Hover preview circle (outline only).
        if let hp = hoverPoint {
            let viewPoint = viewCoord(image: hp, fitRect: fitRect)
            let viewRadius = session.brushRadius * scale
            let rect = CGRect(
                x: viewPoint.x - viewRadius,
                y: viewPoint.y - viewRadius,
                width: viewRadius * 2,
                height: viewRadius * 2
            )
            ctx.stroke(Path(ellipseIn: rect), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    private func drawStroke(
        _ stroke: BrushStroke,
        ctx: GraphicsContext,
        fitRect: CGRect,
        scale: CGFloat
    ) {
        let viewRadius = stroke.radius * scale
        for p in stroke.points {
            let vp = viewCoord(image: p, fitRect: fitRect)
            let rect = CGRect(
                x: vp.x - viewRadius, y: vp.y - viewRadius,
                width: viewRadius * 2, height: viewRadius * 2
            )
            ctx.fill(Path(ellipseIn: rect), with: .color(.white))
        }
    }

    // MARK: - Gesture

    /// Drag handler: tool mode determines behavior. `.eraser` paints
    /// strokes, `.pan` translates the displayed rect.
    private func combinedGesture(fitRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isSaving else { return }
                switch tool {
                case .eraser:
                    let img = imageCoord(view: value.location, fitRect: fitRect)
                    inProgressPoints.append(img)
                case .pan:
                    pan = CGSize(
                        width: panStart.width + value.translation.width,
                        height: panStart.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                switch tool {
                case .eraser:
                    guard !inProgressPoints.isEmpty else { return }
                    commitStroke(points: inProgressPoints)
                    inProgressPoints.removeAll()
                case .pan:
                    panStart = pan
                }
            }
    }

    private func commitStroke(points: [CGPoint]) {
        let densified = EraserApplier.densify(points, step: max(session.brushRadius * 0.5, 2))
        let stroke = BrushStroke(points: densified, radius: session.brushRadius)
        session.strokes.append(stroke)
        registerUndo()
    }

    private func registerUndo() {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: session) { target in
            guard !target.strokes.isEmpty else { return }
            let removed = target.strokes.removeLast()
            // Register the redo (re-append the removed stroke).
            um.registerUndo(withTarget: target) { redoTarget in
                redoTarget.strokes.append(removed)
                // And register undo-of-redo as a fresh removal.
                self.registerUndo()
            }
        }
    }

    // MARK: - Coordinate transforms

    private func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w, height: h
        )
    }

    private func imageCoord(view: CGPoint, fitRect: CGRect) -> CGPoint {
        guard fitRect.width > 0 else { return .zero }
        let scale = CGFloat(session.imageWidth) / fitRect.width
        let x = (view.x - fitRect.minX) * scale
        let y = (view.y - fitRect.minY) * scale
        return CGPoint(x: x, y: y)
    }

    private func viewCoord(image: CGPoint, fitRect: CGRect) -> CGPoint {
        guard session.imageWidth > 0 else { return .zero }
        let scale = fitRect.width / CGFloat(session.imageWidth)
        return CGPoint(
            x: fitRect.minX + image.x * scale,
            y: fitRect.minY + image.y * scale
        )
    }

    // MARK: - Proxy + save

    private func renderProxy() {
        let maxDim: CGFloat = 1500
        let w = CGFloat(session.imageWidth)
        let h = CGFloat(session.imageHeight)
        let scale = min(1.0, maxDim / max(w, h))
        let targetSize = CGSize(width: w * scale, height: h * scale)

        // Create NSImage from session.baseBuffer (grayscale UInt8) at downsampled
        // resolution. Use Core Graphics to draw the proxy.
        guard let cg = makeFullResCGImage() else { return }
        let nsImage = NSImage(size: targetSize)
        nsImage.lockFocus()
        if let proxyCtx = NSGraphicsContext.current?.cgContext {
            proxyCtx.interpolationQuality = .high
            proxyCtx.draw(cg, in: CGRect(origin: .zero, size: targetSize))
        }
        nsImage.unlockFocus()
        proxyImage = nsImage
    }

    /// Build a full-resolution CGImage from `session.baseBuffer`. Used only
    /// once at sheet open to build the display proxy.
    private func makeFullResCGImage() -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            ?? CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(session.baseBuffer) as CFData) else {
            return nil
        }
        return CGImage(
            width: session.imageWidth, height: session.imageHeight,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: session.imageWidth,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func performSave() async {
        let outcome = SaveDestinationDialog.present()
        guard outcome != .cancel else { return }

        isSaving = true
        defer { isSaving = false }

        let target: URL
        switch outcome {
        case .newFile:    target = OutputWriter.resolveEditedURL(source: session.sourceURL)
        case .overwrite:  target = session.sourceURL
        case .cancel:     return  // unreachable
        }

        // Compose strokes onto a full-res copy of the base buffer + encode.
        let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) { [strokes = session.strokes,
                                                                                          base = session.baseBuffer,
                                                                                          width = session.imageWidth,
                                                                                          height = session.imageHeight] in
            var buf = base
            EraserApplier.compose(
                strokes: strokes,
                onto: &buf,
                width: width, height: height
            )
            do {
                try EraserApplier.encodePNG(
                    buffer: buf, width: width, height: height,
                    to: target
                )
                QuarantineUtil.stripQuarantine(at: target)
                return .success(target)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let url):
            onSaved(url)
        case .failure(let err):
            saveError = "Kaydetme başarısız: \(err.localizedDescription)"
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Session helper

extension EraserSession {
    /// Return the strokes list. Renamed wrapper to dodge a SwiftUI/Observation
    /// quirk where `session.strokes` direct read inside `Canvas { ... }`
    /// closure can trip a tracking warning in some Swift toolchains.
    func stroke​Stamps() -> [BrushStroke] { strokes }
}
