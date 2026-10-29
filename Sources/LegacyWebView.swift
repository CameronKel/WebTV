import UIKit

/// tvOS has no public web view, but UIKit on the device still contains UIWebView;
/// it's just hidden from the SDK. We reach it through the Objective-C runtime.
/// Fine for a sideloaded app; the App Store would reject it.
final class LegacyWebView {
    let view: UIView
    private let delegate = Delegate()

    init?() {
        guard let cls = NSClassFromString("UIWebView") as? NSObject.Type,
              let view = cls.init() as? UIView else { return nil }
        self.view = view
        view.setValue(true, forKey: "scalesPageToFit")
        view.setValue(delegate, forKey: "delegate")
    }

    var onFinishLoad: (() -> Void)? {
        get { delegate.onFinish }
        set { delegate.onFinish = newValue }
    }

    var onFailLoad: ((Error) -> Void)? {
        get { delegate.onFail }
        set { delegate.onFail = newValue }
    }

    var canGoBack: Bool {
        (view.value(forKey: "canGoBack") as? Bool) ?? false
    }

    func load(_ url: URL) {
        _ = view.perform(NSSelectorFromString("loadRequest:"), with: URLRequest(url: url))
    }

    func goBack() {
        _ = view.perform(NSSelectorFromString("goBack"))
    }

    @discardableResult
    func evaluate(_ js: String) -> String {
        let result = view.perform(NSSelectorFromString("stringByEvaluatingJavaScriptFromString:"), with: js)
        return result?.takeUnretainedValue() as? String ?? ""
    }
}

/// Stands in for UIWebViewDelegate, which isn't visible to Swift on tvOS.
private final class Delegate: NSObject {
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    @objc(webView:shouldStartLoadWithRequest:navigationType:)
    func webView(_ webView: UIView, shouldStartLoadWith request: URLRequest, navigationType: Int) -> Bool {
        // Only police whole-page navigations; embedded frames (videos, maps) can come from anywhere.
        guard let url = request.url, request.mainDocumentURL == url else { return true }
        return Config.isAllowed(url)
    }

    @objc(webViewDidFinishLoad:)
    func webViewDidFinishLoad(_ webView: UIView) {
        onFinish?()
    }

    @objc(webView:didFailLoadWithError:)
    func webView(_ webView: UIView, didFailLoadWithError error: Error) {
        let nsError = error as NSError
        // Cancelled loads and "frame load interrupted" happen during normal navigation.
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) {
            return
        }
        onFail?(error)
    }
}
