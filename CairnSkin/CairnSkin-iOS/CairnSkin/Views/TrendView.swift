//
//  TrendView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A visual summary of one area's history: how much each photo differs
//  from the baseline, plotted over time, with every point paired to its
//  thumbnail.
//
//  THE MOST IMPORTANT DESIGN DECISION IN THIS FILE:
//  This chart shows MAGNITUDE of change, never direction, and never
//  whether change is good or bad. The underlying metric cannot support
//  that claim: a rash clearing up and a mole growing both register as
//  "more different from baseline." The app has no way to distinguish
//  improvement from deterioration, and a chart implying otherwise would
//  be the most misleading thing in the product — precisely because
//  someone with a real concern would read a falling line as reassurance.
//
//  So the language throughout is about HOW MUCH and WHEN, not better or
//  worse. Thumbnails sit beside every point so the user's own eyes make
//  the judgment, which they are genuinely better equipped to make than
//  this algorithm is.
//

import SwiftUI
import Charts

struct TrendView: View {
    let area: TrackingArea
    @Environment(TrackingStore.self) private var store

    // One plotted point: a photo, when it was taken, and how far it sits
    // from the baseline.
    struct ChangePoint: Identifiable {
        let id: UUID
        let entry: TrackingEntry
        let date: Date
        let changeAmount: Double   // 0 = matches baseline, higher = more different
        let isComparable: Bool
    }

    @State private var points: [ChangePoint] = []
    @State private var isCalculating = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isCalculating {
                    ProgressView("Reading your photos…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if points.count < 2 {
                    ContentUnavailableView(
                        "Not Enough Photos Yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add at least three photos to this area to see how it's changed over time.")
                    )
                    .padding(.top, 40)
                } else {
                    chart
                    interpretation
                    thumbnailStrip
                }
            }
            .padding()
        }
        .navigationTitle("Change Over Time")
        .navigationBarTitleDisplayMode(.inline)
        .task { await calculate() }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How much each photo differs from your baseline")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Change", point.changeAmount)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Change", point.changeAmount)
                )
                .foregroundStyle(.tint)
            }
            .frame(height: 200)
            .chartYAxis {
                // Deliberately unlabeled numerically. A precise-looking
                // y-axis would invite reading this as a measurement with
                // units. "Similar" to "Different" is the honest scale.
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(raw <= 0.05 ? "Similar" : (raw >= 0.7 ? "Different" : ""))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Plain-language summary

    private var interpretation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryText)
                .font(.subheadline)

            Text("This shows how much your photos differ from your baseline — not whether anything is better or worse. Only you and a healthcare provider can judge that. Lighting and camera angle also affect these values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // Describes the shape of the data without characterizing it as good
    // or bad. Points at WHEN things moved, which is the actionable part.
    private var summaryText: String {
        guard points.count >= 2 else { return "" }
        let recent = points.suffix(3).map(\.changeAmount)
        let spread = (recent.max() ?? 0) - (recent.min() ?? 0)

        if spread < 0.08 {
            return "Your recent photos look consistent with each other."
        }

        // Find the largest jump between consecutive photos and name its date.
        var biggestJump = 0.0
        var jumpDate: Date?
        for i in 1..<points.count {
            let delta = abs(points[i].changeAmount - points[i-1].changeAmount)
            if delta > biggestJump {
                biggestJump = delta
                jumpDate = points[i].date
            }
        }
        if let jumpDate, biggestJump > 0.12 {
            return "The largest shift between photos was around \(jumpDate.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Your photos show some variation over time."
    }

    // MARK: - Thumbnails

    private var thumbnailStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your photos")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(points) { point in
                        VStack(spacing: 6) {
                            if let image = store.thumbnail(for: point.entry) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func calculate() async {
        let entries = store.entries(in: area)   // oldest first
        guard let baseline = entries.first,
              let baselinePrint = store.featurePrint(for: baseline) else {
            isCalculating = false
            return
        }

        // Each featurePrint() is a disk read plus an NSKeyedUnarchiver
        // decode. Doing that for every entry on the main thread froze the
        // UI as soon as an area had more than a handful of photos — the
        // spinner couldn't even animate. Task.detached moves the whole
        // loop off the main thread; only the finished array comes back.
        let computed: [ChangePoint] = await Task.detached(priority: .userInitiated) {
            var result: [ChangePoint] = []
            for entry in entries {
                guard let print = store.featurePrint(for: entry) else { continue }
                let distance = (try? FeatureExtractor.distance(between: baselinePrint, and: print)) ?? 0
                // Subtract the noise floor so ordinary capture variation
                // sits at zero rather than looking like real change.
                let adjusted = max(0, Double(distance - FeatureExtractor.noiseFloor))
                result.append(ChangePoint(
                    id: entry.id,
                    entry: entry,
                    date: entry.date,
                    changeAmount: adjusted,
                    isComparable: FeatureExtractor.isComparable(distance: distance)
                ))
            }
            return result
        }.value

        points = computed.filter(\.isComparable)
        isCalculating = false
    }
}
