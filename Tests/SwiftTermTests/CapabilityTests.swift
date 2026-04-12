import Testing
@testable import SwiftTerm

final class CapabilityTests {
    private let esc = "\u{1b}"

    private func makeTerminal(
        cols: Int = 80,
        rows: Int = 24,
        disabled: Set<TerminalCapability> = []
    ) -> (terminal: Terminal, delegate: TerminalTestDelegate) {
        let delegate = TerminalTestDelegate()
        let options = TerminalOptions(cols: cols, rows: rows, scrollback: 0, disabledCapabilities: disabled)
        let terminal = Terminal(delegate: delegate, options: options)
        return (terminal, delegate)
    }

    private func lastResponse(_ delegate: TerminalTestDelegate) -> String {
        guard let data = delegate.sentData.last else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    // MARK: - setMode is blocked when capability is disabled

    @Test func disabledMouseTrackingIgnoresDecset() {
        let (terminal, _) = makeTerminal(disabled: [.mouseTracking])
        // Try to enable VT200 mouse (mode 1000)
        terminal.feed(text: "\(esc)[?1000h")
        #expect(terminal.mouseMode == .off)
    }

    @Test func enabledMouseTrackingStillWorks() {
        let (terminal, _) = makeTerminal()
        terminal.feed(text: "\(esc)[?1000h")
        #expect(terminal.mouseMode == .vt200)
    }

    @Test func disabledBracketedPasteIgnoresDecset() {
        let (terminal, _) = makeTerminal(disabled: [.bracketedPaste])
        terminal.feed(text: "\(esc)[?2004h")
        #expect(terminal.bracketedPasteMode == false)
    }

    @Test func enabledBracketedPasteStillWorks() {
        let (terminal, _) = makeTerminal()
        terminal.feed(text: "\(esc)[?2004h")
        #expect(terminal.bracketedPasteMode == true)
    }

    @Test func disabledAltScreenIgnoresDecset() {
        let (terminal, _) = makeTerminal(disabled: [.alternateScreenBuffer])
        terminal.feed(text: "\(esc)[?1049h")
        #expect(terminal.isCurrentBufferAlternate == false)
    }

    @Test func enabledAltScreenStillWorks() {
        let (terminal, _) = makeTerminal()
        terminal.feed(text: "\(esc)[?1049h")
        #expect(terminal.isCurrentBufferAlternate == true)
    }

    @Test func disabledFocusReportingIgnoresDecset() {
        let (terminal, _) = makeTerminal(disabled: [.focusReporting])
        terminal.feed(text: "\(esc)[?1004h")
        #expect(terminal.sendFocus == false)
    }

    @Test func disabledMouseProtocolIgnoresDecset() {
        let (terminal, delegate) = makeTerminal(disabled: [.mouseProtocolExtensions])
        // Enable mouse tracking first (this is allowed), then try SGR protocol
        terminal.feed(text: "\(esc)[?1000h")
        #expect(terminal.mouseMode == .vt200)
        // Try to set SGR protocol (mode 1006) — should be blocked
        terminal.feed(text: "\(esc)[?1006h")
        // Verify via DECRQM that the protocol mode is not set
        terminal.feed(text: "\(esc)[?1006$p")
        let response = lastResponse(delegate)
        #expect(response.contains("1006;4$y"))
    }

    // MARK: - resetMode is also blocked when capability is disabled

    @Test func disabledAltScreenIgnoresDecrst() {
        let (terminal, _) = makeTerminal(disabled: [.alternateScreenBuffer])
        // Attempt to switch to normal buffer (from already-normal) — should be no-op
        terminal.feed(text: "\(esc)[?1049l")
        #expect(terminal.isCurrentBufferAlternate == false)
    }

    // MARK: - DECRQM returns modeAlwaysReset (4) for disabled capabilities

    @Test func decrqmReportsPermanentlyResetForDisabledMode() {
        let (terminal, delegate) = makeTerminal(disabled: [.bracketedPaste])
        // Send DECRQM for mode 2004 (bracketed paste)
        terminal.feed(text: "\(esc)[?2004$p")
        let response = lastResponse(delegate)
        // Expect: CSI ? 2004 ; 4 $ y  (4 = permanently reset)
        #expect(response.contains("2004;4$y"))
    }

    @Test func decrqmReportsNormalStateForEnabledMode() {
        let (terminal, delegate) = makeTerminal()
        // Mode 2004 is not set, should report modeReset (2)
        terminal.feed(text: "\(esc)[?2004$p")
        let response = lastResponse(delegate)
        #expect(response.contains("2004;2$y"))
    }

    @Test func decrqmReportsPermanentlyResetForDisabledMouse() {
        let (terminal, delegate) = makeTerminal(disabled: [.mouseTracking])
        terminal.feed(text: "\(esc)[?1000$p")
        let response = lastResponse(delegate)
        #expect(response.contains("1000;4$y"))
    }

    // MARK: - DA response omits disabled capabilities

    @Test func daOmitsSixelWhenDisabled() {
        let (terminal, delegate) = makeTerminal(disabled: [.sixelGraphics])
        terminal.feed(text: "\(esc)[c")
        let response = lastResponse(delegate)
        // Sixel = attribute 4, should not appear
        // Response format: CSI ? 65 ; attrs c
        #expect(!response.contains(";4;"))
        // Make sure it's still a valid DA response
        #expect(response.contains("?65;"))
    }

    @Test func daIncludesSixelWhenEnabled() {
        let (terminal, delegate) = makeTerminal()
        terminal.feed(text: "\(esc)[c")
        let response = lastResponse(delegate)
        #expect(response.contains(";4;"))
    }

    @Test func daOmits132ColWhenDisabled() {
        let (terminal, delegate) = makeTerminal(disabled: [.columnMode132])
        terminal.feed(text: "\(esc)[c")
        let response = lastResponse(delegate)
        // 132-col = attribute 1, should not appear after 65
        #expect(!response.contains(";1;"))
    }

    // MARK: - Multiple capabilities can be disabled at once

    @Test func multipleCapabilitiesDisabled() {
        let (terminal, _) = makeTerminal(disabled: [.mouseTracking, .bracketedPaste, .alternateScreenBuffer])
        terminal.feed(text: "\(esc)[?1000h")
        terminal.feed(text: "\(esc)[?2004h")
        terminal.feed(text: "\(esc)[?1049h")
        #expect(terminal.mouseMode == .off)
        #expect(terminal.bracketedPasteMode == false)
        #expect(terminal.isCurrentBufferAlternate == false)
    }

    // MARK: - enableSixelReported still works (backwards compat)

    @Test func enableSixelReportedFalseStillWorks() {
        let delegate = TerminalTestDelegate()
        let options = TerminalOptions(cols: 80, rows: 24, enableSixelReported: false)
        let terminal = Terminal(delegate: delegate, options: options)
        terminal.feed(text: "\(esc)[c")
        let response = lastResponse(delegate)
        #expect(!response.contains(";4;"))
    }

    // MARK: - Default options have all capabilities enabled

    @Test func defaultOptionsEnableAllCapabilities() {
        let options = TerminalOptions.default
        #expect(options.disabledCapabilities.isEmpty)
        for cap in TerminalCapability.allCases {
            #expect(options.isCapabilityEnabled(cap))
        }
    }
}
