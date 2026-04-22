//
//  DimensionLockView.swift  (iOS / iPadOS / visionOS)
//
//  iOS counterpart to the macOS `DimensionLockView`. Same idea: wrap a
//  `TerminalView` so that when dimension lock is engaged, the embedded
//  terminal stays at a fixed natural pixel size (locked cols × locked rows
//  × cell dimensions) and the wrapper applies a GPU-composited scale to
//  fit the container while preserving aspect ratio. No grid reflow, no
//  per-frame redraw churn.
//
//  Why this file is much smaller than the macOS one:
//  - UIKit's `UIView.transform` (CGAffineTransform) is a first-class API,
//    officially supported, and UIKit's input/coord conversion
//    (`UIView.convert(_:from:)`, `UITouch.location(in:)`,
//    `UIGestureRecognizer.location(in:)`) all account for it natively.
//  - So we don't need to intercept touches, inverse-transform points, or
//    synthesize events — the iOS TerminalView (a `UIScrollView` subclass)
//    and its gesture recognizers continue to work unmodified; taps and
//    drags land on the correct cell regardless of scale.
//  - AppKit doesn't give us this: `NSView.convert` ignores layer
//    transforms, which is why the macOS wrapper has to forward
//    synthesized `NSEvent`s with inverse-scaled `locationInWindow`.
//

#if os(iOS) || os(visionOS)
import UIKit
import CoreGraphics
import QuartzCore

/// Wraps a `TerminalView` and optionally applies a uniform scale to the
/// child's visual presentation while keeping its internal grid at a fixed
/// natural size (locked cols × rows × cell dimensions).
///
/// Lock semantics:
/// - When `isLocked == false`: child fills bounds with identity transform;
///   behaves exactly like hosting the TerminalView directly.
/// - When `isLocked == true`: child keeps `bounds.size == naturalSize`
///   (so the terminal's internal layout still thinks it's at locked
///   cols × rows), is centered in the wrapper, and has a uniform
///   `CGAffineTransform(scaleX: s, y: s)` applied so its visual extent
///   fits the wrapper while preserving aspect ratio. Letterbox gaps
///   show the wrapper's own background.
@objc open class DimensionLockView: UIView {

    /// The SwiftTerm terminal view being hosted.
    public let terminalView: TerminalView

    /// Whether dimension lock is currently engaged.
    @objc public var isLocked: Bool = false {
        didSet {
            guard oldValue != isLocked else { return }
            setNeedsLayout()
        }
    }

    /// The locked natural pixel size of the terminal. Updated by the host
    /// when the lock is (re-)engaged; set to `.zero` when the lock is off.
    /// Equals `(lockedCols * cellWidth, lockedRows * cellHeight)` at the
    /// time of locking.
    @objc public var naturalSize: CGSize = .zero {
        didSet {
            guard oldValue != naturalSize else { return }
            setNeedsLayout()
        }
    }

    /// Current applied scale (for clients that want to mirror it elsewhere,
    /// e.g. HUD text "scaled 76%"). Read-only from outside.
    public private(set) var currentScale: CGFloat = 1.0

    public init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)

        // Clip the scaled child so if math ever drifts the letterbox is
        // clean. Belt-and-suspenders — the transform math below lands the
        // scaled content inside the wrapper's bounds by construction.
        clipsToBounds = true

        // Linear is the correct magnification filter for scaled AA text.
        // `.nearest` looks jaggy on glyphs; we want the compositor's
        // bilinear filter to smooth upsamples/downsamples.
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear

        addSubview(terminalView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("DimensionLockView does not support coder init")
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()

        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        if isLocked, naturalSize.width > 0, naturalSize.height > 0 {
            applyLockedLayout(bounds: b)
        } else {
            applyUnlockedLayout(bounds: b)
        }
    }

    /// Lock off — identity transform, child fills bounds.
    private func applyUnlockedLayout(bounds: CGRect) {
        currentScale = 1.0
        // Reset transform BEFORE touching bounds/frame so UIKit's
        // frame-derived-from-(bounds, center, transform) math doesn't
        // produce spurious intermediate values.
        terminalView.transform = .identity
        terminalView.frame = bounds
    }

    /// Lock on — child stays at naturalSize (bounds-wise), is centered in
    /// the wrapper, and receives a uniform scale transform. UIKit's
    /// coord-conversion handles the transform for touches/gestures
    /// automatically — taps land on the correct cell at any scale.
    private func applyLockedLayout(bounds: CGRect) {
        let scale = min(bounds.width / naturalSize.width,
                        bounds.height / naturalSize.height)
        currentScale = scale

        // Order matters: reset transform, then resize, then center,
        // then re-apply transform. Setting geometry while a non-identity
        // transform is live can yield unexpected `frame` side-effects.
        // Resize via `frame.size` so we preserve any existing
        // `bounds.origin` / scroll position instead of resetting it.
        terminalView.transform = .identity
        terminalView.frame.size = naturalSize
        terminalView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        terminalView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}
#endif
