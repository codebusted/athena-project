import AppKit
import AthenaCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let showDashboardNotification = Notification.Name("com.athena.coach.showDashboard")

    private var store: AthenaStore!
    private var lifecycle: AppLifecycleManager!
    private var dashboard: DashboardViewModel!
    private var window: NSWindow?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }

        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        do {
            store = try AthenaStore.openDefault()
        } catch {
            // Never run on a throwaway database: progress would be silently lost. Explain and quit.
            let alert = NSAlert()
            alert.messageText = "Athena couldn't open its database"
            alert.informativeText = "\(error.localizedDescription)\n\n\(Database.defaultURL.path)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        lifecycle = AppLifecycleManager(store: store)
        dashboard = DashboardViewModel(store: store)
        dashboard.onCompletionChange = { [weak self] in self?.updateStatusItem() }

        installStatusItem()
        lifecycle.configureLaunchAtLoginOnFirstRun()

        // Any of these means the user is (back) at the screen.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(screenDidTurnOn), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenDidTurnOn), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showFromOtherInstance), name: Self.showDashboardNotification, object: nil)

        handle(AppLifecycleManager.detectLaunchTrigger())
        scheduleDebugSnapshot()
    }

    /// Dev aid: `ATHENA_SNAPSHOT=/path/out.png` renders the dashboard to a PNG after a delay (no screen-recording
    /// permission needed since the app draws its own view).
    private func scheduleDebugSnapshot() {
        guard let path = ProcessInfo.processInfo.environment["ATHENA_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["ATHENA_SNAPSHOT_DELAY"] ?? "") ?? 8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let size = window?.contentView?.bounds.size else { return }
            switch ProcessInfo.processInfo.environment["ATHENA_SNAPSHOT_PAGE"] {
            case "java": dashboard.show(.java)
            case "progress": dashboard.show(.progress)
            case "leetcode": dashboard.show(.leetcode)
            case "intro": dashboard.show(.intro)
            default: break
            }
            let content = DashboardView(model: dashboard, onSnooze: {}, scrolls: false)
                .frame(width: size.width)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// A second copy (e.g. launched directly from the binary) asks the first to show its window and exits.
    private func handOffToRunningInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            Self.showDashboardNotification, object: nil, userInfo: nil, deliverImmediately: true)
        NSApp.terminate(nil)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        handle(.manual)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func screenDidTurnOn(_ note: Notification) {
        // Give the network and Ollama a moment after wake before refreshing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.handle(.screenOn) }
    }

    @objc private func showFromOtherInstance(_ note: Notification) { handle(.manual) }

    private func handle(_ trigger: AppLifecycleManager.Trigger) {
        guard lifecycle.shouldShow(for: trigger) else {
            updateStatusItem()
            return
        }
        if trigger == .login || trigger == .screenOn { lifecycle.didAutoShow() }
        // If the window is already open, just bring it forward: never yank the user off a half-written answer.
        showDashboard(resetPage: !(window?.isVisible ?? false))
    }

    // MARK: Window

    /// Shows (or brings forward) the single dashboard window. `resetPage` returns to the start screen.
    private func showDashboard(resetPage: Bool) {
        if window == nil {
            var root = DashboardView(model: dashboard, onSnooze: { [weak self] in self?.snooze() })
            root.onContentHeightChange = { [weak self] height in self?.fitWindow(toContentHeight: height) }
            // Fixed width; the height follows the content of the current screen.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: DashboardView.width, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Athena"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            // Appear wherever the user is: on every desktop (Space), and on top of full-screen apps,
            // instead of only on the main desktop.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: root)
            // Athena sizes the window itself (fitWindow); don't let SwiftUI push the window past the screen.
            hosting.sizingOptions = []
            window.contentView = hosting
            self.window = window
            // Moving to another display, or changing resolution, changes how much room there is.
            NotificationCenter.default.addObserver(
                self, selector: #selector(updateAvailableHeight), name: NSWindow.didChangeScreenNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(updateAvailableHeight),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        let wasVisible = window?.isVisible ?? false
        updateAvailableHeight()
        dashboard.refresh()
        if resetPage { dashboard.showStart() }
        if !wasVisible {
            // Every fresh opening starts centred; the next content-driven resize re-centres at the final height.
            centerOnNextFit = true
            centerWindow()
            // After this, resizes keep the top edge in place so the window doesn't jump between screens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.centerOnNextFit = false }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Set when the window opens so it's centred once SwiftUI reports the screen's real height.
    private var centerOnNextFit = false

    private func centerWindow() {
        guard let window, let visible = (NSScreen.main ?? window.screen)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        window.setFrame(frame, display: true)
    }

    private func snooze() {
        lifecycle.snooze(hours: 1)
        window?.close()
    }

    /// Resizes the window to the SwiftUI content's natural height. Right after opening it is centred; after that it
    /// grows downward from the top edge so switching screens doesn't make it jump. Either way it never leaves the
    /// screen: if the bottom would go off-screen it slides up, and it is never taller than the screen.
    private func fitWindow(toContentHeight height: CGFloat) {
        guard let window, height > 0 else { return }
        let current = window.contentRect(forFrameRect: window.frame)
        var frame = window.frameRect(forContentRect: NSRect(
            x: current.minX, y: current.maxY - height, width: current.width, height: height))
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.height = min(frame.height, visible.height)
            // Layout settles over a few passes right after opening (header first, then the page), so keep
            // re-centring until the opening window closes rather than only on the first pass.
            // Re-centre while opening, or when growing from the top edge would push it off the bottom
            // (better than leaving it pinned against the screen edge).
            if centerOnNextFit || frame.minY < visible.minY {
                frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
            }
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        guard abs(frame.height - window.frame.height) > 0.5 || abs(frame.minY - window.frame.minY) > 0.5
                || abs(frame.minX - window.frame.minX) > 0.5 else { return }
        window.setFrame(frame, display: true)
    }

    /// A comfortable ceiling for the window, even on a tall screen; longer pages scroll inside it.
    static let maxWindowHeight: CGFloat = 780

    /// Tells the view how tall the window may get on its current screen, so long pages scroll instead of overflowing.
    @objc private func updateAvailableHeight() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let screenRoom = window.contentRect(forFrameRect: NSRect(origin: .zero, size: visible.size)).height
        dashboard.maxContentHeight = min(screenRoom, Self.maxWindowHeight)
    }

    // MARK: Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Athena")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let session = try? store.sessions.ensureSession(for: store.today)
        let done = session?.completedCount ?? 0
        let header = NSMenuItem(title: done == 2 ? "Today: all done" : "Today: \(done)/2 done", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Open Athena", #selector(openFromMenu), key: "o"))
        menu.addItem(item("Snooze 1 hour", #selector(snoozeFromMenu)))
        menu.addItem(.separator())
        let login = item("Open at Login", #selector(toggleLaunchAtLogin))
        login.state = lifecycle.launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Athena", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let done = (try? store.sessions.session(for: store.today))??.completedCount ?? 0
        button.title = done == 2 ? "" : " \(done)/2"
        button.imagePosition = .imageLeading
        button.contentTintColor = done == 2 ? .systemGreen : nil
    }

    @objc private func openFromMenu() { handle(.manual) }
    @objc private func snoozeFromMenu() { snooze() }

    @objc private func toggleLaunchAtLogin() {
        if let error = lifecycle.setLaunchAtLogin(!lifecycle.launchAtLoginEnabled) {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error + "\n\nMove Athena.app to /Applications and try again."
            alert.runModal()
        }
    }

    /// Accessory apps have no visible menu bar, but the main menu still routes ⌘C/⌘V/⌘W/⌘Z.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Athena", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}
