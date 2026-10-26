import Combine
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

    /// True while any expanded panel is open on any screen. Modules that own a monitor only for the panel
    /// start and stop here so a collapsed notch costs nothing.
    func setPanelActive(_ active: Bool)

    /// Content the module wants beside the notch while the panel is closed, or nil. The publisher emits the
    /// new value, so subscribers never have to read the property during `willSet`.
    var liveActivity: LiveActivity? { get }
    var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> { get }
    /// One ear of the live notch. Only called while this module's activity is the one shown.
    func liveView(_ edge: LiveActivityEdge) -> AnyView
    /// A horizontal swipe over the ears while this module's activity is shown. Most modules ignore it.
    func handleSwipe(_ gesture: ScrollGesture)

    func expandedView() -> AnyView
}

public extension BrimModule {
    func setPanelActive(_ active: Bool) {}

    var liveActivity: LiveActivity? { nil }
    var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> { Just(nil).eraseToAnyPublisher() }
    func liveView(_ edge: LiveActivityEdge) -> AnyView { AnyView(EmptyView()) }
    func handleSwipe(_ gesture: ScrollGesture) {}
}
