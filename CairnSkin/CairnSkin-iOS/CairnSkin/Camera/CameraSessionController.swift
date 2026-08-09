//
//  CameraSessionController.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Manages the live camera: starts the session, hands live frames to
//  FrameQualityAnalyzer for the real-time badges, and captures the
//  final photo when the user taps the shutter.
//
//  WHY NOT UIImagePickerController (what CameraPicker.swift uses)?
//  UIImagePickerController is a closed box — it shows a camera UI and
//  hands you a finished photo, with zero access to the live feed in
//  between. To analyze frames as they come in (for the guidance
//  badges), we need AVFoundation directly, which gives us that raw
//  frame stream. This is more setup code, but it's what makes the
//  differentiator possible at all.
//
//  This class still isn't UI — it's the engine. GuidedCaptureView.swift
//  is the screen that displays what this class produces.
//

import AVFoundation
import UIKit
import Observation

@Observable
final class CameraSessionController: NSObject {

    // What the UI reads and reacts to.
    var latestQuality: FrameQuality?
    var capturedImage: UIImage?
    var isSessionRunning = false
    var permissionDenied = false

    /// True when the selected camera can focus close enough for macro
    /// work. Pro iPhones switch to an autofocusing ultra-wide lens for
    /// this; base models and iPhone Air have a fixed-focus ultra-wide (or
    /// none at all) and simply cannot focus below ~10cm. That's hardware,
    /// not something software can work around — so the UI tells those
    /// users to back up and zoom instead.
    var supportsMacro = false

    /// Closest focusable distance in centimetres, when the device reports
    /// it. Used to give concrete guidance rather than "move back a bit."
    var minimumFocusDistanceCm: Double?

    /// Current zoom, and the range the device allows.
    var zoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 1.0

    private var videoDevice: AVCaptureDevice?

    /// The internal videoZoomFactor that corresponds to display "1×".
    /// 1.0 on single-lens devices; the first switch-over factor
    /// (typically 2.0) on virtual multi-lens devices.
    private var wideBaseFactor: CGFloat = 1.0

    // AVFoundation plumbing — not observed by the UI directly.
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    // A dedicated background queue for camera work — camera setup and
    // frame delivery must never block the main/UI thread.
    private let sessionQueue = DispatchQueue(label: "com.cairnskin.camera-session")

    // Throttle: analyzing EVERY frame (up to 30-60 per second) would
    // burn battery for no benefit — the badges don't need to update
    // that often to feel "live" to a human. We only analyze roughly
    // every 5th frame.
    private var frameCounter = 0
    private let analyzeEveryNthFrame = 5

