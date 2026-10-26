import UIKit
import UserNotifications

/// Receives reminder notifications while the app is running, and hands a tap to the
/// map.
///
/// A tap can arrive while the app is running, in the background, or as the reason it
/// was launched. The first is posted to whoever is listening; the other two are
/// parked in user defaults, because on a cold start there is nobody listening yet.
final class ReminderNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let pendingKey = "pendingReminderTap"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// A banner for a reminder while the app is open, rather than silence.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        // Parked first: a cold start reaches this before the map exists.
        UserDefaults.standard.set(info, forKey: Self.pendingKey)
        NotificationCenter.default.post(name: .reminderNotificationTapped, object: info)
    }
}
