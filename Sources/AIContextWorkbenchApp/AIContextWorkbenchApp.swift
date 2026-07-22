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

private struct ContentView: View {
    @State private var editorState = EditorState(
        initialText: "AI Context Workbench\n\nControlled synchronization prototype"
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(WorkbenchCore.productName)
                    .font(.headline)
                Spacer()
                Text(editorState.isDirty ? "Modified" : "Clean")
                    .font(.caption)
                    .foregroundStyle(editorState.isDirty ? .primary : .secondary)

                Text("Revision \(editorState.revision.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Load Sample") {
                    editorState.replaceCanonicalText(
                        with: "AI Context Workbench\n\nCanonical update at revision \(editorState.revision.rawValue + 1)"
                    )
                }

                Button("Simulate Save") {
                    let request = editorState.makeSaveRequest()
                    editorState.applySaveCompletion(.succeeded(request))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            PlatformTextView(
                text: editorState.text,
                revision: editorState.revision,
                onTextChange: { newText in
                    editorState.applyEditorText(newText)
                }
            )
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

#if canImport(AppKit)
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

        let textView = NSTextView(frame: .zero)
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
