import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The box at the bottom. + on its left adds photos (the camera or the library) and files; they wait above the box till
/// the next message takes them. The microphone on its right: tap it and talk, then send (↑) or throw it away (×); or
/// hold it, talk and let go to send (slide left onto × to throw it away). Once something is typed or added, it's the
/// send button. Opened from a widget, the Control or Siri, it's already listening: × or ↑.
struct Composer: View {
    let name: String
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    var typing: FocusState<Bool>.Binding
    let model: ScreenModel
    @Binding var handsFree: Bool                     // listening with no finger down (a tap on the mic, a widget, Siri)
    @Binding var attaching: Bool                     // the + menu is open (the screen behind it dims)
    let sending: Bool
    let send: (String) -> Void
    @State private var holding = false               // listening while a finger is on the mic
    @State private var pressedAt = Date.distantPast
    @State private var since = Date()                // when this listening began
    @State private var refused = false               // this touch couldn't start the microphone: ignore it till it lifts
    @State private var slide = 0.0
    @State private var boxH = 52.0                   // the box's height: the + menu floats just above it
    @State private var photos: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var camera = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cancelAt = -64.0

    private var listening: Bool { holding || handsFree }
    private var armed: Bool { holding && slide <= Self.cancelAt }        // letting go now throws it away
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty && !listening { tray.transition(.move(edge: .bottom).combined(with: .opacity)) }
            // the + menu floats over whatever is above the box: it moves nothing
            box
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { boxH = $0 }
                .overlay(alignment: .bottomLeading) {
                    if attaching { menu.fixedSize().offset(y: -(boxH + 10)) }
                }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)              // the box grows with the text, up to here
        .animation(Move.snap, value: listening)
        .animation(Move.snap, value: attachments)
        .animation(.snappy(duration: 0.18), value: canSend)
        .onChange(of: listening) { _, on in if on { since = Date() } }
        // listening ends on its own (the time limit, a failed microphone): the box follows the model
        .task(id: listening) {
            while listening && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                if listening && !model.listening { holding = false; handsFree = false; slide = 0 }
            }
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $photos, maxSelectionCount: 6, matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let d = try? await item.loadTransferable(type: Data.self) { await addPhoto { UIImage(data: d) } }
                }
                photos = []
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            let urls = (try? result.get()) ?? []
            Task { await addFiles(urls) }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in Task { await addPhoto { img } } }
                .ignoresSafeArea()
        }
    }

    // MARK: the box

    /// Left, middle, right, at one height whatever it's doing (the conversation above it never moves). The right slot
    /// is the same view from the touch that starts listening to the touch that ends it.
    private var box: some View {
        HStack(alignment: .bottom, spacing: 4) {
            leading.frame(width: 42, height: 42)
            ZStack(alignment: .leading) {
                field.opacity(listening ? 0 : 1).allowsHitTesting(!listening)       // keeps the box's height
                if listening { voice.transition(.opacity) }
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            trailing.frame(width: 42, height: 42)
        }
        .padding(5)
        .glassEffect(listening ? .regular.tint(.white.opacity(0.07)) : .regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private var leading: some View {
        if listening {
            Button { stop(cancel: true) } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(armed || handsFree ? .white : Ink.quiet)
                    .frame(width: 34, height: 34)
                    .background(armed ? Pal.red : Color(white: 0.2), in: Circle())
                    .scaleEffect(armed ? 1.12 : 1)
                    .frame(width: 42, height: 42).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(Move.snap, value: armed)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier("cancel-talk")
        } else {
            Button {
                typing.wrappedValue = false
                withAnimation(Move.snap) { attaching.toggle() }
                Haptics.play(.click)
            } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(white: attaching ? 1 : 0.82))
                    .rotationEffect(.degrees(attaching ? 45 : 0))
                    .frame(width: M.target, height: M.target).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .accessibilityLabel(attaching ? "Close" : "Add photos or files")
        }
    }

    private var field: some View {
        TextField("Message \(name)", text: $draft, axis: .vertical)
            .font(.body).lineLimit(1...6)
            .focused(typing)
            .submitLabel(.send)
            .onSubmit(submit)
            .padding(.leading, 2).padding(.vertical, 10)
            .accessibilityIdentifier("message")
            .onChange(of: typing.wrappedValue) { _, on in if on && attaching { withAnimation(Move.snap) { attaching = false } } }
    }

    /// The middle while it listens: your voice as bars, and how long; or what letting go will do.
    private var voice: some View {
        HStack(spacing: 10) {
            if armed {
                Text("Let go to cancel").font(.subheadline.weight(.medium)).foregroundStyle(Pal.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in Waveform(level: model.talkLevel) }
                    .frame(height: 22)
            }
            TimelineView(.periodic(from: since, by: 1)) { t in
                let s = max(0, Int(t.date.timeIntervalSince(since)))
                Text(String(format: "%d:%02d", s / 60, s % 60)).font(.subheadline.monospacedDigit()).foregroundStyle(Ink.quiet)
            }
        }
        .frame(height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening to you for \(name)")
    }

    @ViewBuilder private var trailing: some View {
        if sending {
            ProgressView().tint(.black).frame(width: 36, height: 36).background(Color.white, in: Circle())
        } else if canSend && !listening {
            Button(action: submit) {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 36, height: 36).background(Color.white, in: Circle())
                    .frame(width: 42, height: 42).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel("Send")
        } else {
            mic
        }
    }

    /// Tap: listen till ↑ or ×. Hold: listen till you let go (slide left onto × first to throw it away). Listening with
    /// no finger down, it's ↑. One gesture on one view, from the first touch to the last.
    private var mic: some View {
        // held, it grows with your voice, read 30 times a second (a change in the level doesn't redraw the box)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !holding)) { _ in
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: handsFree ? "arrow.up" : "mic.fill")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 36, height: 36)
            .scaleEffect(holding ? 1.3 + model.talkLevel * 0.15 : 1)
        }
        .offset(x: holding ? max(slide, -90) * 0.5 : 0)
        .frame(width: 42, height: 42)
        .contentShape(Circle().inset(by: -10))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if attaching { withAnimation(Move.snap) { attaching = false } }          // the + menu goes at the first touch
                    guard !handsFree, !refused else { return }
                    if !holding {
                        typing.wrappedValue = false
                        model.micDown()
                        guard model.listening else { refused = true; return }       // not allowed (yet), or the mic is busy
                        holding = true; pressedAt = Date(); slide = 0
                    }
                    let s = min(0, v.translation.width)
                    if (s <= Self.cancelAt) != (slide <= Self.cancelAt) { Haptics.play(.click) }
                    slide = s
                }
                .onEnded { v in
                    if refused { refused = false; return }
                    if handsFree { stop(cancel: false); return }                           // ↑
                    guard holding else { return }
                    let tap = Date().timeIntervalSince(pressedAt) < 0.35 && abs(v.translation.width) < 12
                    holding = false
                    if tap { handsFree = true; slide = 0; return }                         // a tap: keep listening
                    let cancel = slide <= Self.cancelAt
                    slide = 0
                    model.micUp(cancel: cancel)
                }
        )
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: slide)
        .animation(Move.snap, value: holding)
        .accessibilityLabel(handsFree ? "Send" : "Talk to \(name)")
        .accessibilityHint(handsFree ? "" : "Tap to start, or hold while you talk")
        .accessibilityIdentifier("mic")
    }

    private func stop(cancel: Bool) {
        holding = false; handsFree = false; slide = 0
        if !cancel { Haptics.play(.click) }
        model.micUp(cancel: cancel)
    }

    // MARK: adding things

    /// What + opens: the camera, the photo library and Files, as glass pills of one size that grow up out of the +, one
    /// after another.
    private var menu: some View {
        let options: [(id: String, symbol: String, title: String, run: () -> Void)] =
            (UIImagePickerController.isSourceTypeAvailable(.camera) ? [("camera", "camera", "Take Photo", { camera = true })] : [])
            + [("photos", "photo.on.rectangle", "Photo Library", { choosingPhotos = true }), ("files", "folder", "Files", { choosingFiles = true })]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                Button { pickThen(o.run) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: o.symbol).font(.body.weight(.medium)).frame(width: 24)
                        Text(o.title).font(.body.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 170, height: 30)
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity)
                        .animation(Move.snap.delay(Double(options.count - 1 - i) * 0.04)),
                    removal: .opacity.animation(.easeIn(duration: 0.12))))
            }
        }
        .padding(.leading, 4)
    }
    private func pickThen(_ open: @escaping () -> Void) {
        withAnimation(Move.snap) { attaching = false }
        Task { try? await Task.sleep(for: .milliseconds(180)); open() }
    }

    /// A photo, made smaller to send off the main thread (six of them take a moment), then added.
    private func addPhoto(_ image: @escaping @Sendable () -> UIImage?) async {
        let name = "photo-\(attachments.count + 1).jpg"
        let a = await Task.detached(priority: .userInitiated) { image().flatMap { Attachment.photo($0, name: name) } }.value
        if let a { attachments.append(a); Haptics.play(.click) }
    }

    /// Files, read off the main thread, then added; one over 25 MB isn't, and the conversation says so.
    private func addFiles(_ urls: [URL]) async {
        var big: [String] = []
        for url in urls {
            switch await Task.detached(priority: .userInitiated, operation: { Result { try Attachment.file(url) } }).value {
            case .success(let a): attachments.append(a); Haptics.play(.click)
            case .failure(Attachment.Refusal.tooBig): big.append(url.lastPathComponent)
            case .failure: model.onNotice?("Couldn't read \(url.lastPathComponent).")
            }
        }
        if let one = big.first {
            model.onNotice?(big.count == 1 ? "\(one) wasn't added: it's over 25 MB." : "\(big.count) files weren't added: they're over 25 MB.")
        }
    }

    /// What goes with the next message: pictures as thumbnails, files by name; × takes one out.
    private var tray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(attachments) { a in
                    AttachmentChip(attachment: a, dim: sending) {
                        withAnimation(Move.snap) { attachments.removeAll { $0.id == a.id } }
                        Haptics.play(.click)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.top, 10).padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!t.isEmpty || !attachments.isEmpty) && !sending else { return }
        Haptics.play(.click)                                                    // at the tap, not after the round trip
        draft = ""
        send(t)
    }
}

