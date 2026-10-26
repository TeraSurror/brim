import SwiftUI

/// The prompt bar across the top of the open panel, and the answer view that replaces the cards while a
/// conversation is showing.
struct QuickPromptView: View {
    @ObservedObject var module: QuickPromptModule
    @Environment(\.panelFocus) private var panelFocus
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar
            if module.isShowingConversation {
                conversation
            }
        }
        .onChange(of: panelFocus.isFocused) { _, focused in
            if focused { focusField() }
        }
        .onAppear {
            if panelFocus.isFocused { focusField() }
        }
    }

    /// The window becomes key just after the panel reports focus; asking earlier lets AppKit hand focus to
    /// the first control (the folder menu) instead of the field.
    private func focusField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 8) {
            folderMenu

            TextField(
                module.turns.isEmpty ? "Ask Claude…" : "Ask a follow-up…",
                text: $module.draft
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .focused($fieldFocused)
            .onSubmit { module.send() }
            // A click on the field is a request to type, the one click that may take keyboard focus.
            .simultaneousGesture(TapGesture().onEnded {
                if panelFocus.isFocused {
                    fieldFocused = true
                } else {
                    panelFocus.request()
                }
            })
            .accessibilityLabel("Prompt for Claude")

            if module.isRunning {
                Button(action: module.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help("Stop")
                .accessibilityLabel("Stop answering")
            } else {
                Button(action: module.send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(canSend ? 0.9 : 0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.4))
                .disabled(!canSend)
                .help("Send")
                .accessibilityLabel("Send prompt")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .frame(height: 32)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(fieldFocused ? 0.22 : 0.08)))
    }

    private var canSend: Bool {
        !module.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var folderMenu: some View {
        Menu {
            Button("No Folder (Plain Chat)") { module.choose(.scratch) }
            if !module.recentFolders.isEmpty {
                Section("Recent") {
                    ForEach(module.recentFolders, id: \.self) { url in
                        Button(url.lastPathComponent) { module.choose(.folder(url)) }
                    }
                }
            }
            Divider()
            Button("Choose Folder…") { module.chooseFolderWithPanel() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: folderSymbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(folderName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: 150)
        .help(folderHelp)
        .accessibilityLabel("Folder: \(folderName)")
    }

    private var folderName: String {
        switch module.folder {
        case .scratch: return "No folder"
        case .folder(let url): return url.lastPathComponent
        }
    }

    private var folderSymbol: String {
        if case .scratch = module.folder { return "bubble.left" }
        return "folder.fill"
    }

    private var folderHelp: String {
        switch module.folder {
        case .scratch: return "Plain chat: Claude has no files to read"
        case .folder(let url): return "Claude can read files in \(url.path)"
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(module.turns) { turn in
                            TurnView(turn: turn, onCopy: { module.copyAnswer(turn) })
                                .id(turn.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: module.turns.last?.answer) { _, _ in
                    if let last = module.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack(spacing: 10) {
                Button("New") { module.startNewConversation() }
                    .accessibilityLabel("New conversation")
                Spacer()
                Button("Done") { module.closeConversation() }
                    .accessibilityLabel("Back to the cards")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TurnView: View {
    let turn: PromptTurn
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.prompt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textSelection(.enabled)

            if !turn.answer.isEmpty {
                AnswerView(markdown: turn.answer)
            }

            status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var status: some View {
        switch turn.state {
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.white)
                Text(turn.activeTool.map { "\(Self.verb(for: $0))…" } ?? (turn.answer.isEmpty ? "Thinking…" : "Writing…"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .stopped:
            Text("Stopped")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        case .done:
            HStack(spacing: 10) {
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy answer")
                if let cost = turn.costUSD {
                    Text(cost, format: .currency(code: "USD").precision(.fractionLength(2...3)))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private static func verb(for tool: String) -> String {
        switch tool {
        case "Read": return "Reading files"
        case "Grep": return "Searching"
        case "Glob": return "Looking for files"
        default: return "Running \(tool)"
        }
    }
}

private struct AnswerView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inline(text).font(.system(size: 13))
        case .heading(let level, let text):
            inline(text).font(.system(size: level <= 2 ? 15 : 13, weight: .bold))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inline(text)
            }
            .font(.system(size: 13))
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").monospacedDigit()
                inline(text)
            }
            .font(.system(size: 13))
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return Text(attributed)
    }
}
