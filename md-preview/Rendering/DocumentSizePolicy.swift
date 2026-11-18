//
//  DocumentSizePolicy.swift
//  md-preview
//

import Foundation

/// The size above which the app declines to build a preview.
///
/// Parsing builds a `RawMarkup` tree that costs roughly a hundred times the
/// source: a 40 MB table-heavy document reached 4 GB before the parser was
/// done, twice over because the renderer and the outline each built a tree.
/// Quick Look already refuses the same size, so the preview matches it and
/// explains why instead of hanging the window.
nonisolated enum DocumentSizePolicy {
    static let maximumPreviewBytes = 5 * 1024 * 1024

    static func exceedsPreviewLimit(_ markdown: String) -> Bool {
        markdown.utf8.count > maximumPreviewBytes
    }

    /// Markdown for the placeholder page: rendered through the normal
    /// pipeline, so the preview keeps its theme, bridge and body swaps.
    static func tooLargeMessage(bytes: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let limit = ByteCountFormatter.string(
            fromByteCount: Int64(maximumPreviewBytes), countStyle: .file
        )
        return String(
            format: NSLocalizedString(
                "**This document is too large to preview.**\n\nThe file is %1$@ and the preview limit is %2$@. Split it into smaller files, or open it in an editor that does not render Markdown.",
                comment: "Preview placeholder shown for a Markdown file above the size limit"
            ),
            size,
            limit
        )
    }
}
