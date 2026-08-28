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

    @State private var confirmingDeleteAll = false
    @State private var versionTapCount = 0
    @AppStorage(TrackingStore.excludeFromBackupKey) private var excludeFromBackup = false

    /// Reveals the raw comparison distance on the compare screen.
    ///
    /// Deliberately hidden behind five taps on the version line, the same
    /// pattern Android uses for its developer options. The distance is a
    /// calibration tool, not a feature: it's meaningless without the
    /// reference measurements to read it against, and putting it in plain
    /// settings invites exactly the over-reading that got the percentage
    /// removed. But it can't be #if DEBUG either, because the only way to
    /// run this app on an iOS 27 beta device is a release build through
    /// TestFlight — so calibration would be impossible without it.
    @AppStorage("developerReadoutEnabled") private var developerReadoutEnabled = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

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
                    Text("On by default. \(appLock.biometryName) is asked for before your photos are shown, starting once you've saved your first photo. There's no account and no password: the lock is handled entirely by iOS, and your photos are stored encrypted so they can't be read while the phone is locked.")
                }
            }

            Section {
                Toggle("Keep out of iCloud backups", isOn: $excludeFromBackup)
                    .onChange(of: excludeFromBackup) { _, _ in
                        store.applyBackupPreference()
                    }
            } header: {
                Text("Backups")
            } footer: {
                Text(excludeFromBackup
                     ? "Your photos are excluded from iCloud and computer backups. If you restore this phone or move to a new one, they will not come back — there is no other copy."
                     : "Cairn Skin has no account and no server, so nothing is uploaded by the app itself. If you use iCloud Backup, your photos are included in that encrypted backup like other app data. Turn this on to leave them out, but they then can't be restored to a new phone.")
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
                Link(destination: URL(string: "mailto:support@ramirezlabs.app?subject=Cairn%20Skin%20Support")!) {
                    Label("Contact Support", systemImage: "envelope")
                }
                Link(destination: URL(string: "https://ramirezlabs.app/cairnskin/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            } header: {
                Text("Support")
            } footer: {
                // Version and build come straight from the bundle, so this
                // can't drift out of date. Worth including because it's the
                // first thing you'll want to know from a bug report.
                Text("Cairn Skin \(appVersion) (\(buildNumber))")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 5 {
                            versionTapCount = 0
                            developerReadoutEnabled.toggle()
                        }
                    }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Cairn Skin helps you visually compare photos over time. It does not diagnose, screen for, or provide medical judgment about any condition. Always consult a healthcare provider with medical concerns.")
            }

            if developerReadoutEnabled {
                Section {
                    Toggle("Show comparison distance", isOn: $developerReadoutEnabled)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Raw feature-print distance on the compare screen. Reference points: ~0.20 same photo conditions, ~0.45 framing or lighting differs, ~0.85 likely a different subject. Turn off to hide this section.")
                }
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
