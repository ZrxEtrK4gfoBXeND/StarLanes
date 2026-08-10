//
//  String+Color.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ANSI terminal styling for the console front end.
/// This is presentation-only: the game model and view models remain plain text,
/// so other front ends are unaffected.
enum Ansi {
    private static let escape = "\u{001B}["

    /// Returns the terminal to its default colors.
    static let reset = escape + "0m"
    /// Reverse video, used to highlight the current player's coordinate options.
    static let invert = escape + "7m"
    /// Outpost color. Reserved for outposts, so it is absent from `companyColors`.
    static let yellow = escape + "33m"

    /// One distinct color per company, indexed by company id (A = 0, B = 1, ...).
    /// Deluxe games have ten companies, so ten colors are defined. Yellow is excluded
    /// because outposts own it.
    private static let companyColors = [
        escape + "96m",     // A - bright cyan
        escape + "92m",     // B - bright green
        escape + "95m",     // C - bright magenta
        escape + "91m",     // D - bright red
        escape + "94m",     // E - bright blue
        escape + "36m",     // F - cyan
        escape + "32m",     // G - green
        escape + "35m",     // H - magenta
        escape + "31m",     // I - red
        escape + "34m"      // J - blue
    ]

    /// Whether to emit escape sequences at all.
    /// Disabled when output is redirected, so piped or captured games stay plain text.
    /// Honors the NO_COLOR convention, and CLICOLOR_FORCE to override the redirect check.
    static let isEnabled: Bool = {
        if getenv("NO_COLOR") != nil {
            return false
        }
        if getenv("CLICOLOR_FORCE") != nil {
            return true
        }
        return isatty(1) == 1
    }()

    /// The color a company's tokens are drawn in on the galaxy map.
    /// Tables use this so a company reads as the same color everywhere it appears.
    /// - parameter monogram: Company monogram, "A" for the first company.
    /// - returns: Escape sequence for the company's color.
    static func companyColor(monogram: String) -> String {
        guard let value = monogram.utf8.first, value >= UInt8(65) else {
            return ""
        }
        return companyColors[Int(value - UInt8(65)) % companyColors.count]
    }

    /// Lays out a table cell of fixed visible width, then colors it.
    /// Padding is measured on the plain text and appended outside the escape sequences,
    /// so styling can never disturb column alignment.
    /// - parameter text: Cell contents.
    /// - parameter pad: Column width in visible characters.
    /// - parameter code: Escape sequence to style the contents with. Empty leaves it unstyled.
    /// - returns: The styled, padded cell.
    static func column(_ text: String, pad: Int, code: String) -> String {
        let visible = String(text.prefix(pad))
        let styled = code.isEmpty ? visible : visible.ansi(code)
        return styled + String(repeating: " ", count: pad - visible.count)
    }

    /// Applies color and style to a single galaxy map cell.
    /// Stars, black holes, destroyed space and empty space are left in the default color.
    /// - parameter cell: One-character cell string from `VmoGalaxyMap`.
    /// - returns: The cell wrapped in escape sequences, or unchanged when color is disabled.
    static func galaxyMapCell(_ cell: String) -> String {
        guard isEnabled, let value = cell.utf8.first else {
            return cell
        }

        let plus    = UInt8(43) // 43 is ASCII code for '+'
        let number1 = UInt8(49) // 49 is ASCII code for '1'
        let number9 = UInt8(57) // 57 is ASCII code for '9'
        let letterA = UInt8(65) // 65 is ASCII code for 'A'
        let letterZ = UInt8(90) // 90 is ASCII code for 'Z'

        if value == plus {
            return cell.ansi(yellow)
        } else if value >= number1 && value <= number9 {
            return cell.ansi(invert)
        } else if value >= letterA && value <= letterZ {
            return cell.ansi(companyColors[Int(value - letterA) % companyColors.count])
        }
        return cell
    }
}

extension String {

    /// Wraps the string in an ANSI escape sequence.
    /// - parameter code: Escape sequence to prefix the string with.
    /// - returns: The styled string, or the string unchanged when color is disabled.
    func ansi(_ code: String) -> String {
        return Ansi.isEnabled ? code + self + Ansi.reset : self
    }
}
