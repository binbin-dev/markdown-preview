//
//  OutlineHeading.swift
//  md-preview
//
//  One heading in document order, shared by the renderer and the outline.
//

import Foundation
import Markdown

/// A heading as both the preview and the sidebar see it. `sourceLine` is
/// one-based in the source file, after any frontmatter offset.
nonisolated struct OutlineHeading: Sendable, Equatable {
    let level: Int
    let title: String
    let sourceLine: Int
}

nonisolated enum OutlineHeadingText {

    /// The outline's title for a heading: inline code without its backticks,
    /// and the plain text of every other inline child.
    static func plainText(of markup: Markup) -> String {
        if let code = markup as? InlineCode { return code.code }
        if markup.childCount > 0 {
            return markup.children.map { plainText(of: $0) }.joined()
        }
        return (markup as? InlineMarkup)?.plainText ?? ""
    }

    /// The heading's first source line. Most headings carry a range; the
    /// fallback covers the empty ATX headings after whitespace (`- #`, `> #`,
    /// ` #`) whose range cmark drops. Only blank lines, container markers and
    /// link reference definitions can come between the previous block and the
    /// heading, so it is the first line after that block that ends the way
    /// these headings do.
    static func startLine(of heading: Heading,
                          sourceLines: [Substring],
                          previousHeadingLine: Int?,
                          sourceLineOffset: Int) -> Int {
        if let range = heading.range { return range.lowerBound.line }
        let index = heading.indexInParent
        let previous = index > 0 ? heading.parent?.child(at: index - 1) : nil
        // A previous heading without a range is the last one collected, on one line.
        let previousEnd = previous?.range?.upperBound.line
            ?? (previous is Heading ? previousHeadingLine.map { $0 - sourceLineOffset } : nil)
        let first = previousEnd.map { $0 + 1 } ?? heading.parent?.range?.lowerBound.line ?? 1
        return stride(from: first, through: sourceLines.count, by: 1)
            .first { endsInSpacedHeadingMarker(sourceLines[$0 - 1]) } ?? first
    }

    /// Whether a line ends in one to six `#` after a space or tab: the shape
    /// that loses its range. `>#` and `- # ` keep theirs.
    static func endsInSpacedHeadingMarker(_ line: Substring) -> Bool {
        let marks = line.utf8.reversed().prefix { $0 == UInt8(ascii: "#") }.count
        guard (1...6).contains(marks) else { return false }
        let before = line.utf8.dropLast(marks).last
        return before == UInt8(ascii: " ") || before == UInt8(ascii: "\t")
    }

    /// Splits at LF, CR and CRLF, as CommonMark counts lines. The returned
    /// substrings share the source buffer, so a large document is not copied
    /// line by line.
    static func lines(of text: String) -> [Substring] {
        var lines: [Substring] = []
        lines.reserveCapacity(max(1, text.utf8.count / 48))
        // Walk scalars, not characters: Swift folds CRLF into one Character,
        // so a Character-by-Character scan never sees the CR.
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var index = start
        while index != scalars.endIndex {
            let scalar = scalars[index]
            guard scalar == "\n" || scalar == "\r" else {
                index = scalars.index(after: index)
                continue
            }
            lines.append(text[start..<index])
            index = scalars.index(after: index)
            if scalar == "\r", index != scalars.endIndex, scalars[index] == "\n" {
                index = scalars.index(after: index)
            }
            start = index
        }
        lines.append(text[start...])
        return lines
    }
}

/// Restores the placeholders the render pipeline substitutes before parsing,
/// so an outline title reads like the source instead of like
/// `MdPreviewMathInline0Token`.
nonisolated struct OutlineTokenRestoration: Sendable {
    var mathInlineOriginals: [String] = []
    var footnoteReferenceOriginals: [String] = []

    init(mathInlineOriginals: [String] = [], footnoteReferenceOriginals: [String] = []) {
        self.mathInlineOriginals = mathInlineOriginals
        self.footnoteReferenceOriginals = footnoteReferenceOriginals
    }

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"MdPreview(MathInline|FootnoteRef)(\d+)Token"#
    )

    func restore(_ rawTitle: String) -> String {
        var title = rawTitle
        if title.contains(MarkdownHighlightSource.openingToken)
            || title.contains(MarkdownHighlightSource.closingToken) {
            title = title
                .replacingOccurrences(of: MarkdownHighlightSource.openingToken, with: "==")
                .replacingOccurrences(of: MarkdownHighlightSource.closingToken, with: "==")
        }
        guard title.contains("MdPreview") else { return title }

        let nsTitle = title as NSString
        let matches = Self.tokenRegex.matches(
            in: title,
            range: NSRange(location: 0, length: nsTitle.length)
        )
        guard !matches.isEmpty else { return title }

        var result = ""
        result.reserveCapacity(title.count)
        var cursor = 0
        for match in matches {
            let kind = nsTitle.substring(with: match.range(at: 1))
            let index = Int(nsTitle.substring(with: match.range(at: 2))) ?? -1
            let values = kind == "MathInline" ? mathInlineOriginals : footnoteReferenceOriginals
            guard values.indices.contains(index) else { continue }
            result += nsTitle.substring(with: NSRange(
                location: cursor,
                length: match.range.location - cursor
            ))
            result += values[index]
            cursor = match.range.location + match.range.length
        }
        result += nsTitle.substring(from: cursor)
        return result
    }
}
