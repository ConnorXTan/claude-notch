import AppKit
import SwiftUI

/// The dot's circle, drawn and animated by Core Animation.
///
/// A pulse or a breath that repeats forever, written as a SwiftUI animation,
/// re-renders the view tree every frame: about 5% CPU per moving dot, and a
/// done session can sit breathing for days, which macOS reports as
/// significant energy. As layer animations the window server plays them on
/// its own and the app is not woken per frame.
struct DotLayer: NSViewRepresentable {
    enum Motion: Equatable {
        case still
        /// Red and unacknowledged: grows and glows.
        case pulse
        /// Done and idle: fades slowly.
        case breathe
    }

    let color: NSColor
    let motion: Motion
    let size: CGFloat

    func makeNSView(context: Context) -> DotLayerView {
        let view = DotLayerView()
        view.apply(color: color, motion: motion, size: size)
        return view
    }

    func updateNSView(_ view: DotLayerView, context: Context) {
        view.apply(color: color, motion: motion, size: size)
    }
}

final class DotLayerView: NSView {
    private let dot = CALayer()
    private var motion: DotLayer.Motion = .still

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false
        dot.shadowOffset = .zero
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks and hovers belong to the SwiftUI views around the dot.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// A view put back in a window gets its animation back.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, motion != .still, dot.animation(forKey: Self.key) == nil {
            start(motion)
        }
    }

    func apply(color: NSColor, motion: DotLayer.Motion, size: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        dot.cornerRadius = size / 2
        dot.backgroundColor = color.cgColor
        dot.shadowColor = color.cgColor
        dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
        dot.shadowRadius = 2
        dot.shadowOpacity = motion == .pulse ? 0.35 : 0
        CATransaction.commit()

        guard motion != self.motion else { return }
        self.motion = motion
        settle()
        start(motion)
    }

    private static let key = "motion"

    private func start(_ motion: DotLayer.Motion) {
        let group = CAAnimationGroup()
        switch motion {
        case .still:
            return
        case .pulse:
            group.animations = [
                Self.basic("transform.scale", to: 1.4),
                Self.basic("shadowOpacity", to: 0.9),
                Self.basic("shadowRadius", to: 5),
            ]
            group.duration = 0.8
        case .breathe:
            group.animations = [Self.basic("opacity", to: 0.45)]
            group.duration = 2.2
        }
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.autoreverses = true
        group.repeatCount = .infinity
        dot.add(group, forKey: Self.key)
    }

    /// Stops the running animation without a jump: a short ease from where
    /// the dot is now back to rest.
    private func settle() {
        guard let now = dot.presentation(), dot.animation(forKey: Self.key) != nil else { return }
        let from: [(String, Any?)] = [
            ("transform.scale", now.value(forKeyPath: "transform.scale")),
            ("opacity", now.opacity),
            ("shadowOpacity", now.shadowOpacity),
            ("shadowRadius", now.shadowRadius),
        ]
        dot.removeAnimation(forKey: Self.key)
        let group = CAAnimationGroup()
        group.animations = from.map { keyPath, value in
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = value
            return animation
        }
        group.duration = 0.2
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        dot.add(group, forKey: "settle")
    }

    private static func basic(_ keyPath: String, to value: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.toValue = value
        return animation
    }
}
