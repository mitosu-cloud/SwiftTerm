//
//  DimensionLockView.swift
//
//  A wrapper NSView for TerminalView that implements "dimension lock":
//  when enabled, the embedded TerminalView stays at a fixed natural pixel
//  size (locked cols × locked rows × cell dimensions), and the wrapper
//  applies a GPU-composited CATransform3D scale to fit the available
//  container bounds while preserving aspect ratio. This avoids the
//  cols/rows reflow and the full-grid redraw that a normal setFrameSize
//  triggers — when the parent resizes briefly (sidebar drag, inspector
//  toggle, window resize while in lock), the terminal session is
//  completely unaffected.
//
//  When disabled, the wrapper behaves as a pass-through: the child fills
//  the wrapper's bounds exactly, and there's no transform — normal
//  SwiftTerm resize behavior is preserved.
//

#if os(macOS)
import AppKit
import CoreGraphics
import QuartzCore

/// Wraps a `TerminalView` and optionally applies a GPU-composited scale
/// to the child's visual presentation while keeping the child's frame at
/// a fixed natural size (determined by locked cols × rows × cell size).
///
/// Lock semantics:
/// - When `isLocked == false`: child fills bounds; no transform; behaves
///   exactly like hosting the TerminalView directly.
/// - When `isLocked == true`: child's frame is `naturalSize` (centered in
///   the wrapper). The wrapper's backing layer applies a uniform scale
///   (around the wrapper's center) so the child visually fills as much of
///   the wrapper's bounds as possible while preserving aspect ratio.
///   Letterbox gaps show the wrapper's own background.
///
/// Mouse events are intercepted and forwarded to the child with
/// inverse-scaled coordinates so clicks land on the correct grid cell
/// regardless of scale.
@objc open class DimensionLockView: NSView {

    /// The SwiftTerm terminal view being hosted. Exposed `internal` so the
    /// hosting framework (Mitosu) can access it for delegate wiring.
    public let terminalView: TerminalView

    /// Whether dimension lock is currently engaged.
    @objc public var isLocked: Bool = false {
        didSet {
            guard oldValue != isLocked else { return }
            needsLayout = true
        }
    }

    /// The locked natural pixel size of the terminal. Updated by the host
    /// when the lock is (re-)engaged; set to `.zero` when the lock is off.
    /// Equals `(lockedCols * cellWidth, lockedRows * cellHeight)` at the
    /// time of locking.
    @objc public var naturalSize: CGSize = .zero {
        didSet {
            guard oldValue != naturalSize else { return }
            needsLayout = true
        }
    }

    /// Current applied scale (for clients that want to mirror it elsewhere,
    /// e.g. HUD text "scaled 76%"). Read-only from outside.
    public private(set) var currentScale: CGFloat = 1.0

