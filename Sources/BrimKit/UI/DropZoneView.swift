import SwiftUI
import UniformTypeIdentifiers

/// One module's target in the panel's drop view (F18). The shell lays the zones out; what a drop means is up
/// to the module.
struct DropZoneView: View {
    let module: any BrimModule
    let kinds: Set<DropKind>
    @State private var isTargeted = false

    private var accepted: Set<DropKind> { module.acceptedDrops.intersection(kinds) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 10) {
            Image(systemName: module.symbolName)
                .font(.system(size: 26, weight: .medium))
            Text(module.dropTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.white.opacity(isTargeted ? 0.1 : 0.035)))
        .overlay(
            shape.strokeBorder(
                Color.white.opacity(isTargeted ? 0.55 : 0.18),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
        )
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .onDrop(of: DropLoader.types(for: accepted), isTargeted: $isTargeted) { providers in
            DropLoader.load(providers, accepting: accepted) { payload in
                module.handleDrop(payload)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop here: \(module.dropTitle)")
    }
}

enum DropLoader {
    static func types(for kinds: Set<DropKind>) -> [UTType] {
        var types: [UTType] = []
        if kinds.contains(.files) { types.append(.fileURL) }
        if kinds.contains(.text) { types.append(.plainText) }
        return types
    }

    /// Files win over text when a drag carries both (Finder adds a path string to file drags).
    static func load(
        _ providers: [NSItemProvider],
        accepting kinds: Set<DropKind>,
        completion: @escaping @MainActor (DropPayload) -> Void
    ) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if kinds.contains(.files), !fileProviders.isEmpty {
            let collector = URLCollector(count: fileProviders.count) { urls in
                guard !urls.isEmpty else { return }
                Task { @MainActor in completion(.files(urls)) }
            }
            for provider in fileProviders {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        ?? (item as? URL)
                    collector.add(url)
                }
            }
            return true
        }
        if kinds.contains(.text), let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text, !text.isEmpty else { return }
                Task { @MainActor in completion(.text(text)) }
            }
            return true
        }
        return false
    }
}

/// Item providers call back on arbitrary queues; this gathers every URL before handing them over once.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private let done: ([URL]) -> Void

    init(count: Int, done: @escaping ([URL]) -> Void) {
        self.remaining = count
        self.done = done
    }

    func add(_ url: URL?) {
        lock.lock()
        if let url, url.isFileURL { urls.append(url) }
        remaining -= 1
        let finished = remaining == 0
        let result = urls
        lock.unlock()
        if finished { done(result) }
    }
}
