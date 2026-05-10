import XCTest
@testable import IPTVApp

final class M3UParserTests: XCTestCase {

    let parser = M3UParser()

    func testParseValidM3U() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV-1" tvg-logo="http://logo.com/cctv1.png" group-title="央视",CCTV-1 综合
        http://stream.com/cctv1.m3u8
        #EXTINF:-1 tvg-id="cctv2" tvg-name="CCTV-2" group-title="央视",CCTV-2 财经
        http://stream.com/cctv2.m3u8
        #EXTINF:-1 tvg-id="hunan" tvg-name="湖南卫视" tvg-logo="http://logo.com/hunan.png" group-title="卫视",湖南卫视
        http://stream.com/hunan.m3u8
        """

        let channels = try parser.parse(content: content)

        XCTAssertEqual(channels.count, 3)
        XCTAssertEqual(channels[0].id, "cctv1")
        XCTAssertEqual(channels[0].name, "CCTV-1")
        XCTAssertEqual(channels[0].logoUrl, "http://logo.com/cctv1.png")
        XCTAssertEqual(channels[0].group, "央视")
        XCTAssertEqual(channels[0].url, "http://stream.com/cctv1.m3u8")
    }

    func testParseMinimalM3U() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 ,测试频道
        http://stream.com/test.m3u8
        """

        let channels = try parser.parse(content: content)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "测试频道")
        XCTAssertEqual(channels[0].url, "http://stream.com/test.m3u8")
        XCTAssertNotNil(channels[0].id)
    }

    func testParseEmptyFile() throws {
        let channels = try parser.parse(content: "")
        XCTAssertTrue(channels.isEmpty)
    }

    func testParseNoEXTINF() throws {
        let content = """
        #EXTM3U
        #comment line
        """
        let channels = try parser.parse(content: content)
        XCTAssertTrue(channels.isEmpty)
    }

    func testParseMissingURL() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="cctv1",CCTV-1
        #EXTINF:-1 tvg-id="cctv2",CCTV-2
        http://stream.com/cctv2.m3u8
        """

        let channels = try parser.parse(content: content)
        // 第一个 EXTINF 被丢弃(CCTV-1 缺 URL),只有第二个被解析
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].id, "cctv2")
    }

    func testParseUTF8BOM() throws {
        let content = "\u{FEFF}#EXTM3U\n#EXTINF:-1 tvg-id=\"bomtest\" ,BOM测试\nhttp://stream.com/bom.m3u8\n"

        let channels = try parser.parse(content: content)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].id, "bomtest")
    }

    func testParseSpecialCharacters() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-name="CCTV-1 综合&高清" group-title="央視" ,CCTV-1 <综合>
        http://stream.com/cctv1.m3u8
        """

        let channels = try parser.parse(content: content)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "CCTV-1 综合&高清")
        XCTAssertEqual(channels[0].group, "央視")
    }

    func testParseGroupTitle() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 group-title="央视",CCTV-1
        http://stream.com/cctv1.m3u8
        """

        let channels = try parser.parse(content: content)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].group, "央视")
    }

    func testIdFromTvgId() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="cctv1-custom",CCTV-1
        http://stream.com/cctv1.m3u8
        """

        let channels = try parser.parse(content: content)
        XCTAssertEqual(channels[0].id, "cctv1-custom")
        XCTAssertEqual(channels[0].epgId, "cctv1-custom")
    }

    func testIdFallbackFromURL() throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 ,无ID频道
        http://stream.com/unique-url.m3u8
        """

        let channels = try parser.parse(content: content)
        XCTAssertFalse(channels[0].id.isEmpty)
        XCTAssertNil(channels[0].epgId)
    }

    func testCRLFLineEndings() throws {
        let content = "#EXTM3U\r\n#EXTINF:-1 tvg-id=\"test\",Test\r\nhttp://stream.com/test.m3u8\r\n"

        let channels = try parser.parse(content: content)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].id, "test")
    }
}
