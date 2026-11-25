import Foundation
import UserNotifications

final class ReminderManager {
    private static let key = "weeklyCleanReminderEnabled"
    private static let notifID = "com.local.macsweeper.weeklyReminder"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        let center = UNUserNotificationCenter.current()
        if enabled {
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "Weekly MacSweeper Checkup"
                content.body = "Open MacSweeper to clear browser caches, duplicates, and system junk."
                content.sound = .default

                var date = DateComponents()
                date.weekday = 1 // Sunday
                date.hour = 10
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                let req = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)
                center.add(req)
            }
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [notifID])
        }
    }
}
