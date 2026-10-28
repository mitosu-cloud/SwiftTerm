#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@MainActor
@Suite(.serialized)
struct DimensionLockViewTests {
    private func terminal() -> TerminalView {
        _ = NSApplication.shared
        return TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
    }

    private func wrapper(_ terminal: TerminalView, locked: Bool = true,
                         size: CGSize = CGSize(width: 400, height: 200)) -> DimensionLockView {
        let view = DimensionLockView(terminalView: terminal)
        view.frame = CGRect(origin: CGPoint(x: 40, y: 60), size: size)
        view.naturalSize = CGSize(width: 800, height: 400)
        view.isLocked = locked
        view.layout()
        return view
    }

    private func event(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type,
                           location: view.convert(CGPoint(x: 100, y: 50), to: nil),
                           modifierFlags: [.shift], timestamp: 12, windowNumber: 0,
                           context: nil, eventNumber: 7, clickCount: 2, pressure: 0.5)!
    }

    private func dispatch(_ event: NSEvent, to responder: NSResponder) {
        switch event.type {
        case .leftMouseDown: responder.mouseDown(with: event)
        case .leftMouseUp: responder.mouseUp(with: event)
        case .leftMouseDragged: responder.mouseDragged(with: event)
        case .mouseMoved: responder.mouseMoved(with: event)
        case .rightMouseDown: responder.rightMouseDown(with: event)
        case .rightMouseUp: responder.rightMouseUp(with: event)
        case .otherMouseDown: responder.otherMouseDown(with: event)
        case .otherMouseUp: responder.otherMouseUp(with: event)
        case .scrollWheel: responder.scrollWheel(with: event)
        default: Issue.record("Unexpected test event type")
        }
    }

    @Test func inheritedRightClickEscapesTheWrapperWithoutRecursion() {
        let child = terminal()
        let view = BoundedRightClickLockView(terminalView: child)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        view.naturalSize = CGSize(width: 800, height: 400)
        view.isLocked = true
        view.layout()
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        #expect(child.nextResponder === view)
        let click = event(.rightMouseDown, in: view)
        view.rightMouseDown(with: click)
        // First entry dispatches to the child; second entry is AppKit bubbling it.
        #expect(view.entries == 2)
        #expect(ancestor.events.count == 1)
        #expect(ancestor.events.first === click)
    }

    @Test(arguments: [NSEvent.EventType.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                       .mouseMoved, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp])
    func unhandledMouseEventsContinueUpTheResponderChain(type: NSEvent.EventType) {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        child.bubble = true
        let view = wrapper(child)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        let original = event(type, in: view)
        dispatch(original, to: view)
        #expect(child.events.count == 1)
        #expect(ancestor.events.count == 1)
        // Ancestors need the original visual coordinate, not the transformed terminal cell.
        #expect(ancestor.events.first === original)
    }

    @Test func independentEventsStillReachTheTerminalAfterBubbling() {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        child.bubble = true
        let view = wrapper(child)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        for _ in 0..<3 {
            view.rightMouseDown(with: event(.rightMouseDown, in: view))
        }
        #expect(child.events.count == 3)
        #expect(ancestor.events.count == 3)
    }

    @Test func handledClicksKeepTheirInverseScaledCoordinateAndMetadata() {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let view = wrapper(child)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        let original = event(.leftMouseDown, in: view)
        view.mouseDown(with: original)
        #expect(child.events.count == 1)
        guard let forwarded = child.events.first else { return }
        let point = view.convert(forwarded.locationInWindow, from: nil)
        // Visual (100, 50), scaled around (200, 100) at 0.5, maps to (0, 0).
        #expect(abs(point.x) < 0.001)
        #expect(abs(point.y) < 0.001)
        #expect(forwarded.type == original.type)
        #expect(forwarded.modifierFlags == original.modifierFlags)
        #expect(forwarded.timestamp == original.timestamp)
        #expect(forwarded.clickCount == original.clickCount)
        #expect(ancestor.events.isEmpty)
    }

    @Test func scrollWheelBubblingPreservesItsDeltaAndDoesNotRecurse() {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        child.bubble = true
        let view = wrapper(child)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                              wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        let wheel = NSEvent(cgEvent: cgEvent)!
        view.scrollWheel(with: wheel)
        #expect(child.events.count == 1)
        #expect(ancestor.events.count == 1)
        #expect(child.events.first === wheel)
        #expect(ancestor.events.first === wheel)
        #expect(wheel.scrollingDeltaY != 0)
    }

    @Test func nestedIndependentMouseEventsStillReachTheTerminal() {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        child.bubble = true
        let view = wrapper(child)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        let down = event(.leftMouseDown, in: view)
        let up = event(.leftMouseUp, in: view)
        child.onReceive = { event in
            if event.type == .leftMouseDown { view.mouseUp(with: up) }
        }
        view.mouseDown(with: down)
        #expect(child.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(ancestor.events.count == 2)
        #expect(ancestor.events.first === up)
        #expect(ancestor.events.last === down)
    }

    @Test func unlockedScrollBubblesWithoutRedeliveryToTheChild() {
        _ = NSApplication.shared
        let child = MouseEventTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        child.bubble = true
        let view = wrapper(child, locked: false)
        let ancestor = MouseEventResponder()
        view.nextResponder = ancestor
        let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                              wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        let wheel = NSEvent(cgEvent: cgEvent)!
        child.scrollWheel(with: wheel)
        #expect(child.events.count == 1)
        #expect(ancestor.events.count == 1)
        #expect(ancestor.events.first === wheel)
    }

    @Test func unlockedAndUnityScaleClicksHitTheChildDirectly() {
        let child = terminal()
        let view = wrapper(child, locked: false)
        #expect(view.hitTest(view.convert(CGPoint(x: 20, y: 180), to: view.superview)) === child)
        view.isLocked = true
        view.frame.size = CGSize(width: 800, height: 600)
        view.layout()
        #expect(view.currentScale == 1)
        // Unity-scale layout has a 100-point letterbox above and below the child.
        #expect(view.hitTest(view.convert(CGPoint(x: 20, y: 490), to: view.superview)) === child)
    }
}

