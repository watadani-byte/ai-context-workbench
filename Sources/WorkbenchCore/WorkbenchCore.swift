import Foundation

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

/// Identity of one persistence operation.
public struct PersistenceOperationID: Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Monotonically increasing order assigned to persistence operations.
public struct PersistenceOperationSequence: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = Self(rawValue: 0)

    public static func < (
        lhs: PersistenceOperationSequence,
        rhs: PersistenceOperationSequence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate func advanced() -> Self {
        precondition(rawValue < UInt64.max, "Persistence operation sequence overflow")
        return Self(rawValue: rawValue + 1)
    }
}

/// Identifies the document lifetime to which an asynchronous operation belongs.
public struct DocumentGeneration: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = Self(rawValue: 0)

    public static func < (lhs: DocumentGeneration, rhs: DocumentGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate func advanced() -> Self {
        precondition(rawValue < UInt64.max, "Document generation overflow")
        return Self(rawValue: rawValue + 1)
    }
}

/// Immutable request handed from canonical/editor state to the persistence boundary.
///
/// Snapshot revision, operation order, and document generation remain distinct:
/// none of them may be used as a substitute for another.
public struct SaveRequest: Equatable, Sendable {
    public let snapshot: CanonicalSourceSnapshot
    public let documentGeneration: DocumentGeneration
    public let operationID: PersistenceOperationID
    public let operationSequence: PersistenceOperationSequence
    public let destinationURL: URL?
    public let adoptsDestinationURLOnSuccess: Bool

    public var saveAsURL: URL? {
        adoptsDestinationURLOnSuccess ? destinationURL : nil
    }

    public init(
        snapshot: CanonicalSourceSnapshot,
        documentGeneration: DocumentGeneration = .initial,
        operationID: PersistenceOperationID = PersistenceOperationID(),
        operationSequence: PersistenceOperationSequence = .initial,
        destinationURL: URL? = nil,
        adoptsDestinationURLOnSuccess: Bool = false
    ) {
        self.snapshot = snapshot
        self.documentGeneration = documentGeneration
        self.operationID = operationID
        self.operationSequence = operationSequence
        self.destinationURL = destinationURL
        self.adoptsDestinationURLOnSuccess = adoptsDestinationURLOnSuccess
    }
}

/// Completion reported by the persistence boundary for a specific request.
public enum SaveCompletion: Equatable, Sendable {
    case succeeded(SaveRequest)
    case failed(SaveRequest)
    case cancelled(SaveRequest)

    fileprivate var request: SaveRequest {
        switch self {
        case .succeeded(let request), .failed(let request), .cancelled(let request):
            return request
        }
    }
}

/// Persistence-related facts about the current document.
public struct DocumentState: Equatable, Sendable {
    public private(set) var documentURL: URL?
    public private(set) var cleanBaseline: CanonicalSourceSnapshot
    public private(set) var persistedRevision: CanonicalSourceRevision?
    public private(set) var generation: DocumentGeneration

    fileprivate init(
        documentURL: URL?,
        cleanBaseline: CanonicalSourceSnapshot,
        persistedRevision: CanonicalSourceRevision?,
        generation: DocumentGeneration
    ) {
        self.documentURL = documentURL
        self.cleanBaseline = cleanBaseline
        self.persistedRevision = persistedRevision
        self.generation = generation
    }

    fileprivate mutating func acceptSuccessfulSave(_ request: SaveRequest) {
        cleanBaseline = request.snapshot
        persistedRevision = request.snapshot.revision
        if request.adoptsDestinationURLOnSuccess {
            documentURL = request.destinationURL
        }
    }

    fileprivate mutating func establishCleanBaseline(_ snapshot: CanonicalSourceSnapshot) {
        cleanBaseline = snapshot
    }
}

/// Tracks persistence operations independently from canonical and document state.
public struct PersistenceState: Equatable, Sendable {
    private var nextOperationSequence: PersistenceOperationSequence = .initial
    private var pendingOperations: [PersistenceOperationID: SaveRequest] = [:]
    private var lastAcceptedRequest: SaveRequest?

    public init() {}

    public var pendingOperationCount: Int {
        pendingOperations.count
    }

    public var lastAcceptedSave: SaveRequest? {
        lastAcceptedRequest
    }

    fileprivate mutating func makeRequest(
        snapshot: CanonicalSourceSnapshot,
        documentGeneration: DocumentGeneration,
        currentDocumentURL: URL?,
        saveAsURL: URL?
    ) -> SaveRequest {
        nextOperationSequence = nextOperationSequence.advanced()
        let request = SaveRequest(
            snapshot: snapshot,
            documentGeneration: documentGeneration,
            operationID: PersistenceOperationID(),
            operationSequence: nextOperationSequence,
            destinationURL: saveAsURL ?? currentDocumentURL,
            adoptsDestinationURLOnSuccess: saveAsURL != nil
        )
        pendingOperations[request.operationID] = request
        return request
    }

