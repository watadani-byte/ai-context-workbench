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
