import Foundation
import Combine

protocol PlayerServiceProtocol: AnyObject {
    var state: CurrentValueSubject<PlayerState, Never> { get }
    var currentTime: CurrentValueSubject<TimeInterval, Never> { get }
    var duration: CurrentValueSubject<TimeInterval, Never> { get }
    var isBuffering: CurrentValueSubject<Bool, Never> { get }

    func play(url: URL)
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
}
