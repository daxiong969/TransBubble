import Foundation
import SafariServices
import os.log

/// Safari Web Extension 与原生 App 的通信桥
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        os_log(.default, "TransBubble 收到原生消息: %@", message.debugDescription)

        let response = NSExtensionItem()
        response.userInfo = [
            SFExtensionMessageKey: [
                "ok": true,
                "echo": message ?? [:]
            ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
