import AppKit
import Foundation

/// Opens a project folder in Finder. Kept behind `WorkspaceOpening` so tests can assert the path
/// without launching Finder.
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
}
