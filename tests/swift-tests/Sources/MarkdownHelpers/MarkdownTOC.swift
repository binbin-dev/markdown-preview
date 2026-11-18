//
//  MarkdownTOC.swift
//  md-preview
//

import Foundation
import Markdown

nonisolated struct TOCItem: Identifiable, Hashable, Sendable {
    let id: Int
    let level: Int
    let title: String
    let sourceLine: Int
    var children: [TOCItem]
}

nonisolated enum MarkdownTOC {

    /// Parses Markdown for callers that hold only source text — live editor
    /// updates. Full-document display reuses the headings the renderer already
    /// met and calls `tree(from:)` instead, so the document is parsed once.
    static func parse(_ markdown: String) -> [TOCItem] {
        let headings = extractHeadings(from: markdown)
        return tree(from: headings)
    }

    private static func extractHeadings(from markdown: String) -> [OutlineHeading] {
        // Share the renderer's CommonMark parsing so container nesting and fence
        // delimiters cannot turn code-block contents into outline entries.
        let split = MarkdownFrontmatter.split(markdown)
        let body = split.body
        var collector = HeadingCollector(body: body, sourceLineOffset: split.bodyLineOffset)
        collector.visit(Document(parsing: body))
        return collector.headings
    }

    private struct HeadingCollector: MarkupWalker {
        let body: String
        let sourceLineOffset: Int
        var headings: [OutlineHeading] = []
        // Only split when a heading has no range, which most documents never hit.
        private lazy var bodyLines = OutlineHeadingText.lines(of: body)

        init(body: String, sourceLineOffset: Int) {
            self.body = body
            self.sourceLineOffset = sourceLineOffset
        }

        mutating func visitHeading(_ heading: Heading) {
            // Keep empty headings too: IDs follow rendered heading order.
            let line = OutlineHeadingText.startLine(
                of: heading,
                sourceLines: bodyLines,
                previousHeadingLine: headings.last?.sourceLine,
                sourceLineOffset: sourceLineOffset
            )
            headings.append(OutlineHeading(
                level: heading.level,
                title: OutlineHeadingText.plainText(of: heading),
                sourceLine: line + sourceLineOffset
            ))
        }
    }

    /// Builds the outline tree from headings the renderer collected. This is
    /// proportional to the number of headings, not to the document.
    static func tree(from headings: [OutlineHeading]) -> [TOCItem] {
        final class Node {
            let level: Int
            let id: Int
            let title: String
            let sourceLine: Int
            var children: [Node] = []
            init(level: Int, id: Int, title: String, sourceLine: Int) {
                self.level = level
                self.id = id
                self.title = title
                self.sourceLine = sourceLine
            }
            func toItem() -> TOCItem {
                TOCItem(id: id, level: level, title: title, sourceLine: sourceLine,
                        children: children.map { $0.toItem() })
            }
        }

        // Synthetic root is not included in the returned outline.
        let root = Node(level: 0, id: -1, title: "", sourceLine: 0)
        var stack: [Node] = [root]

        for (index, heading) in headings.enumerated() {
            while let top = stack.last, top.level >= heading.level {
                stack.removeLast()
            }
            let node = Node(level: heading.level, id: index,
                            title: heading.title, sourceLine: heading.sourceLine)
            stack.last?.children.append(node)
            stack.append(node)
        }

        return root.children.map { $0.toItem() }
    }
}
