import AppKit

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let controller = AppController()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.mainMenu = self.makeMainMenu()
            AppEnvironment.shared.controller.start()
        }
    }

    /// Registered `brim://agent` URLs land here, both when Brim is already running and when a hook
    /// launches it. The controller validates the URL before it reaches the agent module.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                AppEnvironment.shared.controller.handle(url)
            }
        }
    }

    /// Brim has no Dock or menu bar icon, so opening it again from Finder or Spotlight is how people look
    /// for it. Show Settings instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppEnvironment.shared.controller.openSettings()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.controller.stop()
        }
    }

    /// An agent app shows no menu bar of its own, but its windows still need the standard key equivalents
    /// (copy, paste, close, quit) and those come from the main menu.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Brim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
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
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)

        return main
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.controller.openSettings()
        }
    }
}

/// Starts Brim without SwiftUI's `App` lifecycle. That lifecycle requires a scene, and its only scene that
/// doesn't open a window at launch (`Settings`) still opens an empty window of its own when triggered.
public enum BrimLauncher {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // matches LSUIElement
        app.delegate = delegate
        app.run()
    }
}
