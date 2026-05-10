import Foundation
import Combine

// MARK: - Brand Compatibility

struct DLNACompatibility {
    let brand: DLNABrand
    let requiresActionDelay: Bool
    let seekMode: SeekMode
    let supportsVolumeControl: Bool
    let supportsPositionInfo: Bool
    let supportsTrackDuration: Bool

    enum SeekMode {
        case relTime
        case absTime
        case unsupported
    }

    static func profile(for device: DLNADevice) -> DLNACompatibility {
        switch device.brand {
        case .xiaomi:
            return DLNACompatibility(
                brand: .xiaomi,
                requiresActionDelay: false,
                seekMode: .absTime,
                supportsVolumeControl: false,
                supportsPositionInfo: true,
                supportsTrackDuration: true
            )
        case .hisense:
            return DLNACompatibility(
                brand: .hisense,
                requiresActionDelay: false,
                seekMode: .relTime,
                supportsVolumeControl: true,
                supportsPositionInfo: true,
                supportsTrackDuration: false
            )
        case .tcl:
            return DLNACompatibility(
                brand: .tcl,
                requiresActionDelay: true,
                seekMode: .relTime,
                supportsVolumeControl: true,
                supportsPositionInfo: true,
                supportsTrackDuration: true
            )
        case .skyworth:
            return DLNACompatibility(
                brand: .skyworth,
                requiresActionDelay: false,
                seekMode: .relTime,
                supportsVolumeControl: true,
                supportsPositionInfo: true,
                supportsTrackDuration: false
            )
        case .sony:
            return DLNACompatibility(
                brand: .sony,
                requiresActionDelay: false,
                seekMode: .relTime,
                supportsVolumeControl: true,
                supportsPositionInfo: true,
                supportsTrackDuration: true
            )
        case .generic:
            return DLNACompatibility(
                brand: .generic,
                requiresActionDelay: false,
                seekMode: .relTime,
                supportsVolumeControl: true,
                supportsPositionInfo: true,
                supportsTrackDuration: true
            )
        }
    }
}

// MARK: - DLNACastingService

final class DLNACastingService: NSObject, PlayerServiceProtocol, CastingServiceProtocol {

    // PlayerServiceProtocol
    let state = CurrentValueSubject<PlayerState, Never>(.idle)
    let currentTime = CurrentValueSubject<TimeInterval, Never>(0)
    let duration = CurrentValueSubject<TimeInterval, Never>(0)
    let isBuffering = CurrentValueSubject<Bool, Never>(false)

    // CastingServiceProtocol
    let castingState = CurrentValueSubject<CastingState, Never>(.idle)
    let discoveredDevices = CurrentValueSubject<[DLNADevice], Never>([])

    // DLNA specific
    let connectedDevice = CurrentValueSubject<DLNADevice?, Never>(nil)
    let volume = CurrentValueSubject<Float, Never>(0.5)

