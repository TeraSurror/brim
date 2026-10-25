import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModulesSettingsTab()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 540)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Peek delay") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.hoverDelay, in: Settings.hoverDelayRange, step: 0.05)
                            .frame(width: 190)
                            .accessibilityLabel("Peek delay")
                            .accessibilityValue("\(milliseconds(model.settings.hoverDelay)) milliseconds")
                        Text("\(milliseconds(model.settings.hoverDelay)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }

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

                Toggle(
                    "Show a handle on displays without a notch",
                    isOn: $model.settings.showOnNonNotchedDisplays
                )
                .accessibilityLabel("Show a handle on displays without a notch")
            } header: {
                Text("Panel")
            } footer: {
                Text("Hover the notch (or the handle) to peek. Keep hovering or click to open the panel. Changes save automatically.")
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
                    Text("Brim never asks for a permission at launch. Modules ask only when you enable them, with an explanation first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
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
        if enabled, !module.isEnabled, !module.requiredPermissions.isEmpty {
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
                HStack(spacing: 2) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    .help("Move up")
                    .accessibilityLabel("Move \(module.title) up")

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    .help("Move down")
                    .accessibilityLabel("Move \(module.title) down")
                }
                .font(.system(size: 10, weight: .semibold))
            }

            // No `.labelsHidden()`: on macOS that strips the checkbox's accessibility action.
            Toggle("", isOn: $isEnabled)
                .accessibilityLabel("Enable \(module.title)")
        }
        .padding(.vertical, 2)
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
