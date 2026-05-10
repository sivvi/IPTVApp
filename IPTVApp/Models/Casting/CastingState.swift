import Foundation

enum CastingState: Equatable {
    case idle
    case discovering
    case connecting(to: DLNADevice)
    case connected(DLNADevice)
    case playing(DLNADevice)
    case paused(DLNADevice)
    case disconnected
    case failed(CastingError)

    var isCasting: Bool {
        switch self {
        case .connected, .playing, .paused:
            return true
        default:
            return false
        }
    }

    var currentDevice: DLNADevice? {
        switch self {
        case .connecting(let device), .connected(let device),
             .playing(let device), .paused(let device):
            return device
        default:
            return nil
        }
    }
}
