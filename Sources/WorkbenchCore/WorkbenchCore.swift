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

/// Advisory classification of a file-name extension.
///
/// Unknown extensions remain readable and writable. The classification exists
/// only so a later UI boundary can inform the user without changing persistence
/// behavior.
public enum PersistenceExtensionAdvisory: Equatable, Sendable {
    case supported
    case unknown
}

/// Persistence failures that callers may handle without interpreting
/// Foundation-specific error codes.
public enum PersistenceFailureKind: Equatable, Sendable {
    case invalidFileURL
    case fileNotFound
    case permissionDenied
    case readFailure
    case invalidUTF8
    case unsupportedBOM
    case unsupportedXMLDeclaredEncoding
    case writeFailure
    case atomicReplacementFailure
}

/// Structured persistence failure with optional diagnostic information from
/// the underlying file-system operation.
public struct PersistenceFailure: Equatable, Sendable {
    public let kind: PersistenceFailureKind
    public let underlyingDomain: String?
    public let underlyingCode: Int?
    public let diagnostic: String?

    public init(
        kind: PersistenceFailureKind,
        underlyingDomain: String? = nil,
        underlyingCode: Int? = nil,
        diagnostic: String? = nil
    ) {
        self.kind = kind
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
        self.diagnostic = diagnostic
    }
}

/// Complete text decoded from one file.
public struct PersistenceReadSuccess: Equatable, Sendable {
    public let sourceFileURL: URL
    public let text: String
    public let hadUTF8BOM: Bool
    public let extensionAdvisory: PersistenceExtensionAdvisory

    public init(
        sourceFileURL: URL,
        text: String,
        hadUTF8BOM: Bool,
        extensionAdvisory: PersistenceExtensionAdvisory
    ) {
        self.sourceFileURL = sourceFileURL
        self.text = text
        self.hadUTF8BOM = hadUTF8BOM
        self.extensionAdvisory = extensionAdvisory
    }
}

/// Result of a read operation. A failed result cannot expose partial text.
public enum PersistenceReadResult: Equatable, Sendable {
    case success(PersistenceReadSuccess)
    case failure(PersistenceFailure)
    case cancellation(sourceFileURL: URL)
}

/// Outcome of a write operation before any completion-adoption decision.
public enum PersistenceWriteOutcome: Equatable, Sendable {
    case success
    case failure(PersistenceFailure)
    case cancellation
}

/// Persistence-layer completion carrying the identity of the immutable Stage 2
/// save request. This value does not adopt the completion into document state.
public struct PersistenceWriteCompletion: Equatable, Sendable {
    public let operationID: PersistenceOperationID
    public let operationSequence: PersistenceOperationSequence
    public let documentGeneration: DocumentGeneration
    public let snapshotRevision: CanonicalSourceRevision
    public let targetFileURL: URL?
    public let outcome: PersistenceWriteOutcome

    public init(
        request: SaveRequest,
        targetFileURL: URL?,
        outcome: PersistenceWriteOutcome
    ) {
        operationID = request.operationID
        operationSequence = request.operationSequence
        documentGeneration = request.documentGeneration
        snapshotRevision = request.snapshot.revision
        self.targetFileURL = targetFileURL
        self.outcome = outcome
    }
}

/// UI-independent UTF-8 file persistence boundary.
///
/// Reads return text only after the complete byte sequence satisfies the
/// approved encoding policy. Writes consume only the immutable snapshot held
/// by `SaveRequest` and always request Foundation's atomic write behavior.
/// This service has no reference to live canonical or document state.
public struct PersistenceService {
    private static let supportedExtensions: Set<String> = [
        "md", "markdown", "txt", "xmd", "xml", "yaml", "yml"
    ]

    private let readData: (URL) throws -> Data
    private let writeDataAtomically: (Data, URL) throws -> Void
    private let fileExists: (URL) -> Bool

