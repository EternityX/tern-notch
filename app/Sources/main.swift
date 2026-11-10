import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if others.contains(where: { $0 != me && $0.processIdentifier < me.processIdentifier && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        store.start()
        SettingsWindow.shared.store = store
        controller = NotchController(store: store)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == ternBundleID {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