/// One thing waiting to go with the next message: a picture as itself, a file by its name; × takes it out.
private struct AttachmentChip: View {
    let attachment: Attachment
    let dim: Bool
    let remove: () -> Void

    var body: some View {
        content
            .opacity(dim ? 0.5 : 1)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Color(white: 0.28), in: Circle())
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 10, y: -10)
                .accessibilityLabel("Remove \(attachment.name)")
            }
    }

    @ViewBuilder private var content: some View {
        if let img = attachment.preview {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill").font(.body).foregroundStyle(Color(white: 0.7))
                Text(attachment.name).font(.footnote.weight(.medium)).foregroundStyle(.white).lineLimit(2)
                    .frame(maxWidth: 130, alignment: .leading)
            }
            .padding(.horizontal, 12).frame(height: 66)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Pressed, a row lights up behind its content.
struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Something to send with the next message: a picture (made smaller to send) or a file.
struct Attachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: String                                 // its MIME type
    let data: Data
    let preview: UIImage?                            // pictures
    static func == (a: Attachment, b: Attachment) -> Bool { a.id == b.id }

    /// A photo, at most 2048 px on its longest side, as JPEG.
    static func photo(_ image: UIImage, name: String) -> Attachment? {
        let k = min(1, 2048 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let d = small.jpegData(compressionQuality: 0.82) else { return nil }
        return Attachment(name: name, type: "image/jpeg", data: d, preview: small.preparingThumbnail(of: CGSize(width: 192, height: 192)) ?? small)
    }

    /// Why a file can't go: it's over 25 MB (the most the Mac takes), or it can't be read.
    enum Refusal: Error { case tooBig, unreadable }

    /// A file from Files (25 MB at most: a bigger one isn't read). A big picture goes as a smaller JPEG; a small one as it is.
    static func file(_ url: URL) throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let most = 25 * 1024 * 1024
        if let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, n > most { throw Refusal.tooBig }
        guard let d = try? Data(contentsOf: url) else { throw Refusal.unreadable }
        guard d.count <= most else { throw Refusal.tooBig }
        let t = UTType(filenameExtension: url.pathExtension)
        if t?.conforms(to: .image) == true, let img = UIImage(data: d) {
            if d.count > 4 * 1024 * 1024, let a = photo(img, name: url.deletingPathExtension().lastPathComponent + ".jpg") { return a }
            return Attachment(name: url.lastPathComponent, type: t?.preferredMIMEType ?? "image/png", data: d,
                              preview: img.preparingThumbnail(of: CGSize(width: 192, height: 192)))
        }
        return Attachment(name: url.lastPathComponent, type: t?.preferredMIMEType ?? "application/octet-stream", data: d, preview: nil)
    }
}

/// The camera, to take a photo for the next message.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.done(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// The voice while it listens: bars that move with how loud you are.
struct Waveform: View {
    let level: Double
    @State private var history: [Double] = Array(repeating: 0.05, count: 28)

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(history.indices, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.4 + 0.6 * Double(i) / Double(history.count)))
                    .frame(width: 3, height: max(3, history[i] * 22))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: level) { _, v in history.removeFirst(); history.append(max(0.06, v)) }
    }
}
