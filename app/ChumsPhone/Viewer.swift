import SwiftUI
import UIKit
import WebKit
import PDFKit
import QuickLook
import AVKit

/// Something an agent showed you (or you sent), opened on the app's sliding card (drag it down by its handle to put it
/// away), live where the iPhone can: a web page or an agent's HTML page runs (scripts, charts, scrolling), a PDF scrolls
/// page by page, a video plays, a document opens in Quick Look. Anything else, or anything that can't be had from the
/// Mac, is its picture: pinch to zoom where your fingers are, drag to look around, double-tap to zoom in or back out.
/// Its title at the top left; Share at the top right sends the original (the file, or the page's address).
struct ArtifactSheet: View {
    let artifact: Artifact
    var character: String = Agents.fallback
    @State private var image: UIImage?
    @State private var zoomed = false
    @State private var file: URL?                    // the original, from the Mac (a PDF, a video, a document, a page)
    @State private var html: String?                 // an HTML page to run (an agent's, or the Mac's rendering of a text)
    @State private var failed = false                // the live one couldn't be had: its picture instead
    @State private var pageLoaded = false            // the live page has loaded: until then, its picture

    private var view: ArtifactView? { artifact.view }
    private var live: String? { failed ? nil : view?.type }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(artifact.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(artifact.label).font(.footnote).foregroundStyle(Ink.quiet)
                }
                Spacer(minLength: 8)
                share.transition(.opacity)
            }
            .frame(minHeight: 44)                                       // Share coming in doesn't move what's below
            .padding(.leading, 22).padding(.trailing, 10).padding(.top, 24).padding(.bottom, 6)
            ZStack { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Move.fade, value: image != nil)
        .animation(Move.fade, value: file != nil || html != nil)
        .cardSheet(character: character)
        .task { await load() }
    }

    /// What it opens as: the live view for its type, else the picture. The picture shows while the live one comes.
    @ViewBuilder private var content: some View {
        switch live {
        case "url":
            if let u = view?.url.flatMap(URL.init(string:)) { page(.url(u)) } else { picture }
        case "html", "text":
            if let html { page(.html(html)) } else { picture }
        case "pdf":
            if let file { PDFPages(url: file) } else { picture }
        case "video":
            if let file { VideoPlayer(player: AVPlayer(url: file)).ignoresSafeArea(edges: .bottom) } else { picture }
        case "doc":
            if let file { DocPreview(url: file).ignoresSafeArea(edges: .bottom) } else { picture }
        default:
            picture
        }
    }

    /// A live page over its picture, which shows until the page has loaded (Safari's engine can take seconds to start):
    /// the picture is the page at phone width, so it sits where the page will. A page that doesn't load stays its picture.
    private func page(_ source: LiveWeb.Source) -> some View {
        ZStack(alignment: .top) {
            if !pageLoaded {
                if let image {
                    GeometryReader { g in
                        Image(uiImage: image).resizable().scaledToFit().frame(width: g.size.width)
                            .frame(width: g.size.width, height: g.size.height, alignment: .top).clipped()
                    }
                } else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            LiveWeb(source: source, loaded: { pageLoaded = true }, failed: { failed = true })
                .opacity(pageLoaded ? 1 : 0)
                .allowsHitTesting(pageLoaded)
        }
        .animation(Move.fade, value: pageLoaded)
    }

    @ViewBuilder private var picture: some View {
        if let image { ZoomableImage(image: image, zoomed: $zoomed) {}.transition(.opacity) }
        else { ProgressView().tint(.white) }
    }

    /// Share: the original file, or the page's address, or the picture.
    @ViewBuilder private var share: some View {
        Group {
            if let file { ShareLink(item: file) { shareIcon } }
            else if live == "url", let u = view?.url.flatMap(URL.init(string:)) { ShareLink(item: u) { shareIcon } }
            else if let image { ShareLink(item: Image(uiImage: image), preview: SharePreview(artifact.title, image: Image(uiImage: image))) { shareIcon } }
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("Share")
    }
    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    /// The picture always (it's the fallback, and Share's when there's nothing else); then what its type opens live.
    private func load() async {
        async let pic: CGImage? = ArtifactImages.shared.whole(artifact)
        let hub = ArtifactImages.shared.hub
        switch view?.type {
        case "html", "text":
            if let d = await hub?.fetch("/v1/artifact/\(artifact.id)/view"), let s = String(data: d, encoding: .utf8) { html = s }
            else { failed = true }
            if let d = await hub?.fetch("/v1/artifact/\(artifact.id)/source") { file = save(d) }
        case "pdf", "video", "doc":
            if let d = await hub?.fetch("/v1/artifact/\(artifact.id)/source") { file = save(d) } else { failed = true }
        default: break
        }
        if let cg = await pic { image = UIImage(cgImage: cg) }
    }

    /// The original, as a file with its own name (what Quick Look, the player and Share go by).
    private func save(_ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artifacts/\(artifact.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (view?.name).flatMap { $0.isEmpty ? nil : $0 } ?? artifact.title
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

/// A web page, live: an address, or an agent's HTML (its scripts run: charts, tables you can scroll). In a private
/// store (nothing kept between pages); a link you tap opens in Safari, not in here. An agent's HTML stays the page it
/// is: it can't go to another page or send a form by itself.
struct LiveWeb: UIViewRepresentable {
    enum Source: Equatable { case url(URL), html(String) }
    let source: Source
    var loaded: () -> Void = {}
    var failed: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.allowsInlineMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: c)
        w.navigationDelegate = context.coordinator
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.accessibilityIdentifier = "artifact-web"
        switch source {
        case .url(let u): w.load(URLRequest(url: u))
        case .html(let h): w.loadHTMLString(h, baseURL: URL(string: "about:blank"))
        }
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) { context.coordinator.loaded = loaded; context.coordinator.failed = failed }
    func makeCoordinator() -> Coordinator { Coordinator(loaded, failed, html: { if case .html = source { true } else { false } }()) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: () -> Void, failed: () -> Void
        let html: Bool
        init(_ loaded: @escaping () -> Void, _ failed: @escaping () -> Void, html: Bool) {
            self.loaded = loaded; self.failed = failed; self.html = html
        }
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { loaded() }
        func webView(_ w: WKWebView, didFail _: WKNavigation!, withError _: Error) { failed() }
        func webView(_ w: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { failed() }
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated, let u = a.request.url, ["http", "https"].contains(u.scheme) {
                UIApplication.shared.open(u); decisionHandler(.cancel)
            } else if html, a.targetFrame?.isMainFrame ?? true, a.request.url?.absoluteString != "about:blank" {
                decisionHandler(.cancel)                            // a script or a form taking the page somewhere else
            } else { decisionHandler(.allow) }
        }
    }
}

/// A PDF, page after page: scroll through it, pinch to zoom.
struct PDFPages: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = PDFDocument(url: url)
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.backgroundColor = .clear
        v.pageShadowsEnabled = false
        v.accessibilityIdentifier = "artifact-pdf"
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

/// A document Quick Look can open (Word, Pages, Keynote, Numbers, Excel, RTF, a table, a 3D model…), as Files shows it.
struct DocPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let q = QLPreviewController()
        q.dataSource = context.coordinator
        return q
    }
    func updateUIViewController(_ q: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in q: QLPreviewController) -> Int { 1 }
        func previewController(_ q: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { url as NSURL }
    }
}

