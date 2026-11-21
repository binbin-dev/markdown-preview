import Foundation
import XCTest
@testable import MarkdownHelpers

/// The share link web viewer (server/share-worker/viewer) draws documents
/// with the app's own stylesheet and renderer scripts, exported from
/// `MarkdownHTML` into `viewer/generated/`. This test fails when the copies
/// drift from the app. Set MDP_WRITE_VIEWER_KIT=1 to rewrite them.
final class ShareViewerKitTests: XCTestCase {

    private static let generated = TestVendor.repositoryRoot
        .appendingPathComponent("server/share-worker/viewer/generated")

    private static let header = """
    /* Generated from the app's MarkdownHTML by ShareViewerKitTests.
       Do not edit; run MDP_WRITE_VIEWER_KIT=1 swift test --filter ShareViewerKitTests. */

    """

    static var files: [String: String] {
        [
            // The app page also sets these per user setting; the viewer
            // shows a share the way a fresh install would.
            "markdown.css": header + MarkdownHTML.stylesheet + """

            /* The app's scroll override; printing uses viewer.css's print layout. */
            @media screen {
            \(MarkdownHTML.scrollOverrideCSS)
            }
            :root {
                --mdp-doc-font: \(DocumentFontSetting.defaultSetting.fontFamily);
                --mdp-code-font-size: \(DocumentFontSetting.defaultSetting.codeFontSize);
                --mdp-page-top-clearance: 0px;
                --mdp-chrome-zoom: 1;
            }

            """,
            "renderers.js": header + """
            (function () {
            // The app's renderers log timings through this; the page has no use for them.
            window.MdPreviewPerf = window.MdPreviewPerf || { log() {}, now: () => performance.now() };
            \(MarkdownHTML.highlightAllBody)
            \(MarkdownHTML.mathElementRenderer)
            \(MarkdownHTML.markdownSelectionScript)
            \(MarkdownHTML.tableColumnResizeScript)
            \(MarkdownHTML.codeBlockScript)
            window.MdpRenderers = {
                highlightAll: highlightAll,
                renderMathElement: renderMathElement,
                markdownForSelection: markdownForSelection,
                wrapTables: wrapTables,
                enableTableColumnResize: enableTableColumnResize,
                enableCodeBlocks: enableCodeBlocks,
                // The app's codeBlockMessagesJS in each of its languages.
                codeBlockMessages: {
            \(byLanguage(MarkdownHTML.codeBlockMessagesJS))
                },
            };
            })();

            """,
            // Loaded after pele.global.js, only for documents with diagrams.
            "diagrams.js": header + """
            window.MdpDiagrams = {
                // (messages, copyText) => { bootstrap, renderAll }
                wiring: \(MarkdownHTML.mermaidWiringFunction),
                // The app's diagramMessagesJS in each of its languages.
                messages: {
            \(byLanguage(MarkdownHTML.diagramMessagesJS))
                },
            };

            """,
        ]
    }

    /// The viewer's languages, named as the app's .lproj folders.
    private static let languages = ["en", "de", "ja", "zh-Hans", "pl", "fa"]

    private static func javaScriptKey(_ language: String) -> String {
        language.contains("-") ? MarkdownHTML.javaScriptStringLiteral(language) : language
    }

    private static func localizedStrings(_ language: String) -> [String: String] {
        let url = TestVendor.repositoryRoot.appendingPathComponent("md-preview/\(language).lproj/Localizable.strings")
        return (try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil))
            as? [String: String] ?? [:]
    }

    /// The app's message objects the viewer shows in the reader's language.
    private static let messageObjects = [MarkdownHTML.diagramMessagesJS, MarkdownHTML.codeBlockMessagesJS]

    /// Each string literal of a message object: the app's English.
    private static func texts(in js: String) -> [String] {
        let literal = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        return literal.matches(in: js, range: NSRange(js.startIndex..., in: js)).map { match in
            let quoted = String(js[Range(match.range, in: js)!])
            return (try! JSONSerialization.jsonObject(with: Data("[\(quoted)]".utf8)) as! [String])[0]
        }
    }

    /// `js` with each English text replaced by `language`'s translation from
    /// the app's Localizable.strings.
    static func translated(_ js: String, into language: String) -> String {
        let strings = localizedStrings(language)
        var result = js
        for text in texts(in: js) {
            result = result.replacingOccurrences(of: MarkdownHTML.javaScriptStringLiteral(text),
                                                 with: MarkdownHTML.javaScriptStringLiteral(strings[text] ?? text))
        }
        return result
    }

    /// `en: {…}, ja: {…}, …`, one line per language.
    private static func byLanguage(_ js: String) -> String {
        languages.map { "        \(javaScriptKey($0)): \(translated(js, into: $0))," }.joined(separator: "\n")
    }

    func testEveryViewerTextHasATranslationInEveryLanguage() {
        for js in Self.messageObjects {
            let texts = Self.texts(in: js)
            XCTAssertFalse(texts.isEmpty)
            for language in Self.languages where language != "en" {
                let strings = Self.localizedStrings(language)
                for text in texts {
                    XCTAssertNotNil(strings[text], "\(language) has no translation for \(text.debugDescription)")
                }
            }
        }
    }

    /// `viewer/strings.js` is hand-written, so it can drift from the app's
    /// languages the way the generated files cannot. Every app language needs
    /// a block, and every block needs the same keys as English (a missing key
    /// leaves that label blank instead of falling back).
    func testSharePageStringsCoverEveryAppLanguage() throws {
        let url = TestVendor.repositoryRoot
            .appendingPathComponent("server/share-worker/viewer/strings.js")
        let source = try String(contentsOf: url, encoding: .utf8)

        var blocks: [String: Set<String>] = [:]
        var current: String?
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.drop(while: { $0 == " " })
            if indent == 2, trimmed.hasSuffix("{") {
                let name = trimmed.prefix(while: { $0 != ":" })
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                current = name
                blocks[name] = []
            } else if indent == 2, trimmed.hasPrefix("}") {
                current = nil
            } else if indent == 4, let current, let colon = trimmed.firstIndex(of: ":") {
                blocks[current, default: []].insert(String(trimmed[..<colon]))
            }
        }

        let english = try XCTUnwrap(blocks["en"])
        XCTAssertFalse(english.isEmpty)
        for language in Self.languages {
            let keys = try XCTUnwrap(blocks[language],
                                     "viewer/strings.js has no \(language) block")
            XCTAssertEqual(keys, english, "viewer/strings.js \(language) keys differ from en")
        }
    }

    func testViewerKitMatchesTheApp() throws {
        let rewrite = ProcessInfo.processInfo.environment["MDP_WRITE_VIEWER_KIT"] == "1"
        for (name, contents) in Self.files {
            let url = Self.generated.appendingPathComponent(name)
            if rewrite {
                try FileManager.default.createDirectory(at: Self.generated, withIntermediateDirectories: true)
                try contents.write(to: url, atomically: true, encoding: .utf8)
            }
            let committed = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(committed, contents,
                           "\(name) is out of date; run MDP_WRITE_VIEWER_KIT=1 swift test --filter ShareViewerKitTests")
        }
    }
}
