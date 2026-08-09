//
//  MotionMonitor.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Detects whether the phone is being held steady, using the device's
//  gyroscope rather than analyzing the image.
//
//  WHY THIS REPLACED THE IMAGE-BASED SHARPNESS CHECK:
//  The original approach measured "edge energy" in the camera frame as a
//  proxy for focus. Real-device testing killed the idea: skin is smooth
//  and low-texture, so a well-framed forearm scored LOWER (~0.0039) than
//  a random keyboard in the background (~0.0051). The metric was really
//  reporting how detailed the subject was, not whether the shot was
//  sharp — useless for an app whose subject is almost always skin.
//
//  Motion is what "hold steady" actually means, and the gyroscope
//  measures it directly, independent of what's in frame. Simpler, more
//  honest, and it can't be fooled by a textureless subject.
//

import CoreMotion
import Observation

@Observable
final class MotionMonitor {

    // Current rotation magnitude in radians/second, smoothed.
    private(set) var rotationRate: Double = 0

    // Below this, the phone is steady enough for a usable photo.
    // Tuned to allow normal hand tremor while catching real movement:
    // resting hands sit well under 0.15, a deliberate pan runs far above it.
    static let steadyThreshold: Double = 0.15

    var isSteady: Bool { rotationRate < Self.steadyThreshold }

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20.0   // 20 Hz is plenty
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rate = motion.rotationRate
            // Magnitude of the rotation vector across all three axes.
            let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            // Low-pass filter: blend with the previous value so the badge
            // doesn't flicker on every tiny twitch.
            self.rotationRate = self.rotationRate * 0.7 + magnitude * 0.3
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
