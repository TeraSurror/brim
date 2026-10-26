import SwiftUI

/// Shown before a module asks macOS for anything. No permission prompt ever appears at launch.
struct PermissionExplanationView: View {
    let module: any BrimModule
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.requiredPermissions.isEmpty ? "Turn on \(module.title)?" : "Allow \(module.title)?")
                        .font(.headline)
                    Text(module.requiredPermissions.isEmpty
                        ? "Here is what it does before you turn it on."
                        : "Brim asks only because you turned this module on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(module.permissionExplanation)

            if !module.requiredPermissions.isEmpty {
                Text("macOS will ask for: \(module.requiredPermissions.map(\.title).joined(separator: ", ")).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !module.requiredPermissions.isEmpty {
                Text("If you decline, the module stays enabled in a limited form. You can change permissions later in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: onAllow)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
