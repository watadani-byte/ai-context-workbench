#if canImport(SwiftUI)
import SwiftUI
import WorkbenchCore

@main
struct AIContextWorkbenchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        Text(WorkbenchCore.productName)
            .frame(minWidth: 640, minHeight: 420)
    }
}
#else
import WorkbenchCore

@main
enum AIContextWorkbenchApp {
    static func main() {
        print("\(WorkbenchCore.productName) requires macOS with SwiftUI.")
    }
}
#endif
