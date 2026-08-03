import Foundation
import Observation
import WorkbenchCore

@MainActor
@Observable
final class ApplicationLifecycleCoordinator {
    enum LifecycleIntent: Equatable, Sendable {
        case newDocument
        case openDocument
    }

    enum DirtyDecision: Equatable, Sendable {
        case save
        case discard
        case cancel
    }

    enum WritePurpose: Equatable, Sendable {
        case ordinarySave
        case explicitSaveAs
        case saveBeforeNew
        case saveBeforeOpen
    }

    enum Phase: Equatable, Sendable {
        case idle
        case awaitingDirtyDecision(LifecycleIntent)
        case awaitingOpenSelection
        case awaitingSaveAsSelection(WritePurpose)
        case reading(PersistenceReadRequest)
        case writing(SaveRequest, WritePurpose)
        case presentingNotice
    }

    enum Notice: String, Equatable, Identifiable, Sendable {
        case readFailure
        case writeFailure
        case readCompletionRejected
        case writeCompletionRejected
        case temporarilyUnavailable

        var id: String { rawValue }

        var title: String {
            switch self {
            case .readFailure:
                return "Open Failed"
            case .writeFailure:
                return "Save Failed"
            case .readCompletionRejected, .writeCompletionRejected:
                return "Operation Could Not Be Applied"
            case .temporarilyUnavailable:
                return "Operation in Progress"
            }
        }

        var message: String {
            switch self {
            case .readFailure:
                return "The selected file could not be opened. The current document was preserved."
            case .writeFailure:
                return "The document could not be saved. Its current state was preserved."
            case .readCompletionRejected:
                return "The open result was no longer valid and was not applied."
            case .writeCompletionRejected:
                return "The save result was no longer valid and was not applied."
            case .temporarilyUnavailable:
                return "Finish or cancel the current document operation, then try again."
            }
        }
    }

    typealias URLSelection = @MainActor @Sendable () async -> URL?

    private(set) var editorState: EditorState
    private(set) var phase: Phase = .idle
    private(set) var notice: Notice?

    @ObservationIgnored
    private let executor: OrderedPersistenceExecutor
    @ObservationIgnored
    private let selectOpenURL: URLSelection
    @ObservationIgnored
    private let selectSaveURL: URLSelection

    init(
        editorState: EditorState = EditorState(),
        executor: OrderedPersistenceExecutor = OrderedPersistenceExecutor(),
        selectOpenURL: @escaping URLSelection,
        selectSaveURL: @escaping URLSelection
    ) {
        self.editorState = editorState
        self.executor = executor
        self.selectOpenURL = selectOpenURL
        self.selectSaveURL = selectSaveURL
    }

    var isAwaitingDirtyDecision: Bool {
        if case .awaitingDirtyDecision = phase {
            return true
        }
        return false
    }

    func applyEditorText(_ text: String) {
        editorState.applyEditorText(text)
    }

    func requestNewDocument() async {
        guard admitCommand() else { return }

        if editorState.isDirty {
            phase = .awaitingDirtyDecision(.newDocument)
        } else {
            editorState.beginNewDocument()
        }
    }

    func requestOpenDocument() async {
        guard admitCommand() else { return }

        if editorState.isDirty {
            phase = .awaitingDirtyDecision(.openDocument)
        } else {
            await selectAndOpenDocument()
        }
    }

    func requestSave() async {
        guard admitCommand() else { return }

        if editorState.documentURL == nil {
            await selectAndWrite(purpose: .ordinarySave)
        } else {
            await write(purpose: .ordinarySave, saveAsURL: nil)
        }
    }

    func requestSaveAs() async {
        guard admitCommand() else { return }
        await selectAndWrite(purpose: .explicitSaveAs)
    }

    func resolveDirtyDecision(_ decision: DirtyDecision) async {
        guard case .awaitingDirtyDecision(let intent) = phase else {
            return
        }

        switch decision {
        case .save:
            let purpose: WritePurpose = intent == .newDocument
                ? .saveBeforeNew
                : .saveBeforeOpen

            if editorState.documentURL == nil {
                await selectAndWrite(purpose: purpose)
            } else {
                await write(purpose: purpose, saveAsURL: nil)
            }
        case .discard:
            switch intent {
            case .newDocument:
                editorState.beginNewDocument()
                phase = .idle
            case .openDocument:
                await selectAndOpenDocument()
            }
        case .cancel:
            phase = .idle
        }
    }

    func acknowledgeNotice() {
        notice = nil
        if phase == .presentingNotice {
            phase = .idle
        }
    }

    private func admitCommand() -> Bool {
        guard phase == .idle, notice == nil else {
            notice = .temporarilyUnavailable
            return false
        }
        return true
    }

    private func selectAndOpenDocument() async {
        phase = .awaitingOpenSelection
        guard let sourceURL = await selectOpenURL() else {
            phase = .idle
            return
        }

        let request = editorState.makeReadRequest(sourceFileURL: sourceURL)
        phase = .reading(request)
        let completion = await executor.read(request)
        let accepted = editorState.applyReadCompletion(completion)

        switch completion.result {
        case .success:
            if accepted {
                phase = .idle
            } else {
                present(.readCompletionRejected)
            }
        case .failure:
            present(.readFailure)
        case .cancellation:
            phase = .idle
        }
    }

    private func selectAndWrite(purpose: WritePurpose) async {
        phase = .awaitingSaveAsSelection(purpose)
        guard let destinationURL = await selectSaveURL() else {
            phase = .idle
            return
        }

        await write(purpose: purpose, saveAsURL: destinationURL)
    }

    private func write(purpose: WritePurpose, saveAsURL: URL?) async {
        let request = editorState.makeSaveRequest(saveAsURL: saveAsURL)
        phase = .writing(request, purpose)
        let completion = await executor.write(request)
        let accepted = editorState.applyWriteCompletion(completion)

        switch completion.outcome {
        case .success where accepted:
            await continueAfterSuccessfulWrite(purpose)
        case .success:
            present(.writeCompletionRejected)
        case .failure:
            present(.writeFailure)
        case .cancellation:
            phase = .idle
        }
    }

    private func continueAfterSuccessfulWrite(_ purpose: WritePurpose) async {
        switch purpose {
        case .ordinarySave, .explicitSaveAs:
            phase = .idle
        case .saveBeforeNew:
            editorState.beginNewDocument()
            phase = .idle
        case .saveBeforeOpen:
            await selectAndOpenDocument()
        }
    }

    private func present(_ newNotice: Notice) {
        notice = newNotice
        phase = .presentingNotice
    }
}
