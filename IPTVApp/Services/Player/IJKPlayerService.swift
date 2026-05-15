import Foundation
import Combine

extension NSNotification.Name {
    static let ijkLoadStateDidChange = NSNotification.Name("IJKMPMoviePlayerLoadStateDidChangeNotification")
    static let ijkPlaybackStateDidChange = NSNotification.Name("IJKMPMoviePlayerPlaybackStateDidChangeNotification")
    static let ijkPlaybackDidFinish = NSNotification.Name("IJKMPMoviePlayerPlaybackDidFinishNotification")
    static let ijkNaturalSizeAvailable = NSNotification.Name("IJKMPMovieNaturalSizeAvailableNotification")
}

final class IJKPlayerService: NSObject, PlayerServiceProtocol {

    let state = CurrentValueSubject<PlayerState, Never>(.idle)
    let currentTime = CurrentValueSubject<TimeInterval, Never>(0)
    let duration = CurrentValueSubject<TimeInterval, Never>(0)
    let isBuffering = CurrentValueSubject<Bool, Never>(false)

    private(set) var player: IJKFFMoviePlayerController?
    var view: UIView? { player?.view }

    private var timeTimer: Timer?
    private var notificationObservers = [Any]()

    override init() {
        super.init()
    }

    deinit {
        shutdown()
    }

    // MARK: - PlayerServiceProtocol

    func play(url: URL) {
        shutdown()

        guard let options = IJKFFOptions.byDefault() else {
            state.send(.failed(.playbackFailed("无法创建播放器配置")))
            return
        }
        options.setCodecOptionIntValue(0, forKey: "skip_frame")
        options.setCodecOptionIntValue(0, forKey: "skip_loop_filter")
        options.setPlayerOptionIntValue(0, forKey: "videotoolbox")
        options.setPlayerOptionIntValue(1, forKey: "enable-ac3")
        options.setPlayerOptionIntValue(1, forKey: "enable-dts")
        options.setFormatOptionIntValue(15 * 1000 * 1000, forKey: "timeout")
        options.setPlayerOptionIntValue(3000, forKey: "max_cached_duration")

        guard let p = IJKFFMoviePlayerController(contentURL: url, with: options) else {
            state.send(.failed(.playbackFailed("无法创建IJK播放器")))
            return
        }
        p.shouldAutoplay = true
        p.scalingMode = .aspectFit
        p.shouldShowHudView = false
        player = p

        observePlayer(p)
        p.prepareToPlay()

        state.send(.loading)
        Logger.player.info("IJK开始加载: \(url.absoluteString)")
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func stop() {
        shutdown()
        currentTime.send(0)
        duration.send(0)
        isBuffering.send(false)
    }

    func seek(to time: TimeInterval) {
        player?.currentPlaybackTime = time
        currentTime.send(time)
    }

    // MARK: - Private

    private func shutdown() {
        timeTimer?.invalidate()
        timeTimer = nil
        for obs in notificationObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        notificationObservers.removeAll()
        player?.shutdown()
        player = nil
    }

    private func observePlayer(_ p: IJKFFMoviePlayerController) {

        let loadObs = NotificationCenter.default.addObserver(
            forName: .ijkLoadStateDidChange,
            object: p, queue: .main
        ) { [weak self] note in
            guard let self, let player = note.object as? IJKFFMoviePlayerController else { return }
            let loadState = player.loadState
            if loadState.contains(.playthroughOK) || loadState.contains(.playable) {
                self.isBuffering.send(false)
            } else if loadState == .stalled {
                self.isBuffering.send(true)
            }
        }
        notificationObservers.append(loadObs)

        let stateObs = NotificationCenter.default.addObserver(
            forName: .ijkPlaybackStateDidChange,
            object: p, queue: .main
        ) { [weak self] note in
            guard let self, let player = note.object as? IJKFFMoviePlayerController else { return }
            switch player.playbackState {
            case .playing:
                self.state.send(.playing)
                self.isBuffering.send(false)
                self.startTimeTimer(player)
            case .paused:
                self.state.send(.paused)
            case .stopped:
                self.state.send(.stopped)
            case .interrupted:
                self.state.send(.paused)
            case .seekingForward, .seekingBackward:
                break
            @unknown default:
                break
            }
        }
        notificationObservers.append(stateObs)

        let finishObs = NotificationCenter.default.addObserver(
            forName: .ijkPlaybackDidFinish,
            object: p, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = note.userInfo?[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] as? Int
            if reason == IJKMPMovieFinishReason.playbackError.rawValue {
                self.state.send(.failed(.playbackFailed("IJK解码错误")))
                Logger.player.error("IJK播放出错")
            } else {
                self.state.send(.stopped)
            }
        }
        notificationObservers.append(finishObs)

        let sizeObs = NotificationCenter.default.addObserver(
            forName: .ijkNaturalSizeAvailable,
            object: p, queue: .main
        ) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let dur = player.duration
            if dur.isFinite, dur > 0 {
                self.duration.send(dur)
            }
        }
        notificationObservers.append(sizeObs)
    }

    private func startTimeTimer(_ p: IJKFFMoviePlayerController) {
        timeTimer?.invalidate()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            let t = p.currentPlaybackTime
            let d = p.duration
            if t.isFinite, t >= 0 {
                self.currentTime.send(t)
            }
            if d.isFinite, d > 0 {
                self.duration.send(d)
            }
        }
    }
}
