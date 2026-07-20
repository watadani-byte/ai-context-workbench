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
    @State private var prototypeText = "AI Context Workbench\n\nNSTextView integration prototype"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(WorkbenchCore.productName)
                    .font(.headline)
                Spacer()
                Text("NSTextView Prototype")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            PlatformTextView(text: $prototypeText)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

#if canImport(AppKit)
private struct PlatformTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        guard let textView = context.coordinator.textView,
              textView.string != text else {
            return
        }

        let selectedRanges = textView.selectedRanges
        textView.string = text
        let textLength = (text as NSString).length
        let validSelections = selectedRanges.filter {
            NSMaxRange($0.rangeValue) <= textLength
        }
        textView.selectedRanges = validSelections.isEmpty
            ? [NSValue(range: NSRange(location: textLength, length: 0))]
            : validSelections
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}
#else
private struct PlatformTextView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
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
