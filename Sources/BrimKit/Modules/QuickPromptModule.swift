import AppKit
import Combine
import SwiftUI

/// Narrow surface `AppModel` needs: the persisted CLI override and recent folders, and what Settings shows.
@MainActor
public protocol QuickPromptControlling: AnyObject {
    var resolvedCLIPath: String? { get }
    func applyCLIPath(_ path: String?)
    func applyRecentFolders(_ paths: [String])
}

/// Where a prompt runs.
public enum PromptFolder: Equatable, Sendable {
    /// An empty folder in Application Support: plain chat, nothing to read.
    case scratch
    case folder(URL)
}

/// Quick Prompt (F19): a prompt bar over the cards that runs the user's own `claude -p` with read-only tools.
/// Brim makes no network request itself; Claude Code does, under the user's login.
@MainActor
public final class QuickPromptModule: BrimModule, QuickPromptControlling, ObservableObject {
    public static let moduleID = "prompt"
    public static let maxRecentFolders = 5

    public let id = QuickPromptModule.moduleID
    public let title = "Quick Prompt"
    public let symbolName = "text.bubble.fill"
    public let requiredPermissions: [PermissionKind] = []
    public let permissionExplanation = """
        Quick Prompt runs the claude command you already use, with your Claude login. It can only read files \
        in the folder you pick (Read, Grep and Glob): it can't edit files, run commands or use MCP servers. \
        Your prompt, and anything Claude reads, goes to Anthropic through Claude Code, not through Brim.
        """
    public var explainsBeforeEnabling: Bool { true }
    public var placement: ModulePlacement { .bar }

    @Published public var draft = ""
    @Published public private(set) var turns: [PromptTurn] = []
    @Published public private(set) var folder: PromptFolder = .scratch
    @Published public private(set) var recentFolders: [URL] = []
    /// The answer view is up and the cards have stepped aside.
    @Published public private(set) var isShowingConversation = false
    @Published public private(set) var liveActivity: LiveActivity?
    @Published public private(set) var isEnabled = false

    /// The project of the most recent agent session (F7), used as the default folder.
    public var defaultFolderPath: () -> String? = { nil }
    public var onRecentFoldersChange: (([String]) -> Void)?
    /// Shows a folder panel; set by the composition root so the module never opens windows itself.
    public var chooseFolderPanel: () -> URL? = { nil }

    private let runner: PromptRunning
    private let locator: ClaudeCLILocating
    private let scratchDirectory: URL
    private var cliPathOverride: String?
    private var sessionID: String?
    private var running: TaskHandle?
    private var folderChosen = false
    private var panelActive = false
    /// A run finished while the panel was closed; the notch shows it until the panel opens.
    private var unread = false

    public init(
        runner: PromptRunning? = nil,
        locator: ClaudeCLILocating? = nil,
        scratchDirectory: URL? = nil
    ) {
        self.runner = runner ?? ClaudeCLIRunner()
        self.locator = locator ?? ClaudeCLILocator()
        self.scratchDirectory = scratchDirectory ?? Self.defaultScratchDirectory
    }

