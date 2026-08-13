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
    @State private var similarityPercent: Int?
    @State private var rawDistance: Float?
    @State private var notComparable = false
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
            } else if let similarityPercent {
                // DEMOTED from a 48pt hero number to a supporting line.
                //
                // The number was the loudest thing on this screen, which
                // made people read it as a verdict on their skin. It isn't:
                // it describes how alike two photographs are, and lighting
                // and backdrop move it as much as the subject does. A
                // tester's healing scratch scored 43% and then 45% while
                // visibly improving — the photos told the truth and the
                // number argued with them.
                //
                // The photographs are the comparison now. This supports
                // them rather than overriding them.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(similarityPercent)%")
                        .font(.title2.weight(.semibold))
                    Text("visually similar to your baseline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(similarityPercent) percent visually similar to your baseline photo")
            } else if let comparisonError {
                Text(comparisonError)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
            }

            // Framing caveat. Shown when the two photos differ enough that
            // the difference could be how they were taken rather than what
            // they show. Deliberately worded as a possibility, not a
            // verdict: a genuinely large change lands in this band too, and
            // the app has no way to tell the two apart.
            if let rawDistance, FeatureExtractor.framingLooksInconsistent(distance: rawDistance) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("These two photos are framed quite differently. Distance, angle, and background all affect this number, so check the framing matches before reading this as a change in the area itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)
            }

            // Raw distance readout — DEBUG builds only. It's a calibration
            // tool, not a feature: the number means nothing without the
            // reference measurements to compare it against, and showing it
            // invites people to over-read a figure the percentage already
            // expresses.
            #if DEBUG
            if let rawDistance {
                Text(String(format: "distance: %.4f", rawDistance))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            #endif

            // The disclaimer travels with the number every time it's shown —
            // never let this figure appear on screen without this context.
            Text("A wellness trend indicator only. This is not a medical measurement and does not diagnose or assess any condition.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
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
                similarityPercent = FeatureExtractor.similarityPercent(forDistance: distance)
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