/// UIKit's zooming scroll view, for the natural pinch, pan and bounce: the picture fits the screen, zooms up to 6×
/// about the fingers, stays centered when it's smaller than the screen.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool
    let tap: () -> Void

    func makeUIView(context: Context) -> ZoomView {
        let v = ZoomView(image: image)
        v.delegate = context.coordinator
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double)
        v.addGestureRecognizer(double)
        v.addGestureRecognizer(single)
        return v
    }
    func updateUIView(_ v: ZoomView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage
        init(_ p: ZoomableImage) { parent = p }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomView)?.center()
            let z = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            if z != parent.zoomed { parent.zoomed = z }
        }
        @objc func singleTap() { parent.tap() }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? ZoomView else { return }
            if v.zoomScale > v.minimumZoomScale + 0.01 { v.setZoomScale(v.minimumZoomScale, animated: true); return }
            let p = g.location(in: v.imageView), k = 2.5
            let size = CGSize(width: v.bounds.width / k, height: v.bounds.height / k)
            v.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

final class ZoomView: UIScrollView {
    let imageView: UIImageView
    private var laidOut = CGSize.zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        minimumZoomScale = 1; maximumZoomScale = 6
        bouncesZoom = true; alwaysBounceVertical = false; alwaysBounceHorizontal = false
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .normal
        backgroundColor = .clear
        accessibilityIdentifier = "viewer-scroll"
        // VoiceOver can't pinch: the same zoom, as actions
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in") { [weak self] _ in
                guard let self else { return false }
                setZoomScale(min(maximumZoomScale, zoomScale * 2), animated: true); return true
            },
            UIAccessibilityCustomAction(name: "Zoom out") { [weak self] _ in
                guard let self else { return false }
                setZoomScale(max(minimumZoomScale, zoomScale / 2), animated: true); return true
            },
        ]
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // the picture fitted to the screen at 1×, laid out again only when the screen's size changes
        guard bounds.size != laidOut, let img = imageView.image, img.size.width > 0, img.size.height > 0 else { return }
        laidOut = bounds.size
        zoomScale = 1
        let k = min(bounds.width / img.size.width, bounds.height / img.size.height)
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: img.size.width * k, height: img.size.height * k))
        contentSize = imageView.frame.size
        center()
    }

    /// Smaller than the screen in a direction, the picture sits in the middle of it.
    func center() {
        let dx = max(0, (bounds.width - contentSize.width) / 2), dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        accessibilityValue = String(format: "zoom %.1f", zoomScale)
    }
}
