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


/// UTF-16 based selection range shared across the editor bridge boundary.
///
/// NSTextView reports selections as NSRange values measured in UTF-16 code
/// units. Keeping the range representation in WorkbenchCore allows selection
/// restoration rules to be tested without making the canonical source depend
/// on AppKit.
public struct EditorSelectionRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        precondition(location >= 0, "Selection location must be non-negative")
        precondition(length >= 0, "Selection length must be non-negative")
        self.location = location
        self.length = length
    }

    /// Returns a range that remains valid for text with the supplied UTF-16
    /// length. A cursor beyond the new end moves to the end; a selection that
    /// overlaps the new end is shortened rather than discarded.
    public func clamped(toUTF16Length textLength: Int) -> Self {
        precondition(textLength >= 0, "Text length must be non-negative")

        let safeLocation = min(location, textLength)
        let availableLength = textLength - safeLocation
        let safeLength = min(length, availableLength)
        return Self(location: safeLocation, length: safeLength)
    }
}


/// Gates editor text changes so IME marked text does not become canonical
/// until the composition is committed.
public struct EditorInputTransactionGate: Equatable, Sendable {
    public private(set) var isComposing = false

    public init() {}

    /// Observes the current editor text and marked-text state.
    ///
    /// - Returns: committed text when the observation is outside an active
    ///   composition; `nil` while marked text is still being composed.
    public mutating func observe(text: String, hasMarkedText: Bool) -> String? {
        if hasMarkedText {
            isComposing = true
            return nil
        }

        isComposing = false
        return text
    }
}

/// Immutable request handed from canonical/editor state to the persistence boundary.
///
/// The request captures a snapshot so downstream processing cannot observe later
/// editor mutations. WP08 deliberately does not perform file-system I/O.
public struct SaveRequest: Equatable, Sendable {
    public let snapshot: CanonicalSourceSnapshot

    public init(snapshot: CanonicalSourceSnapshot) {
        self.snapshot = snapshot
    }
}

/// Completion reported by the persistence boundary for a specific request.
public enum SaveCompletion: Equatable, Sendable {
    case succeeded(SaveRequest)
    case failed(SaveRequest)
}

/// Coordinates editor-originated and canonical-originated text changes.
///
/// The canonical source remains authoritative. This value provides explicit
/// synchronization entry points without introducing UI or file-system state.
public struct EditorState: Equatable, Sendable {
    public private(set) var canonicalSource: CanonicalSource
    private var cleanBaseline: CanonicalSourceSnapshot

    public init(initialText: String = "") {
        let source = CanonicalSource(text: initialText)
        canonicalSource = source
        cleanBaseline = source.makeSnapshot()
    }

    public var text: String {
        canonicalSource.text
    }

    public var revision: CanonicalSourceRevision {
        canonicalSource.revision
    }

    /// Indicates whether canonical text differs from the accepted clean baseline.
    ///
    /// Dirty state is content-based rather than revision-based so an undo that
    /// restores the baseline text also restores a clean state.
    public var isDirty: Bool {
        canonicalSource.text != cleanBaseline.text
    }

    public var cleanBaselineRevision: CanonicalSourceRevision {
        cleanBaseline.revision
    }

    /// Applies text observed from the editor surface to the canonical source.
    @discardableResult
    public mutating func applyEditorText(_ text: String) -> Bool {
        canonicalSource.replaceText(with: text)
    }

    /// Replaces canonical text from a non-editor source.
    @discardableResult
    public mutating func replaceCanonicalText(with text: String) -> Bool {
        canonicalSource.replaceText(with: text)
    }

    /// Establishes the current canonical source as the clean baseline.
    ///
    /// This is deliberately persistence-agnostic. WP08 may invoke this only
    /// after a successful save boundary has been verified.
    public mutating func establishCleanBaseline() {
        cleanBaseline = canonicalSource.makeSnapshot()
    }

    public func makeSnapshot() -> CanonicalSourceSnapshot {
        canonicalSource.makeSnapshot()
    }

    /// Captures the exact canonical snapshot that a persistence boundary should save.
    /// Creating a request does not alter revision or dirty state.
    public func makeSaveRequest() -> SaveRequest {
        SaveRequest(snapshot: canonicalSource.makeSnapshot())
    }

    /// Applies a persistence completion without performing persistence itself.
    ///
    /// A successful completion moves the clean baseline to the snapshot that was
    /// actually saved. If editing continued after the request was created, the
    /// current text remains dirty relative to that older saved snapshot. Failed
    /// completions leave the existing clean baseline unchanged.
    @discardableResult
    public mutating func applySaveCompletion(_ completion: SaveCompletion) -> Bool {
        switch completion {
        case .succeeded(let request):
            cleanBaseline = request.snapshot
            return true
        case .failed:
            return false
        }
    }
}
