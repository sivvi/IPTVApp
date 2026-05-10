import Foundation
import Combine
import UIKit
import AVFAudio

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

    // Casting
    let castingState = CurrentValueSubject<CastingState, Never>(.idle)
    let isCasting = CurrentValueSubject<Bool, Never>(false)
    let castingDeviceName = CurrentValueSubject<String?, Never>(nil)

    private let avPlayerService: AVPlayerService
    private let dlnaCastingService = DLNACastingService()
    private var activeService: PlayerServiceProtocol

    private var retryCount = 0
    private var autoHideWorkItem: DispatchWorkItem?
    private var networkCancellable: AnyCancellable?

    init(channel: Channel, playerService: PlayerServiceProtocol = AVPlayerService()) {
        self.channel = channel
        self.playerService = playerService
        self.avPlayerService = playerService as? AVPlayerService ?? AVPlayerService()
        self.activeService = playerService
        super.init()
        bindToService(playerService)
        setupNetworkWarning()
        setupCastingBindings()
        setupAirPlayObserver()
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
        activeService.play(url: url)
    }

    func togglePlayPause() {
        switch playerState.value {
        case .playing:
            activeService.pause()
        case .paused:
            activeService.resume()
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
        let dur = activeService.duration.value
        guard dur.isFinite, dur > 0 else { return }
        let time = Double(value) * dur
        currentTimeText.send(Self.formatTime(time))
    }

    func endSeek(toProgress value: Float) {
        isSeeking.send(false)
        let dur = activeService.duration.value
        guard dur.isFinite, dur > 0 else { return }
        let clamped = max(0, min(Float(dur), Float(dur) * value))
        activeService.seek(to: TimeInterval(clamped))
        resetAutoHideTimer()
    }

    // MARK: - Casting

    func connectToDevice(_ device: DLNADevice) {
        castingState.send(.connecting(to: device))

        dlnaCastingService.connect(to: device)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage.send(error.localizedDescription)
                    self?.castingState.send(.failed(error))
                }
            } receiveValue: { [weak self] in
                self?.onCastingConnected(device)
            }
            .store(in: &cancellables)
    }

    private func onCastingConnected(_ device: DLNADevice) {
        avPlayerService.pause()
        activeService.stop()

        isCasting.send(true)
        castingDeviceName.send(device.friendlyName)

        bindToService(dlnaCastingService)
        activeService = dlnaCastingService

        guard let url = URL(string: channel.url) else { return }
        dlnaCastingService.play(url: url)
    }

    func disconnectCasting() {
        dlnaCastingService.disconnect()

        bindToService(avPlayerService)
        activeService = avPlayerService

        isCasting.send(false)
        castingDeviceName.send(nil)
        castingState.send(.idle)

        avPlayerService.resume()
    }

    func setCastingVolume(_ volume: Float) {
        dlnaCastingService.setVolume(volume)
    }

    // MARK: - Private

    private func bindToService(_ service: PlayerServiceProtocol) {
        service.state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playerState.send(state)
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        service.currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTimeText.send(Self.formatTime(time))
            }
            .store(in: &cancellables)

        service.duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                let isLive = !dur.isFinite || dur <= 0
                self?.isLiveStream.send(isLive)
                self?.durationText.send(isLive ? "直播" : Self.formatTime(dur))
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            service.currentTime,
            service.duration
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

        service.isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPlayerBuffering.send($0) }
            .store(in: &cancellables)
    }

    private func setupCastingBindings() {
        dlnaCastingService.castingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.castingState.send(state)
                self?.isCasting.send(state.isCasting)
                self?.castingDeviceName.send(state.currentDevice?.friendlyName)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: PlayerState) {
        switch state {
        case .playing:
            retryCount = 0
            resetAutoHideTimer()
        case .failed:
            if !isCasting.value, retryCount < Constants.maxRetryCount {
                retryCount += 1
                let delay = min(pow(2.0, Double(retryCount)), 8.0)
                Logger.player.info("播放失败, \(Int(delay))秒后重试(\(self.retryCount)/\(Constants.maxRetryCount))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, let url = URL(string: self.channel.url) else { return }
                    self.activeService.play(url: url)
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

    private func setupAirPlayObserver() {
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }

                let route = AVAudioSession.sharedInstance().currentRoute
                let isAirPlayActive = route.outputs.contains { $0.portType == .airPlay }

                if isAirPlayActive, self.isCasting.value, self.castingState.value.isCasting {
                    // AirPlay activated while DLNA is active: disconnect DLNA
                    self.disconnectCasting()
                    Logger.player.info("AirPlay已激活, 断开了DLNA连接")
                }
            }
            .store(in: &cancellables)
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
