import Foundation

/// Reads Claude Code's `--output-format stream-json --include-partial-messages` output, one JSON object per
/// line. Unknown lines are skipped, so a newer CLI that adds event types keeps working.
public enum ClaudeStreamParser {
    public static func events(fromLine line: String) -> [PromptEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init", let session = object["session_id"] as? String else {
                return []
            }
            return [.started(sessionID: session)]
        case "stream_event":
            return streamEvents(object["event"] as? [String: Any] ?? [:])
        case "result":
            return [.finished(result(from: object))]
        default:
            return []
        }
    }

    private static func streamEvents(_ event: [String: Any]) -> [PromptEvent] {
        switch event["type"] as? String {
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            guard delta["type"] as? String == "text_delta", let text = delta["text"] as? String, !text.isEmpty else {
                return []
            }
            return [.text(text)]
        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            guard block["type"] as? String == "tool_use", let name = block["name"] as? String else { return [] }
            return [.tool(name)]
        case "message_start":
            return [.turnBreak]
        default:
            return []
        }
    }

    private static func result(from object: [String: Any]) -> PromptResult {
        let isError = object["is_error"] as? Bool ?? (object["subtype"] as? String != "success")
        let message = (object["result"] as? String)
            ?? (object["errors"] as? [String])?.joined(separator: "\n")
            ?? (isError ? "Claude Code stopped with an error." : "")
        return PromptResult(
            isError: isError,
            message: message,
            sessionID: object["session_id"] as? String,
            costUSD: object["total_cost_usd"] as? Double
        )
    }
}
