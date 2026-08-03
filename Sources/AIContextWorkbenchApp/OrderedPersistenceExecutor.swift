import Dispatch
import WorkbenchCore

/// Application-owned execution boundary for persistence work.
///
/// A single serial queue guarantees that physical writes never overlap and
/// begin in submission order. Requests and service completions cross this
/// boundary without reconstruction.
final class OrderedPersistenceExecutor: @unchecked Sendable {
    typealias ReadOperation = @Sendable (PersistenceReadRequest) -> PersistenceReadCompletion
    typealias WriteOperation = @Sendable (SaveRequest) -> PersistenceWriteCompletion

    private let queue: DispatchQueue
    private let readOperation: ReadOperation
    private let writeOperation: WriteOperation

    init(
        label: String = "com.watadani.ai-context-workbench.persistence",
        readOperation: @escaping ReadOperation = { request in
            PersistenceService().read(request)
        },
        writeOperation: @escaping WriteOperation = { request in
            PersistenceService().write(request)
        }
    ) {
        queue = DispatchQueue(label: label)
        self.readOperation = readOperation
        self.writeOperation = writeOperation
    }

    func read(_ request: PersistenceReadRequest) async -> PersistenceReadCompletion {
        await withCheckedContinuation { continuation in
            queue.async { [readOperation] in
                continuation.resume(returning: readOperation(request))
            }
        }
    }

    func write(_ request: SaveRequest) async -> PersistenceWriteCompletion {
        await withCheckedContinuation { continuation in
            queue.async { [writeOperation] in
                continuation.resume(returning: writeOperation(request))
            }
        }
    }
}
