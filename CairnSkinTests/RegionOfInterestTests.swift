//
//  RegionOfInterestTests.swift
//  CairnSkinTests
//
//  WHAT THESE GUARD:
//  The crop is the single most consequential piece of logic in the app.
//  It decides what Vision actually looks at. Two real bugs lived here:
//
//  1. Before the crop existed, the whole photo was compared, so a change
//     of bedspread mattered as much as the skin.
//  2. After it existed, the crop took 0.6 of the full photo while the
//     guide box showed 0.6 of the (narrower) screen, so the analysed
//     square was 2.66x the area users actually framed.
//
//  These tests pin the geometry and, more importantly, prove the end
//  result: background outside the box has no effect on the comparison.
//
//  SERIALIZED because `previewAspectRatio` is shared static state. Run in
//  parallel, one test's aspect ratio would leak into another's crop.
//

import Testing
import UIKit
import Vision
@testable import CairnSkin

@MainActor
@Suite("Region-of-interest crop and Vision comparison", .serialized)
struct RegionOfInterestTests {

    init() {
        // Every test starts from a known state, regardless of what ran
        // before it or what the app host left behind.
        FeatureExtractor.previewAspectRatio = nil
    }

    // MARK: - Crop geometry

    @Test func withoutPreviewInfoCropIsCentredSquareOfShorterSide() throws {
        let image = TestImages.solid(width: 3000, height: 4000, color: .gray)
        let cropped = try #require(FeatureExtractor.cropToRegionOfInterest(image).cgImage)

        // 0.6 of the 3000px short side.
        #expect(cropped.width == 1800)
        #expect(cropped.height == 1800)
    }

    /// The bug-2 regression test. An iPhone 17 Pro Max preview is
    /// 1320x2868, so a 4:3 portrait photo has its sides scaled off-screen
    /// and only ~46% of its width is visible. The crop has to be 0.6 of
    /// THAT visible width, not of the whole photo.
    @Test func portraitPhoneCropMatchesTheOnScreenGuideBox() throws {
        FeatureExtractor.previewAspectRatio = 1320.0 / 2868.0
        let image = TestImages.solid(width: 3024, height: 4032, color: .gray)
        let cropped = try #require(FeatureExtractor.cropToRegionOfInterest(image).cgImage)

        let visibleWidth = 4032.0 * (1320.0 / 2868.0)
        let expectedSide = visibleWidth * 0.6            // ~1113px

        #expect(abs(Double(cropped.width) - expectedSide) <= 1)
        #expect(cropped.width == cropped.height)
        // And specifically NOT the old, wrong answer of 0.6 x 3024.
        #expect(cropped.width < 1814)
    }

    @Test func widePreviewTrimsTopAndBottomInstead() throws {
        FeatureExtractor.previewAspectRatio = 2.0
        let image = TestImages.solid(width: 1000, height: 1000, color: .gray)
        let cropped = try #require(FeatureExtractor.cropToRegionOfInterest(image).cgImage)

        // Visible region is 1000x500, so 0.6 of 500.
        #expect(cropped.width == 300)
        #expect(cropped.height == 300)
    }

    @Test func nonsensePreviewAspectIsIgnored() throws {
        FeatureExtractor.previewAspectRatio = 0
        let image = TestImages.solid(width: 3000, height: 4000, color: .gray)
        let cropped = try #require(FeatureExtractor.cropToRegionOfInterest(image).cgImage)
        #expect(cropped.width == 1800)
    }

