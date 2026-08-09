//
//  TrackingStore.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The app's in-memory model plus its JSON index. It owns the areas and
//  entries arrays that drive every screen, so it lives on the main actor.
//
//  All disk access lives in PhotoArchive instead. That separation is
//  deliberate: mutable UI state belongs on the main actor, while reading
//  a JPEG off disk is safe from any thread. Keeping both in one type is
//  what made the background work (PDF export, trend calculation) fight
//  with actor isolation.
//
//  WHERE FILES LIVE:
//  Everything is inside the app's own sandboxed Documents folder, a
//  private area only this app can read. Nothing uses iCloud, which
//  matters even for wellness data: keep the default local-only until
//  you've deliberately decided on and reviewed a sync strategy.
//

import Foundation
import UIKit
import Vision
import Observation

@Observable
final class TrackingStore {

    private(set) var areas: [TrackingArea] = []
    private(set) var entries: [TrackingEntry] = []

    /// Disk access. Safe to hand to background tasks, unlike this class.
    let archive = PhotoArchive()

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    private var indexFileURL: URL { documentsURL.appendingPathComponent("entries.json") }
    private var areasFileURL: URL { documentsURL.appendingPathComponent("areas.json") }

    init() {
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

    /// Deletes an area and every photo logged under it.
    func deleteArea(_ area: TrackingArea) {
        for entry in entries(in: area) {
            archive.deleteFiles(for: entry)
        }
        entries.removeAll { $0.areaID == area.id }
        areas.removeAll { $0.id == area.id }
        saveAreas()
        saveEntries()
    }

    // MARK: - Entries

    @discardableResult
    func addEntry(image: UIImage, area: TrackingArea, note: String = "") async throws -> TrackingEntry {
        // Vision work runs off the main thread so the UI doesn't freeze.
        // FeatureExtractor is nonisolated (pure computation), so this is
        // safe without any awaiting back onto the main actor.
        let observation = try await Task.detached(priority: .userInitiated) {
            try FeatureExtractor.extract(from: image)
        }.value

        let entry = TrackingEntry(areaID: area.id, category: area.category, note: note)

        try archive.writePhoto(image, entry: entry)
        try archive.writeVector(observation, entry: entry)

        entries.append(entry)
        entries.sort { $0.date > $1.date }   // newest first
        saveEntries()

        return entry
    }

    /// Sets or clears the note on an existing entry. Separate from
    /// addEntry because the note is collected AFTER the photo is saved:
    /// the capture succeeds first, then the user optionally annotates it.
    func updateNote(_ note: String, for entry: TrackingEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].note = note
        saveEntries()
    }

    func delete(_ entry: TrackingEntry) {
        archive.deleteFiles(for: entry)
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    /// Removes every area, entry, photo, and vector. Irreversible, so the
    /// UI in SettingsView requires an explicit confirmation first.
    func deleteAllData() {
        for entry in entries {
            archive.deleteFiles(for: entry)
        }
        entries.removeAll()
        areas.removeAll()
        saveEntries()
        saveAreas()
    }

    /// All entries for one area, oldest first. The first element is that
    /// area's baseline.
    func entries(in area: TrackingArea) -> [TrackingEntry] {
        entries.filter { $0.areaID == area.id }.sorted { $0.date < $1.date }
    }

    // MARK: - Convenience forwarding
    // Screens talk to the store rather than reaching for the archive
    // directly, which keeps call sites tidy on the main actor.

    func image(for entry: TrackingEntry) -> UIImage? { archive.image(for: entry) }
    func thumbnail(for entry: TrackingEntry) -> UIImage? { archive.thumbnail(for: entry) }
    func printImage(for entry: TrackingEntry) -> UIImage? { archive.printImage(for: entry) }
    func featurePrint(for entry: TrackingEntry) -> VNFeaturePrintObservation? { archive.featurePrint(for: entry) }

    // MARK: - Private

    /// Entries saved before tracking areas existed have no areaID. Rather
    /// than discarding them, bucket them into one auto-created area per
    /// category so nothing the user logged disappears.
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
