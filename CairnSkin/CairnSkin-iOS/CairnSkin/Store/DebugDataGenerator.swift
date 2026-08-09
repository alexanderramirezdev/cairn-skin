//
//  DebugDataGenerator.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A development-only tool that bulk-creates realistic test entries, so
//  performance problems that only appear at volume can be found in a
//  minute instead of over two months of real use.
//
//  WHY THIS MATTERS:
//  Everything in this app has been hand-tested with three or four
//  photos. The trend view loads feature prints one at a time, and the
//  PDF renders every photo into a page — both are fine at n=4 and
//  potentially miserable at n=50. Testing the shape of the problem is
//  the only way to know.
//
//  #if DEBUG means none of this compiles into a release build, so it
//  can't ship by accident.
//

#if DEBUG

import UIKit
import SwiftUI

enum DebugDataGenerator {

    /// Creates `count` synthetic entries in the given area, dated
    /// backwards from today at one-day intervals.
    ///
    /// The generated images aren't random noise — they're skin-toned
    /// gradients with speckling that drifts gradually across the series.
    /// Random images would produce meaningless feature-print distances
    /// and wouldn't exercise the comparison path realistically; a slow
    /// drift approximates what a real tracking series looks like.
    static func populate(
        area: TrackingArea,
        count: Int,
        store: TrackingStore,
        progress: @escaping (Int) -> Void
    ) async {
        for index in 0..<count {
            let image = syntheticSkinImage(seed: index, drift: Double(index) / Double(max(count - 1, 1)))
            _ = try? await store.addEntry(
                image: image,
                area: area,
                note: index % 3 == 0 ? "Test entry \(index + 1)" : ""
            )
            await MainActor.run { progress(index + 1) }
        }
    }

    /// Builds a plausible skin-like image. `drift` (0...1) shifts hue and
    /// speckle density across the series so later entries differ from the
    /// baseline the way real photos gradually do.
    private static func syntheticSkinImage(seed: Int, drift: Double) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)

        // Deterministic per-seed randomness, so repeated runs produce
        // identical data and results stay comparable between tests.
        var rng = SeededGenerator(seed: UInt64(seed &+ 1))

        return renderer.image { context in
            let cg = context.cgContext

            // Base skin tone, shifting slightly redder with drift.
            let base = UIColor(
                hue: 0.06 - CGFloat(drift) * 0.02,
                saturation: 0.35 + CGFloat(drift) * 0.10,
                brightness: 0.82 - CGFloat(drift) * 0.05,
                alpha: 1
            )
            base.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Speckles standing in for pores, hair, and texture.
            let speckleCount = 300 + Int(drift * 200)
            for _ in 0..<speckleCount {
                let x = CGFloat(rng.nextDouble()) * size.width
                let y = CGFloat(rng.nextDouble()) * size.height
                let r = CGFloat(rng.nextDouble()) * 6 + 1
                UIColor(white: CGFloat(rng.nextDouble()) * 0.4, alpha: 0.25).setFill()
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }

            // A darker patch that grows with drift — something for the
            // comparison to actually register over the series.
            let patchSize = 80 + drift * 160
            UIColor(red: 0.55, green: 0.32, blue: 0.28, alpha: 0.35).setFill()
            cg.fillEllipse(in: CGRect(
                x: size.width/2 - patchSize/2,
                y: size.height/2 - patchSize/2,
                width: patchSize, height: patchSize
            ))
        }
    }
}

/// A tiny deterministic PRNG so generated data is reproducible.
/// (Swift's default Random is seeded per-process and can't be pinned.)
private struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble() -> Double {
        Double(next() % 1_000_000) / 1_000_000.0
    }
}

/// The debug UI, reachable from Settings in DEBUG builds only.
struct DebugToolsView: View {
    @Environment(TrackingStore.self) private var store

    @State private var selectedAreaID: UUID?
    @State private var count = 30
    @State private var isRunning = false
    @State private var completed = 0
    @State private var elapsed: TimeInterval?

    private var selectedArea: TrackingArea? {
        store.areas.first { $0.id == selectedAreaID } ?? store.areas.first
    }

    var body: some View {
        Form {
            Section("Target area") {
                if store.areas.isEmpty {
                    Text("Create an area first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Area", selection: Binding(
                        get: { selectedArea?.id ?? store.areas[0].id },
                        set: { selectedAreaID = $0 }
                    )) {
                        ForEach(store.areas) { area in
                            Text(area.name).tag(area.id)
                        }
                    }
                }
            }

            Section("How many") {
                Stepper("\(count) entries", value: $count, in: 5...200, step: 5)
                Text("Try 30 to spot the trend view slowing down, 100+ to stress the PDF export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    run()
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Generating \(completed) of \(count)…")
                        }
                    } else {
                        Text("Generate Test Entries")
                    }
                }
                .disabled(isRunning || store.areas.isEmpty)

                if let elapsed {
                    Text(String(format: "Last run: %.1fs for %d entries (%.2fs each)",
                                elapsed, count, elapsed / Double(count)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Generates synthetic skin-like photos that drift gradually across the series, so comparisons behave like a real tracking history. DEBUG builds only — this never ships.")
            }
        }
        .navigationTitle("Debug Tools")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        guard let area = selectedArea else { return }
        isRunning = true
        completed = 0
        let start = Date()
        Task {
            await DebugDataGenerator.populate(area: area, count: count, store: store) { done in
                completed = done
            }
            elapsed = Date().timeIntervalSince(start)
            isRunning = false
        }
    }
}

#endif
