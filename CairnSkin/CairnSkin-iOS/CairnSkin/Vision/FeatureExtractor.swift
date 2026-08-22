//
//  FeatureExtractor.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The core "AI" of the app. Turns a photo into a compact numeric
//  fingerprint (a "feature print") using Apple's built-in Vision
//  framework — entirely on-device, no network call, no cloud AI needed
//  for Phase 1.
//
//  WHY NOT COMPARE RAW PIXELS?
//  Two photos of the same skin patch taken a week apart will have
//  different lighting, a slightly different angle, maybe a different
//  phone position. Comparing raw pixel-by-pixel differences would treat
//  ALL of that as "change," drowning out the real signal. A feature
//  print instead captures the abstract textures/shapes/structure of the
//  image, so it's far more robust to those everyday variations.
//
//  WHAT WE'RE USING:
//  VNGenerateImageFeaturePrintRequest — a request type built into
//  Apple's Vision framework specifically for "how similar are these two
//  images" tasks. It ships on every iPhone, requires no model download,
//  and returns a VNFeaturePrintObservation, which has a built-in
//  computeDistance(to:) method — Apple has already done the "vector
//  math" step for us.
//
//  This is the free, on-device equivalent of the doc's "MobileNet /
//  ResNet -> 1024-dim vector -> cosine distance" pipeline. If Phase 2
//  ever needs a specialized medical vision model, this class is the
//  one place that would be swapped out — everything else in the app
//  just calls `extract(from:)` and `distance(between:and:)` without
//  caring how they're implemented underneath.
//

import Vision
import UIKit

// Errors this class can produce. Swift's "Error" protocol is like
// implementing Exception in C# — anything conforming can be thrown.
enum FeatureExtractionError: Error, LocalizedError {
    case couldNotCreateCGImage
    case requestFailed(String)
    case noObservation

    var errorDescription: String? {
        switch self {
        case .couldNotCreateCGImage:
            return "Could not read the photo's pixel data."
        case .requestFailed(let message):
            return "Vision request failed: \(message)"
        case .noObservation:
            return "Vision did not return a feature print for this photo."
        }
    }
}

