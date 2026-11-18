import XCTest

@testable import MarkdownHelpers

final class RenderedOutlineTests: XCTestCase {
    private func flattened(_ items: [TOCItem]) -> [TOCItem] {
        items.flatMap { [$0] + flattened($0.children) }
    }

    private let sample = """
    ---
    title: Outline
    ---
    # One
    ## Two
    Body.

    ### *Three* and `code`

    > ## Quoted

    ```md
    # Not a heading
    ```

    ## Math $x^2$ and note[^1]

    [^1]: The note.
    """

    func testRenderedOutlineMatchesStandaloneParse() {
        let rendered = MarkdownHTML.render(markdown: sample)
        let expected = flattened(MarkdownTOC.parse(sample))
        let actual = flattened(MarkdownTOC.tree(from: rendered.outline))

        XCTAssertEqual(actual.map(\.level), expected.map(\.level))
        XCTAssertEqual(actual.map(\.title), expected.map(\.title))
        XCTAssertEqual(actual.map(\.sourceLine), expected.map(\.sourceLine))
        XCTAssertEqual(actual.map(\.id), expected.map(\.id))
    }

    func testOutlineRestoresExtractionPlaceholders() {
        let rendered = MarkdownHTML.render(markdown: sample)
        let titles = flattened(MarkdownTOC.tree(from: rendered.outline)).map(\.title)

        XCTAssertTrue(titles.contains("Math $x^2$ and note[^1]"), "\(titles)")
        XCTAssertFalse(titles.contains { $0.contains("MdPreview") }, "\(titles)")
    }

    func testOutlineSkipsHeadingsWithNoParsedRangeOnlyWhenRenderSeesThem() {
        // The same empty-heading fallback the standalone outline uses.
        let markdown = "# A\r\n\r\n #\r\n"
        let rendered = MarkdownHTML.render(markdown: markdown)
        let expected = flattened(MarkdownTOC.parse(markdown))

        XCTAssertEqual(rendered.outline.map(\.sourceLine), expected.map(\.sourceLine))
        XCTAssertEqual(rendered.outline.map(\.level), expected.map(\.level))
    }

    func testOversizedDocumentRendersPlaceholderWithoutBuildingOutline() {
        let markdown = String(repeating: "| a | b |\n| - | - |\n| 1 | 2 |\n", count: 400_000)
        XCTAssertGreaterThan(markdown.utf8.count, DocumentSizePolicy.maximumPreviewBytes)

        let rendered = MarkdownHTML.render(markdown: markdown)

        XCTAssertTrue(rendered.outline.isEmpty)
        XCTAssertTrue(rendered.articleHTML.localizedCaseInsensitiveContains("too large to preview"))
        // The source itself must not ride along into the page.
        XCTAssertLessThan(rendered.articleHTML.utf8.count, 10_000)
        XCTAssertLessThan(rendered.markdown.utf8.count, 10_000)
        XCTAssertFalse(rendered.html.contains("| a | b |"))
    }
}
