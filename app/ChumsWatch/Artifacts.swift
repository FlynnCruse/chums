import SwiftUI
import ImageIO

/// Something a session showed you, or you sent: a screenshot of the Mac's screen or an app window, a web page, an HTML
/// page an agent made, an image, a PDF, a document, text or code, a table, a video. The hub keeps two pictures of it (a
/// 160 px square for the pill, and the whole thing; the watch has no web engine, so it gets pictures), and, for the
/// iPhone, what to open live (`view`: the page's address, or the original file).
struct ArtifactView: Decodable, Equatable {
    let type: String          // url, html, pdf, video, doc, image, text
    var name: String? = nil   // the original file's name
    var url: String? = nil    // a web page's address
    var ext: String? = nil
    var size: Int? = nil
}
struct Artifact: Decodable, Equatable, Identifiable {
    let id: String
    let kind: String          // screenshot, page, image, pdf, doc, text, table, video
    let title: String
    let from: String?         // the app a screenshot was taken of
    let w: Double, h: Double  // the viewer picture's pixels
    var view: ArtifactView? = nil   // what the iPhone opens live (older artifacts have none: their picture)

    /// What it is, under its title: "Screenshot · Safari", "Web page", "Image", "PDF".
    var label: String {
        switch kind {
        case "screenshot": return from.map { $0 == "screen" ? "Screenshot · Screen" : "Screenshot · \($0)" } ?? "Screenshot"
        case "page": return view?.type == "html" ? "Page" : "Web page"
        case "pdf": return "PDF"
        case "doc": return view?.ext.map { "Document · \($0.uppercased())" } ?? "Document"
        case "text": return view?.ext.map { "Text · \($0)" } ?? "Text"
        case "table": return "Table"
        case "video": return "Video"
        default: return "Image"
        }
    }
    var symbol: String {
        switch kind {
        case "page": "safari"
        case "pdf": "doc.richtext"
        case "screenshot": "macwindow"
        case "doc": "doc.text"
        case "text": "text.alignleft"
        case "table": "tablecells"
        case "video": "play.rectangle"
        default: "photo"
        }
    }
}

/// Fetches an artifact's pictures from the hub and decodes them off the main thread. Thumbnails are kept; a whole
/// picture is decoded no larger than 8000 px on its long side (a long page is tall) and only the latest is kept.
@MainActor
final class ArtifactImages {
    static let shared = ArtifactImages()
    var hub: HubClient?
    private var thumbs: [String: CGImage] = [:]
    private var full: (id: String, image: CGImage)?

    func cachedThumb(_ a: Artifact) -> CGImage? { thumbs[a.id] }
    func thumb(_ a: Artifact) async -> CGImage? {
        if let t = thumbs[a.id] { return t }
        guard let data = await hub?.speech("/v1/artifact/\(a.id)/thumb"), let im = await Self.decode(data, max: 320) else { return nil }
        thumbs[a.id] = im
        if thumbs.count > 40 { thumbs.removeValue(forKey: thumbs.keys.first!) }
        return im
    }
    func whole(_ a: Artifact) async -> CGImage? {
        if let f = full, f.id == a.id { return f.image }
        guard let data = await hub?.speech("/v1/artifact/\(a.id)/full"), let im = await Self.decode(data, max: 8000) else { return nil }
        full = (a.id, im)
        return im
    }
    nonisolated static func decode(_ data: Data, max: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                      kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
        }.value
    }
}

/// Its small picture: rounded, with a hairline edge; the kind's symbol until the picture arrives.
struct ArtifactThumb: View {
    let a: Artifact
    var size = 38.0
    @State private var image: CGImage?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        ZStack {
            shape.fill(Color(white: 0.24))
            if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() }
            else { Image(systemName: a.symbol).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(Pal.gray) }
        }
        .frame(width: size, height: size).clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .onAppear { image = ArtifactImages.shared.cachedThumb(a) }
        .task(id: a.id) { if image == nil { image = await ArtifactImages.shared.thumb(a) } }
    }
}

/// In the conversation: a pill with its picture, title and what it is. A tap opens it.
struct ArtifactPill: View {
    let a: Artifact
    let open: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            ArtifactThumb(a: a, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Pal.white).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(a.label).font(.system(size: 11.5)).foregroundStyle(Pal.gray).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5).padding(.trailing, 8)
        .background(Color(white: 0.17).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { open() }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityHint("Opens it")
    }
}

/// On the main screen when one arrives: the same pill, raised, above the handle (the line that came with it is spoken
/// and in the conversation). It goes away by itself after a while; a tap opens it.
struct ArtifactToast: View {
    let a: Artifact
    let line: String
    let open: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            ArtifactThumb(a: a, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Pal.white).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(a.label).font(.system(size: 11.5)).foregroundStyle(Color(white: 0.72)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5).padding(.trailing, 10)
        .background(Color(white: 0.13).opacity(0.96), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .onTapGesture { open() }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityHint("Opens it")
    }
}

