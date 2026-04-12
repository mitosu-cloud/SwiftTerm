//
//  TerminalOptions.swift
//  SwiftTerm
//
//  Created by Miguel de Icaza on 2/29/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import Foundation

/// Configuration option for the desired cursor style, this style can also be overwritten by the application
/// inside the terminal, and the UI control can choose to honor this request.
public enum CursorStyle {
    case blinkBlock
    case steadyBlock
    case blinkUnderline
    case steadyUnderline
    case blinkBar
    case steadyBar
    
    public static func from (string: String) -> CursorStyle? {
        switch string {
        case "blinkBlock":
            return .blinkBlock
        case "steadyBlock":
            return .steadyBlock
        case "blinkUnderline":
            return .blinkUnderline
        case "steadyUnderline":
            return .steadyUnderline
        case "blinkBar":
            return .blinkBar
        case "steadyBar":
            return .steadyBar
        default:
            return nil
        }
    }
}

/// Identifies a terminal capability that can be selectively disabled via
/// ``TerminalOptions/disabledCapabilities``.
///
/// When a capability is disabled, the corresponding DECSET/DECRST escape sequences
/// are silently ignored, DECRQM queries report the mode as permanently reset, and
/// DA responses omit the feature where applicable.
///
/// By default all capabilities are enabled.
public enum TerminalCapability: Hashable, CaseIterable, Sendable {
    // Cursor & Input
    /// Application cursor keys (DECCKM, mode 1)
    case applicationCursorKeys
    /// Application keypad mode (DECNKM, mode 66)
    case applicationKeypad
    /// Cursor blink (ATT610, mode 12)
    case cursorBlink

    // Screen Layout
    /// 132-column mode (DECCOLM, mode 3) and the allow-transition flag (mode 40)
    case columnMode132
    /// Origin mode (DECOM, mode 6)
    case originMode
    /// Wraparound mode (DECAWM, mode 7)
    case wraparound
    /// Reverse wraparound (mode 45)
    case reverseWraparound
    /// Left/right margin mode (DECLRMM, mode 69)
    case marginMode
    /// Smooth scroll (DECSCLM, mode 4)
    case smoothScroll
    /// Reverse video (DECSCNM, mode 5)
    case reverseVideo

    // Alternate Screen
    /// Alternate screen buffer (modes 47, 1047, 1048, 1049)
    case alternateScreenBuffer

    // Mouse Tracking
    /// All mouse tracking modes (modes 9, 1000, 1002, 1003)
    case mouseTracking
    /// All mouse protocol encodings (modes 1005, 1006, 1015, 1016)
    case mouseProtocolExtensions

    // Clipboard & Focus
    /// Bracketed paste mode (mode 2004)
    case bracketedPaste
    /// Focus in/out event reporting (mode 1004)
    case focusReporting
    /// Synchronized output (mode 2026)
    case synchronizedOutput

    // Graphics
    /// Sixel graphics support (DA attribute 4)
    case sixelGraphics
}

/// Configuration options for the terminal at startup, these values are only read at startup
public struct TerminalOptions {
    /// Desired number of columns at startup (default 80)
    public var cols: Int
    /// Desired number of rows at startup (default 25)
    public var rows: Int
    /// Controls whether a Line-Feed character will also behave like a carriage return (true) or not (false).  defaults to false)
    public var convertEol: Bool
    /// Desired value for the terminal name, defaults to xterm-color
    public var termName: String
    /// The desired startup cursor style, this merely sets an internal variable, it is the view job to render it
    public var cursorStyle: CursorStyle
    /// Deprecated?   The new accessibility work will make this useless
    public var screenReaderMode: Bool
    /// Size of the scrollback buffer, defaults to 500 lines
    public var scrollback: Int
    /// Default size of the tabs, defaults to 8
    public var tabStopWidth: Int
    /// Whether to report that sixel support is present
    public var enableSixelReported:Bool
    /// Maximum total bytes to keep for kitty image data; defaults to 320MB and is clamped to 4GB.
    public var kittyImageCacheLimitBytes: Int
    /// Strategy used to derive the 256-color palette from the base 16 colors.
    public var ansi256PaletteStrategy: Ansi256PaletteStrategy
    /// Terminal capabilities to disable. When a capability is in this set,
    /// the corresponding DECSET/DECRST escape sequences are silently ignored,
    /// DECRQM queries report the mode as permanently reset (value 4), and
    /// DA responses omit the capability.
    ///
    /// Defaults to an empty set (all capabilities enabled).
    public var disabledCapabilities: Set<TerminalCapability>

    /// Returns true if the given capability is enabled (not in ``disabledCapabilities``).
    public func isCapabilityEnabled (_ capability: TerminalCapability) -> Bool {
        !disabledCapabilities.contains(capability)
    }

    /// Default options
    public static let `default` = TerminalOptions.init(cols: 80,
                                                       rows: 25,
                                                       convertEol: false,
                                                       termName: "xterm-256color",
                                                       cursorStyle: .blinkBlock,
                                                       screenReaderMode: false,
                                                       scrollback: 500,
                                                       tabStopWidth: 8,
                                                       enableSixelReported: true,
                                                       kittyImageCacheLimitBytes: 320 * 1024 * 1024,
                                                       ansi256PaletteStrategy: .base16Lab,
                                                       disabledCapabilities: [])

  public init(cols: Int = Self.default.cols, rows: Int = Self.default.rows, convertEol: Bool = Self.default.convertEol, termName: String = Self.default.termName, cursorStyle: CursorStyle = Self.default.cursorStyle, screenReaderMode: Bool = Self.default.screenReaderMode, scrollback: Int = Self.default.scrollback, tabStopWidth: Int = Self.default.tabStopWidth,
              enableSixelReported: Bool = Self.default.enableSixelReported, kittyImageCacheLimitBytes: Int = Self.default.kittyImageCacheLimitBytes, ansi256PaletteStrategy: Ansi256PaletteStrategy = Self.default.ansi256PaletteStrategy, disabledCapabilities: Set<TerminalCapability> = Self.default.disabledCapabilities) {
        self.cols = cols
        self.rows = rows
        self.convertEol = convertEol
        self.termName = termName
        self.cursorStyle = cursorStyle
        self.screenReaderMode = screenReaderMode
        self.scrollback = scrollback
        self.tabStopWidth = tabStopWidth
        self.enableSixelReported = enableSixelReported
        self.kittyImageCacheLimitBytes = kittyImageCacheLimitBytes
        self.ansi256PaletteStrategy = ansi256PaletteStrategy
        self.disabledCapabilities = disabledCapabilities
    }
}
