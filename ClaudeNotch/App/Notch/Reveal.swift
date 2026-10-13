import SwiftUI

/// Grows the panel out of the notch and shrinks it back in.
///
/// The panel keeps its final frame the whole time; what animates is a clip
/// that starts as the whole closed box (the notch plus its wing, where the
/// dots are, closed radii) and expands to the panel's own outline in one
/// motion. The content is revealed rather than faded, and the shadow is
/// applied after the clip so it follows the growing shape.
struct Reveal: ViewModifier, Animatable {
    var progress: CGFloat
    let closed: CGSize
    let wing: CGFloat
    /// How far right of its frame the revealed view is drawn, by an `.offset`
    /// outside this clip (the peek hugs its words, so its sides differ and it
    /// is shifted to keep its gap over the notch); zero for the open panel.
    var shift: CGFloat = 0
    /// The corners the clip ends on: the panel's, or the closed shape's for
    /// the peek, which is the closed shape widened.
    var radii: (top: CGFloat, bottom: CGFloat) = NotchMetrics.openRadii
    let lift: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RevealShape(progress: progress, closed: closed, wing: wing, shift: shift, radii: radii))
            .shadow(color: .black.opacity(lift * Double(max(0, min(1, progress)))),
                    radius: 14, x: 0, y: 8)
    }

    static func transition(closed: CGSize, wing: CGFloat, shift: CGFloat = 0,
                           radii: (top: CGFloat, bottom: CGFloat) = NotchMetrics.openRadii,
                           lift: Double) -> AnyTransition {
        .modifier(active: Reveal(progress: 0, closed: closed, wing: wing, shift: shift, radii: radii, lift: lift),
                  identity: Reveal(progress: 1, closed: closed, wing: wing, shift: shift, radii: radii, lift: lift))
    }
}

/// The notch silhouette at some point between the closed box and `rect`
/// moved right by `shift`. The closed box is the notch (centred in `rect`,
/// which is centred on the hardware) plus its wing to the right, exactly
/// where `ClosedLayout` draws it.
struct RevealShape: Shape {
    var progress: CGFloat
    let closed: CGSize
    let wing: CGFloat
    var shift: CGFloat = 0
    var radii: (top: CGFloat, bottom: CGFloat) = NotchMetrics.openRadii

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1, progress))
        let end = rect.offsetBy(dx: shift, dy: 0)
        let start = CGRect(x: rect.midX - closed.width / 2, y: rect.minY,
                           width: closed.width + wing, height: closed.height)
        let frame = CGRect(x: start.minX + (end.minX - start.minX) * p,
                           y: rect.minY,
                           width: start.width + (end.width - start.width) * p,
                           height: start.height + (end.height - start.height) * p)
        let top = NotchMetrics.closedRadii.top + (radii.top - NotchMetrics.closedRadii.top) * p
        let bottom = NotchMetrics.closedRadii.bottom + (radii.bottom - NotchMetrics.closedRadii.bottom) * p
        return NotchShape(topRadius: top, bottomRadius: bottom).path(in: frame)
    }
}
