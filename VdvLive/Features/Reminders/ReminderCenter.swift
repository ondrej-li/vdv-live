import Foundation
import Observation
import UserNotifications

/// Owns the reminders: what the user asked for, what is scheduled, and what could
/// not be scheduled because its timetable is not on the device.
///
/// Scheduling is a re-computation rather than a running timer: every time the app
/// comes to the front, or a reminder changes, the whole pending set is rebuilt from
/// the timetables. That is what makes the notifications survive a reboot, a
/// republished archive and a phone that was asleep for three days.
@MainActor
@Observable
final class ReminderCenter {
    private(set) var reminders: [Reminder]
    /// Lines whose reminder could not be scheduled because their timetable is not
    /// downloaded.
    private(set) var missingTimetableLines: Set<String> = []
    /// Whether the user said no to notifications.
    private(set) var isDenied = false
    /// Set by a notification tap, and read by the map to open what was tapped.
    var pendingTarget: ReminderTarget?

    private let store: ReminderPersisting
    private let notifier: ReminderNotifying
    private let timetables: LineTimetableStore
    private let now: () -> Date

    init(store: ReminderPersisting = UserDefaultsReminderStore(),
         notifier: ReminderNotifying = UserNotificationCentre(),
         timetables: LineTimetableStore,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.notifier = notifier
        self.timetables = timetables
        self.now = now
        self.reminders = store.load()
    }

    /// What a notification tap asks the map to open.
    struct ReminderTarget: Equatable, Sendable {
        let lineNumber: String
        let serviceNumber: String
        let stopName: String
    }

    // MARK: - Editing

    func reminder(forLine lineNumber: String,
                  serviceNumber: String,
                  stopName: String) -> Reminder? {
        reminders.first {
            $0.lineNumber == lineNumber
                && $0.serviceNumber == serviceNumber
                && $0.stopName == stopName
        }
    }

    func save(_ reminder: Reminder) async {
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        reminders.sort {
            $0.lineNumber == $1.lineNumber
                ? $0.serviceNumber.compare($1.serviceNumber, options: .numeric) == .orderedAscending
                : $0.lineNumber < $1.lineNumber
        }
        store.save(reminders)
        await scheduleAll()
    }

    func remove(_ reminder: Reminder) async {
        reminders.removeAll { $0.id == reminder.id }
        store.save(reminders)
        await notifier.cancel(reminderID: reminder.id.uuidString)
        await scheduleAll()
    }

    // MARK: - Scheduling

    /// Rebuilds every pending notification from the timetables on the device.
    ///
    /// Runs on launch, on returning to the foreground and after any edit: a
    /// reminder is only as good as the last time it was computed, and computing it
    /// is cheap - the timetables are on disk and the arithmetic is a few hundred
    /// days at most.
    func scheduleAll() async {
        guard !reminders.isEmpty else {
            await notifier.replaceAll(with: [])
            missingTimetableLines = []
            return
        }

        var timetablesByLine: [String: LineTimetable] = [:]
        var missing: Set<String> = []
        for lineNumber in Set(reminders.map(\.lineNumber)) {
            do {
                if let timetable = try await timetables.timetable(forLine: lineNumber) {
                    timetablesByLine[lineNumber] = timetable
                } else {
                    missing.insert(lineNumber)
                }
            } catch {
                missing.insert(lineNumber)
            }
        }

        let planned = ReminderPlanner.notifications(for: reminders,
                                                    timetables: timetablesByLine,
                                                    now: now())
        await notifier.replaceAll(with: planned)
        missingTimetableLines = missing
        isDenied = await notifier.authorizationStatus() == .denied
    }

    /// Asks for permission the first time a reminder is created. A refusal is not an
    /// error: the reminder is kept, and the screen says why nothing will arrive.
    func requestPermissionIfNeeded() async {
        guard await notifier.authorizationStatus() == .notDetermined else { return }
        _ = await notifier.requestAuthorization()
    }

    /// Reads the tap a cold start was caused by, and forgets it.
    ///
    /// The app delegate cannot reach this object on launch - the view that owns it
    /// does not exist yet - so the tap is parked in user defaults instead.
    static func consumePendingTap(defaults: UserDefaults = .standard,
                                  key: String = "pendingReminderTap") -> ReminderTarget? {
        defer { defaults.removeObject(forKey: key) }
        guard let stored = defaults.dictionary(forKey: key),
              let line = stored[PlannedNotification.Key.line] as? String,
              let service = stored[PlannedNotification.Key.service] as? String,
              let stop = stored[PlannedNotification.Key.stop] as? String else { return nil }
        return ReminderTarget(lineNumber: line, serviceNumber: service, stopName: stop)
    }

    /// Reads a notification tap back into the thing it was about.
    func handleTap(userInfo: [AnyHashable: Any]) {
        guard let line = userInfo[PlannedNotification.Key.line] as? String,
              let service = userInfo[PlannedNotification.Key.service] as? String,
              let stop = userInfo[PlannedNotification.Key.stop] as? String else { return }
        pendingTarget = ReminderTarget(lineNumber: line,
                                       serviceNumber: service,
                                       stopName: stop)
    }
}

extension Notification.Name {
    /// Posted by the app delegate when a reminder notification is tapped. Carries
    /// the notification's `userInfo` as the object.
    static let reminderNotificationTapped = Notification.Name("reminderNotificationTapped")
}
