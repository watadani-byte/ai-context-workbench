import Foundation
import XCTest
@testable import WorkbenchCore

final class WorkbenchCoreTests: XCTestCase {
    func testProductIdentityIsAvailableToApplicationShell() {
        XCTAssertEqual(WorkbenchCore.productName, "AI Context Workbench")
        XCTAssertEqual(WorkbenchCore.version, "0.1")
    }
}

final class CanonicalSourceTests: XCTestCase {
    func testInitialSourceIsEmptyAtInitialRevision() {
        let source = CanonicalSource()

        XCTAssertEqual(source.text, "")
        XCTAssertEqual(source.revision, .initial)
    }

    func testInitialTextDoesNotCountAsAnEdit() {
        let source = CanonicalSource(text: "Initial")

        XCTAssertEqual(source.text, "Initial")
        XCTAssertEqual(source.revision, .initial)
    }

    func testReplacingTextAdvancesRevision() {
        var source = CanonicalSource()

        let changed = source.replaceText(with: "Hello")

        XCTAssertTrue(changed)
        XCTAssertEqual(source.text, "Hello")
        XCTAssertEqual(source.revision.rawValue, 1)
    }

    func testReplacingWithIdenticalTextDoesNotAdvanceRevision() {
        var source = CanonicalSource(text: "Hello")

        let changed = source.replaceText(with: "Hello")

        XCTAssertFalse(changed)
        XCTAssertEqual(source.revision, .initial)
    }

    func testEachDistinctReplacementAdvancesRevisionOnce() {
        var source = CanonicalSource()

        source.replaceText(with: "A")
        source.replaceText(with: "AB")
        source.replaceText(with: "ABC")

        XCTAssertEqual(source.revision.rawValue, 3)
    }

    func testSnapshotCapturesCurrentTextAndRevision() {
        var source = CanonicalSource()
        source.replaceText(with: "Snapshot text")

        let snapshot = source.makeSnapshot()

        XCTAssertEqual(snapshot.text, "Snapshot text")
        XCTAssertEqual(snapshot.revision.rawValue, 1)
    }

    func testSnapshotRemainsIsolatedAfterLaterChange() {
        var source = CanonicalSource(text: "Before")
        let snapshot = source.makeSnapshot()

        source.replaceText(with: "After")

        XCTAssertEqual(snapshot.text, "Before")
        XCTAssertEqual(snapshot.revision, .initial)
        XCTAssertEqual(source.text, "After")
        XCTAssertEqual(source.revision.rawValue, 1)
    }

    func testUnicodeSourceIsPreservedExactly() {
        let text = "日本語\n絵文字: 📝\nXMD: <document>本文</document>"
        let source = CanonicalSource(text: text)

        XCTAssertEqual(source.makeSnapshot().text, text)
    }

    func testWhitespaceIsNotNormalized() {
        let text = "line 1  \r\n\tline 2\n"
        let source = CanonicalSource(text: text)

        XCTAssertEqual(source.makeSnapshot().text, text)
    }
}

final class EditorStateTests: XCTestCase {
    func testInitialTextIsCanonicalAtInitialRevision() {
        let state = EditorState(initialText: "Initial")

        XCTAssertEqual(state.text, "Initial")
        XCTAssertEqual(state.revision, .initial)
    }

    func testEditorChangeUpdatesCanonicalSourceOnce() {
        var state = EditorState(initialText: "Before")

        let changed = state.applyEditorText("After")

        XCTAssertTrue(changed)
        XCTAssertEqual(state.text, "After")
        XCTAssertEqual(state.revision.rawValue, 1)
    }

    func testIdenticalEditorChangeDoesNotAdvanceRevision() {
        var state = EditorState(initialText: "Same")

        let changed = state.applyEditorText("Same")

        XCTAssertFalse(changed)
        XCTAssertEqual(state.revision, .initial)
    }

    func testCanonicalReplacementIsAvailableToEditorSurface() {
        var state = EditorState(initialText: "Before")

        state.replaceCanonicalText(with: "Canonical update")

        XCTAssertEqual(state.text, "Canonical update")
        XCTAssertEqual(state.revision.rawValue, 1)
        XCTAssertEqual(state.makeSnapshot().text, "Canonical update")
    }
}

final class BasicEditingOperationTests: XCTestCase {
    func testInsertResultUpdatesCanonicalSource() {
        var state = EditorState(initialText: "AB")

        state.applyEditorText("AXB")

        XCTAssertEqual(state.text, "AXB")
        XCTAssertEqual(state.revision.rawValue, 1)
    }

    func testDeleteResultUpdatesCanonicalSource() {
        var state = EditorState(initialText: "ABC")

        state.applyEditorText("AC")

        XCTAssertEqual(state.text, "AC")
        XCTAssertEqual(state.revision.rawValue, 1)
    }

    func testReplaceResultUpdatesCanonicalSource() {
        var state = EditorState(initialText: "ABC")

        state.applyEditorText("AXC")

        XCTAssertEqual(state.text, "AXC")
        XCTAssertEqual(state.revision.rawValue, 1)
    }

    func testSelectionInsideReplacementTextIsPreserved() {
        let selection = EditorSelectionRange(location: 2, length: 3)

        XCTAssertEqual(
            selection.clamped(toUTF16Length: 10),
            EditorSelectionRange(location: 2, length: 3)
        )
    }

    func testCursorBeyondReplacementTextMovesToEnd() {
        let cursor = EditorSelectionRange(location: 10, length: 0)

        XCTAssertEqual(
            cursor.clamped(toUTF16Length: 4),
            EditorSelectionRange(location: 4, length: 0)
        )
    }

    func testSelectionCrossingReplacementEndIsShortened() {
        let selection = EditorSelectionRange(location: 3, length: 5)

        XCTAssertEqual(
            selection.clamped(toUTF16Length: 5),
            EditorSelectionRange(location: 3, length: 2)
        )
    }
}

final class EditorInputTransactionGateTests: XCTestCase {
    func testPlainTextPassesThroughImmediately() {
        var gate = EditorInputTransactionGate()

        let committed = gate.observe(text: "abc", hasMarkedText: false)

        XCTAssertEqual(committed, "abc")
        XCTAssertFalse(gate.isComposing)
    }

    func testMarkedTextIsDeferred() {
        var gate = EditorInputTransactionGate()

        let committed = gate.observe(text: "にほ", hasMarkedText: true)

        XCTAssertNil(committed)
        XCTAssertTrue(gate.isComposing)
    }

    func testRepeatedMarkedTextUpdatesRemainDeferred() {
        var gate = EditorInputTransactionGate()

        XCTAssertNil(gate.observe(text: "に", hasMarkedText: true))
        XCTAssertNil(gate.observe(text: "にほ", hasMarkedText: true))
        XCTAssertNil(gate.observe(text: "にほんご", hasMarkedText: true))
        XCTAssertTrue(gate.isComposing)
    }

