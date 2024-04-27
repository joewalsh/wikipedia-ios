import XCTest

class StringHTMLTests: XCTestCase {
    func testApplyBoldTagToTagContent() throws {
        var testString = "<i>testing</i> 123"
        testString.applyBoldTag(to: "i")
        XCTAssertEqual(testString, "<i>test<b>i</b>ng</i> 123", "Bold tag should be applied to the first match in HTML content, not tags.")
    }
    
    func testApplyBoldTagToHTMLEntity() throws {
        var testString = "<i>Romeo &amp; Juliet</i>".wmf_stringByDecodingHTMLEntities()
        testString.applyBoldTag(to: "&")
        XCTAssertEqual(testString, "<i>Romeo <b>&</b> Juliet</i>", "Bold tag should be applied to the first match in HTML content, not tags.")
    }
    
    func testApplyBoldTagToEndOfString() throws {
        var testString = "<i>12345</i> end"
        testString.applyBoldTag(to: "end")
        XCTAssertEqual(testString, "<i>12345</i> <b>end</b>")
    }

    func testApplyBoldTagToStartOfString() throws {
        var testString = "start <b>12345</b>"
        testString.applyBoldTag(to: "start")
        XCTAssertEqual(testString, "<b>start</b> <b>12345</b>")
    }
}
