//
//  AreaSettingsView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Per-area settings: which camera to use, and how often to be reminded.
//
//  Both belong to the area rather than the app. Someone tracking a spot on
//  their cheek needs the front camera every time, while a forearm needs the
//  rear one — a global toggle would have to be flipped on every capture. And
//  a healing wound may warrant a daily nudge where a mole is fine monthly.
//

import SwiftUI
import UserNotifications

struct AreaSettingsView: View {
    let area: TrackingArea
    @Environment(TrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var reminderDays: Int
    @State private var notificationsDenied = false

    init(area: TrackingArea) {
        self.area = area
        _name = State(initialValue: area.name)
        _reminderDays = State(initialValue: area.reminderIntervalDays)
    }

    private let intervalOptions = [0, 1, 3, 7, 14, 30]

    private func label(for days: Int) -> String {
        switch days {
        case 0: return "Off"
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Every 2 weeks"
        case 30: return "Monthly"
        default: return "Every \(days) days"
        }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Area name", text: $name)
            }

            Section {
                Picker("Remind me", selection: $reminderDays) {
                    ForEach(intervalOptions, id: \.self) { days in
                        Text(label(for: days)).tag(days)
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if notificationsDenied {
                    Text("Notifications are turned off for Cairn Skin. Enable them in the Settings app to use reminders.")
                } else {
                    Text("Counts from your last photo, not a fixed schedule, so taking one early won't leave you reminded anyway.")
                }
            }
        }
        .navigationTitle("Area Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task { await save() }
                }
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != area.name {
            store.renameArea(area, to: trimmed)
        }

        if reminderDays > 0 {
            // Ask for permission only at the moment the user turns a
            // reminder on. Prompting at launch, before they know what it's
            // for, gets denied reflexively — and iOS only asks once.
            let status = await ReminderScheduler.authorizationStatus()
            if status == .notDetermined {
                let granted = await ReminderScheduler.requestAuthorization()
                if !granted {
                    notificationsDenied = true
                    return
                }
            } else if status == .denied {
                notificationsDenied = true
                return
            }
        }

        await store.updateReminder(days: reminderDays, for: area)
        dismiss()
    }
}
