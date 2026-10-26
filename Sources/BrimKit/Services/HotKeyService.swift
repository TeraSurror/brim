import Carbon.HIToolbox

/// Carbon's `RegisterEventHotKey` is still the only public API for a global shortcut that needs no
/// Accessibility or Input Monitoring permission.
@MainActor
public final class CarbonHotKeyService: HotKeyRegistering {
    public var onPress: ((HotKeyAction) -> Void)?

    private static let signature: OSType = 0x4252_494D // "BRIM"

    private var registrations: [HotKeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    public init() {}

    public func register(_ hotKey: HotKey, for action: HotKeyAction) -> Bool {
        unregister(action)
        guard hotKey.isValid else { return false }
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.identifier(for: action))
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            Self.carbonModifiers(hotKey.modifiers),
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.general.error("Shortcut \(hotKey.displayString, privacy: .public) was refused (\(status, privacy: .public))")
            return false
        }
        registrations[action] = ref
        Log.general.info("Registered \(hotKey.displayString, privacy: .public) for \(action.rawValue, privacy: .public)")
        return true
    }

    public func unregister(_ action: HotKeyAction) {
        guard let ref = registrations.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(ref)
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr, id.signature == CarbonHotKeyService.signature,
                  let action = CarbonHotKeyService.action(for: id.id) else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<CarbonHotKeyService>.fromOpaque(context).takeUnretainedValue()
            // Carbon dispatches hot keys on the main thread's event loop.
            MainActor.assumeIsolated { service.onPress?(action) }
            return noErr
        }, 1, &spec, context, &handler)
    }

    private static func identifier(for action: HotKeyAction) -> UInt32 {
        UInt32(HotKeyAction.allCases.firstIndex(of: action) ?? 0) + 1
    }

    private static func action(for identifier: UInt32) -> HotKeyAction? {
        let index = Int(identifier) - 1
        return HotKeyAction.allCases.indices.contains(index) ? HotKeyAction.allCases[index] : nil
    }

    private static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
