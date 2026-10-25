import Foundation

/// Owns every known module and the enabled, ordered subset from settings. Unknown IDs are ignored so an
/// old settings file cannot break a newer build.
@MainActor
public final class ModuleRegistry {
    public let allModules: [any BrimModule]
    public private(set) var enabledModules: [any BrimModule] = []

    public init(modules: [any BrimModule]) {
        self.allModules = modules
    }

    public func module(id: String) -> (any BrimModule)? {
        allModules.first { $0.id == id }
    }

    /// Applies the settings order, filtering unknown and duplicate IDs, and toggles each module exactly once.
    public func apply(enabledIDs: [String]) {
        var seen = Set<String>()
        var ordered: [any BrimModule] = []
        for id in enabledIDs where !id.isEmpty {
            guard !seen.contains(id), let module = module(id: id) else { continue }
            seen.insert(id)
            ordered.append(module)
        }
        enabledModules = ordered

        for module in allModules {
            module.setEnabled(seen.contains(module.id))
        }
    }

    public var disabledModules: [any BrimModule] {
        let enabled = Set(enabledModules.map(\.id))
        return allModules.filter { !enabled.contains($0.id) }
    }
}