    func testCompositionCommitEmitsFinalTextOnceObservedWithoutMarkedText() {
        var gate = EditorInputTransactionGate()

        XCTAssertNil(gate.observe(text: "にほんご", hasMarkedText: true))
        let committed = gate.observe(text: "日本語", hasMarkedText: false)

        XCTAssertEqual(committed, "日本語")
        XCTAssertFalse(gate.isComposing)
    }

    func testUndoLikeCommittedTextPassesThrough() {
        var gate = EditorInputTransactionGate()

        XCTAssertEqual(gate.observe(text: "AB", hasMarkedText: false), "AB")
        XCTAssertEqual(gate.observe(text: "A", hasMarkedText: false), "A")
        XCTAssertFalse(gate.isComposing)
    }
}

final class DirtyStateAndSnapshotTests: XCTestCase {
    func testInitialStateIsClean() {
        let state = EditorState(initialText: "Baseline")

        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.cleanBaselineRevision, .initial)
    }

    func testEditorChangeMarksStateDirty() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Changed")

        XCTAssertTrue(state.isDirty)
    }

    func testIdenticalEditorTextKeepsStateClean() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Baseline")

        XCTAssertFalse(state.isDirty)
    }

    func testUndoLikeReturnToBaselineRestoresCleanState() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Changed")
        state.applyEditorText("Baseline")

        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.revision.rawValue, 2)
    }

    func testCanonicalReplacementMarksStateDirty() {
        var state = EditorState(initialText: "Baseline")

        state.replaceCanonicalText(with: "Canonical replacement")

        XCTAssertTrue(state.isDirty)
    }

    func testEstablishCleanBaselineResetsDirtyStateWithoutChangingText() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Changed")
        let revisionBeforeBaseline = state.revision

        state.establishCleanBaseline()

        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.text, "Changed")
        XCTAssertEqual(state.cleanBaselineRevision, revisionBeforeBaseline)
        XCTAssertEqual(state.revision, revisionBeforeBaseline)
    }

    func testSnapshotRemainsIsolatedAfterEditorStateChanges() {
        var state = EditorState(initialText: "Before")
        let snapshot = state.makeSnapshot()

        state.applyEditorText("After")

        XCTAssertEqual(snapshot.text, "Before")
        XCTAssertEqual(snapshot.revision, .initial)
        XCTAssertEqual(state.text, "After")
        XCTAssertEqual(state.revision.rawValue, 1)
    }
}

final class SaveRequestBoundaryTests: XCTestCase {
    func testSaveRequestCapturesCurrentSnapshotWithoutChangingState() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Changed")
        let revisionBeforeRequest = state.revision

        let request = state.makeSaveRequest()

        XCTAssertEqual(request.snapshot.text, "Changed")
        XCTAssertEqual(request.snapshot.revision, revisionBeforeRequest)
        XCTAssertEqual(state.revision, revisionBeforeRequest)
        XCTAssertTrue(state.isDirty)
    }

    func testSaveRequestRemainsIsolatedFromLaterEditing() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("To save")
        let request = state.makeSaveRequest()

        state.applyEditorText("Edited after request")

        XCTAssertEqual(request.snapshot.text, "To save")
        XCTAssertEqual(request.snapshot.revision.rawValue, 1)
        XCTAssertEqual(state.text, "Edited after request")
        XCTAssertEqual(state.revision.rawValue, 2)
    }

    func testSuccessfulSaveOfCurrentSnapshotMarksStateClean() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved text")
        let request = state.makeSaveRequest()

        let accepted = state.applySaveCompletion(.succeeded(request))

        XCTAssertTrue(accepted)
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.cleanBaselineRevision, request.snapshot.revision)
        XCTAssertEqual(state.text, "Saved text")
    }

    func testSuccessfulSaveOfStaleSnapshotKeepsLaterEditingDirty() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Snapshot to save")
        let request = state.makeSaveRequest()
        state.applyEditorText("Newer edit")

        let accepted = state.applySaveCompletion(.succeeded(request))

        XCTAssertTrue(accepted)
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.cleanBaselineRevision, request.snapshot.revision)
        XCTAssertEqual(state.text, "Newer edit")
        XCTAssertEqual(state.revision.rawValue, 2)
    }

    func testFailedSaveDoesNotMoveCleanBaseline() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Unsaved")
        let request = state.makeSaveRequest()

        let accepted = state.applySaveCompletion(.failed(request))

        XCTAssertFalse(accepted)
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.cleanBaselineRevision, .initial)
        XCTAssertEqual(state.text, "Unsaved")
    }
}

final class IntegratedEditorFlowTests: XCTestCase {
    func testMarkedTextDoesNotUpdateCanonicalSource() {
        var gate = EditorInputTransactionGate()
        var state = EditorState(initialText: "")

        let committed = gate.observe(text: "にほ", hasMarkedText: true)
        if let committed {
            state.applyEditorText(committed)
        }

        XCTAssertNil(committed)
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.revision, .initial)
        XCTAssertFalse(state.isDirty)
    }

    func testIMECommitUpdatesCanonicalSourceExactlyOnce() {
        var gate = EditorInputTransactionGate()
        var state = EditorState(initialText: "")

        XCTAssertNil(gate.observe(text: "にほんご", hasMarkedText: true))
        let committed = gate.observe(text: "日本語", hasMarkedText: false)
        if let committed {
            state.applyEditorText(committed)
        }

        XCTAssertEqual(state.text, "日本語")
        XCTAssertEqual(state.revision.rawValue, 1)
        XCTAssertTrue(state.isDirty)
    }

    func testUndoLikeReturnRestoresCanonicalTextAndCleanState() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Edited")
        state.applyEditorText("Baseline")

        XCTAssertEqual(state.text, "Baseline")
        XCTAssertEqual(state.revision.rawValue, 2)
        XCTAssertFalse(state.isDirty)
    }

    func testSnapshotDoesNotObserveEditingAfterCapture() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Captured")
        let snapshot = state.makeSnapshot()

        state.applyEditorText("Later edit")

        XCTAssertEqual(snapshot.text, "Captured")
        XCTAssertEqual(snapshot.revision.rawValue, 1)
        XCTAssertEqual(state.text, "Later edit")
        XCTAssertEqual(state.revision.rawValue, 2)
    }

    func testCompletionForRequestedSnapshotKeepsLaterEditDirty() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Requested")
        let request = state.makeSaveRequest()
        state.applyEditorText("Later edit")

        let accepted = state.applySaveCompletion(.succeeded(request))

        XCTAssertTrue(accepted)
        XCTAssertEqual(state.cleanBaselineRevision.rawValue, 1)
        XCTAssertEqual(state.text, "Later edit")
        XCTAssertTrue(state.isDirty)
    }

    func testOlderCompletionCannotMoveCleanBaselineBackward() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("First")
        let olderRequest = state.makeSaveRequest()
        state.applyEditorText("Second")
        let newerRequest = state.makeSaveRequest()

        XCTAssertTrue(state.applySaveCompletion(.succeeded(newerRequest)))
        let accepted = state.applySaveCompletion(.succeeded(olderRequest))

        XCTAssertFalse(accepted)
        XCTAssertEqual(state.cleanBaselineRevision, newerRequest.snapshot.revision)
        XCTAssertEqual(state.text, "Second")
        XCTAssertFalse(state.isDirty)
    }

    func testFailedCompletionDoesNotChangeAcceptedCleanBaseline() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved")
        let savedRequest = state.makeSaveRequest()
        XCTAssertTrue(state.applySaveCompletion(.succeeded(savedRequest)))

        state.applyEditorText("Unsaved")
        let failedRequest = state.makeSaveRequest()
        let accepted = state.applySaveCompletion(.failed(failedRequest))

        XCTAssertFalse(accepted)
        XCTAssertEqual(state.cleanBaselineRevision, savedRequest.snapshot.revision)
        XCTAssertEqual(state.text, "Unsaved")
        XCTAssertTrue(state.isDirty)
    }

    func testDuplicateCompletionForSameRevisionIsIdempotent() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest()

        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))
        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))
        XCTAssertEqual(state.cleanBaselineRevision, request.snapshot.revision)
        XCTAssertEqual(state.text, "Saved")
        XCTAssertFalse(state.isDirty)
    }
}