@MainActor
private final class BoundedRightClickLockView: DimensionLockView {
    var entries = 0
    override func rightMouseDown(with event: NSEvent) {
        entries += 1
        // Bound the old bug so its regression fails without overflowing the test runner.
        if entries <= 3 { super.rightMouseDown(with: event) }
    }
}

@MainActor
private final class MouseEventResponder: NSResponder {
    var events: [NSEvent] = []
    override func mouseDown(with event: NSEvent) { events.append(event) }
    override func mouseUp(with event: NSEvent) { events.append(event) }
    override func mouseDragged(with event: NSEvent) { events.append(event) }
    override func mouseMoved(with event: NSEvent) { events.append(event) }
    override func rightMouseDown(with event: NSEvent) { events.append(event) }
    override func rightMouseUp(with event: NSEvent) { events.append(event) }
    override func otherMouseDown(with event: NSEvent) { events.append(event) }
    override func otherMouseUp(with event: NSEvent) { events.append(event) }
    override func scrollWheel(with event: NSEvent) { events.append(event) }
}

@MainActor
private final class MouseEventTerminalView: TerminalView {
    var events: [NSEvent] = []
    var bubble = false
    var onReceive: ((NSEvent) -> Void)?
    private func receive(_ event: NSEvent, forward: () -> Void) {
        events.append(event)
        onReceive?(event)
        if bubble, events.count < 4 { forward() }
    }
    override func mouseDown(with event: NSEvent) { receive(event) { nextResponder?.mouseDown(with: event) } }
    override func mouseUp(with event: NSEvent) { receive(event) { nextResponder?.mouseUp(with: event) } }
    override func mouseDragged(with event: NSEvent) { receive(event) { nextResponder?.mouseDragged(with: event) } }
    override func mouseMoved(with event: NSEvent) { receive(event) { nextResponder?.mouseMoved(with: event) } }
    override func rightMouseDown(with event: NSEvent) { receive(event) { nextResponder?.rightMouseDown(with: event) } }
    override func rightMouseUp(with event: NSEvent) { receive(event) { nextResponder?.rightMouseUp(with: event) } }
    override func otherMouseDown(with event: NSEvent) { receive(event) { nextResponder?.otherMouseDown(with: event) } }
    override func otherMouseUp(with event: NSEvent) { receive(event) { nextResponder?.otherMouseUp(with: event) } }
    override func scrollWheel(with event: NSEvent) { receive(event) { nextResponder?.scrollWheel(with: event) } }
}
#endif
