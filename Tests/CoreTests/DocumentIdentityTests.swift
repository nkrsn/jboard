import Foundation
import XCTest
@testable import JBoardCore

private final class UnattachedDocument: NSObject {
    @objc var documentIdentifier: NSUUID? { nil }
}
private final class AttachedDocument: NSObject {
    let id = NSUUID()
    @objc var documentIdentifier: NSUUID? { id }
}
final class DocumentIdentityTests: XCTestCase {
    func testStartupWithoutDocumentDoesNotBridgeNilUUID() {
        XCTAssertNil(DocumentIdentity.read(from: UnattachedDocument()))
    }
    func testAttachedDocumentKeepsItsStableIdentity() {
        let document = AttachedDocument()
        XCTAssertEqual(DocumentIdentity.read(from: document), document.id as UUID)
        XCTAssertEqual(DocumentIdentity.read(from: document), DocumentIdentity.read(from: document))
    }
    func testMissingGetterIsSafelyUnavailable() {
        XCTAssertNil(DocumentIdentity.read(from: NSObject()))
    }
}