    fileprivate func isKnown(_ request: SaveRequest) -> Bool {
        pendingOperations[request.operationID] == request
    }

    fileprivate func isAcceptedDuplicate(_ request: SaveRequest) -> Bool {
        lastAcceptedRequest == request
    }

    fileprivate mutating func accept(_ request: SaveRequest) {
        pendingOperations[request.operationID] = nil
        lastAcceptedRequest = request
    }

    fileprivate mutating func invalidateForDocumentChange() {
        pendingOperations.removeAll()
        lastAcceptedRequest = nil
    }
}

/// Coordinates editor-originated and canonical-originated text changes.
///
/// The canonical source remains authoritative. This value provides explicit
/// synchronization entry points without introducing UI or file-system state.
public struct EditorState: Equatable, Sendable {
    public private(set) var canonicalSource: CanonicalSource
    public private(set) var documentState: DocumentState
    public private(set) var persistenceState: PersistenceState

    public init(
        initialText: String = "",
        documentURL: URL? = nil,
        persistedRevision: CanonicalSourceRevision? = nil
    ) {
        let source = CanonicalSource(text: initialText)
        canonicalSource = source
        documentState = DocumentState(
            documentURL: documentURL,
            cleanBaseline: source.makeSnapshot(),
            persistedRevision: persistedRevision,
            generation: .initial
        )
        persistenceState = PersistenceState()
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
        canonicalSource.text != documentState.cleanBaseline.text
    }

    public var cleanBaselineRevision: CanonicalSourceRevision {
        documentState.cleanBaseline.revision
    }

    public var documentURL: URL? {
        documentState.documentURL
    }

    public var persistedRevision: CanonicalSourceRevision? {
        documentState.persistedRevision
    }

    public var documentGeneration: DocumentGeneration {
        documentState.generation
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
    /// Retained as an internal Stage 1 test seam. Product code moves the clean
    /// baseline only through a validated successful persistence completion.
    mutating func establishCleanBaseline() {
        documentState.establishCleanBaseline(canonicalSource.makeSnapshot())
    }

    public func makeSnapshot() -> CanonicalSourceSnapshot {
        canonicalSource.makeSnapshot()
    }

    /// Captures the exact canonical snapshot that a persistence boundary should save.
    /// Creating a request does not alter revision or dirty state.
    public mutating func makeSaveRequest(saveAsURL: URL? = nil) -> SaveRequest {
        persistenceState.makeRequest(
            snapshot: canonicalSource.makeSnapshot(),
            documentGeneration: documentState.generation,
            currentDocumentURL: documentState.documentURL,
            saveAsURL: saveAsURL
        )
    }

    /// Starts a new unsaved document and invalidates operations from the prior
    /// document lifetime without performing file-system or UI work.
    public mutating func beginNewDocument(initialText: String = "") {
        replaceDocument(
            text: initialText,
            documentURL: nil,
            persistedRevision: nil
        )
    }

    /// Adopts already-loaded document content. File reading belongs to a later
    /// work package; this transition only establishes model state.
    public mutating func openDocument(
        text: String,
        documentURL: URL,
        persistedRevision: CanonicalSourceRevision? = .initial
    ) {
        replaceDocument(
            text: text,
            documentURL: documentURL,
            persistedRevision: persistedRevision
        )
    }

    private mutating func replaceDocument(
        text: String,
        documentURL: URL?,
        persistedRevision: CanonicalSourceRevision?
    ) {
        let nextGeneration = documentState.generation.advanced()
        let source = CanonicalSource(text: text)
        canonicalSource = source
        documentState = DocumentState(
            documentURL: documentURL,
            cleanBaseline: source.makeSnapshot(),
            persistedRevision: persistedRevision,
            generation: nextGeneration
        )
        persistenceState.invalidateForDocumentChange()
    }

    /// Applies a persistence completion without performing persistence itself.
    ///
    /// A successful completion moves the clean baseline to the snapshot that was
    /// actually saved. If editing continued after the request was created, the
    /// current text remains dirty relative to that older saved snapshot. Failed
    /// completions leave the existing clean baseline unchanged. A successful
    /// completion older than the accepted clean baseline is rejected so an
    /// out-of-order persistence response cannot move the baseline backward.
    @discardableResult
    public mutating func applySaveCompletion(_ completion: SaveCompletion) -> Bool {
        let request = completion.request

        guard request.documentGeneration == documentState.generation else {
            return false
        }

        switch completion {
        case .succeeded(let request):
            if persistenceState.isAcceptedDuplicate(request) {
                return true
            }

            guard persistenceState.isKnown(request) else {
                return false
            }

            guard request.snapshot.revision >= documentState.cleanBaseline.revision else {
                return false
            }

            if let lastAccepted = persistenceState.lastAcceptedSave,
               request.operationSequence <= lastAccepted.operationSequence {
                return false
            }

            documentState.acceptSuccessfulSave(request)
            persistenceState.accept(request)
            return true
        case .failed, .cancelled:
            return false
        }
    }
}
