import SwiftUI

/// A brand mark drawn from its own path data rather than approximated with a
/// glyph. The GitHub mark in particular is a silhouette no SF Symbol stands in
/// for — a `</>` chevron is a different logo, and reads as one.
///
/// Supports the subset of the SVG path grammar these marks actually use:
/// M/m L/l H/h V/v C/c S/s Z/z, including implicit repeats and the numeric
/// shorthands (".5.5", "1-2") that minified path data leans on.
struct VectorMark: Shape {
    let commands: String
    /// The path data's own coordinate system, scaled to fit the shape's rect.
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: dx + p.x * scale, y: dy + p.y * scale)
        }

        var tokens = PathScanner(commands)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var verb: Character = "M"

        while let next = tokens.peekVerb() ?? (tokens.hasNumber ? verb : nil) {
            if tokens.peekVerb() != nil { verb = tokens.takeVerb() }
            let relative = next.isLowercase
            func point(_ x: Double, _ y: Double) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch Character(next.lowercased()) {
            case "m":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                current = point(x, y); subpathStart = current
                path.move(to: map(current))
                // A second coordinate pair after M is an implicit lineto.
                verb = relative ? "l" : "L"
                lastControl = nil
            case "l":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                current = point(x, y); path.addLine(to: map(current)); lastControl = nil
            case "h":
                guard let x = tokens.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: map(current)); lastControl = nil
            case "v":
                guard let y = tokens.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: map(current)); lastControl = nil
            case "c":
                guard let x1 = tokens.number(), let y1 = tokens.number(),
                      let x2 = tokens.number(), let y2 = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return path }
                let c1 = point(x1, y1), c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: map(current), control1: map(c1), control2: map(c2))
                lastControl = c2
            case "s":
                guard let x2 = tokens.number(), let y2 = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return path }
                // The reflected control point is what makes S smooth.
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: map(current), control1: map(c1), control2: map(c2))
                lastControl = c2
            case "z":
                path.closeSubpath(); current = subpathStart; lastControl = nil
            default:
                return path
            }
        }
        return path
    }
}

/// Pulls verbs and numbers out of minified path data, where separators are
/// optional and a minus sign or a second decimal point starts a new number.
private struct PathScanner {
    private let chars: [Character]
    private var index = 0

    init(_ source: String) { chars = Array(source) }

    private mutating func skipSeparators() {
        while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" {
            index += 1
        }
    }

    mutating func peekVerb() -> Character? {
        skipSeparators()
        guard index < chars.count, chars[index].isLetter else { return nil }
        return chars[index]
    }

    mutating func takeVerb() -> Character {
        let verb = chars[index]; index += 1; return verb
    }

    var hasNumber: Bool {
        var probe = index
        while probe < chars.count, chars[probe] == " " || chars[probe] == "," { probe += 1 }
        guard probe < chars.count else { return false }
        return chars[probe].isNumber || chars[probe] == "-" || chars[probe] == "."
    }

    mutating func number() -> Double? {
        skipSeparators()
        var text = ""
        var seenDot = false
        while index < chars.count {
            let c = chars[index]
            if c == "-" && !text.isEmpty { break }
            if c == "." {
                if seenDot { break }
                seenDot = true
            } else if !(c.isNumber || c == "-") {
                break
            }
            text.append(c); index += 1
        }
        return Double(text)
    }
}

enum BrandPath {
    /// The GitHub mark, 24x24.
    static let github = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12z"
}