final class DocumentStateAndPersistenceModelTests: XCTestCase {
    func testNewDocumentHasNoURLNoPersistedRevisionAndIsClean() {
        let state = EditorState()

        XCTAssertNil(state.documentURL)
        XCTAssertNil(state.persistedRevision)
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.documentGeneration, .initial)
    }

    func testDocumentWithURLCanBeRepresented() {
        let url = URL(fileURLWithPath: "/tmp/document.md")
        let state = EditorState(
            initialText: "Loaded",
            documentURL: url,
            persistedRevision: .initial
        )

        XCTAssertEqual(state.documentURL, url)
        XCTAssertEqual(state.persistedRevision, .initial)
        XCTAssertFalse(state.isDirty)

        var requestState = state
        let request = requestState.makeSaveRequest()
        XCTAssertEqual(request.destinationURL, url)
        XCTAssertFalse(request.adoptsDestinationURLOnSuccess)
    }

    func testEditingMakesDocumentDirty() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Changed")

        XCTAssertTrue(state.isDirty)
    }

    func testReturningToBaselineMakesDocumentClean() {
        var state = EditorState(initialText: "Baseline")

        state.applyEditorText("Changed")
        state.applyEditorText("Baseline")

        XCTAssertFalse(state.isDirty)
    }

    func testSaveRequestFreezesSnapshotGenerationAndOperationIdentity() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Snapshot")

        let request = state.makeSaveRequest()
        state.applyEditorText("Later")
        let secondRequest = state.makeSaveRequest()

        XCTAssertEqual(request.snapshot.text, "Snapshot")
        XCTAssertEqual(request.snapshot.revision.rawValue, 1)
        XCTAssertEqual(request.documentGeneration, .initial)
        XCTAssertEqual(request.operationSequence.rawValue, 1)
        XCTAssertEqual(secondRequest.snapshot.text, "Later")
        XCTAssertEqual(secondRequest.operationSequence.rawValue, 2)
        XCTAssertNotEqual(request.operationID, secondRequest.operationID)
        XCTAssertEqual(state.persistenceState.pendingOperationCount, 2)
    }

    func testSuccessfulCurrentSnapshotUpdatesCleanAndPersistedRevision() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest()

        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))

        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.cleanBaselineRevision, request.snapshot.revision)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
    }

    func testEditingAfterSaveRequestRemainsDirtyAfterSuccess() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved snapshot")
        let request = state.makeSaveRequest()
        state.applyEditorText("Later edit")

        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))

        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.text, "Later edit")
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
    }

    func testFailureDoesNotChangeState() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Unsaved")
        let request = state.makeSaveRequest()
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.failed(request)))
        XCTAssertEqual(state, stateBeforeCompletion)
    }

    func testCancellationDoesNotChangeState() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Unsaved")
        let request = state.makeSaveRequest()
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.cancelled(request)))
        XCTAssertEqual(state, stateBeforeCompletion)
    }

    func testOlderCompletionCannotMoveBaselineBackward() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Older")
        let olderRequest = state.makeSaveRequest()
        state.applyEditorText("Newer")
        let newerRequest = state.makeSaveRequest()
        XCTAssertTrue(state.applySaveCompletion(.succeeded(newerRequest)))
        let stateBeforeOlderCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.succeeded(olderRequest)))
        XCTAssertEqual(state, stateBeforeOlderCompletion)
    }

    func testCompletionFromDifferentDocumentGenerationIsRejected() {
        var state = EditorState(initialText: "Old document")
        state.applyEditorText("Old unsaved text")
        let oldRequest = state.makeSaveRequest()
        state.beginNewDocument(initialText: "New document")
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.succeeded(oldRequest)))
        XCTAssertEqual(state, stateBeforeCompletion)
    }

    func testCompletionFromPreviousDocumentIsRejectedAfterOpen() {
        var state = EditorState(initialText: "Old document")
        let oldRequest = state.makeSaveRequest()
        let openedURL = URL(fileURLWithPath: "/tmp/opened.md")
        state.openDocument(text: "Opened document", documentURL: openedURL)
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.succeeded(oldRequest)))
        XCTAssertEqual(state, stateBeforeCompletion)
        XCTAssertEqual(state.documentURL, openedURL)
        XCTAssertEqual(state.persistedRevision, CanonicalSourceRevision.initial)
    }

    func testUnknownOperationIDIsRejected() {
        var state = EditorState(initialText: "Target")
        state.applyEditorText("Target edit")
        var otherState = EditorState(initialText: "Other")
        otherState.applyEditorText("Foreign edit")
        let unknownRequest = otherState.makeSaveRequest()
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.succeeded(unknownRequest)))
        XCTAssertEqual(state, stateBeforeCompletion)
    }

    func testDuplicateCompletionIsIdempotent() {
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest()
        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))
        let stateAfterFirstCompletion = state

        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))
        XCTAssertEqual(state, stateAfterFirstCompletion)
    }

    func testSaveAsDoesNotAdoptURLBeforeSuccess() {
        let originalURL = URL(fileURLWithPath: "/tmp/original.md")
        let saveAsURL = URL(fileURLWithPath: "/tmp/replacement.md")
        var state = EditorState(initialText: "Text", documentURL: originalURL)

        let request = state.makeSaveRequest(saveAsURL: saveAsURL)

        XCTAssertEqual(request.saveAsURL, saveAsURL)
        XCTAssertEqual(request.destinationURL, saveAsURL)
        XCTAssertTrue(request.adoptsDestinationURLOnSuccess)
        XCTAssertEqual(state.documentURL, originalURL)
    }

    func testFailedSaveAsDoesNotAdoptURL() {
        let originalURL = URL(fileURLWithPath: "/tmp/original.md")
        let saveAsURL = URL(fileURLWithPath: "/tmp/replacement.md")
        var state = EditorState(initialText: "Text", documentURL: originalURL)
        let request = state.makeSaveRequest(saveAsURL: saveAsURL)
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applySaveCompletion(.failed(request)))
        XCTAssertEqual(state, stateBeforeCompletion)
        XCTAssertEqual(state.documentURL, originalURL)
    }

    func testSaveAsAdoptsURLOnlyAfterSuccess() {
        let originalURL = URL(fileURLWithPath: "/tmp/original.md")
        let saveAsURL = URL(fileURLWithPath: "/tmp/replacement.md")
        var state = EditorState(initialText: "Text", documentURL: originalURL)
        state.applyEditorText("Changed")
        let request = state.makeSaveRequest(saveAsURL: saveAsURL)

        XCTAssertTrue(state.applySaveCompletion(.succeeded(request)))

        XCTAssertEqual(state.documentURL, saveAsURL)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
        XCTAssertFalse(state.isDirty)
    }
}

