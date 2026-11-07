import AppKit
import AthenaCore
import ServiceManagement

/// Decides when the dashboard may appear on its own. Manual opens always show it; automatic triggers
/// (login, screen on) show it whenever today's tasks are incomplete, unless snoozed.
@MainActor
final class AppLifecycleManager {
    enum Trigger: String {
        case login     // launched at login by the login item
        case launch    // launched by the user (Finder, Spotlight, `open`)
        case screenOn  // system wake, display wake or screen unlock
        case manual    // menu bar "Open Athena", Dock/Finder reopen
    }

    /// One screen-on usually fires several notifications (wake, display wake, unlock) within seconds;
    /// treat those as a single event.
    static let screenOnDebounce: TimeInterval = 30

    private let store: AthenaStore
    private var lastAutoShownAt: Date?

    init(store: AthenaStore) { self.store = store }

    func shouldShow(for trigger: Trigger, now: Date = Date()) -> Bool {
        switch trigger {
        case .manual, .launch:
            return true
        case .login, .screenOn:
            guard let session = try? store.sessions.ensureSession(for: store.today), !session.isComplete else { return false }
            if isSnoozed(now: now) { return false }
            if trigger == .screenOn, let shown = lastAutoShownAt, now.timeIntervalSince(shown) < Self.screenOnDebounce {
                return false
            }
            return true
        }
    }

    func didAutoShow(at date: Date = Date()) { lastAutoShownAt = date }

    // MARK: Snooze (persisted so it survives restarts)

    func snooze(hours: Double) {
        let until = Date().addingTimeInterval(hours * 3600)
        try? store.preferences.set(.snoozeUntil, Timestamps.string(from: until))
    }

    private func isSnoozed(now: Date) -> Bool {
        guard let raw = try? store.preferences.get(.snoozeUntil), let until = Timestamps.date(from: raw) else { return false }
        return until > now
    }

    // MARK: Launch reason

    /// Login-item launches carry `keyAELaunchedAsLogInItem` in the open-application Apple Event. As a fallback,
    /// a launch within a few minutes of boot is treated as a login launch.
    static func detectLaunchTrigger() -> Trigger {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == kAEOpenApplication,
           event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return .login
        }
        return ProcessInfo.processInfo.systemUptime < 180 ? .login : .launch
    }

    // MARK: Login item (SMAppService)

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Login items registered from a temporary build folder break when it moves, so only auto-enable once
    /// the app lives in an Applications folder. The user's later choice is always respected.
    func configureLaunchAtLoginOnFirstRun() {
        guard (try? store.preferences.get(.autostartConfigured)) == nil else { return }
        let path = Bundle.main.bundlePath
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard installed, Bundle.main.bundleIdentifier != nil else { return }
        if (try? SMAppService.mainApp.register()) != nil {
            try? store.preferences.set(.autostartConfigured, "yes")
        }
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            try? store.preferences.set(.autostartConfigured, "yes")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
