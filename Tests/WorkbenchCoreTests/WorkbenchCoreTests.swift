import XCTest
@testable import WorkbenchCore

final class WorkbenchCoreTests: XCTestCase {
    func testProductIdentityIsAvailableToApplicationShell() {
        XCTAssertEqual(WorkbenchCore.productName, "AI Context Workbench")
        XCTAssertEqual(WorkbenchCore.version, "0.1")
    }
}