    /// An off-centre crop would analyse the wrong patch of skin while
    /// every size check above still passed.
    @Test func cropIsCentredOnTheSubject() throws {
        FeatureExtractor.previewAspectRatio = 1320.0 / 2868.0
        let image = TestImages.markedCentre(width: 3024, height: 4032)
        let cropped = try #require(FeatureExtractor.cropToRegionOfInterest(image).cgImage)

        let centre = try #require(TestImages.pixel(of: cropped,
                                                   x: cropped.width / 2,
                                                   y: cropped.height / 2))
        #expect(centre.g > 200 && centre.r < 60 && centre.b < 60)
    }

    @Test func cropKeepsImageOrientation() {
        let base = TestImages.solid(width: 400, height: 300, color: .gray)
        let rotated = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)
        let cropped = FeatureExtractor.cropToRegionOfInterest(rotated)
        #expect(cropped.imageOrientation == .right)
    }

    // MARK: - Vision, end to end

    @Test func identicalPhotosHaveZeroDistance() throws {
        let image = TestImages.textured(seed: 1)
        let a = try FeatureExtractor.extract(from: image)
        let b = try FeatureExtractor.extract(from: image)
        let d = try FeatureExtractor.distance(between: a, and: b)
        #expect(d < 0.001)
    }

    @Test func distanceIsSymmetric() throws {
        let a = try FeatureExtractor.extract(from: TestImages.textured(seed: 1))
        let b = try FeatureExtractor.extract(from: TestImages.textured(seed: 99))
        let ab = try FeatureExtractor.distance(between: a, and: b)
        let ba = try FeatureExtractor.distance(between: b, and: a)
        #expect(abs(ab - ba) < 0.0001)
    }

    @Test func clearlyDifferentSubjectsAreFarApart() throws {
        let a = try FeatureExtractor.extract(from: TestImages.solid(width: 1200, height: 1600, color: .gray))
        let b = try FeatureExtractor.extract(from: TestImages.checkerboard(width: 1200, height: 1600))
        let d = try FeatureExtractor.distance(between: a, and: b)
        #expect(d > FeatureExtractor.noiseFloor)
    }

    /// THE POINT OF THE WHOLE CROP, tested directly. Two photos with an
    /// identical subject inside the guide box and completely different
    /// surroundings must compare as identical. Before the crop fix, the
    /// surroundings dominated this number.
    @Test func backgroundOutsideTheBoxHasNoEffect() throws {
        FeatureExtractor.previewAspectRatio = 1320.0 / 2868.0
        let subject = TestImages.textured(seed: 7, width: 600, height: 600)

        let onBedspread = TestImages.subject(subject, onBackground: .systemPink,
                                             width: 3024, height: 4032)
        let inCar = TestImages.subject(subject, onBackground: .darkGray,
                                       width: 3024, height: 4032)

        let a = try FeatureExtractor.extract(from: onBedspread)
        let b = try FeatureExtractor.extract(from: inCar)
        let d = try FeatureExtractor.distance(between: a, and: b)

        #expect(d < 0.001, "Background leaked into the comparison: distance \(d)")
    }
}

// MARK: - Synthetic images

/// Deterministic test images, all rendered at scale 1 so pixel sizes are
/// exactly what the test asks for.
enum TestImages {

    private static func renderer(width: Int, height: Int) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    }

    static func solid(width: Int, height: Int, color: UIColor) -> UIImage {
        renderer(width: width, height: height).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func checkerboard(width: Int, height: Int, cell: Int = 80) -> UIImage {
        renderer(width: width, height: height).image { ctx in
            for row in 0..<(height / cell + 1) {
                for col in 0..<(width / cell + 1) {
                    ((row + col) % 2 == 0 ? UIColor.black : UIColor.white).setFill()
                    ctx.fill(CGRect(x: col * cell, y: row * cell, width: cell, height: cell))
                }
            }
        }
    }

    /// Grey image with a small pure-green square at the exact centre.
    static func markedCentre(width: Int, height: Int) -> UIImage {
        renderer(width: width, height: height).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: width / 2 - 20, y: height / 2 - 20, width: 40, height: 40))
        }
    }

    /// Skin-ish texture with deterministic speckle, so two calls with the
    /// same seed produce byte-identical images.
    static func textured(seed: UInt64, width: Int = 1200, height: Int = 1600) -> UIImage {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func next() -> CGFloat {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }
        return renderer(width: width, height: height).image { ctx in
            UIColor(red: 0.85, green: 0.66, blue: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for _ in 0..<600 {
                let r = next() * 18 + 2
                UIColor(red: 0.55 * next() + 0.3, green: 0.3, blue: 0.25, alpha: 0.6).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: next() * CGFloat(width),
                                                     y: next() * CGFloat(height),
                                                     width: r, height: r))
            }
        }
    }

    /// Places `subject` so it fully covers the analysed square in the
    /// centre, with `background` everywhere else.
    static func subject(_ subject: UIImage, onBackground background: UIColor,
                        width: Int, height: Int) -> UIImage {
        renderer(width: width, height: height).image { ctx in
            background.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // 1300px comfortably covers the ~1113px analysed square.
            let side: CGFloat = 1300
            subject.draw(in: CGRect(x: (CGFloat(width) - side) / 2,
                                    y: (CGFloat(height) - side) / 2,
                                    width: side, height: side))
        }
    }

    /// RGB at a pixel, read by redrawing into a known 8-bit RGBA buffer.
    static func pixel(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                   width: image.width, height: image.height))
        return (data[0], data[1], data[2])
    }
}
