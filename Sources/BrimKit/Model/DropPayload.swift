import Foundation

/// What a drag onto the notch carries, as far as modules care (F18).
public enum DropKind: String, Hashable, CaseIterable, Sendable {
    case files
    case text
}

public enum DropPayload: Equatable, Sendable {
    case files([URL])
    case text(String)

    public var kind: DropKind {
        switch self {
        case .files: return .files
        case .text: return .text
        }
    }
}