    // MARK: - Public API

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Sets zoom in DISPLAY units (1× = the main lens, matching what the
    /// Camera app shows). Conversion to the device's internal factor —
    /// which treats the ultra-wide as 1.0 on virtual devices — happens
    /// here, in exactly one place.
    func setZoom(_ displayFactor: CGFloat) {
        guard let device = videoDevice else { return }
        let raw: CGFloat = displayFactor * wideBaseFactor
        let deviceMin: CGFloat = device.minAvailableVideoZoomFactor
        let deviceMax: CGFloat = device.activeFormat.videoMaxZoomFactor
        let upperBounded: CGFloat = min(raw, deviceMax)
        let clamped: CGFloat = max(deviceMin, upperBounded)
        sessionQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                let base: CGFloat = self?.wideBaseFactor ?? 1.0
                let displayValue: CGFloat = clamped / base
                DispatchQueue.main.async {
                    self?.zoomFactor = displayValue
                }
            } catch {
                // Zoom is a convenience; a failure here shouldn't break capture.
            }
        }
    }

    /// Taps-to-focus at a point in the preview (0...1 coordinate space).
    func focus(at point: CGPoint) {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Setup

    /// Set once the session has been configured. buildSession must be
    /// idempotent: this screen is opened and closed repeatedly, and
    /// re-running configuration on an already-configured session made
    /// canAddInput fail, which bailed out BEFORE startRunning — so the
    /// first use worked and every open after that was a black screen.
    private var isConfigured = false

    private func configureAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            self.sessionQueue.async {
                if self.isConfigured {
                    // Already built — just resume.
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async { self.isSessionRunning = true }
                } else {
                    self.buildSession()
                }
            }
        }
    }

    private func buildSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // CAMERA SELECTION — this ordering is the whole macro fix.
        //
        // Requesting .builtInWideAngleCamera by name pins the session to
        // the main lens and opts OUT of automatic macro switching. iOS
        // only switches to the autofocusing ultra-wide (which is how macro
        // actually works) when the session is bound to a VIRTUAL device
        // that owns several lenses. So ask for those first, and fall back
        // to the single wide lens only on hardware that has nothing else.
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,     // Pro models: wide + ultra-wide + tele
            .builtInDualWideCamera,   // wide + ultra-wide
            .builtInWideAngleCamera   // single lens (iPhone Air, older base models)
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: .back
        )

        guard
            let device = discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        videoDevice = device

        // ZOOM NORMALIZATION — the trap that made "1×" wrong.
        //
        // On a VIRTUAL device (triple/dual-wide), videoZoomFactor 1.0 is
        // the ULTRA-WIDE — what the Camera app calls 0.5×. The main "1×"
        // lens lives at the first switch-over factor (typically 2.0). So
        // a naive "setZoom(1.0)" was actually showing 0.5×, and the whole
        // zoom scale was off by that base factor. Everything user-facing
        // is expressed in DISPLAY units (1× = main lens) and converted
        // here at the boundary.
        // NOTE: written as explicit, separately-typed steps on purpose.
        // Chaining .first + .map + a CGFloat conversion + ?? into one
        // expression made the Swift type-checker time out ("unable to
        // type-check this expression in reasonable time"). Numeric
        // conversions have many overloads; spelling out each type keeps
        // the solver's work linear.
        var baseFactor: CGFloat = 1.0
        let switchOverFactors: [NSNumber] = device.virtualDeviceSwitchOverVideoZoomFactors
        if let firstFactor: NSNumber = switchOverFactors.first {
            let asDouble: Double = firstFactor.doubleValue
            baseFactor = CGFloat(asDouble)
        }
        wideBaseFactor = baseFactor

        // MACRO DETECTION — ask the constituent lenses, not the virtual
        // device. The virtual device reports the ACTIVE lens's minimum
        // focus distance (the wide, ~10cm), which made an iPhone 17 Pro
        // Max look macro-incapable. The real question: is there an
        // autofocusing ultra-wide in there that can focus very close?
        var constituents: [AVCaptureDevice] = device.constituentDevices
        if constituents.isEmpty {
            constituents = [device]
        }

        var macroCapable = false
        for lens in constituents {
            guard lens.deviceType == .builtInUltraWideCamera else { continue }
            let minFocus: Int = lens.minimumFocusDistance   // millimetres, -1 if unknown
            if minFocus > 0 && minFocus <= 60 {             // genuine close-focus
                macroCapable = true
                break
            }
        }

        // For the "can't focus closer than Xcm" guidance on non-macro
        // hardware, the WIDE lens's limit is the relevant number.
        var wideLens: AVCaptureDevice = device
        for lens in constituents where lens.deviceType == .builtInWideAngleCamera {
            wideLens = lens
            break
        }
        let wideMinFocusMm: Int = wideLens.minimumFocusDistance
        var focusCm: Double?
        if wideMinFocusMm > 0 {
            focusCm = Double(wideMinFocusMm) / 10.0
        }

        // ENABLE AUTOMATIC LENS SWITCHING, unrestricted. This is what
        // actually lets iOS hop to the ultra-wide when the subject gets
        // close. Default restrictions can pin the active lens after focus
        // or exposure adjustments — which quietly disables macro.
        do {
            try device.lockForConfiguration()
            if device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
                device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
            }
            // Start at TRUE 1× (the main lens), not the ultra-wide.
            device.videoZoomFactor = baseFactor
            device.unlockForConfiguration()
        } catch { }

        // Cap DISPLAY zoom at 5×. Past a few times magnification it's
        // pure digital upscaling — interpolated pixels would quietly
        // corrupt the comparison the app is built around.
        let hardwareMaxZoom: CGFloat = device.activeFormat.videoMaxZoomFactor
        let displayMaxZoom: CGFloat = hardwareMaxZoom / baseFactor
        let zoomCeiling: CGFloat = 5.0
        let maxDisplayZoom: CGFloat = min(displayMaxZoom, zoomCeiling)

        DispatchQueue.main.async { [weak self] in
            self?.supportsMacro = macroCapable
            self?.minimumFocusDistanceCm = focusCm
            self?.maxZoomFactor = maxDisplayZoom
            self?.zoomFactor = 1.0
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        isConfigured = true
        session.startRunning()

        DispatchQueue.main.async { [weak self] in
            self?.isSessionRunning = true
        }
    }
}

// MARK: - Live frame analysis

// "AVCaptureVideoDataOutputSampleBufferDelegate" is how AVFoundation
// hands us each raw frame as it arrives from the camera, in real time.
extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
        guard frameCounter % analyzeEveryNthFrame == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let quality = FrameQualityAnalyzer.analyze(pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.latestQuality = quality
        }
    }
}

// MARK: - Final photo capture

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
        }
    }
}
