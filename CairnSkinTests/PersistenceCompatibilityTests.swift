//
//  PersistenceCompatibilityTests.swift
//  CairnSkinTests
//
//  WHAT THESE GUARD:
//  The saved JSON on a user's phone outlives every build. Anything that
//  changes how areas.json or entries.json decode can make a user's data
//  look like it vanished — which already happened once, in August, when
//  two fields were added to TrackingArea without decodeIfPresent and
//  every tester updating from the previous build saw an empty app.
//
//  These tests decode JSON shaped exactly like older builds wrote it. If
//  someone adds a field and forgets the backwards-compatible decoder,
//  these fail in seconds instead of on a user's phone.
//

import Testing
import Foundation
@testable import CairnSkin

@MainActor
@Suite("Saved data stays readable across app updates")
struct PersistenceCompatibilityTests {

    // MARK: - TrackingArea

    /// areas.json exactly as builds before reminders and front camera
    /// wrote it: no reminderIntervalDays, no usesFrontCamera.
    ///
    /// THIS IS THE REGRESSION TEST FOR THE AUGUST DATA-LOSS BUG. A
    /// synthesized decoder throws on the missing keys, and the store's
    /// `try? ... ?? []` turned that into an empty list.
    @Test func areaFromBeforeRemindersAndFrontCameraStillDecodes() throws {
        let id = UUID()
        let legacyJSON = """
        [{
            "id": "\(id.uuidString)",
            "name": "Left forearm",
            "category": "Skin Trend",
            "createdDate": 778000000
        }]
        """.data(using: .utf8)!

        let areas = try JSONDecoder().decode([TrackingArea].self, from: legacyJSON)

        #expect(areas.count == 1)
        #expect(areas[0].id == id)
        #expect(areas[0].name == "Left forearm")
        #expect(areas[0].category == .skin)
        // Fields missing from old saves fall back to their defaults.
        #expect(areas[0].reminderIntervalDays == 0)
        #expect(areas[0].usesFrontCamera == false)
    }

    /// A real user upgrading has several areas, not one. The whole file
    /// has to come back, in order.
    @Test func severalLegacyAreasAllDecode() throws {
        let legacyJSON = """
        [
          {"id": "\(UUID().uuidString)", "name": "Left forearm", "category": "Skin Trend", "createdDate": 778000000},
          {"id": "\(UUID().uuidString)", "name": "Knee scar", "category": "Wound Recovery", "createdDate": 778100000},
          {"id": "\(UUID().uuidString)", "name": "Shoulder", "category": "Skin Trend", "createdDate": 778200000}
        ]
        """.data(using: .utf8)!

        let areas = try JSONDecoder().decode([TrackingArea].self, from: legacyJSON)
        #expect(areas.map(\.name) == ["Left forearm", "Knee scar", "Shoulder"])
    }

    @Test func areaRoundTripsEveryField() throws {
        var area = TrackingArea(name: "Cheek", category: .wound, usesFrontCamera: true)
        area.reminderIntervalDays = 7

        let data = try JSONEncoder().encode(area)
        let decoded = try JSONDecoder().decode(TrackingArea.self, from: data)

        #expect(decoded == area)
        #expect(decoded.reminderIntervalDays == 7)
        #expect(decoded.usesFrontCamera == true)
    }

    // MARK: - TrackingEntry

    /// entries.json from before tracking areas existed has no areaID.
    /// Those entries must still load so the store's migration can adopt
    /// them into an area rather than dropping them.
    @Test func entryFromBeforeAreasStillDecodes() throws {
        let id = UUID()
        let legacyJSON = """
        [{
            "id": "\(id.uuidString)",
            "category": "Wound Recovery",
            "date": 778000000,
            "imageFileName": "\(id.uuidString).jpg",
            "vectorFileName": "\(id.uuidString).vec",
            "note": "Day one"
        }]
        """.data(using: .utf8)!

        let entries = try JSONDecoder().decode([TrackingEntry].self, from: legacyJSON)

        #expect(entries.count == 1)
        #expect(entries[0].areaID == nil)
        #expect(entries[0].category == .wound)
        #expect(entries[0].note == "Day one")
    }

    @Test func entryRoundTrips() throws {
        let entry = TrackingEntry(areaID: UUID(), category: .skin, note: "Lotion applied")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TrackingEntry.self, from: data)
        #expect(decoded == entry)
    }

    /// The photo and its vector are paired purely by sharing the entry's
    /// UUID in their file names. If that ever drifts, comparisons load
    /// the wrong vector for a photo with no error at all.
    @Test func photoAndVectorFileNamesShareTheEntryID() {
        let entry = TrackingEntry(areaID: UUID(), category: .skin)
        #expect(entry.imageFileName == "\(entry.id.uuidString).jpg")
        #expect(entry.vectorFileName == "\(entry.id.uuidString).vec")
    }

    // MARK: - Persisted enum values

    /// These raw strings are written to disk. Renaming a case's display
    /// text would silently make every saved area and entry undecodable,
    /// so the stored values are pinned here on purpose. Change the UI
    /// label somewhere else, never these.
    @Test func categoryRawValuesNeverChange() {
        #expect(TrackingCategory.skin.rawValue == "Skin Trend")
        #expect(TrackingCategory.wound.rawValue == "Wound Recovery")
        #expect(TrackingCategory.allCases.count == 2)
    }
}
