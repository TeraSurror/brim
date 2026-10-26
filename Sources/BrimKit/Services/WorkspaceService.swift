import AppKit
import Foundation

/// Opens a project folder in Finder or brings the app running a session forward. Kept behind
/// `WorkspaceOpening` so tests can assert the target without launching anything.
@MainActor
public final class WorkspaceService: WorkspaceOpening {
    public init() {}

    public func openDirectory(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.agent.error("Project path no longer exists: \(path, privacy: .public)")
            return false
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            Log.agent.error("Could not open project at \(path, privacy: .public)")
        }
        return opened
    }

    /// Opening the app's bundle through Launch Services activates it reliably even though Brim itself is
    /// never the active app; `NSRunningApplication.activate` is ignored for inactive callers on macOS 14+.
    public func activateApplication(bundleIdentifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            Log.agent.info("No installed app for \(bundleIdentifier, privacy: .public)")
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.agent.error("Could not activate \(bundleIdentifier, privacy: .public): \(error.localizedDescription)")
            }
        }
        return true
    }
}
