import Foundation

final class DLNADeviceParser: NSObject {

    private var deviceId = ""
    private var friendlyName = ""
    private var manufacturer: String?
    private var modelName: String?
    private var iconUrl: String?
    private var avTransportURL: URL?
    private var renderingControlURL: URL?
    private var baseURL: URL!

    private var currentElement = ""
    private var currentText = ""
    private var parseError: CastingError?
    private var isParsingService = false
    private var currentServiceType = ""
    private var currentControlURL = ""

    func parse(xml: Data, baseURL: URL) throws -> DLNADevice {
        resetState()
        self.baseURL = baseURL

        let parser = XMLParser(data: xml)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        if !parser.parse() {
            if let parseError { throw parseError }
            if let error = parser.parserError {
                throw CastingError.connectionFailed(error.localizedDescription)
            }
            throw CastingError.connectionFailed("设备描述解析失败")
        }

        guard !deviceId.isEmpty, !friendlyName.isEmpty else {
            throw CastingError.connectionFailed("设备描述缺少必要字段")
        }

        guard let avTransportURL else {
            throw CastingError.connectionFailed("设备不支持AVTransport服务")
        }

        return DLNADevice(
            id: deviceId,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            iconUrl: iconUrl.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteString },
            avTransportURL: avTransportURL,
            renderingControlURL: renderingControlURL,
            baseURL: baseURL,
            discoveryTimestamp: Date()
        )
    }

    private func resetState() {
        deviceId = ""
        friendlyName = ""
        manufacturer = nil
        modelName = nil
        iconUrl = nil
        avTransportURL = nil
        renderingControlURL = nil
        parseError = nil
        isParsingService = false
        currentServiceType = ""
        currentControlURL = ""
    }
}

// MARK: - XMLParserDelegate

extension DLNADeviceParser: XMLParserDelegate {

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "service" {
            isParsingService = true
            currentServiceType = ""
            currentControlURL = ""
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
        case "friendlyName":
            friendlyName = text
        case "manufacturer":
            if !text.isEmpty { manufacturer = text }
        case "modelName":
            if !text.isEmpty { modelName = text }
        case "UDN":
            deviceId = text
        case "url":
            if iconUrl == nil { iconUrl = text }
        case "serviceType":
            if isParsingService { currentServiceType = text }
        case "controlURL":
            if isParsingService { currentControlURL = text }
        case "service":
            isParsingService = false
            guard !currentControlURL.isEmpty else { break }

            let resolvedURL: URL?
            if currentControlURL.hasPrefix("/") {
                resolvedURL = URL(string: currentControlURL, relativeTo: baseURL)
            } else {
                resolvedURL = URL(string: currentControlURL)
            }
            let absoluteURL = resolvedURL?.absoluteURL

            if currentServiceType.contains("AVTransport") {
                avTransportURL = absoluteURL
            } else if currentServiceType.contains("RenderingControl") {
                renderingControlURL = absoluteURL
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil {
            self.parseError = .connectionFailed(parseError.localizedDescription)
        }
    }
}