final class StateModelPersistenceIntegrationTests: XCTestCase {
    private let originalURL = URL(fileURLWithPath: "/tmp/original.md")
    private let openedURL = URL(fileURLWithPath: "/tmp/opened.md")
    private let saveAsURL = URL(fileURLWithPath: "/tmp/save-as.md")

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func readSuccess(
        request: PersistenceReadRequest,
        text: String,
        sourceFileURL: URL? = nil
    ) -> PersistenceReadCompletion {
        let sourceURL = sourceFileURL ?? request.sourceFileURL
        return PersistenceReadCompletion(
            request: request,
            result: .success(
                PersistenceReadSuccess(
                    sourceFileURL: sourceURL,
                    text: text,
                    hadUTF8BOM: false,
                    extensionAdvisory: .supported
                )
            )
        )
    }

    private func writeCompletion(
        request: SaveRequest,
        operationID: PersistenceOperationID? = nil,
        operationSequence: PersistenceOperationSequence? = nil,
        documentGeneration: DocumentGeneration? = nil,
        snapshotRevision: CanonicalSourceRevision? = nil,
        targetFileURL: URL? = nil,
        outcome: PersistenceWriteOutcome = .success
    ) -> PersistenceWriteCompletion {
        PersistenceWriteCompletion(
            operationID: operationID ?? request.operationID,
            operationSequence: operationSequence ?? request.operationSequence,
            documentGeneration: documentGeneration ?? request.documentGeneration,
            snapshotRevision: snapshotRevision ?? request.snapshot.revision,
            targetFileURL: targetFileURL ?? request.destinationURL,
            outcome: outcome
        )
    }

    func testValidReadAdoptsCanonicalURLAndCleanRevisionRelationship() {
        var state = EditorState(
            initialText: "Existing",
            documentURL: originalURL,
            persistedRevision: .initial
        )
        state.applyEditorText("Existing edit")
        let generationBeforeRead = state.documentGeneration
        let request = state.makeReadRequest(sourceFileURL: openedURL)

        XCTAssertEqual(state.documentURL, originalURL)
        XCTAssertTrue(state.applyReadCompletion(readSuccess(
            request: request,
            text: "Opened"
        )))

        XCTAssertEqual(state.text, "Opened")
        XCTAssertEqual(state.documentURL, openedURL)
        XCTAssertEqual(state.revision, .initial)
        XCTAssertEqual(state.persistedRevision, .initial)
        XCTAssertEqual(state.cleanBaselineRevision, .initial)
        XCTAssertFalse(state.isDirty)
        XCTAssertGreaterThan(state.documentGeneration, generationBeforeRead)
        XCTAssertEqual(state.persistenceState.pendingOperationCount, 0)
    }

    func testPersistenceServiceReadCompletionFlowsThroughStateValidation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("opened.md")
        try Data("Opened by service".utf8).write(to: fileURL)
        var state = EditorState(initialText: "Existing", documentURL: originalURL)
        let request = state.makeReadRequest(sourceFileURL: fileURL)

        let completion = PersistenceService().read(request)

