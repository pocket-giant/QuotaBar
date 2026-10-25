import Foundation

/// Small value type; existing preference keys remain compatible with earlier releases.
struct AppSettings: Equatable {
    var showFiveHourByDefault = true
    var replaceExhaustedWithCountdown = true
    var notifyFiveHourReset = true
    var notifyWeeklyReset = true
    var usageWarnings = true
    var warningThresholds = [80, 95]

    var notificationsEnabled: Bool { notifyFiveHourReset || notifyWeeklyReset || usageWarnings }

    static func load(from defaults: UserDefaults) -> Self {
        func enabled(_ key: String) -> Bool { defaults.object(forKey: key) == nil || defaults.bool(forKey: key) }
        return Self(
            showFiveHourByDefault: enabled("showFiveHourByDefault"),
            replaceExhaustedWithCountdown: enabled("replaceExhaustedWithCountdown"),
            notifyFiveHourReset: enabled("notifyFiveHourReset"),
            notifyWeeklyReset: enabled("notifyWeeklyReset"),
            usageWarnings: enabled("usageWarnings"),
            warningThresholds: ThresholdTracker.sanitizedThresholds(
                from: defaults.array(forKey: "notificationThresholds"), default: [80, 95]))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showFiveHourByDefault, forKey: "showFiveHourByDefault")
        defaults.set(replaceExhaustedWithCountdown, forKey: "replaceExhaustedWithCountdown")
        defaults.set(notifyFiveHourReset, forKey: "notifyFiveHourReset")
        defaults.set(notifyWeeklyReset, forKey: "notifyWeeklyReset")
        defaults.set(usageWarnings, forKey: "usageWarnings")
        defaults.set(warningThresholds, forKey: "notificationThresholds")
    }

    func initialDisplayMode(from defaults: UserDefaults) -> MenuBarDisplayMode {
        defaults.string(forKey: "menuBarDisplayMode").flatMap(MenuBarDisplayMode.init(rawValue:))
            ?? (showFiveHourByDefault ? .fiveHour : .sevenDay)
    }
}
