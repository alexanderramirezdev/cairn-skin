//
//  TrackingEntry.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The data shape for one logged photo: which tracking area it belongs
//  to, when it was taken, where its image file lives on disk, and where
//  its extracted feature print (the vector) lives on disk.
//
//  WHY WE STORE FILE NAMES INSTEAD OF THE IMAGE/VECTOR DIRECTLY:
//  Photos and vectors are relatively large binary blobs. Keeping them as
//  separate files on disk (instead of packed into one big JSON file) is
//  faster to load and standard practice — this JSON file becomes a
//  lightweight "index," while Photos/ and Vectors/ folders hold the
//  actual bytes. Similar to storing a blob URL in a SQL row instead of
//  the blob itself.
//

import Foundation

// The two kinds of tracking this app supports. An area (see
// TrackingArea.swift) is tagged with one of these.
enum TrackingCategory: String, Codable, CaseIterable, Identifiable {
    case skin = "Skin Trend"
    case wound = "Wound Recovery"

    var id: String { rawValue }

    var captureGuidance: String {
        switch self {
        case .skin:
            return "Frame the same area, similar lighting and distance as your last photo, for the most reliable comparison."
        case .wound:
            return "Center the wound or scar in frame. Consistent lighting and angle matter more than image quality."
        }
    }

    var systemImage: String {
        switch self {
        case .skin: return "face.smiling"
        case .wound: return "bandage"
        }
    }
}

struct TrackingEntry: Codable, Identifiable, Equatable {
    let id: UUID
    // Which tracking area this photo belongs to. Optional ONLY so that
    // entries saved before areas existed can still be decoded; the
    // migration in TrackingStore assigns them an area on first load.
    var areaID: UUID?
    let category: TrackingCategory
    let date: Date
    let imageFileName: String     // e.g. "3F2A1.jpg" inside Photos/
    let vectorFileName: String    // e.g. "3F2A1.vec" inside Vectors/
    var note: String

    init(areaID: UUID, category: TrackingCategory, note: String = "") {
        self.id = UUID()
        self.areaID = areaID
        self.category = category
        self.date = Date()
        // Reuse the same UUID string as both file names so it's obvious
        // at a glance which photo and which vector belong together.
        self.imageFileName = "\(id.uuidString).jpg"
        self.vectorFileName = "\(id.uuidString).vec"
        self.note = note
    }
}
