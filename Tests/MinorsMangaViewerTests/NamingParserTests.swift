import XCTest
@testable import MinorsMangaViewer

final class NamingParserTests: XCTestCase {
    func testDoujinshiParsing() {
        let name = "(C98) [南方ヒトガクシキ (仲村レグラ)] 作品名 (艦隊これくしょん) [無邪気漢化組]"
        let parsed = NamingParser.parse(folderName: name)

        XCTAssertEqual(parsed.prefix, "C98")
        XCTAssertEqual(parsed.creatorInfo, "南方ヒトガクシキ (仲村レグラ)")
        XCTAssertEqual(parsed.title, "作品名")
        XCTAssertEqual(parsed.originalIP, "艦隊これくしょん")
        XCTAssertEqual(parsed.tags, ["無邪気漢化組"])
    }

    func testMangaParsing() {
        let name = "(COMIC 快楽天 2022年2月号) [kakao] 作品名 [漢化組X]"
        let parsed = NamingParser.parse(folderName: name)

        XCTAssertEqual(parsed.prefix, "COMIC 快楽天 2022年2月号")
        XCTAssertEqual(parsed.creatorInfo, "kakao")
        XCTAssertEqual(parsed.title, "作品名")
        XCTAssertNil(parsed.originalIP)
        XCTAssertEqual(parsed.tags, ["漢化組X"])
    }

    func testRawVersionParsing() {
        let name = "(C98) [南方ヒトガクシキ (仲村レグラ)] 作品名 (艦隊これくしょん)"
        let parsed = NamingParser.parse(folderName: name)

        XCTAssertEqual(parsed.tags, [])
        XCTAssertEqual(parsed.originalIP, "艦隊これくしょん")
    }
}