        XCTAssertTrue(state.applyReadCompletion(completion))
        XCTAssertEqual(state.text, "Opened by service")
        XCTAssertEqual(state.documentURL, fileURL)
        XCTAssertEqual(state.persistedRevision, .initial)
        XCTAssertFalse(state.isDirty)
    }

    func testReadFailurePreservesExistingDocumentState() {
        var state = EditorState(
            initialText: "Existing",
            documentURL: originalURL,
            persistedRevision: .initial
        )
        state.applyEditorText("Unsaved edit")
        let request = state.makeReadRequest(sourceFileURL: openedURL)
        let text = state.text
        let revision = state.revision
        let persistedRevision = state.persistedRevision
        let generation = state.documentGeneration
        let dirty = state.isDirty
        let failure = PersistenceFailure(kind: .readFailure)

        XCTAssertFalse(state.applyReadCompletion(
            PersistenceReadCompletion(request: request, result: .failure(failure))
        ))

        XCTAssertEqual(state.text, text)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.documentURL, originalURL)
        XCTAssertEqual(state.persistedRevision, persistedRevision)
        XCTAssertEqual(state.documentGeneration, generation)
        XCTAssertEqual(state.isDirty, dirty)
    }

    func testReadCancellationPreservesExistingDocumentStateAndCandidateURL() {
        var state = EditorState(
            initialText: "Existing",
            documentURL: originalURL,
            persistedRevision: .initial
        )
        let request = state.makeReadRequest(sourceFileURL: openedURL)
        let text = state.text
        let revision = state.revision
        let generation = state.documentGeneration

        XCTAssertFalse(state.applyReadCompletion(
            PersistenceReadCompletion(
                request: request,
                result: .cancellation(sourceFileURL: openedURL)
            )
        ))

        XCTAssertEqual(state.text, text)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.documentURL, originalURL)
        XCTAssertEqual(state.persistedRevision, .initial)
        XCTAssertEqual(state.documentGeneration, generation)
        XCTAssertFalse(state.isDirty)
    }

    func testLaterReadRegistrationSupersedesOlderRead() {
        var state = EditorState(initialText: "Existing", documentURL: originalURL)
        let olderRequest = state.makeReadRequest(
            sourceFileURL: URL(fileURLWithPath: "/tmp/older.md")
        )
        let newerRequest = state.makeReadRequest(sourceFileURL: openedURL)
        let stateBeforeOlderCompletion = state

        XCTAssertFalse(state.applyReadCompletion(readSuccess(
            request: olderRequest,
            text: "Older"
        )))
        XCTAssertEqual(state, stateBeforeOlderCompletion)
        XCTAssertTrue(state.applyReadCompletion(readSuccess(
            request: newerRequest,
            text: "Newer"
        )))
        XCTAssertEqual(state.text, "Newer")
        XCTAssertEqual(state.documentURL, openedURL)
    }

    func testUnknownMismatchedAndPreviousGenerationReadsAreRejected() {
        var state = EditorState(initialText: "Existing", documentURL: originalURL)
        let request = state.makeReadRequest(sourceFileURL: openedURL)
        let unknown = PersistenceReadCompletion(
            operationID: PersistenceOperationID(),
            operationSequence: request.operationSequence,
            documentGeneration: request.documentGeneration,
            sourceFileURL: request.sourceFileURL,
            result: readSuccess(request: request, text: "Unknown").result
        )
        let wrongSequence = PersistenceReadCompletion(
            operationID: request.operationID,
            operationSequence: PersistenceOperationSequence(
                rawValue: request.operationSequence.rawValue + 1
            ),
            documentGeneration: request.documentGeneration,
            sourceFileURL: request.sourceFileURL,
            result: readSuccess(request: request, text: "Wrong sequence").result
        )
        let wrongSourceURL = PersistenceReadCompletion(
            operationID: request.operationID,
            operationSequence: request.operationSequence,
            documentGeneration: request.documentGeneration,
            sourceFileURL: URL(fileURLWithPath: "/tmp/wrong.md"),
            result: readSuccess(request: request, text: "Wrong source").result
        )
        let mismatchedPayload = readSuccess(
            request: request,
            text: "Wrong URL",
            sourceFileURL: URL(fileURLWithPath: "/tmp/wrong.md")
        )
        let stateBeforeInvalidCompletions = state

        XCTAssertFalse(state.applyReadCompletion(unknown))
        XCTAssertFalse(state.applyReadCompletion(wrongSequence))
        XCTAssertFalse(state.applyReadCompletion(wrongSourceURL))
        XCTAssertFalse(state.applyReadCompletion(mismatchedPayload))
        XCTAssertEqual(state, stateBeforeInvalidCompletions)

        state.beginNewDocument(initialText: "New document")
        let stateBeforeLateCompletion = state
        XCTAssertFalse(state.applyReadCompletion(readSuccess(
            request: request,
            text: "Previous document"
        )))
        XCTAssertEqual(state, stateBeforeLateCompletion)
    }

    func testDuplicateReadSuccessIsNotAppliedTwice() {
        var state = EditorState(initialText: "Existing", documentURL: originalURL)
        let request = state.makeReadRequest(sourceFileURL: openedURL)
        let completion = readSuccess(request: request, text: "Opened")

        XCTAssertTrue(state.applyReadCompletion(completion))
        let stateAfterFirstCompletion = state

        XCTAssertFalse(state.applyReadCompletion(completion))
        XCTAssertEqual(state, stateAfterFirstCompletion)
    }

    func testReadSuccessInvalidatesPriorDocumentWriteCompletion() {
        var state = EditorState(initialText: "Existing", documentURL: originalURL)
        state.applyEditorText("Pending save")
        let saveRequest = state.makeSaveRequest()
        let readRequest = state.makeReadRequest(sourceFileURL: openedURL)

        XCTAssertTrue(state.applyReadCompletion(readSuccess(
            request: readRequest,
            text: "Opened"
        )))
        let stateAfterRead = state

        XCTAssertFalse(state.applyWriteCompletion(
            writeCompletion(request: saveRequest)
        ))
        XCTAssertEqual(state, stateAfterRead)
    }

    func testValidWriteUpdatesPersistedRevisionWithoutReplacingCanonicalState() {
        var state = EditorState(initialText: "Baseline", documentURL: originalURL)
        state.applyEditorText("Saved snapshot")
        let request = state.makeSaveRequest()
        state.applyEditorText("Later edit")
        let currentRevision = state.revision

        XCTAssertTrue(state.applyWriteCompletion(
            writeCompletion(request: request)
        ))

        XCTAssertEqual(state.text, "Later edit")
        XCTAssertEqual(state.revision, currentRevision)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
        XCTAssertEqual(state.cleanBaselineRevision, request.snapshot.revision)
        XCTAssertTrue(state.isDirty)
    }

    func testValidWriteWithoutLaterEditProducesCleanRevisionRelationship() {
        var state = EditorState(initialText: "Baseline", documentURL: originalURL)
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest()

        XCTAssertTrue(state.applyWriteCompletion(
            writeCompletion(request: request)
        ))

        XCTAssertEqual(state.revision, request.snapshot.revision)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
        XCTAssertFalse(state.isDirty)
    }

    func testPersistenceServiceWriteCompletionFlowsThroughStateValidation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("saved.md")
        var state = EditorState(initialText: "Baseline")
        state.applyEditorText("Saved by service")
        let request = state.makeSaveRequest(saveAsURL: fileURL)

        let completion = PersistenceService().write(request)

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertTrue(state.applyWriteCompletion(completion))
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("Saved by service".utf8))
        XCTAssertEqual(state.documentURL, fileURL)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
        XCTAssertFalse(state.isDirty)
    }

    func testWriteFailureAndCancellationPreserveDocumentOwnedState() {
        var failedState = EditorState(
            initialText: "Baseline",
            documentURL: originalURL,
            persistedRevision: .initial
        )
        failedState.applyEditorText("Unsaved")
        let failedRequest = failedState.makeSaveRequest(saveAsURL: saveAsURL)
        let failedText = failedState.text
        let failedRevision = failedState.revision

        XCTAssertFalse(failedState.applyWriteCompletion(
            writeCompletion(
                request: failedRequest,
                outcome: .failure(PersistenceFailure(kind: .writeFailure))
            )
        ))
        XCTAssertEqual(failedState.text, failedText)
        XCTAssertEqual(failedState.revision, failedRevision)
        XCTAssertEqual(failedState.persistedRevision, .initial)
        XCTAssertEqual(failedState.documentURL, originalURL)
        XCTAssertTrue(failedState.isDirty)

        var cancelledState = EditorState(
            initialText: "Baseline",
            documentURL: originalURL,
            persistedRevision: .initial
        )
        cancelledState.applyEditorText("Unsaved")
        let cancelledRequest = cancelledState.makeSaveRequest(saveAsURL: saveAsURL)
        let cancelledText = cancelledState.text
        let cancelledRevision = cancelledState.revision

        XCTAssertFalse(cancelledState.applyWriteCompletion(
            writeCompletion(request: cancelledRequest, outcome: .cancellation)
        ))
        XCTAssertEqual(cancelledState.text, cancelledText)
        XCTAssertEqual(cancelledState.revision, cancelledRevision)
        XCTAssertEqual(cancelledState.persistedRevision, .initial)
        XCTAssertEqual(cancelledState.documentURL, originalURL)
        XCTAssertTrue(cancelledState.isDirty)
    }

    func testWriteIdentitySequenceGenerationRevisionAndTargetMustMatch() {
        func assertRejected(
            _ completion: (SaveRequest) -> PersistenceWriteCompletion,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            var state = EditorState(initialText: "Baseline", documentURL: originalURL)
            state.applyEditorText("Unsaved")
            let request = state.makeSaveRequest()
            let stateBeforeCompletion = state

            XCTAssertFalse(
                state.applyWriteCompletion(completion(request)),
                file: file,
                line: line
            )
            XCTAssertEqual(state, stateBeforeCompletion, file: file, line: line)
        }

        assertRejected {
            writeCompletion(
                request: $0,
                operationID: PersistenceOperationID()
            )
        }
        assertRejected {
            writeCompletion(
                request: $0,
                operationSequence: PersistenceOperationSequence(
                    rawValue: $0.operationSequence.rawValue + 1
                )
            )
        }
        assertRejected {
            writeCompletion(
                request: $0,
                documentGeneration: DocumentGeneration(
                    rawValue: $0.documentGeneration.rawValue + 1
                )
            )
        }
        assertRejected {
            writeCompletion(
                request: $0,
                snapshotRevision: CanonicalSourceRevision(
                    rawValue: $0.snapshot.revision.rawValue + 1
                )
            )
        }
        assertRejected {
            writeCompletion(
                request: $0,
                targetFileURL: URL(fileURLWithPath: "/tmp/wrong.md")
            )
        }
    }

    func testUnknownWriteOperationIsRejected() {
        var state = EditorState(initialText: "Target", documentURL: originalURL)
        var otherState = EditorState(
            initialText: "Other",
            documentURL: URL(fileURLWithPath: "/tmp/other.md")
        )
        otherState.applyEditorText("Foreign")
        let foreignRequest = otherState.makeSaveRequest()
        let stateBeforeCompletion = state

        XCTAssertFalse(state.applyWriteCompletion(
            writeCompletion(request: foreignRequest)
        ))
        XCTAssertEqual(state, stateBeforeCompletion)
    }

    func testOutOfOrderWriteCompletionCannotRollStateBackward() {
        var state = EditorState(initialText: "Baseline", documentURL: originalURL)
        state.applyEditorText("Older")
        let older = state.makeSaveRequest()
        state.applyEditorText("Newer")
        let newer = state.makeSaveRequest()

        XCTAssertTrue(state.applyWriteCompletion(writeCompletion(request: newer)))
        let stateAfterNewer = state

        XCTAssertFalse(state.applyWriteCompletion(writeCompletion(request: older)))
        XCTAssertEqual(state, stateAfterNewer)
        XCTAssertEqual(state.persistedRevision, newer.snapshot.revision)
    }

    func testDuplicateWriteCompletionHasNoSecondEffect() {
        var state = EditorState(initialText: "Baseline", documentURL: originalURL)
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest(saveAsURL: saveAsURL)
        let completion = writeCompletion(request: request)

        XCTAssertTrue(state.applyWriteCompletion(completion))
        let stateAfterFirstCompletion = state

        XCTAssertTrue(state.applyWriteCompletion(completion))
        XCTAssertEqual(state, stateAfterFirstCompletion)
        XCTAssertEqual(state.persistedRevision, request.snapshot.revision)
        XCTAssertEqual(state.documentURL, saveAsURL)
    }

    func testDuplicateFailureAndCancellationDoNotChangeDocumentState() {
        for outcome in [
            PersistenceWriteOutcome.failure(
                PersistenceFailure(kind: .writeFailure)
            ),
            .cancellation
        ] {
            var state = EditorState(
                initialText: "Baseline",
                documentURL: originalURL,
                persistedRevision: .initial
            )
            state.applyEditorText("Unsaved")
            let request = state.makeSaveRequest(saveAsURL: saveAsURL)
            let completion = writeCompletion(request: request, outcome: outcome)

            XCTAssertFalse(state.applyWriteCompletion(completion))
            let documentFacts = (
                state.text,
                state.revision,
                state.persistedRevision,
                state.documentURL,
                state.isDirty
            )
            XCTAssertFalse(state.applyWriteCompletion(completion))
            XCTAssertEqual(state.text, documentFacts.0)
            XCTAssertEqual(state.revision, documentFacts.1)
            XCTAssertEqual(state.persistedRevision, documentFacts.2)
            XCTAssertEqual(state.documentURL, documentFacts.3)
            XCTAssertEqual(state.isDirty, documentFacts.4)
        }
    }

    func testDuplicateReadFailureAndCancellationDoNotChangeDocumentState() {
        for result in [
            PersistenceReadResult.failure(
                PersistenceFailure(kind: .readFailure)
            ),
            .cancellation(sourceFileURL: openedURL)
        ] {
            var state = EditorState(
                initialText: "Existing",
                documentURL: originalURL,
                persistedRevision: .initial
            )
            state.applyEditorText("Unsaved")
            let request = state.makeReadRequest(sourceFileURL: openedURL)
            let completion = PersistenceReadCompletion(
                request: request,
                result: result
            )

            XCTAssertFalse(state.applyReadCompletion(completion))
            let text = state.text
            let revision = state.revision
            let persistedRevision = state.persistedRevision
            let documentURL = state.documentURL
            let dirty = state.isDirty

            XCTAssertFalse(state.applyReadCompletion(completion))
            XCTAssertEqual(state.text, text)
            XCTAssertEqual(state.revision, revision)
            XCTAssertEqual(state.persistedRevision, persistedRevision)
            XCTAssertEqual(state.documentURL, documentURL)
            XCTAssertEqual(state.isDirty, dirty)
        }
    }

    func testSaveAsURLIsAdoptedOnlyAfterValidatedSuccess() {
        var state = EditorState(initialText: "Baseline", documentURL: originalURL)
        state.applyEditorText("Saved")
        let request = state.makeSaveRequest(saveAsURL: saveAsURL)

        XCTAssertEqual(state.documentURL, originalURL)
        XCTAssertTrue(state.applyWriteCompletion(writeCompletion(request: request)))
        XCTAssertEqual(state.documentURL, saveAsURL)
    }

    func testStaleAndPreviousGenerationSaveAsCompletionsDoNotAdoptURL() {
        var staleState = EditorState(initialText: "Baseline", documentURL: originalURL)
        staleState.applyEditorText("Older")
        let older = staleState.makeSaveRequest(
            saveAsURL: URL(fileURLWithPath: "/tmp/older-save-as.md")
        )
        staleState.applyEditorText("Newer")
        let newer = staleState.makeSaveRequest(saveAsURL: saveAsURL)
        XCTAssertTrue(staleState.applyWriteCompletion(writeCompletion(request: newer)))

        XCTAssertFalse(staleState.applyWriteCompletion(writeCompletion(request: older)))
        XCTAssertEqual(staleState.documentURL, saveAsURL)

        var generationState = EditorState(
            initialText: "Old document",
            documentURL: originalURL
        )
        let previousGeneration = generationState.makeSaveRequest(saveAsURL: saveAsURL)
        generationState.beginNewDocument(initialText: "New document")

        XCTAssertFalse(generationState.applyWriteCompletion(
            writeCompletion(request: previousGeneration)
        ))
        XCTAssertNil(generationState.documentURL)
    }
}

