import Foundation
import OSLog

struct MediaDiagnostics {
    let helperBundled: Bool
    let helperAvailable: Bool
    let followedPlayer: String?
    let track: String?
}

@MainActor
enum Diagnostics {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    static func report(
        settings: Settings,
        screens: ScreenProviding,
        media: MediaDiagnostics? = nil
    ) -> String {
        var lines = [
            "Brim \(appVersion)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "none")",
            "",
            "Screens:",
        ]
        for screen in screens.screens {
            let notch = screen.notchRect.map {
                "notch \(Int($0.minX))…\(Int($0.maxX)) h\(Int($0.height))"
            } ?? "no notch"
            lines.append(
                "  \(Int(screen.frame.width))×\(Int(screen.frame.height)) at "
                    + "(\(Int(screen.frame.minX)), \(Int(screen.frame.minY))), \(notch), topInset \(Int(screen.topInset))"
            )
        }

        if let media {
            lines += ["", "Media:"]
            lines.append("  helper: bundled \(media.helperBundled), available \(media.helperAvailable)")
            lines.append("  following: \(media.followedPlayer ?? "Automatic (macOS)")")
            lines.append("  now playing: \(media.track ?? "nothing")")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings), let json = String(data: data, encoding: .utf8) {
            lines += ["", "Settings:", json]
        }
        lines += ["", "Recent log:"] + recentLog()
        return lines.joined(separator: "\n")
    }

    private static func recentLog() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return ["  (unavailable)"] }
        let position = store.position(date: Date().addingTimeInterval(-3600))
        let entries = (try? store.getEntries(at: position)) ?? AnySequence([])
        let formatter = ISO8601DateFormatter()
        return entries
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Log.subsystem }
            .suffix(100)
            .map { "  \(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
    }
}
