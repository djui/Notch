import AppKit
import QuartzCore

/// Vsync-driven size interpolator. Writes are applied by the host with SwiftUI
/// animations disabled so layout is not fighting an implicit spring.
@MainActor
final class NotchMorphAnimator: NSObject {
    enum Curve {
        /// Critically damped spring, same ~0.38s settle as the old expand animation, no overshoot.
        case expand
        /// Short cubic ease-out for collapse and hover peek.
        case easeOut
    }

    static let expandResponse: TimeInterval = 0.38
    static let easeOutDuration: TimeInterval = 0.18

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var from: CGSize = .zero
    private var to: CGSize = .zero
    private var curve: Curve = .easeOut
    private var onTick: ((CGSize) -> Void)?
    private var onComplete: (() -> Void)?

    func animate(
        from: CGSize,
        to: CGSize,
        curve: Curve,
        window: NSWindow?,
        onTick: @escaping (CGSize) -> Void,
        onComplete: (() -> Void)? = nil
    ) {
        stop()
        self.from = from
        self.to = to
        self.curve = curve
        self.onTick = onTick
        self.onComplete = onComplete

        if hypot(to.width - from.width, to.height - from.height) < 0.5 {
            onTick(to)
            let complete = onComplete
            self.onTick = nil
            self.onComplete = nil
            complete?()
            return
        }

        let link: CADisplayLink
        if let window {
            link = window.displayLink(target: self, selector: #selector(tick(_:)))
        } else if let screen = NSScreen.main {
            link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        } else {
            onTick(to)
            let complete = onComplete
            self.onTick = nil
            self.onComplete = nil
            complete?()
            return
        }
        // Prefer ProMotion; keep the floor at 60 so 60 Hz displays still fire.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        startTime = CACurrentMediaTime()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onTick = nil
        onComplete = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - startTime
        let progress: Double
        let finished: Bool
        switch curve {
        case .expand:
            progress = min(1, Self.criticallyDamped(response: Self.expandResponse, t: elapsed))
            finished = progress >= 0.999 || elapsed >= Self.expandResponse * 1.8
        case .easeOut:
            let t = elapsed / Self.easeOutDuration
            progress = Self.easeOutCubic(min(1, t))
            finished = t >= 1
        }

        let size = finished ? to : Self.lerp(from, to, CGFloat(progress))
        onTick?(size)
        if finished {
            let complete = onComplete
            stop()
            complete?()
        }
    }

    /// Critically damped spring from 0 to 1. `response` matches SwiftUI's spring response.
    private static func criticallyDamped(response: Double, t: Double) -> Double {
        let omega = 2 * Double.pi / max(response, 0.001)
        return 1 - (1 + omega * t) * exp(-omega * t)
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private static func lerp(_ a: CGSize, _ b: CGSize, _ t: CGFloat) -> CGSize {
        CGSize(
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}
