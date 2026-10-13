import SwiftUI

/// A character that stages itself: it draws the whole screen its own way (Noodle's rendered frames, Pix's pixels)
/// instead of being posed by the shared rig and placed in a world. It reads the rig's state, time, hold and caption.
/// The renderer draws the status label on top of it, then its `front`, then captions over a scrim.
protocol Staged: AnyObject {
    /// Draws its own approval card (Noodle balances it on its hair), so the renderer doesn't.
    var ownsApproval: Bool { get }
    /// It shows the caption itself in this state (Pix's dialog box), so the renderer doesn't.
    func ownsCaption(_ r: Rig) -> Bool
    /// Captions sit at the top instead of the bottom in this state (when the character fills the bottom).
    func captionTop(_ r: Rig) -> Bool
    /// How long it plays out done and dizzy before settling (its animations are longer than the rig's 2.4 / 2.6 s).
    var holds: [ChumsState: Double] { get }
    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool)
    func step(_ r: Rig, _ dt: Double)
    func draw(_ r: Rig, _ ctx: GraphicsContext)
    func front(_ r: Rig, _ ctx: GraphicsContext)
    func hit(_ pt: CGPoint) -> Bool
    /// A finger came down on the screen at `pt` (design points).
    func touched(_ r: Rig, at pt: CGPoint)
    /// The watch moved: its acceleration in g on the screen's axes (x right, y down, z toward you).
    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double)
    func poke(_ r: Rig)
    func pet(_ r: Rig)
    func deny(_ r: Rig)
    /// The crown turned by `delta` (its own units), when this character takes it.
    func crown(_ r: Rig, _ delta: Double)
    /// The finger moved to `pt` (design points) while down; it came off.
    func dragged(_ r: Rig, at pt: CGPoint)
    func released(_ r: Rig)
    /// Nothing in it is moving fast: it can draw at 30 frames a second.
    var calm: Bool { get }
}

extension Staged {
    func crown(_ r: Rig, _ delta: Double) {}
    func dragged(_ r: Rig, at pt: CGPoint) {}
    func released(_ r: Rig) {}
    var calm: Bool { false }
}
