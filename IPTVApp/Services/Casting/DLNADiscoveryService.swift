import Foundation
import Combine
import Network

final class DLNADiscoveryService: NSObject {

    static let shared = DLNADiscoveryService()

    let discoveredDevices = CurrentValueSubject<[DLNADevice], Never>([])
    let isDiscovering = CurrentValueSubject<Bool, Never>(false)
    let discoveryError = PassthroughSubject<CastingError, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var discoveryTimer: AnyCancellable?
    private var cachedDevice: DLNADevice?
    private var discoveredDeviceMap: [String: DLNADevice] = [:]

    // SSDP multicast
    private var sendConnection: NWConnection?
    private var receiveConnection: NWConnection?
    private let ssdpQueue = DispatchQueue(label: "com.iptvapp.ssdp", qos: .utility)

    private override init() {
        super.init()
    }

    // MARK: - Public

    func startDiscovery(timeout: TimeInterval = Constants.ssdpDiscoveryTimeout) {
        guard !isDiscovering.value else { return }
        isDiscovering.send(true)
        discoveredDeviceMap.removeAll()
        discoveredDevices.send([])

        Logger.player.info("开始DLNA设备发现...")

        // First try cached device
        loadCachedDevice()

        if let cached = cachedDevice {
            pingDevice(cached) { [weak self] reachable in
                if reachable {
                    self?.addDevice(cached)
                    Logger.player.info("缓存设备可达: \(cached.friendlyName)")
                }
            }
        }

        // Start SSDP discovery
        startSSDP()

        // Timeout
        discoveryTimer = Timer.publish(every: timeout, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                self?.stopDiscovery()
            }
    }

    func stopDiscovery() {
        discoveryTimer?.cancel()
        discoveryTimer = nil
        sendConnection?.cancel()
        sendConnection = nil
        receiveConnection?.cancel()
        receiveConnection = nil
        isDiscovering.send(false)
        Logger.player.info("DLNA设备发现结束, 找到\(self.discoveredDeviceMap.count)个设备")
    }

    func refreshDiscovery() {
        stopDiscovery()
        startDiscovery()
    }

    func fetchDeviceDescription(from url: URL) -> AnyPublisher<DLNADevice, CastingError> {
        Future { promise in
            var request = URLRequest(url: url, timeoutInterval: Constants.dlnaSoapTimeout)
            request.httpMethod = "GET"

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    promise(.failure(.connectionFailed(error.localizedDescription)))
                    return
                }
                guard let data, let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    promise(.failure(.deviceUnreachable))
                    return
                }
                do {
                    let parser = DLNADeviceParser()
                    let device = try parser.parse(xml: data, baseURL: url)
                    promise(.success(device))
                } catch let error as CastingError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.connectionFailed(error.localizedDescription)))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }

    // MARK: - SSDP

    private func startSSDP() {
        let host = NWEndpoint.Host(Constants.ssdpMulticastAddress)
        let port = NWEndpoint.Port(rawValue: Constants.ssdpPort)!

        // Listen for SSDP responses
        do {
            let listener = try NWListener(using: .udp, on: .any)
            listener.service = NWListener.Service(type: "_ssdp._udp")

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleSSDPResponse(connection)
            }

            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    Logger.player.info("SSDP监听器就绪")
                }
            }

            listener.start(queue: ssdpQueue)
        } catch {
            Logger.player.error("SSDP监听器创建失败: \(error.localizedDescription)")
        }

        // Send M-SEARCH
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "0.0.0.0", port: .any)

        sendConnection = NWConnection(to: endpoint, using: params)
        sendConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendMSearch()
            case .failed(let error):
                Logger.player.error("SSDP发送连接失败: \(error.localizedDescription)")
            default:
                break
            }
        }
        sendConnection?.start(queue: ssdpQueue)

        // Also create a connection to listen on
        let receiveEndpoint = NWEndpoint.hostPort(host: "0.0.0.0", port: .any)
        let recvParams = NWParameters.udp
        recvParams.allowLocalEndpointReuse = true
        recvParams.requiredLocalEndpoint = receiveEndpoint

        receiveConnection = NWConnection(to: endpoint, using: recvParams)
        receiveConnection?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receiveSSDPResponse()
            }
        }
        receiveConnection?.start(queue: ssdpQueue)
    }

    private func sendMSearch() {
        let msearch =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(Constants.ssdpMulticastAddress):\(Constants.ssdpPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 3\r\n" +
            "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
            "\r\n"

        guard let data = msearch.data(using: .utf8) else { return }

        sendConnection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error {
                Logger.player.error("M-SEARCH发送失败: \(error.localizedDescription)")
                self?.discoveryError.send(.networkUnavailable)
            } else {
                Logger.player.info("M-SEARCH已发送")
            }
        }))
    }

    private func receiveSSDPResponse() {
        receiveConnection?.receiveMessage { [weak self] data, _, _, error in
            if let error {
                Logger.player.error("SSDP接收错误: \(error.localizedDescription)")
                return
            }
            if let data, let response = String(data: data, encoding: .utf8) {
                self?.parseSSDPResponse(response)
            }
            // Continue listening
            self?.receiveSSDPResponse()
        }
    }

    private func handleSSDPResponse(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveOnConnection(connection)
            }
        }
        connection.start(queue: ssdpQueue)
    }

    private func receiveOnConnection(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let error {
                Logger.player.error("SSDP接收错误: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            if let data, let response = String(data: data, encoding: .utf8) {
                self?.parseSSDPResponse(response)
            }
            self?.receiveOnConnection(connection)
        }
    }

    private func parseSSDPResponse(_ response: String) {
        guard response.contains("HTTP/1.1 200") else { return }

        var location: String?
        for line in response.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("location:") {
                location = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard let location, let url = URL(string: location) else { return }

        // Check if already discovered
        let dedupKey = location
        guard discoveredDeviceMap[dedupKey] == nil else { return }

        Logger.player.info("发现SSDP设备: \(location)")

        fetchDeviceDescription(from: url)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.player.error("获取设备描述失败: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] device in
                self?.addDevice(device)
                self?.discoveredDeviceMap[dedupKey] = device
            }
            .store(in: &cancellables)
    }

    // MARK: - Device Cache

    private func loadCachedDevice() {
        guard let data = UserDefaults.standard.data(forKey: Constants.cachedDeviceKey),
              let device = try? JSONDecoder().decode(DLNADevice.self, from: data) else {
            return
        }
        cachedDevice = device
    }

    private func saveCachedDevice(_ device: DLNADevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: Constants.cachedDeviceKey)
    }

    private func pingDevice(_ device: DLNADevice, completion: @escaping (Bool) -> Void) {
        let url = device.baseURL

        var request = URLRequest(url: url, timeoutInterval: 3.0)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                completion(httpResponse.statusCode < 500)
            } else {
                completion(error == nil)
            }
        }.resume()
    }

    private func addDevice(_ device: DLNADevice) {
        var updated = device
        if let cached = cachedDevice, cached.id == device.id {
            updated.isCached = true
        }
        var devices = discoveredDevices.value
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = updated
        } else {
            devices.append(updated)
        }
        discoveredDevices.send(devices)
    }

    func saveAsCached(_ device: DLNADevice) {
        saveCachedDevice(device)
    }
}