final class PersistenceServiceTests: XCTestCase {
    private enum TestFailure: Error {
        case forcedReadFailure
        case forcedWriteFailure
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeRequest(
        text: String,
        destinationURL: URL,
        revision: UInt64 = 1
    ) -> SaveRequest {
        SaveRequest(
            snapshot: CanonicalSourceSnapshot(
                text: text,
                revision: CanonicalSourceRevision(rawValue: revision)
            ),
            documentGeneration: DocumentGeneration(rawValue: 3),
            operationID: PersistenceOperationID(),
            operationSequence: PersistenceOperationSequence(rawValue: 7),
            destinationURL: destinationURL
        )
    }

    private func readSuccess(
        _ result: PersistenceReadResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PersistenceReadSuccess? {
        guard case .success(let success) = result else {
            XCTFail("Expected read success, got \(result)", file: file, line: line)
            return nil
        }
        return success
    }

    private func readFailure(
        _ result: PersistenceReadResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PersistenceFailure? {
        guard case .failure(let failure) = result else {
            XCTFail("Expected read failure, got \(result)", file: file, line: line)
            return nil
        }
        return failure
    }

    private func writeFailure(
        _ completion: PersistenceWriteCompletion,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PersistenceFailure? {
        guard case .failure(let failure) = completion.outcome else {
            XCTFail("Expected write failure, got \(completion)", file: file, line: line)
            return nil
        }
        return failure
    }

    func testReadsUTF8FileExactly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("document.md")
        let expected = "Hello, 日本語"
        try Data(expected.utf8).write(to: fileURL)

        let success = readSuccess(PersistenceService().read(from: fileURL))

        XCTAssertEqual(success?.sourceFileURL, fileURL)
        XCTAssertEqual(success?.text, expected)
        XCTAssertEqual(success?.hadUTF8BOM, false)
        XCTAssertEqual(success?.extensionAdvisory, .supported)
    }

    func testReadsEmptyFileAsEmptyText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("empty.txt")
        try Data().write(to: fileURL)

        XCTAssertEqual(
            readSuccess(PersistenceService().read(from: fileURL))?.text,
            ""
        )
    }

    func testRemovesUTF8BOMOnRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("bom.xmd")
        try Data([0xEF, 0xBB, 0xBF] + Array("Text".utf8)).write(to: fileURL)

        let success = readSuccess(PersistenceService().read(from: fileURL))

        XCTAssertEqual(success?.text, "Text")
        XCTAssertEqual(success?.hadUTF8BOM, true)
    }

