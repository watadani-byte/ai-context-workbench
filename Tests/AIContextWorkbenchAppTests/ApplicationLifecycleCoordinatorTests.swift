import Foundation
import Dispatch
import XCTest
import WorkbenchCore

@testable import AIContextWorkbenchApp

final class ApplicationLifecycleCoordinatorTests: XCTestCase {
    @MainActor
    func testNewFromCleanBeginsNewDocument() async {
        let coordinator = makeCoordinator(editorState: EditorState(initialText: "clean"))

        await coordinator.requestNewDocument()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.editorState.text, "")
        XCTAssertNil(coordinator.editorState.documentURL)
    }

    @MainActor
    func testDirtyNewCancelPreservesDocument() async {
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state)

        await coordinator.requestNewDocument()
        XCTAssertEqual(coordinator.phase, .awaitingDirtyDecision(.newDocument))
        await coordinator.resolveDirtyDecision(.cancel)

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.editorState.text, "edited")
        XCTAssertTrue(coordinator.editorState.isDirty)
    }

    @MainActor
    func testDirtyNewDiscardBeginsNewWithoutPersistence() async {
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state)

        await coordinator.requestNewDocument()
        await coordinator.resolveDirtyDecision(.discard)

        XCTAssertEqual(coordinator.editorState.text, "")
        XCTAssertFalse(coordinator.editorState.isDirty)
        XCTAssertEqual(coordinator.editorState.persistenceState.pendingOperationCount, 0)
    }

    @MainActor
    func testDirtyNewContinuesOnlyAfterAcceptedSave() async throws {
        let destination = try temporaryFileURL()
        var state = EditorState(initialText: "baseline", documentURL: destination)
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state)

        await coordinator.requestNewDocument()
        await coordinator.resolveDirtyDecision(.save)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "edited")
        XCTAssertEqual(coordinator.editorState.text, "")
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testOpenFromCleanAppliesActualReadCompletion() async throws {
        let source = try temporaryFileURL(contents: "opened")
        let coordinator = makeCoordinator(
            editorState: EditorState(initialText: "current"),
            openURL: source
        )

        await coordinator.requestOpenDocument()

        XCTAssertEqual(coordinator.editorState.text, "opened")
        XCTAssertEqual(coordinator.editorState.documentURL, source)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testDirtyOpenDiscardKeepsCurrentDocumentUntilSelectionAndReadSucceed() async {
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state, openURL: nil)

        await coordinator.requestOpenDocument()
        await coordinator.resolveDirtyDecision(.discard)

        XCTAssertEqual(coordinator.editorState.text, "edited")
        XCTAssertTrue(coordinator.editorState.isDirty)
        XCTAssertEqual(coordinator.editorState.persistenceState.pendingOperationCount, 0)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testOpenPanelCancellationCreatesNoPersistenceOperation() async {
        let coordinator = makeCoordinator(
            editorState: EditorState(initialText: "current"),
            openURL: nil
        )

        await coordinator.requestOpenDocument()

        XCTAssertEqual(coordinator.editorState.text, "current")
        XCTAssertEqual(coordinator.editorState.persistenceState.pendingOperationCount, 0)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testSaveAsCancellationCreatesNoPersistenceOperation() async {
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state, saveURL: nil)

        await coordinator.requestSaveAs()

        XCTAssertNil(coordinator.editorState.documentURL)
        XCTAssertTrue(coordinator.editorState.isDirty)
        XCTAssertEqual(coordinator.editorState.persistenceState.pendingOperationCount, 0)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testSaveAsAdoptsURLOnlyAfterAcceptedSuccessfulWrite() async throws {
        let destination = try temporaryFileURL()
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state, saveURL: destination)

        await coordinator.requestSaveAs()

        XCTAssertEqual(coordinator.editorState.documentURL, destination)
        XCTAssertFalse(coordinator.editorState.isDirty)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "edited")
    }

    @MainActor
    func testWriteFailurePreservesDirtyStateAndPresentsGeneralNotice() async {
        let destination = URL(fileURLWithPath: "/")
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state, saveURL: destination)

        await coordinator.requestSaveAs()

        XCTAssertNil(coordinator.editorState.documentURL)
        XCTAssertTrue(coordinator.editorState.isDirty)
        XCTAssertEqual(coordinator.notice, .writeFailure)
        XCTAssertEqual(coordinator.phase, .presentingNotice)
    }

    @MainActor
    func testRejectedWriteCompletionDoesNotAdoptURLOrCleanState() async throws {
        let destination = try temporaryFileURL()
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let executor = OrderedPersistenceExecutor(
            writeOperation: { request in
                PersistenceWriteCompletion(
                    operationID: PersistenceOperationID(),
                    operationSequence: request.operationSequence,
                    documentGeneration: request.documentGeneration,
                    snapshotRevision: request.snapshot.revision,
                    targetFileURL: request.destinationURL,
                    outcome: .success
                )
            }
        )
        let coordinator = makeCoordinator(
            editorState: state,
            executor: executor,
            saveURL: destination
        )

        await coordinator.requestSaveAs()

        XCTAssertNil(coordinator.editorState.documentURL)
        XCTAssertTrue(coordinator.editorState.isDirty)
        XCTAssertEqual(coordinator.notice, .writeCompletionRejected)
    }

    @MainActor
    func testRejectedReadCompletionPreservesCurrentDocument() async throws {
        let source = try temporaryFileURL(contents: "candidate")
        let executor = OrderedPersistenceExecutor(
            readOperation: { request in
                PersistenceReadCompletion(
                    operationID: PersistenceOperationID(),
                    operationSequence: request.operationSequence,
                    documentGeneration: request.documentGeneration,
                    sourceFileURL: request.sourceFileURL,
                    result: .success(
                        PersistenceReadSuccess(
                            sourceFileURL: request.sourceFileURL,
                            text: "candidate",
                            hadUTF8BOM: false,
                            extensionAdvisory: .supported
                        )
                    )
                )
            }
        )
        let coordinator = makeCoordinator(
            editorState: EditorState(initialText: "current"),
            executor: executor,
            openURL: source
        )

        await coordinator.requestOpenDocument()

        XCTAssertEqual(coordinator.editorState.text, "current")
        XCTAssertNil(coordinator.editorState.documentURL)
        XCTAssertEqual(coordinator.notice, .readCompletionRejected)
    }

    @MainActor
    func testLifecycleCommandsAreGatedDuringActiveWriteAndNotQueued() async throws {
        let destination = try temporaryFileURL()
        var state = EditorState(initialText: "baseline", documentURL: destination)
        state.applyEditorText("edited")
        let probe = BlockingCoordinatorWriteProbe()
        let executor = OrderedPersistenceExecutor(
            writeOperation: { request in probe.perform(request) }
        )
        let coordinator = makeCoordinator(editorState: state, executor: executor)

        let save = Task { await coordinator.requestSave() }
        await Task.yield()
        XCTAssertEqual(probe.started.wait(timeout: .now() + 2), .success)

        await coordinator.requestNewDocument()
        await coordinator.requestOpenDocument()

        XCTAssertEqual(coordinator.notice, .temporarilyUnavailable)
        XCTAssertEqual(coordinator.editorState.text, "edited")
        probe.release.signal()
        await save.value

        XCTAssertEqual(coordinator.editorState.text, "edited")
        XCTAssertFalse(coordinator.editorState.isDirty)
        XCTAssertEqual(probe.writeCount, 1)
    }

    @MainActor
    func testNoticeAcknowledgementDoesNotMutateDomainState() async {
        let destination = URL(fileURLWithPath: "/")
        var state = EditorState(initialText: "baseline")
        state.applyEditorText("edited")
        let coordinator = makeCoordinator(editorState: state, saveURL: destination)

        await coordinator.requestSaveAs()
        let before = coordinator.editorState
        coordinator.acknowledgeNotice()

        XCTAssertEqual(coordinator.editorState, before)
        XCTAssertNil(coordinator.notice)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    private func makeCoordinator(
        editorState: EditorState,
        executor: OrderedPersistenceExecutor = OrderedPersistenceExecutor(),
        openURL: URL? = nil,
        saveURL: URL? = nil
    ) -> ApplicationLifecycleCoordinator {
        ApplicationLifecycleCoordinator(
            editorState: editorState,
            executor: executor,
            selectOpenURL: { openURL },
            selectSaveURL: { saveURL }
        )
    }

    @MainActor
    private func temporaryFileURL(contents: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("document.md")
        if let contents {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return fileURL
    }
}

private final class BlockingCoordinatorWriteProbe: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var count = 0

    var writeCount: Int {
        lock.withLock { count }
    }

    func perform(_ request: SaveRequest) -> PersistenceWriteCompletion {
        lock.withLock { count += 1 }
        started.signal()
        release.wait()
        return PersistenceService().write(request)
    }
}
