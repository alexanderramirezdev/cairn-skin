//
//  AddNoteView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A small sheet that appears right after a photo is captured, offering
//  an optional note. Context is what makes a photo log useful months
//  later — "started new moisturizer," "bumped it on the door frame" —
//  and the moment right after capture is when the user actually
//  remembers it.
//
//  The note is optional by design. Requiring one would add friction to
//  the core loop, and a tracking app people skip because logging is
//  tedious is worse than one with sparse notes.
//

import SwiftUI

struct AddNoteView: View {
    let image: UIImage
    let onSave: (String) -> Void

    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    // Quick-tap suggestions. Tapping one appends it rather than
    // replacing what's typed, so several can be combined.
    private let suggestions = [
        "Started new product",
        "Looks irritated",
        "Feels better",
        "After sun exposure"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                }

                Section("Note (optional)") {
                    TextField("Anything worth remembering about today",
                              text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Quick add") {
                    // A flexible wrapping row of suggestion chips.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    append(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.quaternary, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Skip" rather than "Cancel" — the photo is already
                    // saved by this point, so backing out only skips the
                    // note. Calling it Cancel would imply losing the photo.
                    Button("Skip") {
                        onSave("")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }

    private func append(_ text: String) {
        if note.isEmpty {
            note = text
        } else {
            note += ". \(text)"
        }
    }
}
