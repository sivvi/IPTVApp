import Foundation
import Combine
import AVKit

final class AVPlayerService: PlayerServiceProtocol {

    let state = CurrentValueSubject<PlayerState, Never>(.idle)
    let currentTime = CurrentValueSubject<TimeInterval, Never>(0)
    let duration = CurrentValueSubject<TimeInterval, Never>(0)
    let isBuffering = CurrentValueSubject<Bool, Never>(false)

    let player: AVPlayer

    private var timeObserver: Any?
    private var itemObserverCancellables = Set<AnyCancellable>()
    private var playerObserverCancellables = Set<AnyCancellable>()
    private var interruptionObserverCancellables = Set<AnyCancellable>()

    private var currentURL: URL?
    private var bufferingStartTime: Date?
    private var hasBufferingRetried = false

    init() {
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        setupAudioSession()
        setupPlayerObservers()
        setupTimeObserver()
        setupInterruptionObserver()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }

    // MARK: - Public API

    func play(url: URL) {
        currentURL = url
        state.send(.loading)
        Logger.player.info("开始加载: \(url.absoluteString)")

        tearDownItemObservers()

        let item = AVPlayerItem(url: url)
        setupItemObservers(item)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        tearDownItemObservers()
        currentURL = nil
        bufferingStartTime = nil
        hasBufferingRetried = false
        state.send(.stopped)
        currentTime.send(0)
        duration.send(0)
        isBuffering.send(false)
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.currentTime.send(time)
        }
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.player.currentItem != nil else { return }
            let seconds = time.seconds
            if seconds.isFinite, seconds >= 0 {
                self.currentTime.send(seconds)
            }

            guard self.isBuffering.value, let start = self.bufferingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > Constants.streamTimeout {
                Logger.player.error("缓冲超时(\(Int(elapsed))秒), 播放失败")
                self.stop()
                self.state.send(.failed(.bufferingTimeout))
            } else if elapsed > Constants.bufferingTimeout, !self.hasBufferingRetried, let url = self.currentURL {
                self.hasBufferingRetried = true
                Logger.player.info("缓冲超过\(Int(elapsed))秒, 自动重试")
                self.play(url: url)
            }
        }
    }

    // MARK: - Player Observers (timeControlStatus + didPlayToEnd)

    private func setupPlayerObservers() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.player.currentItem != nil else { return }
                switch status {
                case .playing:
                    self.state.send(.playing)
                    self.isBuffering.send(false)
                case .paused:
                    if self.state.value != .stopped {
                        self.state.send(.paused)
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering.send(true)
                @unknown default:
                    break
                }
            }
            .store(in: &playerObserverCancellables)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.state.send(.stopped)
            }
            .store(in: &playerObserverCancellables)
    }

    // MARK: - Item Observers (status, duration, buffering)

    private func setupItemObservers(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .failed:
                    let msg = item.error?.localizedDescription ?? "未知错误"
                    self.state.send(.failed(.playbackFailed(msg)))
                    Logger.player.error("播放失败: \(msg)")
                case .readyToPlay:
                    let dur = item.duration.seconds
                    if dur.isFinite, dur > 0 {
                        self.duration.send(dur)
                        Logger.player.info("时长: \(Int(dur))秒")
                    }
                default:
                    break
                }
            }
            .store(in: &itemObserverCancellables)

        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                let seconds = dur.seconds
                guard seconds.isFinite, seconds > 0 else { return }
                self?.duration.send(seconds)
            }
            .store(in: &itemObserverCancellables)

        Publishers.CombineLatest(
            item.publisher(for: \.isPlaybackLikelyToKeepUp),
            item.publisher(for: \.isPlaybackBufferEmpty)
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] keepUp, bufferEmpty in
            let buffering = !keepUp && bufferEmpty
            self?.isBuffering.send(buffering)
            if buffering {
                if self?.bufferingStartTime == nil {
                    self?.bufferingStartTime = Date()
                }
            } else {
                self?.bufferingStartTime = nil
                self?.hasBufferingRetried = false
            }
        }
        .store(in: &itemObserverCancellables)
    }

    private func tearDownItemObservers() {
        itemObserverCancellables.removeAll()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            Logger.player.error("音频会话配置失败: \(error.localizedDescription)")
        }
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let interruptionType = AVAudioSession.InterruptionType(rawValue: type)
                else { return }

                switch interruptionType {
                case .began:
                    self.player.pause()
                    Logger.player.info("音频中断(通话/闹钟), 暂停播放")

                case .ended:
                    if let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                       AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        self.player.play()
                        Logger.player.info("音频中断结束, 恢复播放")
                    }

                @unknown default:
                    break
                }
            }
            .store(in: &interruptionObserverCancellables)
    }
}
