/// Shared implementation boundary for AI Context Workbench.
public enum WorkbenchCore {
    public static let productName = "AI Context Workbench"
    public static let version = "0.1"
}

/// Monotonically increasing version of the canonical source text.
public struct CanonicalSourceRevision: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = Self(rawValue: 0)

    public static func < (
        lhs: CanonicalSourceRevision,
        rhs: CanonicalSourceRevision
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate func advanced() -> Self {
        precondition(rawValue < UInt64.max, "Canonical source revision overflow")
        return Self(rawValue: rawValue + 1)
    }
}

/// Immutable value captured from the canonical source at a specific revision.
public struct CanonicalSourceSnapshot: Equatable, Sendable {
    public let text: String
    public let revision: CanonicalSourceRevision

    public init(text: String, revision: CanonicalSourceRevision) {
        self.text = text
        self.revision = revision
    }
}

/// Owns the authoritative source text for a single document.
///
/// This type deliberately has no UI, file-system, undo, or save behavior.
/// Those responsibilities are introduced at their authorized boundaries.
public struct CanonicalSource: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var revision: CanonicalSourceRevision

    public init(text: String = "") {
        self.text = text
        self.revision = .initial
    }

    /// Replaces the canonical text exactly as supplied.
    ///
    /// - Returns: `true` when the canonical text changed. Identical replacement
    ///   is ignored and does not advance the revision.
    @discardableResult
    public mutating func replaceText(with newText: String) -> Bool {
        guard newText != text else {
            return false
        }

        text = newText
        revision = revision.advanced()
        return true
    }

    /// Captures an immutable copy of the current canonical text and revision.
    public func makeSnapshot() -> CanonicalSourceSnapshot {
        CanonicalSourceSnapshot(text: text, revision: revision)
    }
}
