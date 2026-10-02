//
//  ThumbnailTests.swift
//  CairnSkinTests
//
//  WHAT THESE GUARD:
//  Lists and the photo grid used to decode full-resolution JPEGs, which
//  is what made the timeline and trend screens hang at around 15 photos.
//  Thumbnails fixed that. These check the downsample keeps proportions
//  (a squashed thumbnail would misrepresent the photo) and never upscales.
//

import Testing
import UIKit
@testable import CairnSkin

@MainActor
@Suite("Thumbnail downsampling")
struct ThumbnailTests {

    @Test func landscapePhotoShrinksToLongEdgeLimit() throws {
        let photo = TestImages.solid(width: 4032, height: 3024, color: .gray)
        let thumb = try #require(PhotoArchive.makeThumbnail(from: photo))

        #expect(thumb.size.width == 400)
        #expect(abs(thumb.size.height - 300) < 0.5)
    }

    @Test func portraitPhotoShrinksToLongEdgeLimit() throws {
        let photo = TestImages.solid(width: 3024, height: 4032, color: .gray)
        let thumb = try #require(PhotoArchive.makeThumbnail(from: photo))

        #expect(thumb.size.height == 400)
        #expect(abs(thumb.size.width - 300) < 0.5)
    }

    @Test func aspectRatioIsPreserved() throws {
        let photo = TestImages.solid(width: 3000, height: 1000, color: .gray)
        let thumb = try #require(PhotoArchive.makeThumbnail(from: photo))
        let original = photo.size.width / photo.size.height
        let shrunk = thumb.size.width / thumb.size.height
        #expect(abs(original - shrunk) < 0.01)
    }

    @Test func smallImageIsReturnedUntouched() throws {
        let photo = TestImages.solid(width: 200, height: 150, color: .gray)
        let thumb = try #require(PhotoArchive.makeThumbnail(from: photo))
        #expect(thumb === photo)
    }

    /// PDF export uses 800px rather than 400 so printed photos aren't soft.
    @Test func printSizeUsesItsOwnLimit() throws {
        let photo = TestImages.solid(width: 4032, height: 3024, color: .gray)
        let print = try #require(PhotoArchive.makeThumbnail(from: photo, maxDimension: 800))
        #expect(print.size.width == 800)
    }
}
