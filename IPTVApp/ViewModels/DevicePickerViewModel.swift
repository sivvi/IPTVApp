import Foundation
import Combine

final class DevicePickerViewModel: BaseViewModel {

    let discoveryService = DLNADiscoveryService.shared

    let isScanning = CurrentValueSubject<Bool, Never>(false)
    let selectedDevice = CurrentValueSubject<DLNADevice?, Never>(nil)
    let dlnaDevices = CurrentValueSubject<[DLNADevice], Never>([])
    let isAirPlayAvailable = true

    private var discoveryCancellable: AnyCancellable?
    private var scanningCancellable: AnyCancellable?
    private var errorCancellable: AnyCancellable?

    override init() {
        super.init()
        dlnaDevices.send(discoveryService.discoveredDevices.value)
    }

    func startScan() {
        guard !isScanning.value else { return }

        discoveryCancellable = discoveryService.discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.dlnaDevices.send(devices)
            }

        scanningCancellable = discoveryService.isDiscovering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanning in
                self?.isScanning.send(scanning)
            }

        errorCancellable = discoveryService.discoveryError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage.send(error.localizedDescription)
            }

        discoveryService.startDiscovery()
    }

    func stopScan() {
        discoveryService.stopDiscovery()
        discoveryCancellable?.cancel()
        scanningCancellable?.cancel()
        errorCancellable?.cancel()
    }

    func selectDevice(_ device: DLNADevice) {
        selectedDevice.send(device)
    }

    func clearSelection() {
        selectedDevice.send(nil)
    }
}
