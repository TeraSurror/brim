import CoreGraphics
import Foundation
import SwiftUI
@testable import BrimKit

@MainActor
final class FakeScheduler: Scheduling {
    struct Pending {
        let due: TimeInterval
        let action: @MainActor () -> Void
        let handle: TaskHandle
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Pending] = []

    var pendingCount: Int { pending.filter { !$0.handle.isCancelled }.count }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> TaskHandle {
        let handle = TaskHandle {}
        pending.append(Pending(due: now + interval, action: action, handle: handle))
        return handle
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = pending
            .filter({ !$0.handle.isCancelled && $0.due <= target })
            .min(by: { $0.due < $1.due }) {
            now = next.due
            pending.removeAll { $0.handle === next.handle }
            next.action()
        }
        now = target
    }
}

struct FakeScreens: ScreenProviding {
    var infos: [ScreenInfo]
    @MainActor var screens: [ScreenInfo] { infos }
}

@MainActor
final class FakePointer: PointerMonitoring {
    var onMove: ((CGPoint) -> Void)?
    var onLeftClick: ((CGPoint) -> Void)?
    private(set) var running = false

    func start() { running = true }
    func stop() { running = false }

    func move(_ x: CGFloat, _ y: CGFloat) { onMove?(CGPoint(x: x, y: y)) }
    func click(_ x: CGFloat, _ y: CGFloat) { onLeftClick?(CGPoint(x: x, y: y)) }
}

struct FakeLoginError: Error {}

final class FakeLoginItems: LoginItemControlling {
    var enabled = false
    var failure: Error?
    private(set) var setCalls: [Bool] = []

    var isEnabled: Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let failure { throw failure }
        self.enabled = enabled
    }
}

final class FakeSettingsStore: SettingsPersisting {
    // SwiftUI also declares a `Settings` scene; qualify Brim's value type in this file.
    var stored: BrimKit.Settings
    private(set) var saves: [BrimKit.Settings] = []

    init(_ settings: BrimKit.Settings = BrimKit.Settings()) {
        self.stored = settings
    }

    func load() -> BrimKit.Settings { stored }

    func save(_ settings: BrimKit.Settings) {
        stored = settings
        saves.append(settings)
    }
}

@MainActor
final class FakePermissions: PermissionRequesting {
    var statuses: [PermissionKind: PermissionStatus] = [:]
    var requestResult: PermissionStatus = .granted
    private(set) var requests: [PermissionKind] = []

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        requests.append(kind)
        statuses[kind] = requestResult
        return requestResult
    }
}

@MainActor
final class FakeModule: BrimModule {
    let id: String
    let title: String
    let symbolName = "square.dashed"
    let requiredPermissions: [PermissionKind]
    let permissionExplanation: String
    private(set) var isEnabled = false
    private(set) var enableHistory: [Bool] = []

    init(id: String, permissions: [PermissionKind] = [], explanation: String = "Explanation") {
        self.id = id
        self.title = id.capitalized
        self.requiredPermissions = permissions
        self.permissionExplanation = explanation
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enableHistory.append(enabled)
    }

    func compactView() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}
