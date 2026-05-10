import Foundation
import Combine

protocol CastingServiceProtocol: AnyObject {
    var castingState: CurrentValueSubject<CastingState, Never> { get }
    var discoveredDevices: CurrentValueSubject<[DLNADevice], Never> { get }

    func startDiscovery()
    func stopDiscovery()
    func connect(to device: DLNADevice) -> AnyPublisher<Void, CastingError>
    func disconnect()
}
