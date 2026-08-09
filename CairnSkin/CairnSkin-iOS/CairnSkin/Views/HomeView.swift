//
//  HomeView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The first screen: a list of the body areas the user is tracking,
//  grouped by category, with a button to add a new one. Tapping an area
//  opens its own timeline and baseline.
//

import SwiftUI

struct HomeView: View {
    @Environment(TrackingStore.self) private var store
    @State private var showingNewArea = false

    /// Set when a new area is created, which pushes straight into its
    /// timeline with the camera opening automatically.
    @State private var freshlyCreatedArea: TrackingArea?

    var body: some View {
        NavigationStack {
            List {
                if store.areas.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Tracking Areas",
                            systemImage: "plus.viewfinder",
                            description: Text("Add an area to start logging photos. Each area keeps its own baseline and history, so a forearm and a knee are never compared against each other.")
                        )
                    }
                } else {
                    // One section per category, so skin areas and wound
                    // areas stay visually separated.
                    ForEach(TrackingCategory.allCases) { category in
                        let categoryAreas = store.areas.filter { $0.category == category }
                        if !categoryAreas.isEmpty {
                            Section(category.rawValue) {
                                ForEach(categoryAreas) { area in
                                    NavigationLink {
                                        TimelineView(area: area)
                                    } label: {
                                        AreaRow(area: area, count: store.entries(in: area).count)
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets {
                                        store.deleteArea(categoryAreas[index])
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Cairn Skin helps you visually compare photos over time. It does not diagnose, screen for, or provide medical judgment about any condition. Always consult a healthcare provider with medical concerns.")
                }
            }
            .navigationTitle("Cairn Skin")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewArea = true
                    } label: {
                        Label("Add Area", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingNewArea) {
                NewAreaView { newArea in
                    freshlyCreatedArea = newArea
                }
            }
            // Pushes into the new area's timeline once the sheet closes.
            .navigationDestination(item: $freshlyCreatedArea) { area in
                TimelineView(area: area, autoOpenCamera: true)
            }
        }
    }
}

private struct AreaRow: View {
    let area: TrackingArea
    let count: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: area.category.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.name)
                    .font(.headline)
                Text(count == 0 ? "No photos yet" : "\(count) photo\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(area.name), \(area.category.rawValue), \(count == 0 ? "no photos yet" : "\(count) photo\(count == 1 ? "" : "s")")")
    }
}

// The "create a new tracking area" sheet.
private struct NewAreaView: View {
    /// Called with the created area so the caller can navigate to it.
    let onCreate: (TrackingArea) -> Void

    @Environment(TrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: TrackingCategory = .skin

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Left forearm", text: $name)
                }
                Section("Type") {
                    Picker("Type", selection: $category) {
                        ForEach(TrackingCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Give each spot its own area. Photos are only ever compared within the same area, so tracking several places at once stays accurate.")
                }
            }
            .navigationTitle("New Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let area = store.addArea(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category
                        )
                        dismiss()
                        onCreate(area)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(TrackingStore())
        .environment(AppLock())
}
