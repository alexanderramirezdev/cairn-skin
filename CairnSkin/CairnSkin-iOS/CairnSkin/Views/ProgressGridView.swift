//
//  ProgressGridView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Every photo in an area, in date order, at a size big enough to
//  actually compare by eye.
//
//  WHY THIS REPLACED THE TREND CHART:
//  The old screen plotted the Vision feature-print distance over time as a
//  line chart. The underlying number turned out to be dominated by
//  lighting and background rather than by the subject — a tester's healing
//  scratch scored 43%, then 45%, then 22% across three photos while
//  visibly getting better.
//
//  A single noisy number is bad. Plotting it is worse: a chart reads as
//  more authoritative than a figure, so it would have drawn a confident
//  downward line while the thing it claimed to describe was improving.
//
//  What people actually want from this screen is "show me all of them at
//  once," and photographs answer that honestly. Change is obvious to a
//  human eye looking at a sequence, and the app doesn't have to make a
//  claim it can't support.
//

import SwiftUI

struct ProgressGridView: View {
    let area: TrackingArea
    @Environment(TrackingStore.self) private var store

    private var entries: [TrackingEntry] {
        store.entries(in: area)   // oldest first
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Photos you add to this area will appear here in order.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            CompareView(area: area, selectedEntry: entry)
                        } label: {
                            gridCell(entry: entry, isBaseline: index == 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Text("Change is easiest to see by looking across the sequence. Photos taken in similar lighting and framing are the most useful to compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("All Photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gridCell(entry: TrackingEntry, isBaseline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let image = store.thumbnail(for: entry) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(height: 150)
                }

                if isBaseline {
                    Text("Baseline")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }

            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (isBaseline ? "Baseline photo, " : "Photo from ")
            + entry.date.formatted(date: .long, time: .omitted)
            + (entry.note.isEmpty ? "" : ", note: \(entry.note)")
        )
    }
}
