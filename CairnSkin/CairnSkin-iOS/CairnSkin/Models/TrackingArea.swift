//
//  TrackingArea.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A named place on the body that the user is tracking over time — for
//  example "Left forearm mole", "Knee scar", or "Right shoulder".
//
//  WHY THIS EXISTS:
//  The app originally had two fixed categories (Skin, Wound), which meant
//  every skin photo shared one timeline and one baseline. That falls apart
//  immediately in real use: photographing a forearm and then a shoulder
//  would compare them against each other, which is meaningless. Each body
//  location needs its own baseline and its own history.
//
//  The category still exists, but now it's an attribute OF an area rather
//  than the thing you track. So you might have three areas: two skin, one
//  wound — each with a separate timeline.
//

import Foundation

// "Hashable" is required for navigationDestination(item:) to use this
// type as a navigation value.
struct TrackingArea: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String                  // user-provided, e.g. "Left forearm"
    var category: TrackingCategory    // Skin Trend or Wound Recovery
    let createdDate: Date

    /// How often to remind the user to photograph this area, in days.
    /// 0 means no reminder.
    ///
    /// Per-area rather than a single app-wide setting on purpose: someone
    /// tracking a healing wound may want a daily nudge, while someone
    /// watching a mole is fine with monthly. One global interval would be
    /// wrong for both.
    var reminderIntervalDays: Int = 0

    /// Which camera to use for this area. A spot on the face can't be
    /// framed with the rear camera — the user can't see the guide box or
    /// the ghost overlay — so the choice belongs to the area, not to a
    /// global setting they'd have to toggle every time.
    var usesFrontCamera: Bool = false

    init(name: String, category: TrackingCategory, usesFrontCamera: Bool = false) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.createdDate = Date()
        self.usesFrontCamera = usesFrontCamera
    }

    // Used by the migration path in TrackingStore when adopting entries
    // that were logged before areas existed.
    init(id: UUID, name: String, category: TrackingCategory, createdDate: Date) {
        self.id = id
        self.name = name
        self.category = category
        self.createdDate = createdDate
    }

    // Both new properties have defaults, so areas saved before they
    // existed still decode cleanly — no migration needed.

    // MARK: - Codable
    //
    // A default value on a stored property (like "= 0" above) only tells
    // the COMPILER what to use for new instances. It does NOT make the
    // auto-generated decoder tolerant of that key being absent from
    // already-saved JSON — the synthesized decoder still calls decode(),
    // not decodeIfPresent(), and throws if the key is missing.
    //
    // That's what broke existing users' data here: reminderIntervalDays
    // and usesFrontCamera were added after people already had areas.json
    // on disk without those keys. Decoding threw, and TrackingStore's
    // "try? decode(...) ?? []" turned that failure into a silently empty
    // list — indistinguishable from "no areas" to anyone looking at the
    // app, even though the real data was untouched on disk the whole
    // time.
    //
    // This explicit initializer uses decodeIfPresent for the fields added
    // after launch, so old saves without them decode successfully instead
    // of failing the whole array. Encoding still writes every field, so
    // once re-saved once, the JSON is fully up to date and this path
    // isn't hit for that record again.
    //
    // RULE FOR NEXT TIME: any Codable stored property added to a type
    // that already has saved data on people's devices needs this same
    // treatment — decodeIfPresent with a fallback, not decode(). Adding a
    // plain "= default" alone is not enough.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(TrackingCategory.self, forKey: .category)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        reminderIntervalDays = try container.decodeIfPresent(Int.self, forKey: .reminderIntervalDays) ?? 0
        usesFrontCamera = try container.decodeIfPresent(Bool.self, forKey: .usesFrontCamera) ?? false
    }
}
