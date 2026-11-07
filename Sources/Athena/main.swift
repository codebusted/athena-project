import AppKit

// AppKit-managed lifecycle (rather than a SwiftUI App scene) so Athena fully controls when its single
// dashboard window appears: on login/wake only if today's tasks are incomplete, never duplicated.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
