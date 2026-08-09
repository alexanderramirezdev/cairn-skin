//
//  FrameQualityAnalyzer.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Analyzes ONE live camera frame for lighting quality. This runs
//  continuously while the camera is open and drives the "Too dark" /
//  "Good lighting" badge the user sees BEFORE they tap the shutter.
//
//  HISTORY — why there's no sharpness check here anymore:
//  This file originally also scored "sharpness" using edge energy, on
//  the theory that blurry photos have softer edges. Real-device testing
//  disproved it for this app: a well-framed forearm measured LOWER edge
//  energy (~0.0039) than an out-of-frame keyboard (~0.0051), because
//  skin is smooth and keyboards are not. The metric was reporting
//  subject texture, not focus. Steadiness moved to MotionMonitor.swift,
//  which reads the gyroscope directly — see that file for the reasoning.
//
//  Brightness, by contrast, works fine as an image measurement: it's a
//  genuine property of the frame regardless of subject. Still a
//  heuristic for guidance, not a precise instrument.
//

import CoreImage
import UIKit

struct FrameQuality {
    let brightness: Double   // roughly 0 (black) to 1 (white)

    var isGoodLighting: Bool { brightness > 0.18 && brightness < 0.88 }
}

enum FrameQualityAnalyzer {

    // Reuse one CIContext across every frame — creating a new one per
    // frame is expensive. This is the CoreImage equivalent of reusing
    // a single HttpClient instead of `new`-ing one per request.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func analyze(_ pixelBuffer: CVPixelBuffer) -> FrameQuality {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return FrameQuality(brightness: averageBrightness(of: image))
    }

    // CIAreaAverage is a built-in Core Image filter that reduces an
    // entire image down to the average color of every pixel in it —
    // we then read that single averaged pixel back out.
    private static func averageBrightness(of image: CIImage) -> Double {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // Standard perceived-brightness weighting (green reads brighter
        // to the eye than red or blue, so it counts for more).
        let r = Double(pixel[0]) / 255, g = Double(pixel[1]) / 255, b = Double(pixel[2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
