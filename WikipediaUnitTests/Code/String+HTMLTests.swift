import XCTest

class StringHTMLTests: XCTestCase {
    func testApplyingBoldTagToTagContent() throws {
        let result = "<i>testing</i> 123".applyingBoldTag(to: "i")
        XCTAssertEqual(result, "<i>test<b>i</b>ng</i> 123", "Bold tag should be applied to the first match in HTML content, not tags.")
    }
    
    func testApplyingBoldTagToHTMLEntity() throws {
        let result = "<i>Romeo &amp; Juliet</i>".wmf_stringByDecodingHTMLEntities().applyingBoldTag(to: "&")
        XCTAssertEqual(result, "<i>Romeo <b>&</b> Juliet</i>", "Bold tag should be applied to the first match in HTML content, not tags.")
    }
    
    func testApplyingBoldTagToEndOfString() throws {
        let result =  "<i>12345</i> end".applyingBoldTag(to: "end")
        XCTAssertEqual(result, "<i>12345</i> <b>end</b>")
    }

    func testApplyingBoldTagToStartOfString() throws {
        let result = "start <b>12345</b>".applyingBoldTag(to: "start")
        XCTAssertEqual(result, "<b>start</b> <b>12345</b>")
    }
    
    func testAR() {
        let result = "توم هانكس".applyingBoldTag(to: "هانكس")
        XCTAssertEqual(result, "توم <b>هانكس</b>")
        let result2 = "توم هانكس".applyingBoldTag(to: "ت")
        XCTAssertEqual(result2, "<b>ت</b>وم هانكس")
    }
    
    func testHE() {
        let result = "& ג'ולייט".applyingBoldTag(to: "ג'ולייט")
        XCTAssertEqual(result, "& <b>ג'ולייט</b>")
        let result2 = "& ג'ולייט".applyingBoldTag(to: "&")
        XCTAssertEqual(result2, "<b>&</b> ג'ולייט")
    }
    
    func testJA() {
        let result = "トム・ハンクス".applyingBoldTag(to: "ハンクス")
        XCTAssertEqual(result, "トム・<b>ハンクス</b>")
    }
    
    func testSR() {
        let result = "Србија".applyingBoldTag(to: "Србија")
        XCTAssertEqual(result, "<b>Србија</b>")
        let result2 = "Србија".applyingBoldTag(to: "ија")
        XCTAssertEqual(result2, "Срб<b>ија</b>")
    }
    
    func testZH() {
        let result = "汤姆·汉克斯".applyingBoldTag(to: "汤姆")
        XCTAssertEqual(result, "<b>汤姆</b>·汉克斯")
    }
}
