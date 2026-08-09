//
//  PhotoArchive.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  All the disk reading and writing, separated out from TrackingStore so
//  it can be used from any thread.
//
//  WHY IT EXISTS:
//  TrackingStore was doing two jobs at once. It owns mutable state (the
//  areas and entries arrays that drive the UI), which belongs on the main
//  actor. It also read photos and vectors off disk, which is stateless
//  and perfectly safe from a background thread.
//
//  Mixing those meant the background work (PDF export, trend
//  calculation) kept bumping into main-actor isolation. Sprinkling
//  "nonisolated" on individual methods didn't hold up, because those
//  methods still reached into main-actor-isolated properties.
//
//  Splitting the disk layer out fixes it at the root: this type has no
//  main-actor state to reach into, so it needs no annotations to be
//  usable anywhere. TrackingStore keeps one and forwards to it.
//

import UIKit
import Vision

/// `nonisolated` on the class is what actually frees it from the main
/// actor. This project sets Default Actor Isolation to MainActor, so
/// every type is main-actor-bound unless it says otherwise, and without
/// this keyword the whole point of splitting disk access out would be
/// lost: the methods would still be main-actor-isolated and background
/// tasks still couldn't call them.
///
/// `@unchecked Sendable` is accurate rather than a shortcut: every stored
/// property is either a computed URL or an NSCache, and NSCache is
/// documented as thread-safe. There is no unsynchronised mutable state.
nonisolated final class PhotoArchive: @unchecked Sendable {

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    var photosURL: URL { documentsURL.appendingPathComponent("Photos", isDirectory: true) }
    var thumbnailsURL: URL { documentsURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    var vectorsURL: URL { documentsURL.appendingPathComponent("Vectors", isDirectory: true) }

    // Scrolling a timeline shouldn't re-decode the same thumbnails over
    // and over. NSCache evicts under memory pressure; a Dictionary
    // wouldn't, and would also need its own locking.
    private let thumbnailCache = NSCache<NSString, UIImage>()

    init() {
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: vectorsURL, withIntermediateDirectories: true)
    }

    // MARK: - Reading

    /// Full-resolution photo. Only for screens that show the image large;
    /// everywhere else use `thumbnail(for:)`.
    func image(for entry: TrackingEntry) -> UIImage? {
        UIImage(contentsOfFile: photosURL.appendingPathComponent(entry.imageFileName).path)
    }

    /// Small cached thumbnail for lists and strips. Generates one on first
    /// access for entries saved before thumbnails existed, so older data
    /// gets the speedup without a migration pass.
    func thumbnail(for entry: TrackingEntry) -> UIImage? {
        let key = entry.imageFileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let thumbPath = thumbnailsURL.appendingPathComponent(entry.imageFileName)
        if let existing = UIImage(contentsOfFile: thumbPath.path) {
            thumbnailCache.setObject(existing, forKey: key)
            return existing
        }

        guard let full = image(for: entry),
              let thumb = Self.makeThumbnail(from: full) else { return nil }
        if let data = thumb.jpegData(compressionQuality: 0.8) {
            try? data.write(to: thumbPath)
        }
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// Larger downsample for PDF export. List thumbnails (400px) look
    /// soft printed at 130pt; 800px gives roughly 4x the print resolution
    /// while staying far cheaper than the original. Not cached, since
    /// export is a one-off and caching these would crowd out the
    /// thumbnails that actually get reused.
    func printImage(for entry: TrackingEntry) -> UIImage? {
        guard let full = image(for: entry) else { return nil }
        return Self.makeThumbnail(from: full, maxDimension: 800)
    }

    func featurePrint(for entry: TrackingEntry) -> VNFeaturePrintObservation? {
        let url = vectorsURL.appendingPathComponent(entry.vectorFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    // MARK: - Writing

    func writePhoto(_ image: UIImage, entry: TrackingEntry) throws {
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw FeatureExtractionError.couldNotCreateCGImage
        }
        try jpegData.write(to: photosURL.appendingPathComponent(entry.imageFileName))

        if let thumb = Self.makeThumbnail(from: image),
           let thumbData = thumb.jpegData(compressionQuality: 0.8) {
            try? thumbData.write(to: thumbnailsURL.appendingPathComponent(entry.imageFileName))
        }
    }

    func writeVector(_ observation: VNFeaturePrintObservation, entry: TrackingEntry) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        try data.write(to: vectorsURL.appendingPathComponent(entry.vectorFileName))
    }

    func deleteFiles(for entry: TrackingEntry) {
        try? FileManager.default.removeItem(at: photosURL.appendingPathComponent(entry.imageFileName))
        try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(entry.imageFileName))
        try? FileManager.default.removeItem(at: vectorsURL.appendingPathComponent(entry.vectorFileName))
        thumbnailCache.removeObject(forKey: entry.imageFileName as NSString)
    }

    // MARK: - Helpers

    /// Downsamples to `maxDimension` on the long edge, preserving aspect.
    static func makeThumbnail(from image: UIImage, maxDimension: CGFloat = 400) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
