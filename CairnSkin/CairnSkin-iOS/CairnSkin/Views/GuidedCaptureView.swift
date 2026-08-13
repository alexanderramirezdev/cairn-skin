//
//  GuidedCaptureView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The differentiator screen. Instead of a plain shutter button, this
//  shows:
//    1. A translucent "ghost" of the user's PREVIOUS photo overlaid on
//       the live camera feed, so they can visually match position,
//       distance, and framing before shooting.
//    2. Live badges for lighting (from the camera frame) and steadiness
//       (from the gyroscope), updating continuously
//       as FrameQualityAnalyzer scores each frame.
//  Both directly target the #1 real-world complaint about this whole
//  category of app: it's genuinely hard to take two photos of the same
//  spot, days apart, that are actually comparable.
//

import SwiftUI
import AVFoundation

struct GuidedCaptureView: View {
    let area: TrackingArea

    /// Called when the user flips the camera, so the choice can be saved
    /// against the area and restored next time.
    var onCameraChange: ((Bool) -> Void)?

    init(area: TrackingArea,
         baselineImage: UIImage?,
         onCameraChange: ((Bool) -> Void)? = nil,
         onCapture: @escaping (UIImage) -> Void) {
        self.area = area
        self.baselineImage = baselineImage
        self.onCameraChange = onCameraChange
        self.onCapture = onCapture
        // The camera is chosen per area, so it has to be built here rather
        // than default-initialised as a property.
        _camera = State(initialValue: CameraSessionController(
            position: area.usesFrontCamera ? .front : .back
        ))
    }
    let baselineImage: UIImage?     // nil if this is the very first photo

    // A closure the caller provides to receive the finished photo —
    // keeps this view from needing to know about TrackingStore at all.
    let onCapture: (UIImage) -> Void

    @State private var camera: CameraSessionController
    @State private var motion = MotionMonitor()
    @State private var focusPoint: CGPoint = .zero
    @State private var showFocusIndicator = false
    @Environment(\.dismiss) private var dismiss

    // CALIBRATION AID — set to false before shipping. Shows the live
    // brightness and rotation numbers under the badges so the thresholds
    // can be tuned on evidence rather than guesswork.
    private let showDebugValues = false

