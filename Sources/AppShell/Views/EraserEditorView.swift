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
            HStack(spacing: 8) {
                Text("Brush")
                    .font(.callout)
                Slider(value: $session.brushDiameter, in: 10...400, step: 2)
                    .frame(width: 200)
                Text("\(Int(session.brushDiameter)) px")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    undoManager?.undo()
                } label: {
                    Label("Geri al", systemImage: "arrow.uturn.backward")
                }
                .disabled(undoManager?.canUndo != true)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    undoManager?.redo()
                } label: {
                    Label("Yinele", systemImage: "arrow.uturn.forward")
                }
                .disabled(undoManager?.canRedo != true)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Spacer()

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

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let fitRect = aspectFitRect(
                content: CGSize(width: session.imageWidth, height: session.imageHeight),
                in: geo.size
            )
            Canvas { ctx, _ in
                drawCanvas(ctx: ctx, fitRect: fitRect)
            }
            .contentShape(Rectangle())
            .gesture(strokeGesture(fitRect: fitRect))
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    hoverPoint = imageCoord(view: p, fitRect: fitRect)
                case .ended:
                    hoverPoint = nil
                }
            }
        }
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

    private func strokeGesture(fitRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isSaving else { return }
                let img = imageCoord(view: value.location, fitRect: fitRect)
                inProgressPoints.append(img)
            }
            .onEnded { _ in
                guard !inProgressPoints.isEmpty else { return }
                commitStroke(points: inProgressPoints)
                inProgressPoints.removeAll()
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

// MARK: - Session helper

extension EraserSession {
    /// Return the strokes list. Renamed wrapper to dodge a SwiftUI/Observation
    /// quirk where `session.strokes` direct read inside `Canvas { ... }`
    /// closure can trip a tracking warning in some Swift toolchains.
    func stroke​Stamps() -> [BrushStroke] { strokes }
}