    private var device: DLNADevice?
    private var compatibility = DLNACompatibility(
        brand: .generic,
        requiresActionDelay: false,
        seekMode: .relTime,
        supportsVolumeControl: true,
        supportsPositionInfo: true,
        supportsTrackDuration: true
    )
    private let session: URLSession
    private var heartbeatTimer: AnyCancellable?
    private var positionPollTimer: AnyCancellable?
    private var heartbeatFailures = 0
    private var cancellables = Set<AnyCancellable>()
    private let soapQueue = DispatchQueue(label: "com.iptvapp.dlna.soap", qos: .utility)

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.dlnaSoapTimeout
        config.timeoutIntervalForResource = Constants.dlnaSoapTimeout + 5
        self.session = URLSession(configuration: config)
        super.init()
    }

    // MARK: - CastingServiceProtocol

    func startDiscovery() {
        DLNADiscoveryService.shared.startDiscovery()
    }

    func stopDiscovery() {
        DLNADiscoveryService.shared.stopDiscovery()
    }

    func connect(to device: DLNADevice) -> AnyPublisher<Void, CastingError> {
        castingState.send(.connecting(to: device))

        // Verify device is reachable by fetching its description
        let requestURL = device.baseURL

        var request = URLRequest(url: requestURL, timeoutInterval: 5.0)
        request.httpMethod = "GET"

        return Future { [weak self] promise in
            self?.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                if let error {
                    self.castingState.send(.failed(.connectionFailed(error.localizedDescription)))
                    promise(.failure(.connectionFailed(error.localizedDescription)))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode < 500 else {
                    self.castingState.send(.failed(.deviceUnreachable))
                    promise(.failure(.deviceUnreachable))
                    return
                }

                self.device = device
                self.compatibility = DLNACompatibility.profile(for: device)
                self.connectedDevice.send(device)
                self.castingState.send(.connected(device))
                self.heartbeatFailures = 0
                DLNADiscoveryService.shared.saveAsCached(device)
                Logger.player.info("已连接到DLNA设备: \(device.friendlyName)")
                promise(.success(()))
            }.resume()
        }.eraseToAnyPublisher()
    }

    func disconnect() {
        stopHeartbeat()
        stopPositionPolling()
        sendSOAP(action: "Stop", body: "<InstanceID>0</InstanceID>", serviceType: .avTransport) { _ in
            // Best effort stop
        }
        device = nil
        connectedDevice.send(nil)
        castingState.send(.disconnected)
        state.send(.stopped)
        currentTime.send(0)
        duration.send(0)
        isBuffering.send(false)
        Logger.player.info("DLNA设备已断开")
    }

    // MARK: - PlayerServiceProtocol

    func play(url: URL) {
        guard let device else {
            state.send(.failed(.castFailed("未连接投屏设备")))
            return
        }
        state.send(.loading)
        isBuffering.send(false)

        let setURI = "<InstanceID>0</InstanceID><CurrentURI>\(url.absoluteString)</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>"

        sendSOAP(action: "SetAVTransportURI", body: setURI, serviceType: .avTransport) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if self.compatibility.requiresActionDelay {
                    // TCL TVs need a delay between SetAVTransportURI and Play
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.sendPlayCommand(device)
                    }
                } else {
                    self.sendPlayCommand(device)
                }
            case .failure(let error):
                self.state.send(.failed(.castFailed(error.localizedDescription)))
            }
        }
    }

    private func sendPlayCommand(_ device: DLNADevice) {
        sendSOAP(action: "Play", body: "<InstanceID>0</InstanceID><Speed>1</Speed>", serviceType: .avTransport) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.state.send(.playing)
                self.castingState.send(.playing(device))
                self.startHeartbeat()
                self.startPositionPolling()
                Logger.player.info("DLNA开始播放: \(device.friendlyName)")
            case .failure(let error):
                self.state.send(.failed(.castFailed(error.localizedDescription)))
            }
        }
    }

    func pause() {
        sendSOAP(action: "Pause", body: "<InstanceID>0</InstanceID>", serviceType: .avTransport) { [weak self] result in
            if case .success = result {
                self?.state.send(.paused)
                self?.stopPositionPolling()
                if let device = self?.device {
                    self?.castingState.send(.paused(device))
                }
            }
        }
    }

    func resume() {
        sendSOAP(action: "Play", body: "<InstanceID>0</InstanceID><Speed>1</Speed>", serviceType: .avTransport) { [weak self] result in
            if case .success = result {
                self?.state.send(.playing)
                self?.startPositionPolling()
                if let device = self?.device {
                    self?.castingState.send(.playing(device))
                }
            }
        }
    }

    func stop() {
        disconnect()
    }

    func seek(to time: TimeInterval) {
        guard compatibility.seekMode != .unsupported else {
            Logger.player.info("设备不支持seek操作")
            return
        }

        let unit = compatibility.seekMode == .absTime ? "ABS_TIME" : "REL_TIME"
        let timeStr = formatDLNATime(time)
        let body = "<InstanceID>0</InstanceID><Unit>\(unit)</Unit><Target>\(timeStr)</Target>"

        sendSOAP(action: "Seek", body: body, serviceType: .avTransport) { [weak self] result in
            if case .success = result {
                self?.currentTime.send(time)
            }
        }
    }

    // MARK: - Volume

    func setVolume(_ volume: Float) {
        guard compatibility.supportsVolumeControl, device?.renderingControlURL != nil else { return }
        let vol = Int(volume * 100)
        let body = "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\(vol)</DesiredVolume>"

        sendSOAP(action: "SetVolume", body: body, serviceType: .renderingControl) { [weak self] result in
            if case .success = result {
                self?.volume.send(volume)
            }
        }
    }

    // MARK: - Position Polling

    func getPositionInfo() -> AnyPublisher<(time: TimeInterval, duration: TimeInterval), CastingError> {
        Future { [weak self] promise in
            self?.sendSOAP(
                action: "GetPositionInfo",
                body: "<InstanceID>0</InstanceID>",
                serviceType: .avTransport
            ) { result in
                switch result {
                case .success(let data):
                    if let info = self?.parsePositionInfo(data) {
                        promise(.success(info))
                    } else {
                        promise(.failure(.soapError("无法解析位置信息")))
                    }
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }

    func startPositionPolling(interval: TimeInterval = Constants.dlnaPositionPollInterval) {
        positionPollTimer?.cancel()
        positionPollTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self,
                      self.state.value.isPlaying || self.state.value.isPaused else { return }
                self.getPositionInfo()
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] info in
                        self?.currentTime.send(info.time)
                        if info.duration.isFinite, info.duration > 0 {
                            self?.duration.send(info.duration)
                        }
                    })
                    .store(in: &self.cancellables)
            }
    }

    func stopPositionPolling() {
        positionPollTimer?.cancel()
        positionPollTimer = nil
    }

    // MARK: - Heartbeat

    func startHeartbeat(interval: TimeInterval = Constants.castingHeartbeatInterval) {
        heartbeatTimer?.cancel()
        heartbeatTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendHeartbeat()
            }
    }

    func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        heartbeatFailures = 0
    }

    private func sendHeartbeat() {
        sendSOAP(action: "GetTransportInfo", body: "<InstanceID>0</InstanceID>", serviceType: .avTransport) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                self.heartbeatFailures = 0
                if let state = self.parseTransportState(data) {
                    self.handleTransportState(state)
                }
            case .failure:
                self.heartbeatFailures += 1
                if self.heartbeatFailures >= Constants.dlnaMaxReconnectAttempts {
                    Logger.player.error("DLNA心跳丢失, 断开连接")
                    DispatchQueue.main.async {
                        self.castingState.send(.failed(.heartbeatLost))
                        self.disconnect()
                    }
                }
            }
        }
    }

    private func handleTransportState(_ transportState: String) {
        switch transportState {
        case "PLAYING":
            if case .playing = self.state.value {} else {
                self.state.send(.playing)
            }
        case "PAUSED_PLAYBACK":
            if case .paused = self.state.value {} else {
                self.state.send(.paused)
            }
        case "STOPPED", "NO_MEDIA_PRESENT":
            if case .stopped = self.state.value {} else {
                self.state.send(.stopped)
            }
        default:
            break
        }
    }

    // MARK: - SOAP Client

    private enum ServiceType {
        case avTransport
        case renderingControl

        var serviceURN: String {
            switch self {
            case .avTransport: return "urn:schemas-upnp-org:service:AVTransport:1"
            case .renderingControl: return "urn:schemas-upnp-org:service:RenderingControl:1"
            }
        }
    }

    private func sendSOAP(action: String, body: String, serviceType: ServiceType, completion: @escaping (Result<Data, CastingError>) -> Void) {
        guard let device else {
            completion(.failure(.soapError("设备未连接")))
            return
        }

        let url: URL
        switch serviceType {
        case .avTransport:
            url = device.avTransportURL
        case .renderingControl:
            guard let rcURL = device.renderingControlURL else {
                completion(.failure(.unsupportedAction(action)))
                return
            }
            url = rcURL
        }

        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(serviceType.serviceURN)">
              \(body)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """

        var request = URLRequest(url: url, timeoutInterval: Constants.dlnaSoapTimeout)
        request.httpMethod = "POST"
        request.httpBody = soapBody.data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType.serviceURN)#\(action)\"", forHTTPHeaderField: "SOAPAction")

        Logger.player.info("DLNA SOAP: \(action) → \(url.absoluteString)")

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.soapError(error.localizedDescription)))
                return
            }
            guard let data else {
                completion(.failure(.soapError("无响应数据")))
                return
            }

            // Check for UPnP error in SOAP response
            if let responseStr = String(data: data, encoding: .utf8),
               responseStr.contains("UPnPError") || responseStr.contains("errorCode") {
                // Try to extract error code, but treat most as non-fatal for compatibility
                Logger.player.error("DLNA SOAP错误响应: \(String(data: Data(data.prefix(200)), encoding: .utf8) ?? "unknown")")
            }

            completion(.success(data))
        }.resume()
    }

    // MARK: - XML Parsing Helpers

    private func parsePositionInfo(_ data: Data) -> (time: TimeInterval, duration: TimeInterval)? {
        let parser = XMLParser(data: data)
        let delegate = PositionInfoParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.result : nil
    }

    private func parseTransportState(_ data: Data) -> String? {
        let parser = XMLParser(data: data)
        let delegate = TransportStateParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.transportState : nil
    }

    // MARK: - Formatting

    private func formatDLNATime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Mini XML Parsers for SOAP responses

private final class PositionInfoParser: NSObject, XMLParserDelegate {
    var result: (time: TimeInterval, duration: TimeInterval)?
    private var currentElement = ""
    private var currentText = ""
    private var relTime: String?
    private var trackDuration: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespaces)
        switch elementName {
        case "RelTime": relTime = text
        case "TrackDuration": trackDuration = text
        default: break
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        let time = parseDLNATime(relTime)
        let dur = parseDLNATime(trackDuration)
        if time >= 0, dur >= 0 {
            result = (time, dur)
        } else if time >= 0 {
            result = (time, 0)
        }
    }

    private func parseDLNATime(_ raw: String?) -> TimeInterval {
        guard let raw, !raw.isEmpty else { return -1 }
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return -1 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

private final class TransportStateParser: NSObject, XMLParserDelegate {
    var transportState: String?
    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "CurrentTransportState" {
            transportState = currentText.trimmingCharacters(in: .whitespaces)
        }
    }
}
