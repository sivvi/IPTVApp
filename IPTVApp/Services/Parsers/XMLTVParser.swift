import Foundation

final class XMLTVParser: NSObject, EPGParser {

    private var channels: [String: EPGChannel] = [:]
    private var programs: [Program] = []
    private var parseError: AppError?

    // 当前解析状态
    private var currentElement = ""
    private var currentText = ""

    // 当前 channel
    private var currentChannelId = ""
    private var currentDisplayName = ""
    private var currentIconUrl: String?

    // 当前 programme
    private var currentProgramChannel = ""
    private var currentProgramStart: Date?
    private var currentProgramStop: Date?
    private var currentProgramTitle = ""
    private var currentProgramDesc: String?
    private var currentProgramCategory: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    func parse(xml: Data) throws -> EPGData {
        channels.removeAll()
        programs.removeAll()
        parseError = nil

        let parser = XMLParser(data: xml)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        Logger.parser.info("开始解析XMLTV, 数据大小: \(xml.count) bytes")

        if !parser.parse() {
            if let parseError {
                throw parseError
            }
            if let error = parser.parserError {
                throw AppError.parseError(error.localizedDescription)
            }
            throw AppError.parseError("XML解析失败")
        }

        let channelCount = channels.count
        let programCount = programs.count
        Logger.parser.info("XMLTV解析完成, \(channelCount)个频道, \(programCount)个节目")

        return EPGData(
            sourceUrl: "",
            channels: channels.values.sorted { $0.id < $1.id },
            programs: programs,
            lastUpdated: Date()
        )
    }
}

// MARK: - XMLParserDelegate

extension XMLTVParser: XMLParserDelegate {

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "channel":
            currentChannelId = attributes["id"] ?? ""
            currentDisplayName = ""
            currentIconUrl = nil
        case "icon":
            currentIconUrl = attributes["src"]
        case "programme":
            currentProgramChannel = attributes["channel"] ?? ""
            currentProgramStart = parseDate(attributes["start"])
            currentProgramStop = parseDate(attributes["stop"])
            currentProgramTitle = ""
            currentProgramDesc = nil
            currentProgramCategory = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespaces)

        switch elementName {
        case "channel":
            if !currentChannelId.isEmpty {
                let displayName = currentDisplayName.isEmpty ? currentChannelId : currentDisplayName
                channels[currentChannelId] = EPGChannel(
                    id: currentChannelId,
                    displayName: displayName,
                    iconUrl: currentIconUrl
                )
            }
        case "display-name":
            if currentDisplayName.isEmpty && !text.isEmpty {
                currentDisplayName = text
            }
        case "programme":
            if !currentProgramTitle.isEmpty, let start = currentProgramStart {
                let stop = currentProgramStop ?? start.addingTimeInterval(3600)
                let programId = Program.generateId(channelId: currentProgramChannel, startTime: start)
                programs.append(Program(
                    id: programId,
                    channelId: currentProgramChannel,
                    title: currentProgramTitle,
                    description: currentProgramDesc,
                    startTime: start,
                    endTime: stop,
                    category: currentProgramCategory
                ))
            }
        case "title":
            currentProgramTitle = text
        case "desc":
            if !text.isEmpty { currentProgramDesc = text }
        case "category":
            if !text.isEmpty { currentProgramCategory = text }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil {
            self.parseError = .parseError(parseError.localizedDescription)
        }
    }
}

// MARK: - Private Helpers

extension XMLTVParser {

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        // 尝试标准格式: "20260510190000 +0800"
        if let date = dateFormatter.date(from: raw) {
            return date
        }

        // 去除时区中的空格: "20260510190000 +0800" → "20260510190000+0800"
        let compact = raw.replacingOccurrences(of: " +", with: "+", options: .regularExpression)
        if let date = dateFormatter.date(from: compact) {
            return date
        }

        // 尝试无时区: "20260510190000" (假设UTC)
        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.dateFormat = "yyyyMMddHHmmss"
        if let date = utcFormatter.date(from: raw) ?? utcFormatter.date(from: compact) {
            return date
        }

        return nil
    }
}
