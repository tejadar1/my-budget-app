import BackgroundTasks
import Foundation
import UserNotifications

/// Local notifications: a nudge at 80% and 100% of a limit (once per
/// category per month) and a Sunday-evening weekly summary. Checked after
/// every sync, including background refreshes iOS schedules on its own.
enum Alerts {
    static let refreshTaskId = "com.tejadar1.upside.refresh"
    private static let limitsKey = "alertsLimits"
    private static let weeklyKey = "alertsWeekly"
    private static let lastWeeklyKey = "alertsLastWeekly"

    static var limitAlertsOn: Bool { UserDefaults.standard.object(forKey: limitsKey) as? Bool ?? true }
    static var weeklyOn: Bool { UserDefaults.standard.object(forKey: weeklyKey) as? Bool ?? true }
    static var billsOn: Bool { UserDefaults.standard.object(forKey: "alertsBills") as? Bool ?? true }
    static var lowBalanceOn: Bool { UserDefaults.standard.object(forKey: "alertsLowBalance") as? Bool ?? true }
    static var largeOn: Bool { UserDefaults.standard.object(forKey: "alertsLarge") as? Bool ?? true }
    static var paydayOn: Bool { UserDefaults.standard.object(forKey: "alertsPayday") as? Bool ?? true }
    /// Dollars; picked in Settings.
    static var lowBalanceThreshold: Cents { (UserDefaults.standard.object(forKey: "alertsLowBalanceAt") as? Int ?? 500) * 100 }
    static var largeThreshold: Cents { (UserDefaults.standard.object(forKey: "alertsLargeAt") as? Int ?? 300) * 100 }

    /// Ask once; iOS remembers the answer.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func check(_ store: BudgetStore, now: Date = Date()) async {
        guard !store.isDemo else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if limitAlertsOn {
            let pending = store.pendingLimitAlerts()
            for alert in pending {
                await post(
                    id: alert.key,
                    title: alert.percent >= 100 ? "\(alert.categoryName) is over its limit"
                                                : "\(alert.categoryName) is at 80%",
                    body: alert.percent >= 100 ? "\(Money.short(-alert.left)) over for this month."
                                               : "\(Money.short(alert.left)) left for the rest of the month.")
            }
            store.markAlertsSent(pending.map(\.key))
        }

        await scheduleBillReminders(store)

        if lowBalanceOn, let low = store.lowBalanceAlert(threshold: lowBalanceThreshold) {
            await post(id: low.key, title: low.title, body: low.body)
            store.markAlertsSent([low.key])
        }

        if largeOn {
            let large = store.largePurchases(threshold: largeThreshold)
            for t in large {
                let category = store.category(t.categoryId ?? "")?.name ?? "Uncategorized"
                await post(id: "large-\(t.id)", title: "\(Money.short(-t.amount)) at \(Merchant.clean(t.payee))",
                           body: "A bigger purchase than usual, in \(category).")
            }
            store.markAlertsSent(large.map { "large-\($0.id)" })
        }

        if paydayOn, let payday = store.paydayReminder() {
            await post(id: payday.keys[0], title: payday.title, body: payday.body)
            store.markAlertsSent(payday.keys)
        }

        if weeklyOn, isSummaryDue(now: now, calendar: store.calendar) {
            let month = store.currentMonth
            let limit = store.totalLimit(in: month)
            let spent = store.totalSpent(in: month)
            let body = limit > 0
                ? "\(Money.short(max(0, limit - spent))) left of \(Money.short(limit)) this month, \(store.daysLeftInMonth) days to go."
                : "\(Money.short(spent)) spent so far this month."
            await post(id: "weekly-\(Int(now.timeIntervalSince1970))", title: "Your week in Upside", body: body)
            UserDefaults.standard.set(now, forKey: lastWeeklyKey)
        }
    }

    /// Sunday after 5pm, once a week.
    static func isSummaryDue(now: Date, calendar: Calendar, last: Date? = UserDefaults.standard.object(forKey: lastWeeklyKey) as? Date) -> Bool {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let hour = calendar.component(.hour, from: now)
        guard weekday == 1, hour >= 17 else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) > 5 * 86_400
    }

    /// Bill reminders are scheduled ahead (9am two days before), so they
    /// arrive even if Upside isn't opened. Re-planned after every sync.
    @MainActor
    static func scheduleBillReminders(_ store: BudgetStore) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("bill-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard billsOn else { return }
        for reminder in store.billReminders() {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let parts = store.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    private static func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: Background refresh

    @MainActor
    static func backgroundRefresh(_ store: BudgetStore) async {
        scheduleRefresh()
        guard BankSync.isConnected else { return }
        try? await BankSync.sync(store: store)
        await check(store)
    }

    /// Ask iOS to wake Upside every few hours to sync and check alerts.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
