import Foundation
import Combine
import UIKit

final class PlayerViewModel: BaseViewModel {

    let channel: Channel
    let playerService: PlayerServiceProtocol

    let playerState = CurrentValueSubject<PlayerState, Never>(.idle)
    let currentTimeText = CurrentValueSubject<String, Never>("00:00")
    let durationText = CurrentValueSubject<String, Never>("00:00")
    let progress = CurrentValueSubject<Float, Never>(0)
    let isPlayerBuffering = CurrentValueSubject<Bool, Never>(false)
    let isControlBarVisible = CurrentValueSubject<Bool, Never>(true)
    let isFullscreen = CurrentValueSubject<Bool, Never>(false)
    let isSeeking = CurrentValueSubject<Bool, Never>(false)
    let isLiveStream = CurrentValueSubject<Bool, Never>(false)

    private var retryCount = 0
    private var autoHideWorkItem: DispatchWorkItem?
    private var networkCancellable: AnyCancellable?

    init(channel: Channel, playerService: PlayerServiceProtocol = AVPlayerService()) {
        self.channel = channel
        self.playerService = playerService
        super.init()
        setupBindings()
        setupNetworkWarning()
    }

    // MARK: - Public

    func startPlayback() {
        guard let url = URL(string: channel.url) else {
            playerState.send(.failed(.streamNotFound))
            errorMessage.send("无效的频道地址")
            return
        }
        Logger.player.info("开始播放: \(self.channel.name)")
        retryCount = 0
        playerService.play(url: url)
    }

    func togglePlayPause() {
        switch playerState.value {
        case .playing:
            playerService.pause()
        case .paused:
            playerService.resume()
        default:
            break
        }
    }

    func toggleFullscreen() {
        isFullscreen.send(!isFullscreen.value)
    }

    func toggleControlBarVisibility() {
        let newValue = !isControlBarVisible.value
        isControlBarVisible.send(newValue)
        if newValue, playerState.value.isPlaying {
            resetAutoHideTimer()
        }
    }

    func resetAutoHideTimer() {
        autoHideWorkItem?.cancel()
        guard playerState.value.isPlaying else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.isControlBarVisible.send(false)
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.controlBarAutoHideDelay, execute: workItem)
    }

    func beginSeek() {
        isSeeking.send(true)
    }

    func updateSeek(toProgress value: Float) {
        let dur = playerService.duration.value
        guard dur.isFinite, dur > 0 else { return }
        let time = Double(value) * dur
        currentTimeText.send(Self.formatTime(time))
    }

    func endSeek(toProgress value: Float) {
        isSeeking.send(false)
        let dur = playerService.duration.value
        guard dur.isFinite, dur > 0 else { return }
        let clamped = max(0, min(Float(dur), Float(dur) * value))
        playerService.seek(to: TimeInterval(clamped))
        resetAutoHideTimer()
    }

    // MARK: - Private

    private func setupBindings() {
        playerService.state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playerState.send(state)
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        playerService.currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTimeText.send(Self.formatTime(time))
            }
            .store(in: &cancellables)

        playerService.duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                let isLive = !dur.isFinite || dur <= 0
                self?.isLiveStream.send(isLive)
                self?.durationText.send(isLive ? "直播" : Self.formatTime(dur))
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            playerService.currentTime,
            playerService.duration
        )
        .receive(on: DispatchQueue.main)
        .map { time, dur -> Float in
            guard dur.isFinite, dur > 0 else { return 0 }
            return Float(time / dur)
        }
        .sink { [weak self] p in
            guard self?.isSeeking.value == false else { return }
            self?.progress.send(p)
        }
        .store(in: &cancellables)

        playerService.isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPlayerBuffering.send($0) }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: PlayerState) {
        switch state {
        case .playing:
            retryCount = 0
            resetAutoHideTimer()
        case .failed:
            if retryCount < Constants.maxRetryCount {
                retryCount += 1
                let delay = min(pow(2.0, Double(retryCount)), 8.0)
                Logger.player.info("播放失败, \(Int(delay))秒后重试(\(self.retryCount)/\(Constants.maxRetryCount))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, let url = URL(string: self.channel.url) else { return }
                    self.playerService.play(url: url)
                }
            }
        case .stopped:
            autoHideWorkItem?.cancel()
        default:
            break
        }
    }

    private func setupNetworkWarning() {
        networkCancellable = NetworkMonitor.shared.isExpensive
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] expensive in
                guard let self, expensive, self.playerState.value.isPlaying else { return }
                self.errorMessage.send("正在使用移动数据播放")
            }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