    public init() {
        readData = { try Data(contentsOf: $0) }
        writeDataAtomically = { data, url in
            try data.write(to: url, options: [.atomic])
        }
        fileExists = { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Test seam for deterministic file-system failure coverage.
    init(
        readData: @escaping (URL) throws -> Data,
        writeDataAtomically: @escaping (Data, URL) throws -> Void,
        fileExists: @escaping (URL) -> Bool
    ) {
        self.readData = readData
        self.writeDataAtomically = writeDataAtomically
        self.fileExists = fileExists
    }

    public func extensionAdvisory(for fileURL: URL) -> PersistenceExtensionAdvisory {
        let fileExtension = fileURL.pathExtension.lowercased()
        return Self.supportedExtensions.contains(fileExtension) ? .supported : .unknown
    }

    public func read(from sourceFileURL: URL) -> PersistenceReadResult {
        guard sourceFileURL.isFileURL else {
            return .failure(PersistenceFailure(kind: .invalidFileURL))
        }

        let data: Data
        do {
            data = try readData(sourceFileURL)
        } catch {
            return .failure(
                classifyFileSystemFailure(
                    error,
                    fallback: .readFailure,
                    targetExistedBeforeWrite: false
                )
            )
        }

        let inspectedData: Data
        let hadUTF8BOM: Bool
        switch inspectBOM(in: data) {
        case .utf8:
            inspectedData = Data(data.dropFirst(3))
            hadUTF8BOM = true
        case .unsupported:
            return .failure(PersistenceFailure(kind: .unsupportedBOM))
        case .none:
            inspectedData = data
            hadUTF8BOM = false
        }

        guard let text = String(data: inspectedData, encoding: .utf8) else {
            return .failure(PersistenceFailure(kind: .invalidUTF8))
        }

        if sourceFileURL.pathExtension.caseInsensitiveCompare("xml") == .orderedSame,
           let declaredEncoding = incompatibleXMLDeclaredEncoding(in: text) {
            return .failure(
                PersistenceFailure(
                    kind: .unsupportedXMLDeclaredEncoding,
                    diagnostic: "Declared encoding: \(declaredEncoding)"
                )
            )
        }

        return .success(
            PersistenceReadSuccess(
                sourceFileURL: sourceFileURL,
                text: text,
                hadUTF8BOM: hadUTF8BOM,
                extensionAdvisory: extensionAdvisory(for: sourceFileURL)
            )
        )
    }

    public func write(_ request: SaveRequest) -> PersistenceWriteCompletion {
        guard let targetFileURL = request.destinationURL,
              targetFileURL.isFileURL else {
            return PersistenceWriteCompletion(
                request: request,
                targetFileURL: request.destinationURL,
                outcome: .failure(PersistenceFailure(kind: .invalidFileURL))
            )
        }

        if targetFileURL.pathExtension.caseInsensitiveCompare("xml") == .orderedSame,
           let declaredEncoding = incompatibleXMLDeclaredEncoding(in: request.snapshot.text) {
            return PersistenceWriteCompletion(
                request: request,
                targetFileURL: targetFileURL,
                outcome: .failure(
                    PersistenceFailure(
                        kind: .unsupportedXMLDeclaredEncoding,
                        diagnostic: "Declared encoding: \(declaredEncoding)"
                    )
                )
            )
        }

        let targetExistedBeforeWrite = fileExists(targetFileURL)
        let data = Data(request.snapshot.text.utf8)

        do {
            try writeDataAtomically(data, targetFileURL)
            return PersistenceWriteCompletion(
                request: request,
                targetFileURL: targetFileURL,
                outcome: .success
            )
        } catch {
            return PersistenceWriteCompletion(
                request: request,
                targetFileURL: targetFileURL,
                outcome: .failure(
                    classifyFileSystemFailure(
                        error,
                        fallback: .writeFailure,
                        targetExistedBeforeWrite: targetExistedBeforeWrite
                    )
                )
            )
        }
    }

    private enum BOMInspection {
        case none
        case utf8
        case unsupported
    }

    private func inspectBOM(in data: Data) -> BOMInspection {
        let bytes = Array(data.prefix(4))

        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8
        }

        let unsupportedBOMs: [[UInt8]] = [
            [0x00, 0x00, 0xFE, 0xFF],
            [0xFF, 0xFE, 0x00, 0x00],
            [0x00, 0x00, 0xFF, 0xFE],
            [0xFE, 0xFF, 0x00, 0x00],
            [0xFE, 0xFF],
            [0xFF, 0xFE]
        ]

        return unsupportedBOMs.contains(where: { bytes.starts(with: $0) })
            ? .unsupported
            : .none
    }

    private func incompatibleXMLDeclaredEncoding(in text: String) -> String? {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let declarationPattern = #"(?is)\A\s*<\?xml\b.*?\?>"#
        guard let declarationExpression = try? NSRegularExpression(
            pattern: declarationPattern
        ),
        let declarationMatch = declarationExpression.firstMatch(
            in: text,
            range: fullRange
        ),
        let declarationRange = Range(declarationMatch.range, in: text) else {
            return nil
        }

        let declaration = String(text[declarationRange])
        let declarationNSRange = NSRange(
            declaration.startIndex..<declaration.endIndex,
            in: declaration
        )
        let encodingPattern = #"\bencoding\s*=\s*["']\s*([^"']+?)\s*["']"#
        guard let encodingExpression = try? NSRegularExpression(
            pattern: encodingPattern,
            options: [.caseInsensitive]
        ),
        let encodingMatch = encodingExpression.firstMatch(
            in: declaration,
            range: declarationNSRange
        ),
        encodingMatch.numberOfRanges > 1,
        let encodingRange = Range(encodingMatch.range(at: 1), in: declaration) else {
            return nil
        }

        let declaredEncoding = String(declaration[encodingRange])
        return declaredEncoding.caseInsensitiveCompare("UTF-8") == .orderedSame
            ? nil
            : declaredEncoding
    }

    private func classifyFileSystemFailure(
        _ error: Error,
        fallback: PersistenceFailureKind,
        targetExistedBeforeWrite: Bool
    ) -> PersistenceFailure {
        let nsError = error as NSError
        let kind: PersistenceFailureKind

        if nsError.domain == NSCocoaErrorDomain,
           [NSFileNoSuchFileError, NSFileReadNoSuchFileError]
            .contains(nsError.code) {
            kind = .fileNotFound
        } else if nsError.domain == NSCocoaErrorDomain,
                  [NSFileReadNoPermissionError, NSFileWriteNoPermissionError]
                    .contains(nsError.code) {
            kind = .permissionDenied
        } else if nsError.domain == NSPOSIXErrorDomain,
                  nsError.code == 2 {
            kind = .fileNotFound
        } else if nsError.domain == NSPOSIXErrorDomain,
                  [1, 13].contains(nsError.code) {
            kind = .permissionDenied
        } else if fallback == .writeFailure && targetExistedBeforeWrite {
            kind = .atomicReplacementFailure
        } else {
            kind = fallback
        }

        return PersistenceFailure(
            kind: kind,
            underlyingDomain: nsError.domain,
            underlyingCode: nsError.code,
            diagnostic: nsError.localizedDescription
        )
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
