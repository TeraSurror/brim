import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            MediaSettingsTab()
                .tabItem { Label("Media", systemImage: "play.circle") }
                .tag(SettingsTab.media)
            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "sparkles") }
                .tag(SettingsTab.agents)
            ModulesSettingsTab()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.modules)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 560)
    }
}

/// Shown at the top of a module's tab while that module is off, so its options are never a dead end.
private struct ModuleOffNotice: View {
    @EnvironmentObject var model: AppModel
    let moduleID: String
    let title: String
    let message: String

    var body: some View {
        if !model.isModuleEnabled(moduleID) {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "power.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Turn On \(title)") {
                        model.setModuleEnabled(moduleID, true)
                    }
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            if model.showsWelcome {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Brim lives in your notch").font(.headline)
                            Text("Move the pointer to the notch to open the panel. While music plays or an agent needs you, the notch shows it on both sides. Right-click the panel for Settings and Quit, or open Brim again from Finder or Spotlight to come back here.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("Got It") { model.showsWelcome = false }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Picker("Open the panel", selection: $model.settings.opensOnHover) {
                    Text("On hover").tag(true)
                    Text("On click").tag(false)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Open the panel")

                LabeledContent("Hover delay") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.hoverDelay, in: Settings.hoverDelayRange, step: 0.05)
                            .frame(width: 190)
                            .accessibilityLabel("Hover delay")
                            .accessibilityValue("\(milliseconds(model.settings.hoverDelay)) milliseconds")
                        Text("\(milliseconds(model.settings.hoverDelay)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                .disabled(!model.settings.opensOnHover)

                LabeledContent("Collapse delay") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.collapseDelay, in: Settings.collapseDelayRange, step: 0.05)
                            .frame(width: 190)
                            .accessibilityLabel("Collapse delay")
                            .accessibilityValue("\(milliseconds(model.settings.collapseDelay)) milliseconds")
                        Text("\(milliseconds(model.settings.collapseDelay)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            } header: {
                Text("Panel")
            } footer: {
                Text("The panel closes when the pointer leaves it. Changes save automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show activity beside the notch", isOn: $model.settings.showLiveActivity)
                    .accessibilityLabel("Show activity beside the notch")
                Picker("Show Brim on", selection: $model.settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .accessibilityLabel("Show Brim on")
            } header: {
                Text("Notch")
            } footer: {
                Text("While media plays or an agent needs you, the notch widens to show it, so you can see it without opening the panel. A display without a notch gets a slim handle at the top, which becomes a small pill when something is live. With the lid closed, \"Only the notched display\" uses the main display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Open Brim") {
                    ShortcutRecorder(
                        shortcut: model.settings.openPanelShortcut,
                        isRecording: $model.isRecordingShortcut,
                        onRecord: { model.setOpenPanelShortcut($0) },
                        onClear: { model.setOpenPanelShortcut(nil) }
                    )
                }
                if let error = model.shortcutError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Opens the panel on the display under the pointer, ready for the keyboard, without switching away from your app. Esc, the shortcut again or a click elsewhere closes it. No permission is needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .accessibilityLabel("Launch at login")
                if let error = model.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Startup")
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cursorarrow.motionlines")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Brim never asks for a permission at launch. Features ask only when you turn them on, with an explanation first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshLaunchAtLogin()
        }
    }

    private func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }
}

// MARK: - Media

private struct MediaSettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            ModuleOffNotice(
                moduleID: MediaModule.moduleID,
                title: "Now Playing",
                message: "Now Playing is off. Turning it on needs no permission."
            )

