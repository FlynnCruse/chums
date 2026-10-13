import SwiftUI

/// Where the character is: at the bottom left of the conversation once there is one (what it's doing beside it, its
/// newest line just above it), in the middle when there's no conversation yet, or in front when you tap it.
enum StagePlace { case dock, middle, front }

/// The character, drawn by the watch's rig every frame. Big, it's in a window the shape of the watch's screen with the
/// crown on its side, and takes the watch's touches (hold to talk, tap to poke, stroke to pet, the crown or a two-finger
/// twist). Small, it's the character alone, its edges fading into the black (no frame); a tap brings it to the front, a
/// long press opens its settings. It's one view that moves between the two, so it shrinks and grows without a cut.
/// It only draws: the rig moves on the model's own clock (ScreenModel.frame), drawn or not.
struct CharacterStage: View {
    let model: ScreenModel
    let agent: AgentInfo
    let small: Bool
    let paused: Bool
    let open: () -> Void
    let settings: () -> Void
    @State private var crop = Crop()
    @State private var twisted = 0.0

    /// How far it's cropped in, eased each frame (small: closer in on the character).
    final class Crop { var k = 1.0; var last: Date? }
    /// 30 frames a second when it's small or plays frames; the screen's own rate when it's big and drawn live.
    private var live: Bool { !small && CharacterKind(id: agent.character)?.framed != true }

    var body: some View {
        GeometryReader { g in
            let shape = RoundedRectangle(cornerRadius: small ? min(g.size.width, g.size.height) / 2 : g.size.width * 0.21,
                                         style: .continuous)
            TimelineView(.animation(minimumInterval: live ? nil : 1.0 / 30, paused: paused)) { tl in
                Canvas { ctx, size in
                    let dt = crop.last.map { tl.date.timeIntervalSince($0) } ?? 1
                    crop.last = tl.date
                    crop.k += ((small ? 1.3 : 1) - crop.k) * min(1, max(0, dt) * 9)
                    var c = ctx
                    c.translateBy(x: size.width / 2, y: size.height / 2)
                    c.scaleBy(x: crop.k, y: crop.k)
                    c.translateBy(x: -size.width / 2, y: -size.height / 2)
                    Renderer.draw(model.rig, c, size: size)
                }
            }
            .mask {
                // big: the watch's screen; small: no edge at all, it fades out
                ZStack {
                    shape.fill(.black).opacity(small ? 0 : 1)
                    Rectangle().fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                                            .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                                    startPoint: .top, endPoint: .bottom))
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .opacity(small ? 1 : 0)
                }
            }
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in model.drag(v.location, in: g.size) }
                    .onEnded { v in _ = model.dragEnd(v.location, in: g.size) },
                including: small ? .none : .all
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { v in model.crown((v.rotation.degrees - twisted) / 12); twisted = v.rotation.degrees }
                    .onEnded { _ in twisted = 0 },
                including: small ? .none : .all
            )
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.1)], startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1.5)
                    .opacity(small ? 0 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if !small {                                              // only with the watch's window around it
                    Crown { model.crown($0) }
                        .offset(x: 24, y: g.size.height * 0.17 - 18)    // just outside the right edge, where the watch has it
                        .transition(.opacity)
                }
            }
            .overlay {
                if small {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture(perform: open)
                        .onLongPressGesture(minimumDuration: 0.45) { Haptics.play(.strong); settings() }
                }
            }
        }
        // the big one, drawing live, has the clock run at the screen's rate with it
        .onChange(of: live && !paused, initial: true) { _, on in if !small { model.fullRate = on } }
        .onDisappear { if !small { model.fullRate = false } }
        .accessibilityElement()
        .accessibilityIdentifier("character")
        .accessibilityLabel(agent.name)
        .accessibilityHint(small ? "Shows \(agent.name) in front" : "Hold to talk to \(agent.name)")
        .accessibilityAddTraits(small ? .isButton : [])
    }
}

/// A scale that follows your voice while `on` (the character in its row, the microphone held). The voice's level is
/// read from the recorder, not tracked, so it's read here every frame, 30 a second, without redrawing what it scales.
struct VoiceScale: ViewModifier {
    let model: ScreenModel
    let on: Bool
    let base: Double, gain: Double
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !on)) { _ in
            content.scaleEffect(on ? base + model.talkLevel * gain : 1)
        }
    }
}
