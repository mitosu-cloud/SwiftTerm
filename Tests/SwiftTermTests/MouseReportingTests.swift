import Testing
@testable import SwiftTerm

struct MouseReportingTests {
    private final class Capture: TerminalDelegate {
        var sent: [String] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) {
            sent.append(String(decoding: data, as: UTF8.self))
        }
    }

    @Test(arguments: [1006, 1016], [0, 4, 8, 12, 16, 20, 24, 28])
    func sgrHoverKeepsNoButtonAndMotionBits(protocolMode: Int, modifiers: Int) {
        let capture = Capture()
        let terminal = Terminal(delegate: capture)
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?\(protocolMode)h")
        terminal.sendMotion(buttonFlags: 3 | modifiers, x: 8, y: 4, pixelX: 90, pixelY: 50)
        let coordinates = protocolMode == 1006 ? "9;5" : "90;50"
        #expect(capture.sent == ["\u{1b}[<\(35 | modifiers);\(coordinates)M"])
    }

    @Test(arguments: [1006, 1016])
    func clicksDragsWheelAndReleasesKeepTheirEncoding(protocolMode: Int) {
        let capture = Capture()
        let terminal = Terminal(delegate: capture)
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?\(protocolMode)h")
        terminal.sendEvent(buttonFlags: 0, x: 8, y: 4, pixelX: 90, pixelY: 50)
        terminal.sendMotion(buttonFlags: 0, x: 8, y: 4, pixelX: 90, pixelY: 50)
        terminal.sendEvent(buttonFlags: 3, x: 8, y: 4, pixelX: 90, pixelY: 50)
        terminal.sendEvent(buttonFlags: 64, x: 8, y: 4, pixelX: 90, pixelY: 50)
        let coordinates = protocolMode == 1006 ? "9;5" : "90;50"
        #expect(capture.sent == ["\u{1b}[<0;\(coordinates)M", "\u{1b}[<32;\(coordinates)M",
                                 "\u{1b}[<0;\(coordinates)m", "\u{1b}[<64;\(coordinates)M"])
    }

    @Test(arguments: [0, 1005, 1015])
    func legacyHoverEncodingIsUnchanged(protocolMode: Int) {
        let capture = Capture()
        let terminal = Terminal(delegate: capture)
        terminal.feed(text: "\u{1b}[?1003h")
        if protocolMode != 0 { terminal.feed(text: "\u{1b}[?\(protocolMode)h") }
        terminal.sendMotion(buttonFlags: 3, x: 8, y: 4, pixelX: 90, pixelY: 50)
        #expect(capture.sent == [protocolMode == 1015 ? "\u{1b}[67;9;5M" : "\u{1b}[MC)%"])
    }
}

#if os(macOS)
import AppKit

@MainActor
@Suite(.serialized)
struct MacMouseReportingTests {
    private func view(scrollback: Bool = false) -> MouseCaptureTerminalView {
        _ = NSApplication.shared
        let view = MouseCaptureTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        if scrollback { view.feed(text: String(repeating: "line\r\n", count: 100)) }
        view.feed(text: "\u{1b}[?1003h\u{1b}[?1006h")
        view.sent.removeAll()
        return view
    }

    private func event(_ type: NSEvent.EventType = .mouseMoved, in view: TerminalView) -> NSEvent {
        let point = CGPoint(x: view.cellDimension.width * 2.25,
                            y: view.frame.height - view.cellDimension.height * 3.25)
        return NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                                  modifierFlags: [], timestamp: 1, windowNumber: 0,
                                  context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
    }

    @Test func actualHoverProducesOneValidReportPerCell() {
        let view = view()
        let hover = event(in: view)
        view.mouseMoved(with: hover)
        view.mouseMoved(with: hover)
        #expect(view.sent == ["\u{1b}[<35;3;4M"])
    }

    @Test func hoverUsesViewportRowsAfterScrollback() {
        let view = view(scrollback: true)
        #expect(view.getTerminal().displayBuffer.yDisp > 0)
        view.mouseMoved(with: event(in: view))
        #expect(view.sent == ["\u{1b}[<35;3;4M"])
    }

    @Test func disablingHoverKeepsDragReports() {
        let view = view()
        view.allowMouseMotionTracking = false
        view.mouseMoved(with: event(in: view))
        #expect(view.sent.isEmpty)
        view.mouseDragged(with: event(.leftMouseDragged, in: view))
        #expect(view.sent == ["\u{1b}[<32;3;4M"])
    }

    @Test func hoverRequiresNegotiatedAnyEventModeAndMouseReporting() {
        let view = view()
        view.allowMouseReporting = false
        view.mouseMoved(with: event(in: view))
        #expect(view.sent.isEmpty)
        view.allowMouseReporting = true
        view.feed(text: "\u{1b}[?1003l\u{1b}[?1002h")
        view.mouseMoved(with: event(in: view))
        #expect(view.sent.isEmpty)
    }
}

private final class MouseCaptureTerminalView: TerminalView {
    var sent: [String] = []
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        sent.append(String(decoding: data, as: UTF8.self))
    }
}
#endif