            Section {
                Picker(
                    "Follow",
                    selection: Binding(
                        get: { model.settings.preferredPlayerBundleID ?? "" },
                        set: { value in
                            let sourceID = value.isEmpty ? nil : value
                            model.setPreferredPlayer(sourceID)
                            // Choosing a player is the moment Automation becomes useful; the footer below
                            // is the in-app explanation and macOS only asks for a running player.
                            if sourceID != nil {
                                Task { await model.requestAutomationPermission() }
                            }
                        }
                    )
                ) {
                    Text("Automatic (macOS)").tag("")
                    ForEach(model.mediaSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .accessibilityLabel("Player to follow")

                HStack(spacing: 8) {
                    Image(systemName: automationStatus.symbol)
                        .foregroundStyle(automationStatus.color)
                        .accessibilityHidden(true)
                    Text(automationStatus.label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if model.automationStatus != .granted {
                        Button("Grant Automation…") {
                            Task { await model.requestAutomationPermission() }
                        }
                        .accessibilityLabel("Grant Automation permission")
                    }
                }
            } header: {
                Text("Player")
            } footer: {
                Text("Automatic shows whatever macOS reports as Now Playing, including Safari and Chrome, and needs no permission. Choosing Spotify or Music lets Brim follow that player when several are playing; macOS then asks for Automation so Brim can read and control it. If you decline, Brim keeps following macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshAutomationStatus() }
    }

    private var automationStatus: (label: String, symbol: String, color: Color) {
        switch model.automationStatus {
        case .granted:
            ("Automation allowed", "checkmark.circle.fill", .green)
        case .denied:
            ("Automation denied — following macOS only", "exclamationmark.circle.fill", .orange)
        case .restricted:
            ("Automation restricted by macOS", "exclamationmark.circle.fill", .orange)
        case .unavailable:
            ("Start Spotify or Music to grant Automation", "info.circle", .secondary)
        case .notDetermined:
            ("Automation not granted yet", "circle.dashed", .secondary)
        }
    }
}

// MARK: - Agents

private struct AgentsSettingsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var showNotificationExplanation = false
    @State private var confirmHookInstall = false
    @State private var confirmHookRemoval = false

    var body: some View {
        Form {
            ModuleOffNotice(
                moduleID: AgentModule.moduleID,
                title: "Agent Status",
                message: "Agent Status is off. Turning it on opens a local socket; nothing leaves the Mac."
            )

            Section {
                HStack(spacing: 8) {
                    Image(systemName: hookStatus.symbol)
                        .foregroundStyle(hookStatus.color)
                        .accessibilityHidden(true)
                    Text(hookStatus.label)
                        .font(.callout)
                    Spacer(minLength: 8)
                    switch model.claudeHookStatus {
                    case .notInstalled?:
                        Button("Connect…") { confirmHookInstall = true }
                    case .outdated?:
                        Button("Update…") { confirmHookInstall = true }
                    case .installed?:
                        Button("Disconnect…") { confirmHookRemoval = true }
                    default:
                        EmptyView()
                    }
                }
                if let error = model.claudeHookError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Claude Code reports when it is working, needs your input or has finished. Start a new Claude Code session after connecting; running sessions keep their old hooks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Alert when an agent needs input or fails", isOn: notificationBinding)
                    .accessibilityLabel("Alert when an agent needs input or fails")

                if model.agentNotificationAuthorization == .denied {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("macOS banners are off; Brim will show a notch alert instead.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Open Settings…") { model.openNotificationSettings() }
                            .accessibilityLabel("Open Notification settings")
                    }
                } else if let error = model.agentNotificationError {
                    Label(error, systemImage: "info.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("The notch lights up whenever an agent needs you. Alerts add a card under the notch, or a macOS banner when notifications are allowed, while the panel is closed. Clicking one switches to the app running the session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Keep finished sessions", selection: $model.settings.agentFinishedRetentionMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("5 minutes").tag(5.0)
                    Text("10 minutes").tag(10.0)
                    Text("15 minutes").tag(15.0)
                    Text("30 minutes").tag(30.0)
                    Text("1 hour").tag(60.0)
                    Text("2 hours").tag(120.0)
                }
                .accessibilityLabel("Keep finished agent sessions")

                HStack(spacing: 8) {
                    Button("Show a Test Session") { model.showTestAgentSession() }
                        .disabled(!model.isModuleEnabled(AgentModule.moduleID))
                    Button("Clear Finished") { model.clearFinishedAgentSessions() }
                        .accessibilityLabel("Clear finished agent sessions")
                    Spacer()
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Finished and failed sessions clear automatically; working ones stay until they report again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Event socket") {
                    HStack(spacing: 6) {
                        Text(model.agentSocketPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button {
                            model.copyAgentSocketPath()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy the agent socket path")
                        .accessibilityLabel("Copy agent socket path")
                    }
                }
            } header: {
                Text("Other tools")
            } footer: {
                Text("Codex, Cursor, editor extensions and scripts can report by writing one JSON line to this socket or opening a brim://agent link. See the README for the fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            QuickPromptSettingsSection()
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshClaudeHook()
            Task { await model.refreshAgentNotificationAuthorization() }
        }
        .alert("Enable agent alerts?", isPresented: $showNotificationExplanation) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") {
                Task { await model.requestAgentNotificationPermission() }
            }
        } message: {
            Text("Brim will show a small alert under the notch when an agent is waiting for you or has failed, but only while the panel is closed. It will also use a macOS banner when notifications are allowed. Nothing leaves the Mac.")
        }
        .alert("Connect Claude Code?", isPresented: $confirmHookInstall) {
            Button("Cancel", role: .cancel) {}
            Button("Connect") { model.installClaudeHook() }
        } message: {
            Text("Brim will write ~/.brim/claude-hook.sh and add hooks for session start, prompts, tool use, notifications and stop to ~/.claude/settings.json. A backup of that file is saved next to it first, and your other hooks are kept. The hook only talks to Brim's local socket.")
        }
        .alert("Disconnect Claude Code?", isPresented: $confirmHookRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) { model.removeClaudeHook() }
        } message: {
            Text("Brim will remove its hooks from ~/.claude/settings.json (after saving a backup) and delete ~/.brim/claude-hook.sh. Other hooks are kept.")
        }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { model.settings.agentNotificationsEnabled },
            set: { enabled in
                if !enabled {
                    model.settings.agentNotificationsEnabled = false
                    model.agentNotificationError = nil
                    return
                }
                if model.agentNotificationAuthorization.isAuthorized {
                    model.settings.agentNotificationsEnabled = true
                } else {
                    showNotificationExplanation = true
                }
            }
        )
    }

    private var hookStatus: (label: String, symbol: String, color: Color) {
        switch model.claudeHookStatus {
        case .installed?:
            ("Connected", "checkmark.circle.fill", .green)
        case .outdated?:
            ("Connected with an older hook", "arrow.triangle.2.circlepath.circle.fill", .orange)
        case .notInstalled?:
            ("Not connected", "circle.dashed", .secondary)
        case .claudeNotFound?:
            ("Claude Code hasn't run on this Mac yet", "info.circle", .secondary)
        case .unreadableSettings?:
            ("~/.claude/settings.json isn't valid JSON", "exclamationmark.triangle.fill", .orange)
        case nil:
            ("Unavailable", "circle.dashed", .secondary)
        }
    }
}

private struct QuickPromptSettingsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            if model.isModuleEnabled(QuickPromptModule.moduleID) {
                LabeledContent("Claude Code") {
                    HStack(spacing: 8) {
                        if let path = model.quickPromptCLIPath {
                            Label(path, systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .trailing)
                        } else {
                            Label("Not found", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Button("Choose…") { model.chooseQuickPromptCLI() }
                        if model.settings.quickPromptCLIPath != nil {
                            Button("Reset") { model.setQuickPromptCLIPath(nil) }
                        }
                    }
                }
                if model.quickPromptCLIPath == nil {
                    Text("Install Claude Code (claude.com/claude-code) and run claude once in Terminal to log in. If it lives somewhere unusual, choose it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "power.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Quick Prompt is off. Turn it on in Modules to ask Claude from the notch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Quick Prompt")
        } footer: {
            Text("Runs your claude command with read-only tools (Read, Grep, Glob) in the folder shown in the prompt bar. Brim makes no network requests itself; Claude Code does, under your login.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { model.refreshQuickPromptCLI() }
    }
}

// MARK: - Modules

private struct ModulesSettingsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var permissionModuleID: String?

    var body: some View {
        Form {
            Section {
                if model.activeModules.isEmpty {
                    Text("No modules are enabled. Brim still opens; turn one on below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.activeModules.enumerated()), id: \.element.id) { index, module in
                        ModuleRow(
                            module: module,
                            isEnabled: moduleBinding(for: module),
                            canMoveUp: index > 0,
                            canMoveDown: index < model.activeModules.count - 1,
                            onMoveUp: { model.moveModule(id: module.id, by: -1) },
                            onMoveDown: { model.moveModule(id: module.id, by: 1) }
                        )
                    }
                }
            } header: {
                Text("In the panel")
            } footer: {
                Text("Modules appear side by side in the expanded panel. Use the arrows to change their order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.disabledModules.isEmpty {
                    Text("Every available module is already enabled.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.disabledModules, id: \.id) { module in
                        ModuleRow(
                            module: module,
                            isEnabled: moduleBinding(for: module),
                            canMoveUp: false,
                            canMoveDown: false,
                            onMoveUp: {},
                            onMoveDown: {}
                        )
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("A module that needs a permission explains why before macOS asks. Declining keeps it working in a limited form.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(
            get: { permissionModuleID != nil },
            set: { if !$0 { permissionModuleID = nil } }
        )) {
            if let id = permissionModuleID, let module = model.module(id: id) {
                PermissionExplanationView(
                    module: module,
                    onAllow: {
                        permissionModuleID = nil
                        Task { await model.enableModuleAfterPermissionExplanation(id) }
                    },
                    onCancel: { permissionModuleID = nil }
                )
            }
        }
    }

    private func moduleBinding(for module: any BrimModule) -> Binding<Bool> {
        Binding(
            get: { model.settings.enabledModules.contains(module.id) },
            set: { setEnabled(module, $0) }
        )
    }

    private func setEnabled(_ module: any BrimModule, _ enabled: Bool) {
        // Turning a module on is the only path that can lead to a permission prompt.
        if enabled, !module.isEnabled, module.explainsBeforeEnabling {
            permissionModuleID = module.id
        } else {
            model.setModuleEnabled(module.id, enabled)
        }
    }
}

private struct ModuleRow: View {
    let module: any BrimModule
    @Binding var isEnabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                if isEnabled && !module.requiredPermissions.isEmpty {
                    Text("Needs \(module.requiredPermissions.map(\.title).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if isEnabled {
                VStack(spacing: 1) {
                    reorderButton(
                        "chevron.up",
                        label: "Move \(module.title) up",
                        enabled: canMoveUp,
                        action: onMoveUp
                    )
                    reorderButton(
                        "chevron.down",
                        label: "Move \(module.title) down",
                        enabled: canMoveDown,
                        action: onMoveDown
                    )
                }
                .frame(width: 20)
            }

            // No `.labelsHidden()`: on macOS that strips the checkbox's accessibility action.
            Toggle("", isOn: $isEnabled)
                .accessibilityLabel("Enable \(module.title)")
        }
        .padding(.vertical, 2)
    }

    /// A 20×14 hit target per chevron, stacked so the pair reads as one reorder control. The old
    /// borderless buttons were only 9×5 and sat unevenly next to the toggle.
    private func reorderButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - About

private struct AboutTab: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.black, Color(red: 0.25, green: 0.28, blue: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Brim").font(.title.bold())
                Text("Version \(version)").foregroundStyle(.secondary)
            }

            Text("The good stuff is right at the top edge.")
                .italic()
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    model.copyDiagnostics()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button(role: .destructive) {
                    model.quit()
                } label: {
                    Label("Quit Brim", systemImage: "power")
                }
            }
            .padding(.top, 6)

            Text("No network access. No analytics.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
