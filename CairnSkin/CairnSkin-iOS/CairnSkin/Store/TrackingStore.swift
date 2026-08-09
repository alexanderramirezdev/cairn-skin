//
//  TrackingStore.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The app's local database. Entries and areas are kept in JSON index
//  files, and each photo/vector is its own file on disk. For an app this
//  size that's plenty — no need for CoreData or SwiftData yet. Every
//  screen talks to this store's methods rather than touching files
//  directly, so swapping in a real database later stays contained.
//
//  WHERE FILES LIVE:
//  Everything is saved inside the app's own sandboxed Documents folder —
//  a private area only this app can read. Nothing here uses iCloud,
//  which matters even for wellness data: keep the default local-only
//  until you've deliberately decided on and reviewed a sync strategy.
//

import Foundation
import UIKit
import Vision
import Observation

@Observable
final class TrackingStore {

    private(set) var areas: [TrackingArea] = []
    private(set) var entries: [TrackingEntry] = []

    // MARK: - Folder locations

    // These path helpers and the read-only accessors below are marked
    // nonisolated so they can be called from background tasks.
    //
    // They touch no mutable state — only FileManager lookups and disk
    // reads — which makes them genuinely safe off the main actor. That
    // matters because the trend view and PDF export deliberately run in
    // Task.detached; forcing them back onto the main actor would restore
    // the hangs that work was done to eliminate.
    nonisolated private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    nonisolated private var photosURL: URL { documentsURL.appendingPathComponent("Photos", isDirectory: true) }
    nonisolated private var thumbnailsURL: URL { documentsURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    nonisolated private var vectorsURL: URL { documentsURL.appendingPathComponent("Vectors", isDirectory: true) }
    private var indexFileURL: URL { documentsURL.appendingPathComponent("entries.json") }
    private var areasFileURL: URL { documentsURL.appendingPathComponent("areas.json") }

    // In-memory cache so scrolling a timeline doesn't re-decode the same
    // thumbnails over and over. NSCache evicts automatically under memory
    // pressure, which a plain Dictionary would not.
    private let thumbnailCache = NSCache<NSString, UIImage>()

    init() {
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: vectorsURL, withIntermediateDirectories: true)
        load()
        migrateLegacyEntriesIfNeeded()
    }

    // MARK: - Areas

    @discardableResult
    func addArea(name: String, category: TrackingCategory) -> TrackingArea {
        let area = TrackingArea(name: name, category: category)
        areas.append(area)
        areas.sort { $0.createdDate < $1.createdDate }
        saveAreas()
        return area
    }

    func renameArea(_ area: TrackingArea, to newName: String) {
        guard let index = areas.firstIndex(where: { $0.id == area.id }) else { return }
        areas[index].name = newName
        saveAreas()
    }

    // Deletes an area AND every photo logged under it.
    func deleteArea(_ area: TrackingArea) {
        for entry in entries(in: area) {
            deleteFiles(for: entry)
        }
        entries.removeAll { $0.areaID == area.id }
        areas.removeAll { $0.id == area.id }
        saveAreas()
        saveEntries()
    }

    // MARK: - Entries

    @discardableResult
    func addEntry(image: UIImage, area: TrackingArea, note: String = "") async throws -> TrackingEntry {
        // STEP 1: run the on-device Vision request (see FeatureExtractor.swift).
        // "Task.detached" runs this on a background thread so the UI
        // doesn't freeze during processing — like Task.Run in C#.
        // NOTE: if you switch the project to Swift 6 strict concurrency
        // mode, UIImage isn't Sendable and this line will need
        // restructuring. Fine under Swift 5 language mode.
        let observation = try await Task.detached(priority: .userInitiated) {
            try FeatureExtractor.extract(from: image)
        }.value

        // STEP 2: build the entry record (this also decides the file names).
        let entry = TrackingEntry(areaID: area.id, category: area.category, note: note)

        // STEP 3: write the JPEG to Photos/.
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw FeatureExtractionError.couldNotCreateCGImage
        }
        try jpegData.write(to: photosURL.appendingPathComponent(entry.imageFileName))

        // STEP 3b: write a small thumbnail alongside it.
        // Lists and the trend strip were loading full-resolution JPEGs —
        // a dozen multi-megabyte images decoded into memory at once, which
        // is what made those screens hang. A 400px thumbnail is ~30x
        // cheaper to decode and indistinguishable at display size.
        if let thumb = Self.makeThumbnail(from: image),
           let thumbData = thumb.jpegData(compressionQuality: 0.8) {
            try? thumbData.write(to: thumbnailsURL.appendingPathComponent(entry.imageFileName))
        }

        // STEP 4: write the feature print to Vectors/.
        let vectorData = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        try vectorData.write(to: vectorsURL.appendingPathComponent(entry.vectorFileName))

        // STEP 5: update our in-memory list and persist the index.
        entries.append(entry)
        entries.sort { $0.date > $1.date }   // newest first
        saveEntries()

