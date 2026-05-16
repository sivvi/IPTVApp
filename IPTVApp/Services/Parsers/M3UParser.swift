import Foundation

final class M3UParser: PlaylistParser {

    private(set) var epgUrl: String?

    func parse(content: String) throws -> [Channel] {
        var channels: [Channel] = []
        let normalized = stripBOM(content).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var currentAttrs: [String: String]?
        var currentTitle: String?
        var lineNumber = 0

        for line in lines {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#EXTINF:") {
                // 如果之前有未消费的EXTINF,记录警告
                if currentAttrs != nil {
                    Logger.parser.warning("连续#EXTINF行缺少URL, 第\(lineNumber)行")
                }
                (currentAttrs, currentTitle) = parseExtinfLine(trimmed)
            } else if trimmed.hasPrefix("#EXTM3U") {
                epgUrl = parseHeaderAttribute(trimmed, key: "url-tvg")
                    ?? parseHeaderAttribute(trimmed, key: "x-tvg-url")
            } else if trimmed.hasPrefix("#") {
                // Scan any comment line for EPG URL patterns
                if epgUrl == nil {
                    epgUrl = scanForEpgUrl(in: trimmed)
                }
            } else {
                // URL行
                if let attrs = currentAttrs {
                    let channel = buildChannel(attrs: attrs, title: currentTitle, url: trimmed)
                    channels.append(channel)
                    currentAttrs = nil
                    currentTitle = nil
                }
            }
        }

        Logger.parser.info("M3U解析完成, 共\(channels.count)个频道")
        return channels
    }

    // MARK: - Private

    private func stripBOM(_ content: String) -> String {
        if content.hasPrefix("\u{FEFF}") {
            return String(content.dropFirst())
        }
        return content
    }

    private func parseExtinfLine(_ line: String) -> (attrs: [String: String], title: String?) {
        var attrs: [String: String] = [:]
        var title: String?

        // 去除 #EXTINF: 前缀
        let content = String(line.dropFirst("#EXTINF:".count))

        // 跳过时长部分 (如 -1, 0)
        let afterDuration: String
        let parts = content.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            afterDuration = String(parts[1])
        } else {
            afterDuration = content
        }

        // 提取属性 - 在逗号之前的部分
        if let commaIndex = afterDuration.firstIndex(of: ",") {
            let attrString = String(afterDuration[..<commaIndex])
            title = String(afterDuration[afterDuration.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)

            attrs["tvg-name"] = extractAttribute(attrString, key: "tvg-name")
            attrs["tvg-id"] = extractAttribute(attrString, key: "tvg-id")
            attrs["tvg-logo"] = extractAttribute(attrString, key: "tvg-logo")
            attrs["group-title"] = extractAttribute(attrString, key: "group-title")
        } else {
            title = afterDuration.trimmingCharacters(in: .whitespaces)
        }

        if title?.isEmpty ?? true { title = nil }
        return (attrs, title)
    }

    private func extractAttribute(_ raw: String, key: String) -> String? {
        let pattern = #"\#(key)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let valueRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        let value = String(raw[valueRange])
        return value.isEmpty ? nil : value
    }

    /// Extracts an attribute from a `#EXTM3U` header line (e.g. `url-tvg="..."` or `x-tvg-url="..."`).
    private func parseHeaderAttribute(_ line: String, key: String) -> String? {
        extractAttribute(line, key: key)
    }

    /// Scans a comment line for any EPG-related URL. Handles formats like:
    /// `#EPG:http://...`, `#EXTVLCOPT:...`, `# url-tvg="..."`, bare URLs with epg/xmltv/.xml
    private func scanForEpgUrl(in line: String) -> String? {
        // Try key=value attribute format first
        if let url = extractAttribute(line, key: "url-tvg")
            ?? extractAttribute(line, key: "x-tvg-url")
            ?? extractAttribute(line, key: "epg-url")
            ?? extractAttribute(line, key: "epgurl") {
            return url
        }

        // Try bare URL pattern: any http/https URL containing epg/xmltv/guide keywords
        let urlPattern = #"(https?://[^\s"']+(?:epg|xmltv|guide|xml|tvguide)[^\s"']*\.(?:xml|php|gz|zip))"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = regex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 1), in: line) {
            return String(line[urlRange])
        }

        // Broader: any http URL on a comment line that ends with .xml or .xmltv
        let xmlUrlPattern = #"(https?://[^\s"']+\.xml(?:tv)?)"#
        guard let xmlRegex = try? NSRegularExpression(pattern: xmlUrlPattern, options: .caseInsensitive) else { return nil }
        if let match = xmlRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 1), in: line) {
            return String(line[urlRange])
        }

        return nil
    }

    private func buildChannel(attrs: [String: String], title: String?, url: String) -> Channel {
        let tvgId = attrs["tvg-id"]
        let tvgName = attrs["tvg-name"]
        let channelId = tvgId ?? Channel.generateId(from: url)
        let channelName = tvgName ?? title ?? "频道-\(channelId.prefix(6))"

        return Channel(
            id: channelId,
            name: channelName,
            url: url,
            logoUrl: attrs["tvg-logo"],
            group: attrs["group-title"],
            epgId: tvgId,
            playlistId: nil
        )
    }
}
