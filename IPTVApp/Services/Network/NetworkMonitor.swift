import Network
import Combine

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    let isExpensive = CurrentValueSubject<Bool, Never>(false)
    let isAvailable = CurrentValueSubject<Bool, Never>(true)

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.iptvapp.networkmonitor")

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isExpensive.send(path.isExpensive)
            self?.isAvailable.send(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