        return entry
    }

    // Sets or clears the note on an existing entry. Separate from
    // addEntry because the note is collected AFTER the photo is saved —
    // the capture succeeds first, then the user optionally annotates it.
    func updateNote(_ note: String, for entry: TrackingEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].note = note
        saveEntries()
    }

    func delete(_ entry: TrackingEntry) {        deleteFiles(for: entry)
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    // All entries for one area, oldest first — the first element is that
    // area's baseline.
    func entries(in area: TrackingArea) -> [TrackingEntry] {
        entries.filter { $0.areaID == area.id }.sorted { $0.date < $1.date }
    }

    /// Full-resolution photo. Use only where the image is displayed large
    /// (the compare screen); everywhere else prefer `thumbnail(for:)`.
    nonisolated func image(for entry: TrackingEntry) -> UIImage? {
        UIImage(contentsOfFile: photosURL.appendingPathComponent(entry.imageFileName).path)
    }

    /// Small cached thumbnail for lists and strips. Generates one on first
    /// access for entries saved before thumbnails existed, so old data
    /// gets the speedup too without a migration pass.
    nonisolated func thumbnail(for entry: TrackingEntry) -> UIImage? {
        let key = entry.imageFileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let thumbPath = thumbnailsURL.appendingPathComponent(entry.imageFileName)
        if let existing = UIImage(contentsOfFile: thumbPath.path) {
            thumbnailCache.setObject(existing, forKey: key)
            return existing
        }

        // Legacy entry — build the thumbnail now and keep it.
        guard let full = image(for: entry),
              let thumb = Self.makeThumbnail(from: full) else { return nil }
        if let data = thumb.jpegData(compressionQuality: 0.8) {
            try? data.write(to: thumbPath)
        }
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// A larger downsample for PDF export. List thumbnails (400px) would
    /// look soft printed at 130pt; 800px gives roughly 4x the print
    /// resolution while still being far cheaper than the original.
    /// Not cached — export is a one-off, and caching these would waste
    /// memory that the list thumbnails actually need.
    nonisolated func printImage(for entry: TrackingEntry) -> UIImage? {
        guard let full = image(for: entry) else { return nil }
        return Self.makeThumbnail(from: full, maxDimension: 800)
    }

    /// Downsamples to `maxDimension` on the long edge, preserving aspect.
    nonisolated static func makeThumbnail(from image: UIImage, maxDimension: CGFloat = 400) -> UIImage? {
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

    nonisolated func featurePrint(for entry: TrackingEntry) -> VNFeaturePrintObservation? {
        let url = vectorsURL.appendingPathComponent(entry.vectorFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    // Removes every area, entry, photo, and vector — the whole database.
    // Irreversible, so the UI in SettingsView requires an explicit
    // confirmation before calling this.
    func deleteAllData() {
        for entry in entries {
            deleteFiles(for: entry)
        }
        entries.removeAll()
        areas.removeAll()
        saveEntries()
        saveAreas()
    }

    // MARK: - Private

    private func deleteFiles(for entry: TrackingEntry) {
        try? FileManager.default.removeItem(at: photosURL.appendingPathComponent(entry.imageFileName))
        try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(entry.imageFileName))
        thumbnailCache.removeObject(forKey: entry.imageFileName as NSString)
        try? FileManager.default.removeItem(at: vectorsURL.appendingPathComponent(entry.vectorFileName))
    }

    // Entries saved before tracking areas existed have no areaID. Rather
    // than discarding them, bucket them into one auto-created area per
    // category so nothing the user logged disappears.
    private func migrateLegacyEntriesIfNeeded() {
        let orphans = entries.filter { $0.areaID == nil }
        guard !orphans.isEmpty else { return }

        for category in TrackingCategory.allCases {
            let categoryOrphans = orphans.filter { $0.category == category }
            guard !categoryOrphans.isEmpty else { continue }

            let area = TrackingArea(
                id: UUID(),
                name: "\(category.rawValue) (imported)",
                category: category,
                createdDate: categoryOrphans.map(\.date).min() ?? Date()
            )
            areas.append(area)

            for index in entries.indices where entries[index].areaID == nil && entries[index].category == category {
                entries[index].areaID = area.id
            }
        }
        areas.sort { $0.createdDate < $1.createdDate }
        saveAreas()
        saveEntries()
    }

    private func saveEntries() {
        do {
            try JSONEncoder().encode(entries).write(to: indexFileURL)
        } catch {
            print("TrackingStore saveEntries failed: \(error)")
        }
    }

    private func saveAreas() {
        do {
            try JSONEncoder().encode(areas).write(to: areasFileURL)
        } catch {
            print("TrackingStore saveAreas failed: \(error)")
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: areasFileURL) {
            areas = (try? JSONDecoder().decode([TrackingArea].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: indexFileURL) {
            entries = (try? JSONDecoder().decode([TrackingEntry].self, from: data)) ?? []
        }
    }
}
