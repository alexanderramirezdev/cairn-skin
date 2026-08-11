//
//  ReminderScheduler.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Schedules local notifications reminding the user to photograph an area
//  they haven't captured in a while.
//
//  WHY LOCAL NOTIFICATIONS AND NOT PUSH:
//  Push notifications need a server, a device token, and an account to
//  associate them with, which would collapse the local-only privacy model
//  the whole app is built around. Local notifications are scheduled by
//  the app and fired by iOS on the same device. Nothing leaves the phone,
//  and no infrastructure is required.
//
//  WHY REMINDERS AND NOT "TIPS":
//  A reminder makes no claim about the user's skin. It says a number of
//  days has passed, which is a fact about the calendar rather than a
//  judgment about a body. Skin care advice would have moved this app from
//  observation into recommendation, which is the line it deliberately
//  doesn't cross.
//

import Foundation
import UserNotifications

enum ReminderScheduler {

    /// Identifier prefix so reminders can be found and cancelled per area.
    private static func identifier(for areaID: UUID) -> String {
        "cairnskin.reminder.\(areaID.uuidString)"
    }

    /// Asks for notification permission. Returns whether it was granted.
    ///
    /// Called only when the user actually turns a reminder on, never at
    /// launch. A permission prompt that appears before the person has any
    /// idea why gets denied reflexively, and iOS only asks once.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Schedules a repeating reminder for one area.
    ///
    /// The interval counts from the last photo, not from a fixed calendar
    /// date, so someone who captures early doesn't get nagged on schedule
    /// anyway. Re-scheduling on each new capture is what keeps it aligned.
    static func schedule(for area: TrackingArea, intervalDays: Int, lastCapture: Date?) async {
        cancel(for: area)
        guard intervalDays > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = area.name
        content.body = intervalDays == 1
            ? "It's been a day since your last photo."
            : "It's been \(intervalDays) days since your last photo."
        content.sound = .default

        // Fire at the interval measured from the most recent photo. If the
        // area has no photos yet, count from now.
        let anchor = lastCapture ?? Date()
        let fireDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: anchor) ?? Date()

        // If that moment has already passed (the user is overdue), nudge
        // shortly rather than firing instantly, which would feel like a
        // glitch right after changing a setting.
        let interval = max(fireDate.timeIntervalSinceNow, 60 * 60)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: area.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(for area: TrackingArea) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: area.id)])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
