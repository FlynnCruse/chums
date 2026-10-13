import SwiftUI

// The iPhone app's few constants, in one place: sizes, the motions, the inks, a pressed state, the chat's edge fades
// and the switch. Every screen takes its numbers from here, so a change is made once.

/// Sizes, in points.
enum M {
    static let margin: CGFloat = 16                  // the screen's side margin
    static let target: CGFloat = 44                  // the smallest thing a finger has to hit
    static let tile: CGFloat = 24                    // a glass tile's corner
    static let bubble: CGFloat = 18                  // a message's corner
}

/// The motions. Springs for things that move with a finger or between places; one ease for bars and scrims.
enum Move {
    static let place = Animation.spring(response: 0.55, dampingFraction: 0.84)   // the character between its places
    static let panel = Animation.spring(response: 0.38, dampingFraction: 0.86)   // the agents' panel
    static let snap = Animation.spring(response: 0.30, dampingFraction: 0.78)    // controls changing under the thumb
    static let settle = Animation.spring(response: 0.50, dampingFraction: 1.00)  // text and layout: never bounces
    static let lift = Animation.spring(response: 0.32, dampingFraction: 0.72)    // a row picked up
    static let fade = Animation.easeOut(duration: 0.20)                          // bars, scrims

    /// The same motion, or a plain fade when Reduce Motion is on.
    static func or(_ a: Animation, reduced: Bool) -> Animation { reduced ? .easeInOut(duration: 0.2) : a }
}

/// The inks: white and grays, amber (needs you) and red (stuck) are the only colours.
enum Ink {
    static let text = Color.white
    static let quiet = Color(white: 0.6)             // secondary words, readable at small sizes
    static let ghost = Color(white: 0.42)            // placeholders
    static let you = Color(white: 0.2)               // your messages
    static let agent = Color(white: 0.11)            // the agent's
    static let panel = Color(white: 0.065)           // the agents' panel
}

/// Pressed: a little smaller and dimmer, at once.
struct Pressable: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .opacity(c.isPressed ? 0.75 : 1)
            .animation(Move.snap, value: c.isPressed)
    }
}

/// A mask that thins content out toward the top and bottom edges on a smoothstep curve (no visible start or end).
/// Each edge has a bar over it (`top`, `bottom` points): content is gone `depth` of the way under the bar and whole
/// again `reach` points past it, where it rests.
struct EdgeFade: View {
    let top: CGFloat
    let bottom: CGFloat
    var topReach: CGFloat = 30, topDepth: CGFloat = 0.25        // gone before the name under the character
    var bottomReach: CGFloat = 14, bottomDepth: CGFloat = 0.6   // gone by the middle of the box

    private static let stops: [Gradient.Stop] = stride(from: 0.0, through: 1.0, by: 0.0625).map { (t: Double) -> Gradient.Stop in
        let eased: Double = t * t * (3 - 2 * t)
        return Gradient.Stop(color: Color.black.opacity(eased), location: CGFloat(t))
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(0, top * (1 - topDepth)))
            LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom).frame(height: top * topDepth + topReach)
            Color.black
            LinearGradient(stops: Self.stops, startPoint: .bottom, endPoint: .top).frame(height: bottom * bottomDepth + bottomReach)
            Color.clear.frame(height: max(0, bottom * (1 - bottomDepth)))
        }
    }
}

/// The switch, in the app's inks: on, a white track with a black knob; off, a gray track with a white knob.
struct InkToggle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button {
            withAnimation(Move.snap) { c.isOn.toggle() }
            Haptics.play(.click)
        } label: {
            HStack {
                c.label
                Spacer(minLength: 12)
                Capsule().fill(c.isOn ? Color.white : Color(white: 0.24))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: c.isOn ? .trailing : .leading) {
                        Circle().fill(c.isOn ? Color.black : Color.white).padding(3)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(c.isOn ? "On" : "Off")
    }
}