/// The whole artifact, full screen. It opens fitted to the width; the crown or a drag scrolls it; a double tap zooms in
/// where you tapped (and back out); a drag down from the top, or the × at the top left, closes it. Its title shows for
/// a moment at the bottom; a hairline on the right shows where you are in a long one.
struct ArtifactViewer: View {
    let a: Artifact
    let close: () -> Void
    @State private var image: CGImage?
    @State private var zoom = 1.0
    @State private var offset = CGPoint.zero                       // the picture's top left, in screen points
    @State private var start = CGPoint.zero
    @State private var dragging = false
    @State private var pull = 0.0                                  // dragged down past the top: closes past 60 pt
    @State private var crown = 0.0
    @State private var titleShown = true
    @State private var indicator = false
    @State private var hideIndicator: Task<Void, Never>?
    @FocusState private var focused: Bool
    private static let zoomIn = 2.6

    var body: some View {
        GeometryReader { g in
            let S = g.size, fitW = S.width, fitH = fitW * a.h / max(1, a.w)
            let cw = fitW * zoom, ch = fitH * zoom
            let maxY = max(0, ch - S.height)
            ZStack(alignment: .topLeading) {
                Color.black
                picture(cw, ch)
                    .offset(x: offset.x, y: (ch < S.height ? (S.height - ch) / 2 : offset.y) + pull)
                    .scaleEffect(1 - min(pull, 120) / 900, anchor: .top)
                // where you are in a long one
                if maxY > 40 {
                    let k = S.height / ch, top = -offset.y / ch * S.height
                    Capsule().fill(.white.opacity(0.55))
                        .frame(width: 2.5, height: max(14, S.height * k))
                        .offset(x: S.width - 5, y: top)
                        .opacity(indicator || dragging ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: indicator || dragging)
                }
                // the title, for a moment
                VStack { Spacer()
                    Text(a.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pal.white).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity).opacity(titleShown ? 1 : 0).allowsHitTesting(false)
                // close
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Pal.white)
                        .frame(width: 30, height: 30).background(.black.opacity(0.6), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                        .frame(width: 50, height: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.leading, 2).padding(.top, 2)
                .accessibilityLabel("Close")
                if image == nil { ProgressView().tint(Pal.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { v in
                    if !dragging { dragging = true; start = offset }
                    var o = CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height)
                    // pulled down from the top: the picture follows and shrinks a little, to close
                    if start.y >= -0.5 && v.translation.height > 0 && abs(v.translation.width) < v.translation.height { pull = v.translation.height; o.y = 0 } else { pull = 0 }
                    offset = clamp(o, cw, ch, S); crown = -offset.y / 100; scrolled()
                }
                .onEnded { v in
                    dragging = false
                    if pull > 60 { close(); return }
                    let fling = CGPoint(x: start.x + v.predictedEndTranslation.width, y: start.y + v.predictedEndTranslation.height)
                    withAnimation(.smooth(duration: 0.45)) { pull = 0; offset = clamp(fling, cw, ch, S) }
                    crown = -offset.y / 100; scrolled()
                })
            .onTapGesture(count: 2) { p in
                // zoom in around the finger, or back out to the width
                let z2 = zoom > 1.01 ? 1.0 : Self.zoomIn
                let base = CGPoint(x: offset.x, y: ch < S.height ? (S.height - ch) / 2 : offset.y)
                let o = CGPoint(x: p.x - (p.x - base.x) * z2 / zoom, y: p.y - (p.y - base.y) * z2 / zoom)
                Haptics.play(.click)
                withAnimation(.smooth(duration: 0.32)) { zoom = z2; offset = clamp(o, fitW * z2, fitH * z2, S) }
                crown = -offset.y / 100
            }
#if os(watchOS)
            .focusable().focused($focused)
            .digitalCrownRotation($crown, from: 0, through: max(0.01, maxY / 100), by: nil, sensitivity: .medium,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
#endif
            .onChange(of: crown) { _, c in
                guard !dragging else { return }
                offset.y = clamp(CGPoint(x: offset.x, y: -c * 100), cw, ch, S).y; scrolled()
            }
        }
        .ignoresSafeArea()
        .task(id: a.id) {
            focused = true
            image = await ArtifactImages.shared.whole(a)
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.4)) { titleShown = false }
        }
    }

    /// The position hairline shows while it scrolls and a moment after.
    private func scrolled() {
        indicator = true; hideIndicator?.cancel()
        hideIndicator = Task { try? await Task.sleep(for: .seconds(1.2)); if !Task.isCancelled { indicator = false } }
    }

    @ViewBuilder private func picture(_ cw: Double, _ ch: Double) -> some View {
        if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high).frame(width: cw, height: ch) }
        else { ArtifactThumb(a: a, size: min(cw, ch)).blur(radius: 6).opacity(0.6).frame(width: cw, height: ch, alignment: .top) }
    }

    /// Never past the picture's edges; a picture shorter than the screen stays centered (see the y in body).
    private func clamp(_ o: CGPoint, _ cw: Double, _ ch: Double, _ S: CGSize) -> CGPoint {
        CGPoint(x: min(0, max(S.width - cw, o.x)), y: min(0, max(min(0, S.height - ch), o.y)))
    }
}