// "nonisolated" marks this whole type as safe to use from any thread.
//
// Xcode's newer project template sets Default Actor Isolation to
// MainActor, which makes every type main-actor-bound unless it says
// otherwise. That's a sensible default for UI code, but this enum is
// pure computation over values passed in — no shared mutable state, no
// UI — and it's deliberately called from Task.detached so that Vision
// work stays off the main thread. Without this annotation the compiler
// would (correctly, under Swift 6 rules) reject those calls, and
// "fixing" it by awaiting them on the main actor would silently undo
// the performance work: feature extraction would freeze the UI again.
nonisolated enum FeatureExtractor {

    // How much of the frame to actually analyze, measured from the center.
    // 0.6 means the central 60% square — everything outside is discarded
    // before the feature print is generated.
    //
    // WHY THIS EXISTS (learned from real testing):
    // Vision analyzes whatever image you hand it, with no notion of what
    // the "subject" is. In early testing, two photos of the same forearm
    // scored poorly simply because the background changed — one was shot
    // over dark clothing, the other over a laptop and wood floor. The arm
    // occupied under half the frame, so the room dominated the comparison.
    // The app was measuring the environment, not the skin.
    //
    // Cropping to the center forces the metric to focus on the area the
    // user is actually pointing at, and pairs with the on-screen framing
    // guide in GuidedCaptureView so people know where to put the subject.
    /// Bumped whenever anything changes about how a feature print is
    /// produced: the crop region, the preview-aware cropping, any future
    /// colour normalisation.
    ///
    /// WHY THIS EXISTS:
    /// Feature prints are computed once at capture time and archived to
    /// disk. Changing the extraction pipeline therefore does NOT update
    /// vectors that already exist — a baseline captured before a change
    /// describes a different region than a photo captured after it, and
    /// comparing the two produces a number that means nothing.
    ///
    /// That's exactly what happened when the region-of-interest crop was
    /// corrected: every stored vector suddenly described a wider region
    /// than new ones did. TrackingStore compares this against the
    /// generation it last migrated and recomputes vectors from the saved
    /// photos when they differ.
    ///
    /// Generation history:
    ///   1 — original centred crop at 0.6 of the full photo
    ///   2 — crop reduced to the preview's visible region first, so the
    ///       analysed square matches the on-screen guide box
    static let extractionGeneration = 2

    static let regionOfInterestFraction: CGFloat = 0.6

    // Crops to the central square region defined above.
    /// The aspect ratio (width / height) of the preview the user framed
    /// through, when known.
    ///
    /// This exists because the preview uses `.resizeAspectFill`: the
    /// captured photo is 4:3 but the screen is far taller and narrower, so
    /// the sides of the photo are scaled off-screen. On an iPhone 17 Pro
    /// Max the user only ever sees about 61% of the photo's width.
    ///
    /// That caused a real bug. The guide box was drawn at 0.6 of the
    /// SCREEN, while the crop took 0.6 of the whole PHOTO — the same
    /// fraction of two different things. The analyzed square ended up 1.63x
    /// wider than the box, meaning 2.66x its area, so roughly 62% of what
    /// was being compared was background the user never saw and had no way
    /// to control. Lighting and backdrop swamped the subject, which is why
    /// two photos of the same healing scratch scored 43% and then 45%
    /// despite obviously improving.
    ///
    /// Cropping to the visible region first makes "0.6" mean 0.6 of what
    /// the user actually framed, so the box on screen and the region
    /// analyzed are finally the same square.
    nonisolated(unsafe) static var previewAspectRatio: CGFloat?

    static func cropToRegionOfInterest(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        var width = CGFloat(cgImage.width)
        var height = CGFloat(cgImage.height)
        var originX: CGFloat = 0
        var originY: CGFloat = 0

        // STEP 1: reduce to the region the user could actually see, so the
        // fraction below is applied to the framed view rather than to
        // parts of the photo that were never on screen.
        if let previewAspect = previewAspectRatio, previewAspect > 0 {
            let imageAspect = width / height
            if imageAspect > previewAspect {
                // Photo is wider than the preview: the sides were cropped.
                let visibleWidth = height * previewAspect
                originX = (width - visibleWidth) / 2
                width = visibleWidth
            } else {
                // Photo is taller: the top and bottom were cropped.
                let visibleHeight = width / previewAspect
                originY = (height - visibleHeight) / 2
                height = visibleHeight
            }
        }

        // STEP 2: the centred square, matching the dashed guide box.
        let side = min(width, height) * regionOfInterestFraction
        let cropRect = CGRect(
            x: originX + (width - side) / 2,
            y: originY + (height - side) / 2,
            width: side,
            height: side
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    // Turns a UIImage into a VNFeaturePrintObservation (the "vector").
    // "throws" means this can fail with an error instead of returning a
    // value — like a method that might throw an exception in C#, except
    // Swift makes the possibility visible in the function signature.
    static func extract(from image: UIImage) throws -> VNFeaturePrintObservation {
        // Crop to the region of interest FIRST — see the long note above.
        // This single step matters more for real-world accuracy than any
        // other tuning in this file.
        let focused = cropToRegionOfInterest(image)

        // Vision needs a CGImage, not a UIImage — this converts it.
        guard let cgImage = focused.cgImage else {
            throw FeatureExtractionError.couldNotCreateCGImage
        }

        // The request object describes WHAT we want Vision to compute.
        let request = VNGenerateImageFeaturePrintRequest()

        // PIN THE ALGORITHM VERSION. Apple has shipped multiple
        // "revisions" of the feature print algorithm across iOS
        // versions, and distances between vectors made by DIFFERENT
        // revisions are not comparable. Without pinning, a user's
        // baseline photo (saved before an iOS update) could silently
        // stop comparing correctly against new photos (saved after).
        // Pinning revision 2 (iOS 17+) keeps every stored vector in
        // this app comparable with every other, permanently.
        request.revision = VNGenerateImageFeaturePrintRequestRevision2

        // The handler actually RUNS the request against our image.
        // This happens synchronously and entirely on-device.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw FeatureExtractionError.requestFailed(error.localizedDescription)
        }

        // "results" is an array because some request types return
        // multiple observations (e.g. one per detected face). Feature
        // print requests return exactly one for the whole image.
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw FeatureExtractionError.noObservation
        }
        return observation
    }

    // Compares two feature prints and returns a distance: 0 = identical,
    // larger = more different. Apple computes this using an L2
    // (Euclidean) distance internally — a similar spirit to the cosine
    // similarity math in the doc, just Apple's own metric.
    static func distance(between a: VNFeaturePrintObservation, and b: VNFeaturePrintObservation) throws -> Float {
        var distance: Float = 0
        try a.computeDistance(&distance, to: b)
        return distance
    }

    // Above this distance, two photos almost certainly aren't the same
    // subject, and a similarity percentage between them is meaningless
    // rather than merely low.
    //
    // CALIBRATION — measured on device, post-crop:
    //   ~0.20  same subject, photos seconds apart
    //   ~0.26  same subject, re-framed using the alignment guide
    //   ~0.96  an unrelated object (a water bottle vs. an arm)
    //
    // The first version of this sat at 0.95, which "worked" — the water
    // bottle was refused — but only by 0.014. A slightly less dissimilar
    // unrelated photo would have slipped under and been reported as ~1%
    // similar, which is a worse failure than refusing a valid comparison:
    // a number implies a real measurement happened.
    //
    // 0.85 keeps a real margin below the observed unrelated-subject value
    // while sitting far above anything a genuine same-subject pair has
    // produced. Re-check if new measurements cluster differently.
    static let notComparableThreshold: Float = 0.85

    /// Above this distance, a comparison is still shown but flagged as
    /// possibly reflecting framing rather than the subject.
    ///
    /// CALIBRATION — measured on device, post-crop:
    ///   ~0.20  same subject, photos seconds apart
    ///   ~0.26  same subject, re-framed using the alignment guide
    ///   ~0.57  same subject, re-framed BADLY (different distance,
    ///          angle, and background)
    ///   ~0.96  an unrelated object
    ///
    /// 0.45 sits well clear of a properly re-framed capture while
    /// catching the badly-framed case. It deliberately does NOT claim the
    /// difference IS framing — a genuinely large change can land here too.
    /// It only says the photos differ enough that framing is worth ruling
    /// out, which is the honest reading of a single number that describes
    /// two photographs rather than a body.
    static let framingConcernThreshold: Float = 0.45

    /// Whether a comparison is far enough from the baseline that framing
    /// should be ruled out before reading it as change.
    static func framingLooksInconsistent(distance: Float) -> Bool {
        distance >= framingConcernThreshold && distance < notComparableThreshold
    }

    static func isComparable(distance: Float) -> Bool {
        distance < notComparableThreshold
    }

    // The practical best case. Two photos taken seconds apart of the
    // exact same subject still measure ~0.19 apart, because between
    // shutter presses the camera re-runs autofocus, auto-exposure and
    // white balance, the sensor adds noise, and JPEG compression differs.
    // Feature prints are perceptual, not exact — identical scenes never
    // reach zero.
    //
    // Without accounting for this, back-to-back photos displayed as "84%
    // similar," implying a 16% change that did not occur. In a tracking
    // app that false signal is worse than no signal. Anything at or below
    // this floor is reported as no detectable change.
    /// Distance below which two photos are effectively identical: the
    /// residual noise of re-photographing the same thing under the same
    /// conditions. Measured on device at ~0.204.
    ///
    /// Nothing computes with this any more — the percentage it used to
    /// scale is gone. It's kept as the reference point for reading a raw
    /// distance during calibration, and it's shown next to the developer
    /// readout for exactly that purpose.
    static let noiseFloor: Float = 0.20

}
