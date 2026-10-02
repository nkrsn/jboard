import UIKit

final class ProxyDocument: TextDocument {
    private let proxy: () -> UITextDocumentProxy
    init(proxy: @escaping () -> UITextDocumentProxy) { self.proxy = proxy }
    var beforeInput: String? { proxy().documentContextBeforeInput }
    var afterInput: String? { proxy().documentContextAfterInput }
    var selection: String? { proxy().selectedText }
    func insertText(_ text: String) { proxy().insertText(text) }
    func deleteBackward() { proxy().deleteBackward() }
}
