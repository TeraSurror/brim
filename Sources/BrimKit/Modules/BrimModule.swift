import Combine
import SwiftUI

/// Where a module sits in the open panel.
public enum ModulePlacement: Sendable {
    /// Side by side with the other cards, each with its own width share.
    case card
    /// A strip across the top of the panel, above the cards (Quick Prompt).
    case bar
}

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
    /// Shows `permissionExplanation` before enabling even when no permission is needed, for modules whose
    /// effects deserve a word first (Quick Prompt runs the user's `claude` command).
    var explainsBeforeEnabling: Bool { get }

    var placement: ModulePlacement { get }
    /// True while the module wants the whole open panel, such as an answer being read; the cards step aside.
    var fillsPanelPublisher: AnyPublisher<Bool, Never> { get }

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

    /// What can be dropped on this module from the notch. Empty for none; the panel then shows no zone for it.
    var acceptedDrops: Set<DropKind> { get }
    /// The label on the module's drop zone, such as "Ask Claude".
    var dropTitle: String { get }
    func handleDrop(_ payload: DropPayload)

    /// Esc in an open panel. Return true when the module used it (Quick Prompt leaves its conversation);
    /// otherwise the panel closes.
    func handleEscape() -> Bool

    func expandedView() -> AnyView
}

public extension BrimModule {
    func setPanelActive(_ active: Bool) {}

    var explainsBeforeEnabling: Bool { !requiredPermissions.isEmpty }
    var placement: ModulePlacement { .card }
    var fillsPanelPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }

    var liveActivity: LiveActivity? { nil }
    var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> { Just(nil).eraseToAnyPublisher() }
    func liveView(_ edge: LiveActivityEdge) -> AnyView { AnyView(EmptyView()) }
    func handleSwipe(_ gesture: ScrollGesture) {}

    var acceptedDrops: Set<DropKind> { [] }
    var dropTitle: String { title }
    func handleDrop(_ payload: DropPayload) {}
    func handleEscape() -> Bool { false }
}
