import Foundation

/// Where reminders are kept between launches.
protocol ReminderPersisting: Sendable {
    func load() -> [Reminder]
    func save(_ reminders: [Reminder])
}

/// Keeps reminders in `UserDefaults`, as JSON.
///
/// A list rather than a dictionary: a reminder is identified by a `UUID` that only
/// exists so a notification can carry it back, and sorting by creation keeps the
/// list stable for the reader.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` in the SDK
/// even though it is safe to use from several threads.
struct UserDefaultsReminderStore: ReminderPersisting, @unchecked Sendable {
    static let defaultKey = "reminders"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = UserDefaultsReminderStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [Reminder] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Reminder].self, from: data)) ?? []
    }

    func save(_ reminders: [Reminder]) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Store that only lives for as long as the process does, for tests and previews.
final class InMemoryReminderStore: ReminderPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var reminders: [Reminder]

    init(reminders: [Reminder] = []) {
        self.reminders = reminders
    }

    func load() -> [Reminder] {
        lock.lock()
        defer { lock.unlock() }
        return reminders
    }

    func save(_ reminders: [Reminder]) {
        lock.lock()
        defer { lock.unlock() }
        self.reminders = reminders
    }
}
