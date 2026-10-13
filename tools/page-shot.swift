// page-shot: a web page (a URL or an HTML file) rendered by Safari's engine at phone width, the whole page top to bottom,
// as a PNG. The hub uses it to show pages on the watch, which has no web engine of its own.
//   page-shot <url-or-file> <out.png> [width 390] [scale 2] [max width]
// It loads the page as an iPhone would (its user agent and width), waits for it to settle (its animations ended), grows
// the view to the page's full height (at most 9000 pt) and snapshots it. With a max width, a page wider than width (a
// wide table) widens the view up to it, and the picture stays at most 1200 px wide. Prints "<w>x<h>", with " cut" when
// the page was taller than 9000 pt. Exits 0 with the PNG written, 1 on a failure, 2 after 25 s.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("usage: page-shot <url-or-file> <out.png> [width] [scale] [max width]\n".data(using: .utf8)!); exit(1) }
let target = args[1], out = URL(fileURLWithPath: args[2])
let width = args.count > 3 ? Double(args[3]) ?? 390 : 390, scale = args.count > 4 ? Double(args[4]) ?? 2 : 2
let maxWidth = args.count > 5 ? max(width, Double(args[5]) ?? width) : width
let maxHeight = 9000.0
var shown = width                                                   // the view's width: more for a page wider than width

final class Shot: NSObject, WKNavigationDelegate {
    let web: WKWebView, window: NSWindow
    override init() {
        let cfg = WKWebViewConfiguration()
        // no scroll bar: with one (a Mac set to always show them) the page is laid out narrower while it's measured
        // than when it's snapped, and its picture ends in blank space
        cfg.userContentController.addUserScript(WKUserScript(source: """
            const s = document.createElement('style'); s.textContent = '::-webkit-scrollbar { display: none }'; document.documentElement.appendChild(s)
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // a page WebKit isn't showing (the screen locked or asleep) gets no animation frames: its frames come from a
        // timer then, so an animation that goes by the clock (Chart.js, D3) still ends
        cfg.userContentController.addUserScript(WKUserScript(source: """
            const raf = window.requestAnimationFrame.bind(window), caf = window.cancelAnimationFrame.bind(window)
            window.requestAnimationFrame = cb => document.visibilityState === 'visible' ? raf(cb) : -setTimeout(() => cb(performance.now()), 16)
            window.cancelAnimationFrame = id => id < 0 ? clearTimeout(-id) : caf(id)
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 844), configuration: cfg)
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        // WebKit only paints a view that's in a window, and runs a page's animations and timers only while the window
        // is on screen: one in the corner, above the others, that can't be seen (0.4% opaque) or clicked
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 844), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.alphaValue = 0.004
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]   // on every Space, a full-screen app's too
        window.orderFrontRegardless()
        super.init()
        web.navigationDelegate = self
    }
    func start() {
        if target.hasPrefix("http://") || target.hasPrefix("https://"), let u = URL(string: target) { web.load(URLRequest(url: u)) }
        else { let f = URL(fileURLWithPath: target); web.loadFileURL(f, allowingReadAccessTo: f.deletingLastPathComponent()) }
    }
    func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
        // fonts, images and the page's own scripts settle first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.measure() }
    }
    func webView(_ w: WKWebView, didFail _: WKNavigation!, withError e: Error) { fail(e) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError e: Error) { fail(e) }
    func fail(_ e: Error) { FileHandle.standardError.write("page-shot: \(e.localizedDescription)\n".data(using: .utf8)!); exit(1) }

    func measure() {
        // the end of any animation still running (a screen that's locked or asleep doesn't run them): a chart drawn in
        let js = "document.getAnimations().forEach(a => { try { a.finish() } catch (e) {} }); [document.documentElement.scrollWidth, Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)]"
        web.evaluateJavaScript(js) { v, _ in
            let wh = (v as? [NSNumber])?.map(\.doubleValue) ?? []
            // wider than the view: widen it (up to the max width), and measure again once the page has laid out anew
            if wh.count == 2, wh[0] > shown + 1, shown < maxWidth {
                shown = min(maxWidth, wh[0])
                self.window.setContentSize(NSSize(width: shown, height: 844))
                self.web.frame = NSRect(x: 0, y: 0, width: shown, height: 844)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.measure() }
                return
            }
            let full = wh.count == 2 ? wh[1] : 844, H = min(maxHeight, max(300, full))
            self.window.setContentSize(NSSize(width: shown, height: H))
            self.web.frame = NSRect(x: 0, y: 0, width: shown, height: H)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.snap(H, cut: full > maxHeight) }
        }
    }
    func snap(_ H: Double, cut: Bool) {
        let c = WKSnapshotConfiguration()
        c.rect = CGRect(x: 0, y: 0, width: shown, height: H)
        // in points; the image comes back at the screen's backing scale, so this gives width × scale pixels (a widened
        // page: up to 1200)
        c.snapshotWidth = NSNumber(value: min(shown * scale, max(width * scale, 1200)) / (NSScreen.main?.backingScaleFactor ?? 2))
        web.takeSnapshot(with: c) { img, e in
            guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { self.fail(e ?? NSError(domain: "page-shot", code: 1)); return }
            do { try png.write(to: out); print("\(rep.pixelsWide)x\(rep.pixelsHigh)\(cut ? " cut" : "")"); exit(0) } catch { self.fail(error) }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let shot = Shot()
shot.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { FileHandle.standardError.write("page-shot: timed out\n".data(using: .utf8)!); exit(2) }
app.run()
