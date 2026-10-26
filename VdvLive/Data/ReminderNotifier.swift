import Foundation
import UserNotifications

/// One notification the app wants the system to deliver.
///
/// A value rather than a `UNNotificationRequest`, so that everything that decides
/// *what* is sent can be tested without a notification centre, a permission prompt
/// or a device.
struct PlannedNotification: Equatable, Sendable {
    /// Stable per reminder and fire moment, so scheduling twice replaces rather
    /// than duplicates.
    let identifier: String
    let fireAt: DateComponents
    let title: String
    let body: String
    /// What tapping it should open: the line, the run and the stop.
    let userInfo: [String: String]

    enum Key {
        static let line = "line"
        static let service = "service"
        static let stop = "stop"
        static let reminder = "reminder"
    }
}

/// The app's side of the notification centre.
protocol ReminderNotifying: Sendable {
    /// Whether the user has already answered the permission prompt.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Asks for permission. Returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Replaces every pending reminder notification with `notifications`.
    func replaceAll(with notifications: [PlannedNotification]) async
    /// Removes the notifications of one reminder.
    func cancel(reminderID: String) async
}

/// The real thing: `UNUserNotificationCenter`.
///
/// Local notifications only - the app has no server, so there is nothing that could
/// arrive from elsewhere. The consequence, recorded in `docs/reminders.md`, is that
/// what a notification says is what was true when it was scheduled.
struct UserNotificationCentre: ReminderNotifying {
    /// Category the reminder notifications belong to, so the app can recognise a
    /// tap and read `userInfo` without guessing.
    static let category = "reminder"

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replaceAll(with notifications: [PlannedNotification]) async {
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: await pendingReminderIdentifiers())

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.userInfo = notification.userInfo
            content.categoryIdentifier = Self.category
            // A bus a few minutes away is exactly what this level is for: it gets
            // through a Focus mode that would otherwise swallow it.
            content.interruptionLevel = .timeSensitive
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: notification.fireAt,
                                                        repeats: false)
            let request = UNNotificationRequest(identifier: notification.identifier,
                                                content: content,
                                                trigger: trigger)
            try? await centre.add(request)
        }
    }

    func cancel(reminderID: String) async {
        let centre = UNUserNotificationCenter.current()
        let identifiers = await pendingReminderIdentifiers()
            .filter { $0.hasPrefix("\(reminderID).") }
        centre.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Identifiers of everything this app has pending that belongs to a reminder.
    private func pendingReminderIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == Self.category }
            .map(\.identifier)
    }
}
