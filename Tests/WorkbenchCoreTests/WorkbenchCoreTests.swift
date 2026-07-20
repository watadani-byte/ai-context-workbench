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
