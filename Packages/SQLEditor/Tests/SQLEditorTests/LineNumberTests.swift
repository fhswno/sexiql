import AppKit
import XCTest
@testable import SQLEditor

final class LineNumberTests: XCTestCase {
    func testHardLineCount() {
        XCTAssertEqual(LineNumberGutterView.hardLineCount(""), 1)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("a"), 1)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("a\n"), 2)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("a\nb"), 2)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("a\nb\n"), 3)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("a\n\n"), 3)
        XCTAssertEqual(LineNumberGutterView.hardLineCount("\n"), 2)
    }

    func testHardLineIndex() {
        let s = "ab\ncd\n"
        XCTAssertEqual(LineNumberGutterView.hardLineIndex(at: 0, in: s), 0)
        XCTAssertEqual(LineNumberGutterView.hardLineIndex(at: 2, in: s), 0)
        XCTAssertEqual(LineNumberGutterView.hardLineIndex(at: 3, in: s), 1)
        XCTAssertEqual(LineNumberGutterView.hardLineIndex(at: 5, in: s), 1)
        XCTAssertEqual(LineNumberGutterView.hardLineIndex(at: 6, in: s), 2)
    }

    func testShouldDrawExtraLineNumber() {
        XCTAssertTrue(LineNumberGutterView.shouldDrawExtraLineNumber(for: ""))
        XCTAssertTrue(LineNumberGutterView.shouldDrawExtraLineNumber(for: "a\n"))
        XCTAssertTrue(LineNumberGutterView.shouldDrawExtraLineNumber(for: "a\n\n"))
        XCTAssertFalse(LineNumberGutterView.shouldDrawExtraLineNumber(for: "a"))
        XCTAssertFalse(LineNumberGutterView.shouldDrawExtraLineNumber(for: "a\nb"))
        XCTAssertFalse(LineNumberGutterView.shouldDrawExtraLineNumber(for: "SELECT * FROM users;"))
    }
}

final class LineNumberGeometryTests: XCTestCase {
    private let epsilon: CGFloat = 1.0

    func testSlotCountMatchesHardLines() {
        let cases: [(String, Int)] = [
            ("", 1),
            ("SELECT * FROM users;", 1),
            ("SELECT * FROM users;\n", 2),
            ("SELECT * FROM users;\n\n\n\n", 5),
            ("a\nb\nc", 3),
            ("a\nb\nc\n", 4),
        ]
        for (text, expected) in cases {
            let view = makeEditor(text: text)
            let slots = LineNumberGutterView.lineSlots(for: view)
            XCTAssertEqual(
                slots.count,
                expected,
                "slots for \(String(reflecting: text)): got \(slots.map(\.lineNumber))"
            )
            XCTAssertEqual(slots.map(\.lineNumber), Array(1...expected))
        }
    }

    func testNumberMidYMatchesFragmentMidY() {
        let texts = [
            "SELECT * FROM users;",
            "SELECT * FROM users;\n",
            "SELECT * FROM users;\n\n\n\n",
            "line1\nline2\nline3\n",
            "",
        ]
        for text in texts {
            let view = makeEditor(text: text)
            let slots = LineNumberGutterView.lineSlots(for: view)
            for slot in slots {
                let delta = abs(slot.midY - slot.fragmentInText.midY)
                XCTAssertTrue(
                    delta < 0.01,
                    "line \(slot.lineNumber) midY must equal fragment midY (Δ=\(delta)) text=\(String(reflecting: text))"
                )
            }
        }
    }

    func testCaretLineMidYMatchesSelectedSlot() {
        let text = "SELECT * FROM users;\n\n\n\n"
        let view = makeEditor(text: text)
        let end = (text as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))

        let slots = LineNumberGutterView.lineSlots(for: view)
        guard let last = slots.last else {
            XCTFail("expected slots")
            return
        }
        XCTAssertEqual(last.lineNumber, 5)

        guard let caretMid = LineNumberGutterView.caretLineMidY(for: view) else {
            XCTFail("caret midY nil")
            return
        }
        XCTAssertTrue(
            abs(caretMid - last.midY) < epsilon,
            "caret midY \(caretMid) vs last number midY \(last.midY)"
        )
    }

    func testCaretOnFirstLineMatchesSlot1() {
        let text = "SELECT * FROM users;\n\n"
        let view = makeEditor(text: text)
        view.setSelectedRange(NSRange(location: 0, length: 0))

        let slots = LineNumberGutterView.lineSlots(for: view)
        guard let first = slots.first else {
            XCTFail("expected slots")
            return
        }
        guard let caretMid = LineNumberGutterView.caretLineMidY(for: view) else {
            XCTFail("caret midY nil")
            return
        }
        XCTAssertTrue(
            abs(caretMid - first.midY) < epsilon,
            "caret \(caretMid) vs line1 \(first.midY)"
        )
    }

    func testFragmentHeightsAreUniform() {
        let text = "SELECT * FROM users;\n\n\n\n"
        let view = makeEditor(text: text)
        let slots = LineNumberGutterView.lineSlots(for: view)
        XCTAssertTrue(slots.count >= 2, "need multiple lines")
        let heights = slots.map(\.fragmentInText.height)
        guard let first = heights.first else { return }
        for (index, height) in heights.enumerated() {
            XCTAssertTrue(
                abs(height - first) < epsilon,
                "line \(index + 1) height \(height) != \(first)"
            )
        }
    }

    func testConsecutiveMidsStepByLineHeight() {
        let text = "SELECT * FROM users;\n\n\n\n"
        let view = makeEditor(text: text)
        let slots = LineNumberGutterView.lineSlots(for: view)
        guard slots.count >= 2 else {
            XCTFail("setup")
            return
        }
        let expectedStep = slots[0].fragmentInText.height
        XCTAssertTrue(
            expectedStep >= 16,
            "line box too tight: \(expectedStep)"
        )
        for i in 1..<slots.count {
            let step = slots[i].midY - slots[i - 1].midY
            XCTAssertTrue(
                abs(step - expectedStep) < epsilon,
                "step \(i)→\(i + 1) was \(step), expected ~\(expectedStep)"
            )
        }
    }

    // MARK: - Fixture

    private func makeEditor(text: String) -> SQLEditorTextView {
        _ = NSApplication.shared
        let view = SQLEditorTextView()
        view.setFrameSize(NSSize(width: 640, height: 400))
        view.applyGutterLayout(viewWidth: 640)
        view.string = text
        if let storage = view.textStorage, storage.length > 0 {
            let attrs = SQLEditorTextView.baseTypingAttributes(layoutManager: view.layoutManager)
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
        view.typingAttributes = SQLEditorTextView.baseTypingAttributes(layoutManager: view.layoutManager)
        if let lm = view.layoutManager, let tc = view.textContainer {
            lm.ensureLayout(for: tc)
        }
        view.layoutGutter()
        return view
    }
}