    public init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)

        wantsLayer = true
        // No drawRect of our own; we're purely a transform host. This
        // avoids redraw churn during scale changes.
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Linear is the correct magnification filter for scaled AA text.
        // .nearest makes glyphs jaggy; we want the compositor's bilinear
        // filter to smooth the upsample.
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear

        // Clip to bounds so if the locked child's natural frame extends
        // outside the wrapper (natural > wrapper), the pre-transform layer
        // rendering doesn't bleed into sibling views (sidebars, etc.).
        // The transform math below places the scaled content inside the
        // wrapper, but masksToBounds is belt-and-suspenders insurance.
        layer?.masksToBounds = true

        addSubview(terminalView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("DimensionLockView does not support coder init")
    }

    // MARK: - Layout

    open override var isFlipped: Bool { true }

    open override func layout() {
        super.layout()

        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        if isLocked, naturalSize.width > 0, naturalSize.height > 0 {
            applyLockedLayout(bounds: bounds)
        } else {
            applyUnlockedLayout(bounds: bounds)
        }
    }

    /// Lock off — identity sublayerTransform, child fills bounds. Parent-
    /// driven resizes go straight to SwiftTerm (normal behavior).
    private func applyUnlockedLayout(bounds: CGRect) {
        currentScale = 1.0
        // Clear any residual sublayer transform from a previous locked state.
        layer?.sublayerTransform = CATransform3DIdentity
        // Child fills the wrapper (natural SwiftTerm hosting).
        terminalView.frame = bounds
    }

    /// Lock on — child stays at naturalSize centered; wrapper applies a
    /// uniform scale via `sublayerTransform` about the wrapper's center.
    /// This is the GPU path.
    ///
    /// Why `sublayerTransform` (not `layer.transform`):
    /// - With `layer.transform` and no masking, the child's pre-scale frame
    ///   (e.g. natural 1200×400 centered in a 500×300 wrapper → origin
    ///   (-350, -50)) renders to negative-x in the wrapper's parent's
    ///   coord space → leaks into sibling views (the sidebar, in practice).
    /// - With `layer.transform` + `masksToBounds = true`, the child is
    ///   clipped to wrapper bounds *before* the transform, losing most of
    ///   the terminal content.
    /// - `sublayerTransform` applies per-sublayer at composite time, after
    ///   each sublayer's own rendering, so the full child content passes
    ///   through the transform. `masksToBounds = true` then clips the
    ///   already-scaled result to the wrapper's bounds — no leakage.
    ///
    /// Why the compound translate-scale-translate: `NSView.layer.anchorPoint`
    /// defaults to `(0, 0)` on macOS (unlike UIKit's `(0.5, 0.5)`), and
    /// `sublayerTransform` is applied relative to the layer's anchor point.
    /// To scale about the wrapper's center we conjugate the scale with a
    /// pair of translations.
    private func applyLockedLayout(bounds: CGRect) {
        let scale = min(bounds.width / naturalSize.width,
                        bounds.height / naturalSize.height)
        currentScale = scale

        // Place the child's natural frame so its center coincides with the
        // wrapper's center. After the center-anchored scale below, the
        // scaled content stays visually centered in the wrapper with
        // letterbox gaps on whichever axis isn't the binding constraint.
        let childOrigin = CGPoint(
            x: (bounds.width - naturalSize.width) / 2,
            y: (bounds.height - naturalSize.height) / 2
        )
        terminalView.frame = CGRect(origin: childOrigin, size: naturalSize)

        // Compound transform: translate to the wrapper's center, scale,
        // translate back. Applied per-sublayer at composite time.
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, cx, cy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        layer?.sublayerTransform = t
    }

    // MARK: - Mouse & hit test forwarding

    // When the wrapper's layer has a scale transform, AppKit's default
    // `hitTest` and `convert(_:from:)` don't account for the transform
    // (they walk the un-transformed NSView frame tree). Without
    // intervention, a click at the visually-scaled child's top-left
    // would hit-test at the child's un-transformed coords, which is the
    // wrong cell. We intercept here and synthesize events whose
    // `locationInWindow` has been pre-adjusted so that SwiftTerm's
    // existing `convert(event.locationInWindow, from: nil)` yields the
    // correct natural-coord point.

    open override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in our superview's coord system (standard NSView.hitTest
        // convention). First transition to our own coord (bounds) via the
        // inverse of our frame offset; AppKit normally does this for us, but
        // since we're intercepting, do it explicitly.
        let pointInSelf = self.convert(point, from: superview)

        // When unlocked, defer to default behavior.
        if !isLocked || currentScale == 1.0 {
            return super.hitTest(point)
        }

        // Inverse-transform around the wrapper's center (the anchor the
        // layer.transform scales around).
        let natural = inverseTransform(pointInSelf)

        // If the natural point lies inside the child's frame, return self
        // (the wrapper) so AppKit routes events to our overridden
        // mouseDown/etc., which then forward synthesized events to the
        // child.
        if terminalView.frame.contains(natural) {
            return self
        }
        return nil
    }

    /// Convert a point in the wrapper's bounds coord (visually, where the
    /// user sees the cursor) to the natural (un-scaled) point in the same
    /// bounds coord — which is also the point the child's frame is laid
    /// out in.
    private func inverseTransform(_ p: CGPoint) -> CGPoint {
        guard currentScale != 0 else { return p }
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        return CGPoint(
            x: (p.x - center.x) / currentScale + center.x,
            y: (p.y - center.y) / currentScale + center.y
        )
    }

    /// Synthesize a mouse event whose `locationInWindow` is shifted so
    /// that the child's `convert(locationInWindow, from: nil)` yields the
    /// natural-coord point corresponding to the user's visual click.
    private func forward(_ event: NSEvent, to child: TerminalView,
                         invoke: (TerminalView, NSEvent) -> Void) {
        // event.locationInWindow is in the window's coord.
        // Convert to wrapper bounds coord:
        let inWrapper = self.convert(event.locationInWindow, from: nil)
        // Inverse-transform to natural coord (still in wrapper's bounds
        // system; identical to child's frame system since we just offset):
        let natural = inverseTransform(inWrapper)
        // Convert that natural point into window coord via the child —
        // child's frame.origin is known (we set it in layout()), so
        // this places locationInWindow such that
        //   child.convert(newLoc, from: nil) == natural - child.frame.origin
        // which is what SwiftTerm's mouse handlers expect as a local
        // natural-coord point inside the child.
        let newLocInWindow = self.convert(natural, to: nil)
        guard let newEvent = NSEvent.mouseEvent(
            with: event.type,
            location: newLocInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) else {
            invoke(child, event)
            return
        }
        invoke(child, newEvent)
    }

    open override func mouseDown(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.mouseDown(with: $1) }
        } else {
            terminalView.mouseDown(with: event)
        }
    }

    open override func mouseUp(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.mouseUp(with: $1) }
        } else {
            terminalView.mouseUp(with: event)
        }
    }

    open override func mouseDragged(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.mouseDragged(with: $1) }
        } else {
            terminalView.mouseDragged(with: event)
        }
    }

    open override func mouseMoved(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.mouseMoved(with: $1) }
        } else {
            terminalView.mouseMoved(with: event)
        }
    }

    open override func rightMouseDown(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.rightMouseDown(with: $1) }
        } else {
            terminalView.rightMouseDown(with: event)
        }
    }

    open override func rightMouseUp(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.rightMouseUp(with: $1) }
        } else {
            terminalView.rightMouseUp(with: event)
        }
    }

    open override func otherMouseDown(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.otherMouseDown(with: $1) }
        } else {
            terminalView.otherMouseDown(with: event)
        }
    }

    open override func otherMouseUp(with event: NSEvent) {
        if isLocked, currentScale != 1.0 {
            forward(event, to: terminalView) { $0.otherMouseUp(with: $1) }
        } else {
            terminalView.otherMouseUp(with: event)
        }
    }

    open override func scrollWheel(with event: NSEvent) {
        // Scroll-wheel events cannot be synthesized through public AppKit
        // API (`NSEvent.mouseEvent(...)` is for button events only — it
        // asserts on `NSEvent.eventNumber` for ScrollWheel types). We
        // forward the original event unmodified. The wheel delta and phase
        // are position-independent, so scrolling works correctly at any
        // scale. The minor caveat: in mouse-reporting TUIs that encode
        // scroll as button-4/5 + position, the reported col/row will be
        // the unscaled (natural-frame) cell the cursor hits, which in
        // locked mode may be slightly off-center versus where the user
        // visually aimed. This is a rare edge case and not worth the
        // complexity of coordinate mangling in CGEvent space.
        terminalView.scrollWheel(with: event)
    }

    // MARK: - First responder

    // We never want the wrapper itself to become first responder — the
    // TerminalView is the focus target. Returning false here means clicks
    // that land on the wrapper (for key events, text input, etc.) forward
    // their first-responder intent through.
    open override var acceptsFirstResponder: Bool { false }
}
#endif
