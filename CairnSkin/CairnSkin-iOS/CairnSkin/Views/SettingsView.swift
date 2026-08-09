//
//  SettingsView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  App settings: the biometric lock toggle, a comparison-details option,
//  data deletion, and the standing disclaimer.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(TrackingStore.self) private var store

    /// Surfaces the raw distance value on the compare screen. Off by
    /// default; genuinely useful for anyone curious about what the
    /// similarity number is derived from — and for calibration work.
    @AppStorage("showComparisonDetails") private var showComparisonDetails = false

    @State private var confirmingDeleteAll = false

    var body: some View {
        @Bindable var lock = appLock

        Form {
            if appLock.biometricsAvailable {
                Section {
                    Toggle("Require \(appLock.biometryName)", isOn: $lock.isEnabled)
                    Text(appLock.biometryDiagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("On by default. \(appLock.biometryName) is asked for before your photos are shown, starting once you've saved your first photo. Your photos never leave this device, and there's no account or password — this lock is handled entirely by iOS.")
                }
            }

            Section {
                Toggle("Show comparison details", isOn: $showComparisonDetails)
            } footer: {
                Text("Displays the underlying distance value on the compare screen. Smaller means more visually similar. For the curious — the plain percentage tells the same story.")
            }

            Section {
                Button("Delete All Data", role: .destructive) {
                    confirmingDeleteAll = true
                }
                .accessibilityHint("Permanently deletes every tracking area and photo")
            } footer: {
                Text("Permanently removes every tracking area, photo, and note from this device. This cannot be undone.")
            }

            Section {
                EmptyView()
            } footer: {
                Text("Cairn Skin helps you visually compare photos over time. It does not diagnose, screen for, or provide medical judgment about any condition. Always consult a healthcare provider with medical concerns.")
            }

            // Development only — stripped from release builds entirely.
            #if DEBUG
            Section("Development") {
                NavigationLink("Debug Tools") {
                    DebugToolsView()
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // An ALERT, not a confirmationDialog. The dialog renders as a
        // popover anchored to the triggering row on current iOS, which
        // looked broken — cramped, floating mid-screen, Cancel easy to
        // miss. A centered alert is the right shape for a small
        // destructive confirmation.
        .alert(
            "Delete all data?",
            isPresented: $confirmingDeleteAll
        ) {
            Button("Delete Everything", role: .destructive) {
                store.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every tracking area, photo, and note will be permanently removed from this device. This cannot be undone.")
        }
    }
}
