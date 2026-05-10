import XCTest
@testable import IPTVApp

final class XMLTVParserTests: XCTestCase {

    let parser = XMLTVParser()

    func testParseValidXMLTV() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv generator-info-name="test">
          <channel id="cctv1">
            <display-name>CCTV-1 综合</display-name>
            <icon src="http://logo.com/cctv1.png"/>
          </channel>
          <channel id="cctv2">
            <display-name>CCTV-2 财经</display-name>
          </channel>
          <programme channel="cctv1" start="20260510090000 +0800" stop="20260510100000 +0800">
            <title>新闻联播</title>
            <desc>今日要闻</desc>
            <category>新闻</category>
          </programme>
          <programme channel="cctv1" start="20260510100000 +0800" stop="20260510110000 +0800">
            <title>焦点访谈</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.channels.count, 2)
        XCTAssertEqual(result.channels[0].id, "cctv1")
        XCTAssertEqual(result.channels[0].displayName, "CCTV-1 综合")
        XCTAssertEqual(result.channels[0].iconUrl, "http://logo.com/cctv1.png")
        XCTAssertEqual(result.programs.count, 2)
        XCTAssertEqual(result.programs[0].title, "新闻联播")
        XCTAssertEqual(result.programs[0].category, "新闻")
    }

    func testParseNoChannels() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme channel="cctv1" start="20260510090000 +0800" stop="20260510100000 +0800">
            <title>测试节目</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertTrue(result.channels.isEmpty)
        XCTAssertEqual(result.programs.count, 1)
    }

    func testParseMissingStopTime() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme channel="cctv1" start="20260510090000 +0800">
            <title>无结束时间的节目</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.programs.count, 1)
        let program = result.programs[0]
        // 结束时间应该是开始时间 + 1 小时
        let expectedEnd = program.startTime.addingTimeInterval(3600)
        XCTAssertEqual(program.endTime, expectedEnd)
    }

    func testParseWithTimezone() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme channel="cctv1" start="20260510090000 +0800" stop="20260510100000 +0800">
            <title>带时区的节目</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.programs.count, 1)
        // 验证时间被正确解析为 UTC
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = utcCalendar.component(.hour, from: result.programs[0].startTime)
        // 09:00 +0800 = 01:00 UTC
        XCTAssertEqual(hour, 1)
    }

    func testParseWithoutTimezone() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme channel="cctv1" start="20260510090000" stop="20260510100000">
            <title>无时区节目</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.programs.count, 1)
    }

    func testParseEmptyXML() {
        let data = Data()
        XCTAssertThrowsError(try parser.parse(xml: data)) { error in
            XCTAssertTrue(error is AppError)
        }
    }

    func testParseMalformedXML() {
        let data = Data("这不是XML".utf8)
        XCTAssertThrowsError(try parser.parse(xml: data)) { error in
            XCTAssertTrue(error is AppError)
        }
    }

    func testParseCDATA() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme channel="cctv1" start="20260510090000 +0800" stop="20260510100000 +0800">
            <title><![CDATA[新闻<联播>]]></title>
            <desc><![CDATA[包含 <special> 字符的描述]]></desc>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.programs.count, 1)
        XCTAssertEqual(result.programs[0].title, "新闻<联播>")
        XCTAssertEqual(result.programs[0].description, "包含 <special> 字符的描述")
    }

    func testMultipleProgrammesSameChannel() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="cctv1"><display-name>CCTV-1</display-name></channel>
          <programme channel="cctv1" start="20260510090000 +0800" stop="20260510100000 +0800">
            <title>节目一</title>
          </programme>
          <programme channel="cctv1" start="20260510100000 +0800" stop="20260510110000 +0800">
            <title>节目二</title>
          </programme>
          <programme channel="cctv1" start="20260510110000 +0800" stop="20260510120000 +0800">
            <title>节目三</title>
          </programme>
        </tv>
        """

        let data = Data(xml.utf8)
        let result = try parser.parse(xml: data)

        XCTAssertEqual(result.channels.count, 1)
        XCTAssertEqual(result.programs.count, 3)
    }
}
