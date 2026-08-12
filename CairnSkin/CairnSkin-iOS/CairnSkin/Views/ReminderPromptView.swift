//
//  ReminderPromptView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A one-time prompt offering a capture reminder, shown after the user
//  saves their first photo in an area.
//
//  WHY HERE AND NOT IN SETTINGS:
//  Reminders were originally only reachable through the timeline's menu,
//  under Area Settings. Nobody finds that, and a feature whose entire
//  value is accountability provides none if it's never discovered.
//
//  WHY NOT DURING CAPTURE:
//  The moment right after taking a photo is already occupied by the note
//  sheet, and stacking a second ask there would clutter the one part of
//  the flow that's currently clean. This appears once the user has
//  finished the whole loop and landed back on the timeline, where they
//  can see the photo they just made and the empty space where the next
//  one goes.
//
//  It's offered once per area, and dismissing it is a single tap. The
//  system notification permission prompt only appears if they pick an
//  interval, so nobody gets asked for permission before they've asked
//  for the feature.
//

import SwiftUI

struct ReminderPromptView: View {
    let areaName: String
    /// Called with the chosen interval in days, or 0 if declined.
    let onChoose: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let options: [(days: Int, label: String)] = [
        (3, "Every 3 days"),
        (7, "Weekly"),
        (14, "Every 2 weeks"),
        (30, "Monthly")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .padding(.top, 32)

                    // Naming the area makes it concrete about what's being
                    // reminded, and reads better than a generic question.
                    Text("Remind you about \(areaName)?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)

                    Text("Photos are only worth comparing if you keep taking them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        // "fixedSize" stops the text truncating when the
                        // sheet is shorter than the content wants. Without
                        // it the sentence clipped mid-word.
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 28)

                VStack(spacing: 10) {
                    ForEach(options, id: \.days) { option in
                        Button {
                            onChoose(option.days)
                            dismiss()
                        } label: {
                            Text(option.label)
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Not now" rather than "Cancel" — nothing is being
                    // cancelled, and it makes clear this can be turned on
                    // later without implying something was lost.
                    Button("Not now") {
                        onChoose(0)
                        dismiss()
                    }
                }
            }
        }
        // ".height" sized to the content rather than ".medium". The medium
        // detent is a fixed fraction of the screen and was clipping the
        // body text on smaller devices.
        .presentationDetents([.height(430)])
    }
}