    func testRejectsInvalidUTF8WithoutLossyConversion() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("invalid.md")
        try Data([0x48, 0x69, 0xFF]).write(to: fileURL)

        let failure = readFailure(PersistenceService().read(from: fileURL))

        XCTAssertEqual(failure?.kind, .invalidUTF8)
    }

    func testMissingFileReturnsStructuredFailure() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("missing.md")

        let failure = readFailure(PersistenceService().read(from: fileURL))

        XCTAssertEqual(failure?.kind, .fileNotFound)
        XCTAssertNotNil(failure?.underlyingDomain)
        XCTAssertNotNil(failure?.underlyingCode)
    }

    func testRejectsNonFileURL() {
        let result = PersistenceService().read(
            from: URL(string: "https://example.com/document.md")!
        )

        XCTAssertEqual(readFailure(result)?.kind, .invalidFileURL)
    }

    func testReadFailureIsStructuredAndReturnsNoPartialText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("unreadable.md")
        try Data("partial".utf8).write(to: fileURL)
        let service = PersistenceService(
            readData: { _ in throw TestFailure.forcedReadFailure },
            writeDataAtomically: { data, url in
                try data.write(to: url, options: [.atomic])
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )

        let result = service.read(from: fileURL)

        XCTAssertEqual(readFailure(result)?.kind, .readFailure)
        if case .success = result {
            XCTFail("A failed read exposed adoptable text")
        }
    }

    func testPermissionDeniedIsStructured() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("protected.md")
        try Data("Text".utf8).write(to: fileURL)
        let service = PersistenceService(
            readData: { _ in
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoPermissionError
                )
            },
            writeDataAtomically: { data, url in
                try data.write(to: url, options: [.atomic])
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )

        XCTAssertEqual(
            readFailure(service.read(from: fileURL))?.kind,
            .permissionDenied
        )
    }

    func testPreservesLFOnRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("lf.txt")
        let text = "a\nb\n"
        try Data(text.utf8).write(to: fileURL)

        XCTAssertEqual(readSuccess(PersistenceService().read(from: fileURL))?.text, text)
    }

    func testPreservesCRLFOnRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("crlf.txt")
        let text = "a\r\nb\r\n"
        try Data(text.utf8).write(to: fileURL)

        XCTAssertEqual(readSuccess(PersistenceService().read(from: fileURL))?.text, text)
    }

    func testPreservesCROnRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("cr.txt")
        let text = "a\rb\r"
        try Data(text.utf8).write(to: fileURL)

        XCTAssertEqual(readSuccess(PersistenceService().read(from: fileURL))?.text, text)
    }

    func testWritesSnapshotToNewFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("new.md")
        let request = makeRequest(text: "Snapshot", destinationURL: fileURL)

        let completion = PersistenceService().write(request)

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(completion.operationID, request.operationID)
        XCTAssertEqual(completion.operationSequence, request.operationSequence)
        XCTAssertEqual(completion.documentGeneration, request.documentGeneration)
        XCTAssertEqual(completion.snapshotRevision, request.snapshot.revision)
        XCTAssertEqual(completion.targetFileURL, fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("Snapshot".utf8))
    }

    func testAtomicallyUpdatesExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("existing.md")
        try Data("Before".utf8).write(to: fileURL)
        let request = makeRequest(text: "After", destinationURL: fileURL)

        let completion = PersistenceService().write(request)

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("After".utf8))
    }

    func testWritesEmptySnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("empty.md")

        let completion = PersistenceService().write(
            makeRequest(text: "", destinationURL: fileURL)
        )

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data())
    }

    func testWritesUnicodeAsUTF8() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("unicode.md")
        let text = "日本語 📝 café"

        let completion = PersistenceService().write(
            makeRequest(text: text, destinationURL: fileURL)
        )

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(text.utf8))
    }

    func testDoesNotAddUTF8BOMOnWrite() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("no-bom.md")

        XCTAssertEqual(
            PersistenceService().write(
                makeRequest(text: "Text", destinationURL: fileURL)
            ).outcome,
            .success
        )

        let data = try Data(contentsOf: fileURL)
        XCTAssertFalse(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    }

    func testWriteFailureIsStructured() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("failure.md")
        let service = PersistenceService(
            readData: { try Data(contentsOf: $0) },
            writeDataAtomically: { _, _ in throw TestFailure.forcedWriteFailure },
            fileExists: { _ in false }
        )

        let failure = writeFailure(
            service.write(makeRequest(text: "Text", destinationURL: fileURL))
        )

        XCTAssertEqual(failure?.kind, .writeFailure)
        XCTAssertNotNil(failure?.underlyingDomain)
        XCTAssertNotNil(failure?.underlyingCode)
    }

    func testWriteUsesFrozenSnapshotDespiteLaterEditing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.md")
        var state = EditorState(initialText: "Before", documentURL: fileURL)
        state.applyEditorText("Frozen")
        let request = state.makeSaveRequest()
        state.applyEditorText("Later edit")

        let completion = PersistenceService().write(request)

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("Frozen".utf8))
        XCTAssertEqual(state.text, "Later edit")
        XCTAssertTrue(state.isDirty)
    }

    func testDoesNotAddWorkbenchMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("plain.xmd")
        let text = "<document>\nBody\n</document>"

        XCTAssertEqual(
            PersistenceService().write(
                makeRequest(text: text, destinationURL: fileURL)
            ).outcome,
            .success
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), Data(text.utf8))
    }

    func testPreservesLineEndingsOnWrite() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("line-endings.txt")
        let text = "lf\ncrlf\r\ncr\r"

        XCTAssertEqual(
            PersistenceService().write(
                makeRequest(text: text, destinationURL: fileURL)
            ).outcome,
            .success
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), Data(text.utf8))
    }

    func testAtomicReplacementFailureIsNotReportedAsSuccess() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("existing.md")
        try Data("Original".utf8).write(to: fileURL)
        let service = PersistenceService(
            readData: { try Data(contentsOf: $0) },
            writeDataAtomically: { _, _ in throw TestFailure.forcedWriteFailure },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )

        let completion = service.write(
            makeRequest(text: "Replacement", destinationURL: fileURL)
        )

        XCTAssertEqual(writeFailure(completion)?.kind, .atomicReplacementFailure)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("Original".utf8))
    }

    func testReadsUTF8XMLAsOrdinaryText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("document.xml")
        let text = #"<?xml version="1.0" encoding="UTF-8"?><root>日本語</root>"#
        try Data(text.utf8).write(to: fileURL)

        XCTAssertEqual(readSuccess(PersistenceService().read(from: fileURL))?.text, text)
    }

    func testRoundTripsXMLAsOrdinaryText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.xml")
        let targetURL = directory.appendingPathComponent("target.xml")
        let text = "<?xml version=\"1.0\"?>\r\n<root>Body</root>\r\n"
        try Data(text.utf8).write(to: sourceURL)
        let read = try XCTUnwrap(
            readSuccess(PersistenceService().read(from: sourceURL))
        )

        let completion = PersistenceService().write(
            makeRequest(text: read.text, destinationURL: targetURL)
        )

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(try Data(contentsOf: targetURL), Data(text.utf8))
    }

    func testDoesNotInsertXMLDeclaration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("no-declaration.xml")
        let text = "<root>Body</root>"

        XCTAssertEqual(
            PersistenceService().write(
                makeRequest(text: text, destinationURL: fileURL)
            ).outcome,
            .success
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), Data(text.utf8))
    }

    func testDoesNotRewriteXMLDeclaration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("declaration.xml")
        let text = #"<?xml version='1.0' encoding='utf-8'?><root/>"#

        XCTAssertEqual(
            PersistenceService().write(
                makeRequest(text: text, destinationURL: fileURL)
            ).outcome,
            .success
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), Data(text.utf8))
    }

    func testAcceptsCaseInsensitiveUTF8XMLDeclaration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("case.XML")
        let text = #"<?xml version="1.0" encoding="uTf-8"?><root/>"#
        try Data(text.utf8).write(to: fileURL)

        XCTAssertEqual(readSuccess(PersistenceService().read(from: fileURL))?.text, text)
    }

    func testRejectsExplicitNonUTF8XMLDeclaration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("latin.xml")
        let text = #"<?xml version="1.0" encoding="ISO-8859-1"?><root/>"#
        try Data(text.utf8).write(to: fileURL)

        let failure = readFailure(PersistenceService().read(from: fileURL))

        XCTAssertEqual(failure?.kind, .unsupportedXMLDeclaredEncoding)
        XCTAssertEqual(failure?.diagnostic, "Declared encoding: ISO-8859-1")
    }

    func testRejectsWritingExplicitNonUTF8XMLDeclaration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("latin.xml")
        let text = #"<?xml version="1.0" encoding="ISO-8859-1"?><root/>"#

        let completion = PersistenceService().write(
            makeRequest(text: text, destinationURL: fileURL)
        )

        XCTAssertEqual(
            writeFailure(completion)?.kind,
            .unsupportedXMLDeclaredEncoding
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRejectsUTF16AndUTF32BOMs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let utf16URL = directory.appendingPathComponent("utf16.xml")
        let utf32URL = directory.appendingPathComponent("utf32.xml")
        try Data([0xFF, 0xFE, 0x3C, 0x00]).write(to: utf16URL)
        try Data([0x00, 0x00, 0xFE, 0xFF]).write(to: utf32URL)

        XCTAssertEqual(
            readFailure(PersistenceService().read(from: utf16URL))?.kind,
            .unsupportedBOM
        )
        XCTAssertEqual(
            readFailure(PersistenceService().read(from: utf32URL))?.kind,
            .unsupportedBOM
        )
    }

    func testDoesNotParseDTDOrResolveExternalEntity() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("entity.xml")
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE root [<!ENTITY external SYSTEM "file:///not-read.txt">]>
        <root>&external;</root>
        """
        try Data(text.utf8).write(to: fileURL)

        let success = readSuccess(PersistenceService().read(from: fileURL))

        XCTAssertEqual(success?.text, text)
        XCTAssertTrue(success?.text.contains("&external;") == true)
    }

    func testSupportedExtensionMatchingIsCaseInsensitive() {
        let service = PersistenceService()

        XCTAssertEqual(
            service.extensionAdvisory(
                for: URL(fileURLWithPath: "/tmp/document.MarkDown")
            ),
            .supported
        )
        XCTAssertEqual(
            service.extensionAdvisory(
                for: URL(fileURLWithPath: "/tmp/document.XML")
            ),
            .supported
        )
    }

    func testUnknownExtensionIsAdvisoryAndNonBlocking() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("document.custom")
        try Data("Text".utf8).write(to: fileURL)

        let success = readSuccess(PersistenceService().read(from: fileURL))

        XCTAssertEqual(success?.text, "Text")
        XCTAssertEqual(success?.extensionAdvisory, .unknown)
    }

    func testOutcomeModelsDistinguishCancellation() {
        let fileURL = URL(fileURLWithPath: "/tmp/document.md")
        let request = makeRequest(text: "Text", destinationURL: fileURL)
        let readResult = PersistenceReadResult.cancellation(sourceFileURL: fileURL)
        let writeCompletion = PersistenceWriteCompletion(
            request: request,
            targetFileURL: fileURL,
            outcome: .cancellation
        )

        XCTAssertEqual(
            readResult,
            .cancellation(sourceFileURL: fileURL)
        )
        XCTAssertEqual(writeCompletion.outcome, .cancellation)
    }

    func testWriteRejectsMissingOrNonFileTarget() {
        let missingTargetRequest = SaveRequest(
            snapshot: CanonicalSourceSnapshot(text: "Text", revision: .initial)
        )
        let nonFileTarget = URL(string: "https://example.com/document.md")!
        let nonFileRequest = makeRequest(
            text: "Text",
            destinationURL: nonFileTarget
        )

        XCTAssertEqual(
            writeFailure(PersistenceService().write(missingTargetRequest))?.kind,
            .invalidFileURL
        )
        XCTAssertEqual(
            writeFailure(PersistenceService().write(nonFileRequest))?.kind,
            .invalidFileURL
        )
    }
}