    nonisolated public static var defaultScratchDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brim/Quick Prompt", isDirectory: true)
    }

    public var isRunning: Bool { running != nil }

    public var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> {
        $liveActivity.eraseToAnyPublisher()
    }

    public var fillsPanelPublisher: AnyPublisher<Bool, Never> {
        $isShowingConversation.eraseToAnyPublisher()
    }

    // MARK: - Lifecycle

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            startNewConversation()
        }
    }

    public func setPanelActive(_ active: Bool) {
        panelActive = active
        guard active else { return }
        unread = false
        updateLiveActivity()
        if !folderChosen, turns.isEmpty {
            folder = Self.existingFolder(defaultFolderPath()).map(PromptFolder.folder) ?? .scratch
        }
    }

    public func liveView(_ edge: LiveActivityEdge) -> AnyView {
        AnyView(QuickPromptLiveView(module: self, edge: edge))
    }

    public func expandedView() -> AnyView {
        AnyView(QuickPromptView(module: self))
    }

    // MARK: - Settings

    public var resolvedCLIPath: String? {
        locator.locate(override: cliPathOverride)?.path
    }

    public func applyCLIPath(_ path: String?) {
        cliPathOverride = path?.isEmpty == true ? nil : path
    }

    public func applyRecentFolders(_ paths: [String]) {
        recentFolders = paths.compactMap(Self.existingFolder).prefix(Self.maxRecentFolders).map { $0 }
    }

    // MARK: - Folder

    /// Claude Code keeps conversations per folder, so a different folder starts a new conversation.
    public func choose(_ choice: PromptFolder) {
        folderChosen = true
        guard choice != folder else { return }
        if !turns.isEmpty { startNewConversation() }
        folder = choice
        if case .folder(let url) = choice { remember(url) }
    }

    public func chooseFolderWithPanel() {
        guard let url = chooseFolderPanel() else { return }
        choose(.folder(url))
    }

    private func remember(_ url: URL) {
        var folders = recentFolders.filter { $0.standardizedFileURL != url.standardizedFileURL }
        folders.insert(url, at: 0)
        recentFolders = Array(folders.prefix(Self.maxRecentFolders))
        onRecentFoldersChange?(recentFolders.map(\.path))
    }

    private static func existingFolder(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Conversation

    public func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !prompt.isEmpty, running == nil else { return }
        draft = ""
        isShowingConversation = true

        var turn = PromptTurn(prompt: prompt)
        guard let executable = locator.locate(override: cliPathOverride) else {
            turn.state = .failed("Brim can't find the claude command. Install Claude Code, or choose it in Settings → Agents.")
            turns.append(turn)
            return
        }
        guard let directory = workingDirectory() else {
            turn.state = .failed("Brim couldn't open the folder for this prompt.")
            turns.append(turn)
            return
        }
        turns.append(turn)

        let turnID = turn.id
        let request = PromptRequest(prompt: prompt, folder: directory, resumeSessionID: sessionID)
        running = runner.run(request, executable: executable) { [weak self] event in
            self?.handle(event, turnID: turnID)
        }
        updateLiveActivity()
    }

    public func stop() {
        running?.cancel()
    }

    /// Esc or Done: back to the cards. The conversation is kept, so the next prompt continues it.
    public func closeConversation() {
        isShowingConversation = false
    }

    public func handleEscape() -> Bool {
        guard isShowingConversation else { return false }
        closeConversation()
        return true
    }

    public func showConversation() {
        guard !turns.isEmpty else { return }
        isShowingConversation = true
    }

    public func startNewConversation() {
        running?.cancel()
        running = nil
        turns.removeAll()
        sessionID = nil
        isShowingConversation = false
        unread = false
        updateLiveActivity()
    }

    public func copyAnswer(_ turn: PromptTurn) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(turn.answer, forType: .string)
    }

    private func workingDirectory() -> URL? {
        switch folder {
        case .folder(let url):
            return url
        case .scratch:
            do {
                try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
                return scratchDirectory
            } catch {
                Log.agent.error("Quick prompt scratch folder failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func handle(_ event: PromptEvent, turnID: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        switch event {
        case .started(let session):
            sessionID = session
        case .text(let text):
            turns[index].answer += text
            turns[index].activeTool = nil
        case .tool(let name):
            turns[index].activeTool = name
        case .turnBreak:
            let answer = turns[index].answer
            if !answer.isEmpty, !answer.hasSuffix("\n\n") {
                turns[index].answer += answer.hasSuffix("\n") ? "\n" : "\n\n"
            }
        case .finished(let result):
            running = nil
            turns[index].activeTool = nil
            turns[index].costUSD = result.costUSD
            if let session = result.sessionID { sessionID = session }
            if result.isError {
                turns[index].state = .failed(result.message)
            } else if result.message == "Stopped." {
                turns[index].state = .stopped
            } else {
                turns[index].state = .done
                if turns[index].answer.isEmpty { turns[index].answer = result.message }
            }
            if !panelActive { unread = true }
            updateLiveActivity()
        }
    }

    /// Quiet glyphs only: a run in progress, or an answer that arrived while the panel was closed.
    private func updateLiveActivity() {
        let next: LiveActivity? = running != nil || unread ? LiveActivity(priority: .ambient) : nil
        if next != liveActivity { liveActivity = next }
    }

    /// The state the notch glyph shows.
    public var liveState: PromptTurn.State? {
        if running != nil { return .running }
        guard unread else { return nil }
        return turns.last?.state
    }
}
