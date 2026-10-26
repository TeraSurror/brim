/// Picks the one module that gets the live notch. Kept pure so the priority rules are testable with plain
/// values.
public enum LiveActivityResolver {
    /// `candidates` are in panel order. The highest priority wins; ties go to the module listed first.
    public static func winner(_ candidates: [(id: String, activity: LiveActivity?)]) -> String? {
        var best: (id: String, priority: LiveActivityPriority)?
        for candidate in candidates {
            guard let priority = candidate.activity?.priority else { continue }
            if best == nil || priority > best!.priority {
                best = (candidate.id, priority)
            }
        }
        return best?.id
    }
}
