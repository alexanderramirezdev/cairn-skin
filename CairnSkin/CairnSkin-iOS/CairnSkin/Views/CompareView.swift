//
//  CompareView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The payoff screen: shows the very first ("baseline") photo in a
//  category side by side with a photo the user picked, and runs the
//  Vision distance calculation between their two stored feature prints
//  to produce a "visual similarity" figure.
//
//  Note this does NOT recompute the feature print here — that already
//  happened once, at capture time, and was saved to disk. This screen
//  just loads the two saved vectors and compares them, which is fast
//  since there's no image processing happening now, only vector math.
//

import SwiftUI

struct CompareView: View {
    let area: TrackingArea
    let selectedEntry: TrackingEntry

    @Environment(TrackingStore.self) private var store
    @State private var rawDistance: Float?
    @State private var notComparable = false
    @AppStorage("developerReadoutEnabled") private var developerReadoutEnabled = false
    @State private var comparisonError: String?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var baselineEntry: TrackingEntry? {
        store.entries(in: area).first   // oldest entry in the area = baseline
    }

    private var isBaseline: Bool {
        baselineEntry?.id == selectedEntry.id
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let baselineEntry, baselineEntry.id != selectedEntry.id {
                    HStack(spacing: 16) {
                        PhotoCard(title: "Baseline", date: baselineEntry.date, image: store.image(for: baselineEntry))
                        PhotoCard(title: "This Photo", date: selectedEntry.date, image: store.image(for: selectedEntry))
                    }

                    resultCard

                    // Notes from either photo, if present — context is
                    // often more useful than the number.
                    if !baselineEntry.note.isEmpty || !selectedEntry.note.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !baselineEntry.note.isEmpty {
                                NoteBlock(label: "Baseline note", text: baselineEntry.note)
                            }
                            if !selectedEntry.note.isEmpty {
                                NoteBlock(label: "This photo", text: selectedEntry.note)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // The selected photo IS the baseline — nothing to compare yet.
                    PhotoCard(title: "Baseline", date: selectedEntry.date, image: store.image(for: selectedEntry))
                    Text("This is your first photo in this category. Add more over time to see comparisons here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
                .accessibilityHint("Deletes this photo from the area")
            }
        }
        // Alert rather than confirmationDialog — the dialog's popover
        // presentation on current iOS looked broken (see SettingsView).
        .alert(
            "Delete this photo?",
            isPresented: $confirmingDelete
        ) {
            Button("Delete Photo", role: .destructive) {
                store.delete(selectedEntry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Deleting the baseline re-anchors every comparison, which is
            // worth saying out loud before it happens.
            Text(isBaseline
                 ? "This is the baseline photo. The next-oldest photo will become the new baseline, and comparisons will be measured against it instead."
                 : "This photo and its note will be permanently removed.")
        }
        .task {
            await runComparison()
        }
    }

    /// Short note about whether the two photos are fair to compare.
    ///
    /// Deliberately no icon. A small glyph beside a paragraph reads as a
    /// badge on a warning, which is more alarm than this deserves — it's a
    /// note about photography, not about the user's body. Centred text
    /// matches the rest of the card and the wording carries the meaning.
    private func resultNote(_ text: String, prominent: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(prominent ? Color.primary : Color.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var resultCard: some View {
        VStack(spacing: 8) {
            if notComparable {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Not comparable")
                    .font(.title3.bold())
                Text("These two photos don't appear to show the same subject. Try photographing the same area you used for your baseline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if rawDistance != nil {
                // NO PERCENTAGE.
                //
                // The distance is still computed and is reliable enough to
                // say "these two photographs differ a lot." It is not
                // reliable enough to put a number on: lighting and backdrop
                // move it as much as the subject does. A tester's healing
                // scratch scored 43%, then 45%, then 22% across three
                // photos while visibly improving — the pictures told the
                // truth and the figure argued with them, and a number on
                // screen always wins that argument.
                //
                // So the measurement stays, but only to decide which note
                // appears. The photographs above are the comparison.
                if let rawDistance, FeatureExtractor.framingLooksInconsistent(distance: rawDistance) {
                    resultNote(
                        "Lighting, distance, or background changed between these two photos. Match how you took the first one to compare them fairly.",
                        prominent: true
                    )
                } else {
                    // Worth saying explicitly: it confirms the guided
                    // capture did its job, which is the behaviour to
                    // encourage, and tells the user the pair is honest to
                    // judge by eye.
                    resultNote(
                        "Taken under similar conditions, so these are fair to compare side by side.",
                        prominent: false
                    )
                }
            } else if let comparisonError {
                Text(comparisonError)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
            }

            // Kept even though no figure is shown now: the screen still
            // invites a judgement about a body, and this is the line that
            // says the app isn't making one.
            Text("A wellness journal only. This does not diagnose, screen for, or assess any condition.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            // Calibration readout. Off unless deliberately enabled (five
            // taps on the version line in Settings), and placed last, in
            // the faintest style available, so it reads as the development
            // artifact it is rather than as something the app is saying.
            if developerReadoutEnabled, let rawDistance {
                Text(String(format: "%.4f  ref %.2f / %.2f / %.2f",
                            rawDistance,
                            FeatureExtractor.noiseFloor,
                            FeatureExtractor.framingConcernThreshold,
                            FeatureExtractor.notComparableThreshold))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func runComparison() async {
        guard let baselineEntry, baselineEntry.id != selectedEntry.id else { return }
        guard
            let baselinePrint = store.featurePrint(for: baselineEntry),
            let selectedPrint = store.featurePrint(for: selectedEntry)
        else {
            comparisonError = "Could not load saved data for one of these photos."
            return
        }
        do {
            let distance = try FeatureExtractor.distance(between: baselinePrint, and: selectedPrint)
            rawDistance = distance
            // Guard first: if these look like different subjects entirely,
            // don't produce a percentage at all. A low number would still
            // read as a measurement, and there's nothing real to measure
            // between two unrelated photos.
            if FeatureExtractor.isComparable(distance: distance) {
            } else {
                notComparable = true
            }
        } catch {
            comparisonError = error.localizedDescription
        }
    }
}

private struct PhotoCard: View {
    let title: String
    let date: Date
    let image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Taller than the old 180. The photographs ARE the
                    // comparison — a person looking at two pictures of a
                    // healing scratch can see it improving, which is more
                    // reliable than any single number describing them.
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text(title).font(.caption.bold())
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NoteBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        CompareView(area: TrackingArea(name: "Left forearm", category: .skin), selectedEntry: TrackingEntry(areaID: UUID(), category: .skin))
            .environment(TrackingStore())
    }
}
