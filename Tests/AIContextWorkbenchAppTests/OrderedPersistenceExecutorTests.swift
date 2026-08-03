import Foundation
import Dispatch
import XCTest
import WorkbenchCore

@testable import AIContextWorkbenchApp

final class OrderedPersistenceExecutorTests: XCTestCase {
    func testWritesExecuteInSubmissionOrderWithoutOverlap() async throws {
        let probe = BlockingWriteProbe()
        let executor = OrderedPersistenceExecutor(
            writeOperation: { request in probe.perform(request) }
        )
        let firstRequest = makeRequest(sequence: 1)
        let secondRequest = makeRequest(sequence: 2)

        let first = Task { await executor.write(firstRequest) }
        XCTAssertEqual(probe.firstStarted.wait(timeout: .now() + 2), .success)

        let second = Task { await executor.write(secondRequest) }
        await Task.yield()
        XCTAssertEqual(probe.startedSequences, [1])

        probe.releaseFirst.signal()
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(probe.startedSequences, [1, 2])
        XCTAssertEqual(probe.completedSequences, [1, 2])
        XCTAssertEqual(probe.maximumConcurrentWrites, 1)
    }

    func testExecutorReturnsTheOperationCompletionUnchanged() async {
        let request = makeRequest(sequence: 7)
        let expected = PersistenceWriteCompletion(
            request: request,
            targetFileURL: request.destinationURL,
            outcome: .failure(PersistenceFailure(kind: .permissionDenied))
        )
        let executor = OrderedPersistenceExecutor(
            writeOperation: { _ in expected }
        )

        let actual = await executor.write(request)

        XCTAssertEqual(actual, expected)
    }

    func testExecutorDoesNotReadLiveEditorState() async {
        var editorState = EditorState(initialText: "snapshot")
        let request = editorState.makeSaveRequest(
            saveAsURL: URL(fileURLWithPath: "/tmp/executor-snapshot.txt")
        )
        editorState.applyEditorText("later edit")
        let executor = OrderedPersistenceExecutor(
            writeOperation: { request in
                PersistenceWriteCompletion(
                    request: request,
                    targetFileURL: request.destinationURL,
                    outcome: request.snapshot.text == "snapshot"
                        ? .success
                        : .failure(PersistenceFailure(kind: .writeFailure))
                )
            }
        )

        let completion = await executor.write(request)

        XCTAssertEqual(completion.outcome, .success)
        XCTAssertEqual(editorState.text, "later edit")
    }

    private func makeRequest(sequence: UInt64) -> SaveRequest {
        SaveRequest(
            snapshot: CanonicalSourceSnapshot(
                text: "request-\(sequence)",
                revision: CanonicalSourceRevision(rawValue: sequence)
            ),
            operationSequence: PersistenceOperationSequence(rawValue: sequence),
            destinationURL: URL(fileURLWithPath: "/tmp/request-\(sequence).txt")
        )
    }
}

private final class BlockingWriteProbe: @unchecked Sendable {
    let firstStarted = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var activeWrites = 0
    private var maximumActiveWrites = 0
    private var starts: [UInt64] = []
    private var completions: [UInt64] = []

    var startedSequences: [UInt64] {
        lock.withLock { starts }
    }

    var completedSequences: [UInt64] {
        lock.withLock { completions }
    }

    var maximumConcurrentWrites: Int {
        lock.withLock { maximumActiveWrites }
    }

    func perform(_ request: SaveRequest) -> PersistenceWriteCompletion {
        lock.withLock {
            activeWrites += 1
            maximumActiveWrites = max(maximumActiveWrites, activeWrites)
            starts.append(request.operationSequence.rawValue)
        }

        if request.operationSequence.rawValue == 1 {
            firstStarted.signal()
            releaseFirst.wait()
        }

        lock.withLock {
            completions.append(request.operationSequence.rawValue)
            activeWrites -= 1
        }

        return PersistenceWriteCompletion(
            request: request,
            targetFileURL: request.destinationURL,
            outcome: .success
        )
    }
}
