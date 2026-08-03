#if canImport(SwiftUI)
import SwiftUI
import WorkbenchCore

#if canImport(AppKit)
import AppKit
#endif

@main
struct AIContextWorkbenchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
private struct ContentView: View {
    @State private var lifecycle: ApplicationLifecycleCoordinator

    init() {
        _lifecycle = State(
            initialValue: ApplicationLifecycleCoordinator(
                editorState: EditorState(
                    initialText: "AI Context Workbench\n\nCanonical document"
                ),
                selectOpenURL: {
#if canImport(AppKit)
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    return panel.runModal() == .OK ? panel.url : nil
#else
                    return nil
#endif
                },
                selectSaveURL: {
#if canImport(AppKit)
                    let panel = NSSavePanel()
                    panel.canCreateDirectories = true
                    return panel.runModal() == .OK ? panel.url : nil
#else
                    return nil
#endif
                }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(WorkbenchCore.productName)
                    .font(.headline)
                Spacer()
                Text(lifecycle.editorState.documentURL?.lastPathComponent ?? "Untitled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(lifecycle.editorState.isDirty ? "Modified" : "Clean")
                    .font(.caption)
                    .foregroundStyle(lifecycle.editorState.isDirty ? .primary : .secondary)

                Text("Revision \(lifecycle.editorState.revision.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("New") {
                    Task { await lifecycle.requestNewDocument() }
                }

                Button("Open") {
                    Task { await lifecycle.requestOpenDocument() }
                }

                Button("Save") {
                    Task { await lifecycle.requestSave() }
                }

                Button("Save As") {
                    Task { await lifecycle.requestSaveAs() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            PlatformTextView(
                text: lifecycle.editorState.text,
                revision: lifecycle.editorState.revision,
                onTextChange: { newText in
                    lifecycle.applyEditorText(newText)
                }
            )
        }
        .frame(minWidth: 640, minHeight: 420)
        .confirmationDialog(
            "Save changes before continuing?",
            isPresented: Binding(
                get: { lifecycle.isAwaitingDirtyDecision },
                set: { _ in }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await lifecycle.resolveDirtyDecision(.save) }
            }
            Button("Discard Changes", role: .destructive) {
                Task { await lifecycle.resolveDirtyDecision(.discard) }
            }
            Button("Cancel", role: .cancel) {
                Task { await lifecycle.resolveDirtyDecision(.cancel) }
            }
        }
        .alert(
            lifecycle.notice?.title ?? "",
            isPresented: Binding(
                get: { lifecycle.notice != nil },
                set: { isPresented in
                    if !isPresented {
                        lifecycle.acknowledgeNotice()
                    }
                }
            )
        ) {
            Button("OK") {
                lifecycle.acknowledgeNotice()
            }
        } message: {
            Text(lifecycle.notice?.message ?? "")
        }
    }
}

#if canImport(AppKit)
private final class TransactionBoundaryTextView: NSTextView {
    private enum IMETransactionState: String {
        case idle
        case composing
        case committedPendingBoundary
    }

    private var imeTransactionState: IMETransactionState = .idle
    private var imeTransactionSequence = 0
    private var activeIMETransaction: Int?

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
#if DEBUG
        logLifecycleDiagnostic(method: "setMarkedText", phase: "entry")
#endif
        beginOrContinueIMETransaction()
#if DEBUG
        logLifecycleDiagnostic(method: "setMarkedText", phase: "before-super")
#endif
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        imeTransactionState = .composing
#if DEBUG
        logLifecycleDiagnostic(method: "setMarkedText", phase: "exit")
#endif
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let commitsMarkedText = hasMarkedText()
#if DEBUG
        logLifecycleDiagnostic(
            method: "insertText",
            phase: "entry",
            commitsMarkedText: commitsMarkedText
        )
#endif

        if !commitsMarkedText {
            closePendingIMETransaction(reason: "before-direct-insert")
        }
#if DEBUG
        logLifecycleDiagnostic(
            method: "insertText",
            phase: "before-super",
            commitsMarkedText: commitsMarkedText
        )
#endif
        super.insertText(insertString, replacementRange: replacementRange)
#if DEBUG
        logLifecycleDiagnostic(
            method: "insertText",
            phase: "after-super",
            commitsMarkedText: commitsMarkedText
        )
#endif

        if commitsMarkedText {
            imeTransactionState = .committedPendingBoundary
        }
#if DEBUG
        logLifecycleDiagnostic(
            method: "insertText",
            phase: "exit",
            commitsMarkedText: commitsMarkedText
        )
#endif
    }

    override func unmarkText() {
        let commitsMarkedText = hasMarkedText()
#if DEBUG
        logLifecycleDiagnostic(
            method: "unmarkText",
            phase: "entry",
            commitsMarkedText: commitsMarkedText
        )
#endif

        super.unmarkText()
        if commitsMarkedText {
            imeTransactionState = .committedPendingBoundary
        }
#if DEBUG
        logLifecycleDiagnostic(
            method: "unmarkText",
            phase: "exit",
            commitsMarkedText: commitsMarkedText
        )
#endif
    }

    override func doCommand(by selector: Selector) {
        if imeTransactionState == .committedPendingBoundary {
            closePendingIMETransaction(reason: "before-command:\(NSStringFromSelector(selector))")
        }
        super.doCommand(by: selector)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isUndoOrRedo = commandFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "z"

        if isUndoOrRedo {
            closePendingIMETransaction(reason: "before-key-equivalent-undo-redo")
        }
        return super.performKeyEquivalent(with: event)
    }

    private func beginOrContinueIMETransaction() {
        switch imeTransactionState {
        case .idle:
            breakUndoCoalescing()
            imeTransactionSequence += 1
            activeIMETransaction = imeTransactionSequence
#if DEBUG
            logBoundaryDiagnostic(reason: "before-composition-start")
#endif
        case .composing, .committedPendingBoundary:
            break
        }
        imeTransactionState = .composing
    }

    private func closePendingIMETransaction(reason: String) {
        guard imeTransactionState == .committedPendingBoundary else {
            return
        }

        breakUndoCoalescing()
#if DEBUG
        logBoundaryDiagnostic(reason: reason)
#endif
        imeTransactionState = .idle
        activeIMETransaction = nil
    }

#if DEBUG
    private func logLifecycleDiagnostic(
        method: String,
        phase: String,
        commitsMarkedText: Bool? = nil
    ) {
        let undo = undoManager
        let message = [
            "transaction=\(activeIMETransaction.map { String($0) } ?? "none")",
            "state=\(imeTransactionState.rawValue)",
            "method=\(method)",
            "phase=\(phase)",
            "commitCandidate=\(commitsMarkedText.map { String($0) } ?? "n/a")",
            "hasMarkedText=\(hasMarkedText())",
            "markedRange=\(diagnosticRange(markedRange()))",
            "selectedRange=\(diagnosticRange(selectedRange()))",
            "undoGroupingLevel=\(undo?.groupingLevel ?? -1)",
            "canUndo=\(undo?.canUndo ?? false)",
            "canRedo=\(undo?.canRedo ?? false)",
            "isUndoing=\(undo?.isUndoing ?? false)",
            "isRedoing=\(undo?.isRedoing ?? false)"
        ].joined(separator: " ")

        NSLog("%@", "[ST3-WP02-IME-LIFECYCLE] \(message)")
    }

    private func logBoundaryDiagnostic(reason: String) {
        let undo = undoManager
        let message = [
            "transaction=\(activeIMETransaction.map { String($0) } ?? "none")",
            "state=\(imeTransactionState.rawValue)",
            "boundary=\(reason)",
            "hasMarkedText=\(hasMarkedText())",
            "markedRange=\(diagnosticRange(markedRange()))",
            "selectedRange=\(diagnosticRange(selectedRange()))",
            "undoGroupingLevel=\(undo?.groupingLevel ?? -1)",
            "canUndo=\(undo?.canUndo ?? false)",
            "canRedo=\(undo?.canRedo ?? false)",
            "isUndoing=\(undo?.isUndoing ?? false)",
            "isRedoing=\(undo?.isRedoing ?? false)"
        ].joined(separator: " ")

        NSLog("%@", "[ST3-WP02-IME-LIFECYCLE] \(message)")
    }

    private func diagnosticRange(_ range: NSRange) -> String {
        guard range.location != NSNotFound else {
            return "not-found"
        }

        return "\(range.location):\(range.length)"
    }
#endif
}

private struct PlatformTextView: NSViewRepresentable {
    let text: String
    let revision: CanonicalSourceRevision
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = TransactionBoundaryTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = text

        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTextChange = onTextChange

        guard let textView = context.coordinator.textView,
              textView.string != text else {
            context.coordinator.appliedRevision = revision
            return
        }

        let selectedRanges = textView.selectedRanges
        context.coordinator.isApplyingCanonicalText = true
        textView.string = text
        context.coordinator.isApplyingCanonicalText = false
        context.coordinator.appliedRevision = revision

        let textLength = (text as NSString).length
        textView.selectedRanges = selectedRanges.map { value in
            let range = value.rangeValue
            let restored = EditorSelectionRange(
                location: range.location,
                length: range.length
            ).clamped(toUTF16Length: textLength)

            return NSValue(
                range: NSRange(
                    location: restored.location,
                    length: restored.length
                )
            )
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        weak var textView: NSTextView?
        var appliedRevision = CanonicalSourceRevision.initial
        var isApplyingCanonicalText = false
        var inputTransactionGate = EditorInputTransactionGate()

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingCanonicalText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            guard let committedText = inputTransactionGate.observe(
                text: textView.string,
                hasMarkedText: textView.hasMarkedText()
            ) else {
                return
            }

            onTextChange(committedText)
        }
    }
}
#else
private struct PlatformTextView: View {
    let text: String
    let revision: CanonicalSourceRevision
    let onTextChange: (String) -> Void

    var body: some View {
        TextEditor(
            text: Binding(
                get: { text },
                set: onTextChange
            )
        )
    }
}
#endif
#else
import WorkbenchCore

@main
enum AIContextWorkbenchApp {
    static func main() {
        print("\(WorkbenchCore.productName) requires macOS with SwiftUI.")
    }
}
#endif
