import UIKit

/// Everything you'd normally want to change lives here.
enum Config {
    /// The site the app opens on launch (and when you press Play/Pause).
    static let homeURL = URL(string: "https://cinejoy.pk/")!

    /// The app stays on your site: links to other websites do nothing.
    /// If your site's login goes through another domain (e.g. "accounts.google.com"), add it here.
    static let extraAllowedHosts: [String] = []

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return true }
        guard let host = url.host?.lowercased() else { return false }
        var site = homeURL.host?.lowercased() ?? ""
        if site.hasPrefix("www.") { site.removeFirst(4) }
        let allowed = [site] + extraAllowedHosts.map { $0.lowercased() }
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Pretend to be desktop Safari so sites serve their normal layout.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// How far the cursor moves per unit of swipe on the remote's touch surface.
    static let cursorSpeed: CGFloat = 1.6

    /// Stop the Apple TV screensaver from kicking in while the app is open.
    static let keepScreenAwake = true

    /// Hide the cursor after this many seconds without touching the remote.
    static let cursorHideDelay: TimeInterval = 5
}