    var body: some View {
        ZStack {
            // LAYERS 1 & 2: the live camera feed, with the ghost overlay
            // painted directly on top of it.
            //
            // The ghost is attached with .overlay rather than being its own
            // ZStack child, and this is load-bearing. .scaledToFill() makes
            // the image wider than the screen; as a sibling it inflated the
            // ZStack's layout width, which re-centered the control layer in
            // an oversized frame and pushed the Cancel button off the left
            // edge. An overlay is constrained to its host's bounds and can
            // never affect the parent's size, so the problem can't recur.
            CameraPreviewView(session: camera.session, isMirrored: camera.position == .front)
                // Tap anywhere to focus there. Close-up subjects confuse
                // centre-weighted autofocus, and a skin patch filling the
                // frame gives it very little contrast to lock onto.
                .onTapGesture { location in
                    focusPoint = location
                    camera.focus(at: CGPoint(x: 0.5, y: 0.5))
                    withAnimation { showFocusIndicator = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        withAnimation { showFocusIndicator = false }
                    }
                }
                .overlay {
                    if let baselineImage {
                        Image(uiImage: baselineImage)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.35)
                            .allowsHitTesting(false)
                            // Decorative for VoiceOver — the guidance text
                            // already explains the alignment task.
                            .accessibilityHidden(true)
                    }
                }
                .clipped()
                .ignoresSafeArea()

            // LAYER 2.5: the framing guide — shows exactly which part of
            // the frame will actually be analyzed. Everything outside this
            // square gets cropped away before the comparison runs (see
            // FeatureExtractor.regionOfInterestFraction), so the user needs
            // to know where to put the subject. Without this, people frame
            // naturally and half their photo turns out to be background.
            // Brief square that appears where the user tapped to focus.
            if showFocusIndicator {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .position(focusPoint)
                    .allowsHitTesting(false)
            }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * FeatureExtractor.regionOfInterestFraction
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: side, height: side)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    // Tell the extractor what the user is actually seeing.
                    // The preview crops the photo to fill the screen, so
                    // without this the analyzed square is much larger than
                    // this box — see FeatureExtractor.previewAspectRatio.
                    .onAppear {
                        FeatureExtractor.previewAspectRatio = geo.size.width / geo.size.height
                    }
            }
            .allowsHitTesting(false)

            // LAYER 3: UI chrome — badges, guidance text, shutter button.
            // The two layers beneath deliberately ignore safe areas so the
            // camera feed runs edge to edge. That makes this ZStack expand
            // to the full physical screen, so ordinary .padding() here
            // would measure from the display edge and slide the controls
            // under the Dynamic Island / home indicator.
            // .safeAreaPadding() measures from the *usable* area instead,
            // which is what we want for anything interactive.
            VStack {
                topBar
                Spacer()
                Text(baselineImage != nil
                     ? "Fill the box with the same area as your reference photo"
                     : "Fill the box with the area you want to track")
                    .font(.footnote.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                zoomControls
                macroGuidance
                qualityBadges
                shutterButton
                    .padding(.bottom, 24)
            }
            .safeAreaPadding(.all)
        }
        // Swipe down to back out — a second escape route, matching the
        // gesture people already expect from the system Camera app and
        // any sheet. Belt and suspenders: nobody should ever feel
        // trapped on a full-screen camera view.
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { value in
                    if value.translation.height > 60 {
                        dismiss()
                    }
                }
        )
        // Status bar intentionally left visible. Hiding it on a screen
        // with top-aligned controls invites exactly the "button is under
        // the notch" problem — leaving it on keeps the safe area honest.
        .onAppear {
            camera.start()
            motion.start()
        }
        .onDisappear {
            camera.stop()
            motion.stop()
        }
        .onChange(of: camera.capturedImage) { _, image in
            if let image {
                onCapture(image)
                dismiss()
            }
        }
        .alert("Camera Access Needed", isPresented: .constant(camera.permissionDenied)) {
            Button("OK") { dismiss() }
        } message: {
            Text("Enable camera access in Settings to log photos.")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                // Explicit "Cancel" text alongside the X — an icon alone
                // was too easy to miss against a bright ghost overlay.
                Label("Cancel", systemImage: "xmark")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // Near-opaque so it stays legible over any photo
                    // that happens to be behind it.
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
            }
            // Generous tap target — the visual capsule is smaller than
            // the actual touchable area, which is what you want for a
            // control people reach for in a hurry.
            .contentShape(Rectangle())
            Spacer()
            flipButton
        }
        .padding(.horizontal)
        // Push clear of the notch / Dynamic Island. The status bar is
        // hidden on this screen, so without this the button can end up
        // underneath the sensor housing on newer iPhones.
        .padding(.top, 12)
    }

    @ViewBuilder
    private var qualityBadges: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if let quality = camera.latestQuality {
                    QualityBadge(
                        label: quality.isGoodLighting ? "Good lighting" : (quality.brightness < 0.18 ? "Too dark" : "Too bright"),
                        isGood: quality.isGoodLighting,
                        systemImage: "sun.max"
                    )
                }
                // Steadiness now comes from the gyroscope, not the image —
                // see MotionMonitor.swift for why the pixel-based approach
                // was abandoned.
                QualityBadge(
                    label: motion.isSteady ? "Steady" : "Hold steady",
                    isGood: motion.isSteady,
                    systemImage: "hand.raised"
                )
            }

            if showDebugValues {
                Text(String(format: "rotation %.3f (need <%.2f)   bright %.3f",
                            motion.rotationRate,
                            MotionMonitor.steadyThreshold,
                            camera.latestQuality?.brightness ?? 0))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        }
        .padding(.bottom, 16)
    }

    /// Flip button, placed on the capture screen rather than buried in
    /// settings. Someone standing at a mirror with the camera facing the
    /// wrong way reaches for this, not a configuration screen two taps
    /// away. The choice is remembered per area, so it's a one-time action
    /// in practice without ever being a setup step.
    private var flipButton: some View {
        Button {
            camera.flipCamera()
            onCameraChange?(camera.position == .back)   // about to become front
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel(camera.position == .front
                            ? "Switch to rear camera"
                            : "Switch to front camera")
    }

    /// Zoom presets. On hardware without macro this is the actual
    /// workaround for close-up shots: stand where the lens can focus and
    /// zoom in to get the framing you wanted.
    @ViewBuilder
    private var zoomControls: some View {
        if camera.maxZoomFactor > 1.5 {
            HStack(spacing: 8) {
                ForEach([1.0, 2.0, 3.0], id: \.self) { level in
                    if CGFloat(level) <= camera.maxZoomFactor {
                        Button {
                            camera.setZoom(CGFloat(level))
                        } label: {
                            Text(level == 1.0 ? "1×" : "\(Int(level))×")
                                .font(.caption.bold())
                                .frame(width: 42, height: 32)
                                .background(
                                    abs(camera.zoomFactor - CGFloat(level)) < 0.1
                                        ? Color.white.opacity(0.9)
                                        : Color.black.opacity(0.55),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    abs(camera.zoomFactor - CGFloat(level)) < 0.1
                                        ? .black : .white
                                )
                        }
                        .accessibilityLabel("Zoom \(Int(level)) times")
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    /// Tells the user what their specific hardware can do. A phone without
    /// an autofocusing ultra-wide physically cannot focus closer than
    /// roughly 10cm — no amount of holding still fixes that, and without
    /// this hint people just keep moving closer and getting blurrier
    /// results.
    @ViewBuilder
    private var macroGuidance: some View {
        if camera.position == .front {
            Text("Front camera. Hold the phone about arm's length away and use the screen to line up the box.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        } else if !camera.supportsMacro {
            let distance = camera.minimumFocusDistanceCm.map { String(format: "%.0f", $0) } ?? "10"
            Text("This iPhone can't focus closer than about \(distance)cm. Stay back and use zoom to fill the box.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto()
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 74, height: 74)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 4).frame(width: 86, height: 86))
        }
        // A bare circle means nothing to VoiceOver without this.
        .accessibilityLabel("Take photo")
        // Still tappable even with poor quality — we GUIDE, we don't
        // block. A user might have a good reason to shoot anyway
        // (unusual lighting they can't fix, a moving subject, etc.).
    }
}

private struct QualityBadge: View {
    let label: String
    let isGood: Bool
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((isGood ? Color.green : Color.orange).opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}

#Preview {
    GuidedCaptureView(area: TrackingArea(name: "Left forearm", category: .skin), baselineImage: nil) { _ in }
}
