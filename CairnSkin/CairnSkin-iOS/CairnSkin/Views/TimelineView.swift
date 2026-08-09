//
//  TimelineView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Shows every logged photo for one category, newest first, plus a
//  button to capture a new one. Tapping an entry opens the comparison
//  screen against the very first (baseline) photo in that category.
//
//  CAPTURE ROUTING: on a real device, "Add Photo" opens GuidedCaptureView
//  (the live-guidance camera). On the Simulator, which has no camera at
//  all, it automatically falls back to CameraPicker's photo-library mode
//  instead — so the app runs everywhere with no manual switching.
//

import SwiftUI

struct TimelineView: View {
    let area: TrackingArea

    /// When true, the capture screen opens immediately on appear. Set
    /// when arriving straight from creating a new area — someone who
    /// just named "Left forearm" is there to photograph it, and making
    /// them tap through an empty list first is pure friction.
    var autoOpenCamera: Bool = false

    @Environment(TrackingStore.self) private var store
    @State private var showingGuidedCapture = false
    @State private var showingLibraryPicker = false
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // After a photo saves we hold onto it (and its new entry) so the
    // note sheet can show the photo the user just took.
    @State private var pendingNoteEntry: TrackingEntry?
    @State private var pendingNoteImage: UIImage?

    // The generated PDF, held until the share sheet is dismissed.
    @State private var reportURL: URL?
    @State private var isGeneratingReport = false
    @State private var renamingArea = false
    @State private var renameText = ""

    /// The live area record from the store. The `area` parameter is a
    /// value copy taken at navigation time, so after a rename it would
    /// show the old name — always read the current one for display.
    private var currentArea: TrackingArea {
        store.areas.first { $0.id == area.id } ?? area
    }
    @State private var hasAutoOpened = false

    private var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var baselineImage: UIImage? {
        guard let first = store.entries(in: area).first else { return nil }
        return store.image(for: first)
    }

    var body: some View {
        let areaEntries = store.entries(in: area).reversed()  // newest first for display

        List {
            if areaEntries.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: area.category.systemImage,
                    description: Text(area.category.captureGuidance)
                )
            } else {
                ForEach(Array(areaEntries)) { entry in
                    NavigationLink {
                        CompareView(area: area, selectedEntry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete { offsets in
                    let list = Array(areaEntries)
                    for index in offsets {
                        store.delete(list[index])
                    }
                }
            }
        }
        .navigationTitle(currentArea.name)
        .alert("Rename Area", isPresented: $renamingArea) {
            TextField("Area name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.renameArea(currentArea, to: trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            // Only on first appearance, and only when there's nothing
            // logged yet — reopening an existing area shouldn't ambush
            // the user with a camera.
            if autoOpenCamera && store.entries(in: area).isEmpty && !hasAutoOpened {
                hasAutoOpened = true
                if hasCamera {
                    showingGuidedCapture = true
                } else {
                    showingLibraryPicker = true
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if hasCamera {
                        showingGuidedCapture = true
                    } else {
                        showingLibraryPicker = true
                    }
                } label: {
                    Label("Add Photo", systemImage: "camera.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Trend needs at least 3 photos to say anything useful.
                    NavigationLink {
                        TrendView(area: area)
                    } label: {
                        Label("Change Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(store.entries(in: area).count < 3)

                    Button {
                        generateReport()
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                    .disabled(store.entries(in: area).isEmpty)

                    Button {
                        renameText = currentArea.name
                        renamingArea = true
                    } label: {
                        Label("Rename Area", systemImage: "pencil")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        // Real device: the live-guidance camera, full screen.
        .fullScreenCover(isPresented: $showingGuidedCapture) {
            GuidedCaptureView(area: area, baselineImage: baselineImage) { image in
                capturedImage = image
            }
        }
        // Simulator fallback: the plain photo-library picker.
        .sheet(isPresented: $showingLibraryPicker) {
            CameraPicker(capturedImage: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let newImage else { return }
            Task { await save(newImage) }
        }
        // Note sheet appears right after a successful save. The photo is
        // already stored by this point — skipping only skips the note.
        .sheet(item: $pendingNoteEntry) { entry in
            if let image = pendingNoteImage {
                AddNoteView(image: image) { note in
                    if !note.isEmpty {
                        store.updateNote(note, for: entry)
                    }
                    pendingNoteImage = nil
                }
            }
        }
        .sheet(item: $reportURL) { url in
            ShareSheet(items: [url])
        }
        .overlay {
            if isGeneratingReport {
                ProgressView("Building PDF…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if isProcessing {
                ProgressView("Processing photo…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Couldn't Save Photo", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func generateReport() {
        isGeneratingReport = true

        // Snapshot what the background task needs BEFORE leaving the main
        // actor. `entries` is a plain array of value types and `archive`
        // is thread-safe; the store itself stays behind.
        let entriesSnapshot = store.entries(in: area)
        let archive = store.archive
        let targetArea = currentArea

        // PDF rendering is synchronous and slow with many photos, so it
        // runs off the main thread.
        Task.detached(priority: .userInitiated) {
            do {
                let url = try ReportGenerator.generate(
                    area: targetArea,
                    entries: entriesSnapshot,
                    archive: archive
                )
                await MainActor.run {
                    isGeneratingReport = false
                    reportURL = url
                }
            } catch {
                await MainActor.run {
                    isGeneratingReport = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func save(_ image: UIImage) async {
        isProcessing = true
        defer {
            isProcessing = false
            capturedImage = nil   // reset so onChange fires again next time
        }
        do {
            let entry = try await store.addEntry(image: image, area: area)
            pendingNoteImage = image
            pendingNoteEntry = entry      // presenting this triggers the note sheet
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EntryRow: View {
    let entry: TrackingEntry
    @Environment(TrackingStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail, not the full image — a list of full-resolution
            // JPEGs is what made this screen hang.
            if let image = store.thumbnail(for: entry) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        // One VoiceOver stop per row: "Photo from <date>, note: <note>"
        // instead of the image and texts as separate elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Photo from \(entry.date.formatted(date: .long, time: .shortened))"
            + (entry.note.isEmpty ? "" : ", note: \(entry.note)")
        )
    }
}

#Preview {
    NavigationStack {
        TimelineView(area: TrackingArea(name: "Left forearm", category: .skin))
            .environment(TrackingStore())
    }
}
