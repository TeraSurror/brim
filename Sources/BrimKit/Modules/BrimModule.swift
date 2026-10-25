import SwiftUI

/// The extension point for everything that lives in the panel. Modules own their content and their
/// permission request; the window shell only lays them out.
@MainActor
public protocol BrimModule: AnyObject, Identifiable {
    var id: String { get }
    var title: String { get }
    var symbolName: String { get }

    /// Empty for modules that need nothing. Anything here is requested only when the module is enabled,
    /// and only after the user has seen `permissionExplanation`.
    var requiredPermissions: [PermissionKind] { get }
    var permissionExplanation: String { get }

    /// Whether the module is currently active. The registry drives this from settings.
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)

    func compactView() -> AnyView
    func expandedView() -> AnyView
}
