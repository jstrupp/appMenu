import SwiftUI
import AppKit
import WebKit

enum HelpManager {
    static func openHelp(anchor: String? = nil) {
        // Try to open the bundled Help.html in the default browser.
        if let url = Bundle.main.url(forResource: "Help", withExtension: "html") {
            let finalURL: URL
            if let anchor, !anchor.isEmpty {
                // Append #anchor if provided
                // URLComponents doesn’t handle fragments for file URLs well; build manually:
                finalURL = URL(string: url.absoluteString + "#" + anchor) ?? url
            } else {
                finalURL = url
            }
            NSWorkspace.shared.open(finalURL)
        } else {
            // Beep, log, and fall back to an in-app help window.
            NSSound.beep()
            NSLog("HelpManager: Help.html not found in bundle. Falling back to in-app help window.")
            presentFallbackHelpWindow()
        }
    }
    
    // MARK: - Fallback: simple help window with WebView if resource exists
    private static var window: NSWindow?
    
    private static func presentFallbackHelpWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let vc = NSHostingController(rootView: HelpView())
        let w = NSWindow(contentViewController: vc)
        w.title = "appMenu Help"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 720, height: 560))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct HelpView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("appMenu Help").font(.headline)
                Spacer()
                Button("Open in Browser") {
                    if let url = Bundle.main.url(forResource: "Help", withExtension: "html") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding()
            Divider()
            HelpWebView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HelpWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        if let url = Bundle.main.url(forResource: "Help", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = """
            <html><head><meta charset="utf-8"><style>body{font-family:-apple-system;padding:20px}</style></head>
            <body><h2>Help Not Found</h2><p>The bundled Help.html could not be located in the app bundle.</p>
            <p>Make sure Help.html is added to the app target under “Copy Bundle Resources”.</p></body></html>
            """
            web.loadHTMLString(html, baseURL: nil)
        }
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
