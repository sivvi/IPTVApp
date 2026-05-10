import Foundation

enum PlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(PlayerError)
    case stopped

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}
