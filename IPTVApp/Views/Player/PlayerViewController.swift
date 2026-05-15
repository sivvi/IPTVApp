import UIKit
import CoreMedia
import AVFoundation
import SnapKit
import Combine

final class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {

    private let viewModel: PlayerViewModel
    private let playerView = PlayerView()
    private let controlBar = PlayerControlBar()
    private let closeButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private let errorOverlay = UIView()
    private let nowPlayingView = EPGNowPlayingView()
    private let infoTagBar = PlayerInfoTagBar()
    private let infoContentScrollView = UIScrollView()
    private let infoContentStack = UIStackView()
    private let castingStatusOverlay = CastingStatusOverlay()
    private let viewTapRecognizer = UITapGestureRecognizer()

    private var playerAspectConstraint: Constraint?
    private var playerTopConstraint: Constraint?
    private var cancellables = Set<AnyCancellable>()
    private var backgroundObserver: Any?

    /// Non-nil when resuming from floating window — renderer view and service already exist.
    private let floatingRenderer: UIView?
    private let floatingService: PlayerServiceProtocol?

    init(channel: Channel) {
        self.viewModel = PlayerViewModel(channel: channel)
        self.floatingRenderer = nil
        self.floatingService = nil
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    init(channel: Channel, renderer: UIView?, service: PlayerServiceProtocol) {
        self.viewModel = PlayerViewModel(channel: channel, playerService: service)
        self.floatingRenderer = renderer
        self.floatingService = service
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupViews()
        setupBindings()
        setupControlBarCallbacks()
        setupPlayerViewCallbacks()
        if let renderer = floatingRenderer {
            playerView.attachRenderer(renderer)
        } else {
            viewModel.startPlayback()
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.autoEnterFloatingMode()
        }
    }

    deinit {
        if let obs = backgroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.resetAutoHideTimer()
        nowPlayingView.configure(epgId: viewModel.channel.epgId)
        infoTagBar.selectTag(at: 1)
        presentProgramList()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Safety net: force portrait before this view leaves the window.
        // If the user double-taps close or a system gesture dismisses us
        // while in landscape, the app would be stuck in landscape forever.
        if viewModel.isFullscreen.value {
            viewModel.toggleFullscreen()
            setupPortraitConstraints()
        }
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.window?.windowScene?.requestGeometryUpdate(
                .iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        viewModel.isFullscreen.value ? .landscape : .portrait
    }

    override var prefersStatusBarHidden: Bool {
        viewModel.isFullscreen.value
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        viewModel.isFullscreen.value
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    // MARK: - Setup

    private func setupViews() {
        view.addSubview(playerView)

        if let renderer = floatingRenderer {
            // Already attached in viewDidLoad, skip default AV setup
        } else if let avService = viewModel.playerService as? AVPlayerService {
            playerView.attachAVPlayer(avService.player)
        }

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 16
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        pipButton.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        pipButton.tintColor = .white
        pipButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        pipButton.layer.cornerRadius = 16
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        view.addSubview(pipButton)

        controlBar.alpha = 0
        view.addSubview(controlBar)

        infoTagBar.alpha = 0
        view.addSubview(infoTagBar)
        setupInfoTagCallbacks()

        infoContentScrollView.alpha = 0
        infoContentScrollView.showsVerticalScrollIndicator = false
        infoContentStack.axis = .vertical
        infoContentStack.spacing = 0
        infoContentStack.alignment = .fill
        infoContentScrollView.addSubview(infoContentStack)
        infoContentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }
        view.addSubview(infoContentScrollView)

        nowPlayingView.alpha = 0
        nowPlayingView.isUserInteractionEnabled = false
        view.addSubview(nowPlayingView)
        nowPlayingView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(controlBar.snp.top)
        }

        castingStatusOverlay.isHidden = true
        castingStatusOverlay.onDisconnectTapped = { [weak self] in
            self?.viewModel.disconnectCasting()
        }
        view.addSubview(castingStatusOverlay)
        castingStatusOverlay.snp.makeConstraints { $0.edges.equalToSuperview() }

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        view.addSubview(bufferingIndicator)
        bufferingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        setupErrorOverlay()

        viewTapRecognizer.delegate = self
        viewTapRecognizer.cancelsTouchesInView = false
        viewTapRecognizer.addTarget(self, action: #selector(viewTapped))
        // Wait for PlayerView's single tap to fire first — if it handles the tap,
        // this recognizer will fail, avoiding a double-toggle.
        if let playerSingleTap = playerView.gestureRecognizers?.first(where: {
            ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired == 1
        }) {
            viewTapRecognizer.require(toFail: playerSingleTap)
        }
        view.addGestureRecognizer(viewTapRecognizer)

        setupPortraitConstraints()
    }

    private func setupErrorOverlay() {
        errorOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        errorOverlay.isHidden = true
        view.addSubview(errorOverlay)
        errorOverlay.snp.makeConstraints { $0.edges.equalToSuperview() }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        errorOverlay.addSubview(stack)
        stack.snp.makeConstraints { $0.center.equalToSuperview() }

        let iconLabel = UILabel()
        iconLabel.text = "⚠️"
        iconLabel.font = .systemFont(ofSize: 48)
        stack.addArrangedSubview(iconLabel)

        let messageLabel = UILabel()
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.tag = 100
        stack.addArrangedSubview(messageLabel)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        stack.addArrangedSubview(buttonRow)

        let exitButton = UIButton(type: .system)
        exitButton.setTitle("返回频道列表", for: .normal)
        exitButton.setTitleColor(UIColor(hex: "#FF6B35"), for: .normal)
        exitButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        exitButton.layer.borderColor = UIColor(hex: "#FF6B35").cgColor
        exitButton.layer.borderWidth = 1
        exitButton.layer.cornerRadius = 8
        exitButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        exitButton.snp.makeConstraints { $0.width.equalTo(100).priority(.high) }
        buttonRow.addArrangedSubview(exitButton)

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("重新播放", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.backgroundColor = UIColor(hex: "#FF6B35")
        retryButton.layer.cornerRadius = 8
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.snp.makeConstraints { $0.width.equalTo(120).priority(.high) }
        buttonRow.addArrangedSubview(retryButton)
    }

    private func setupPortraitConstraints() {
        playerView.snp.remakeConstraints { make in
            playerTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide).constraint
            make.leading.trailing.equalToSuperview()
            playerAspectConstraint = make.height.equalTo(playerView.snp.width).multipliedBy(9.0 / 16.0).constraint
        }

        closeButton.snp.remakeConstraints { make in
            make.top.equalTo(playerView).offset(12)
            make.leading.equalTo(playerView).offset(12)
            make.width.height.equalTo(32)
        }

        pipButton.snp.remakeConstraints { make in
            make.top.equalTo(playerView).offset(12)
            make.trailing.equalTo(playerView).offset(-12)
            make.width.height.equalTo(32)
        }

        infoTagBar.snp.remakeConstraints { make in
            make.top.equalTo(playerView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(64)
        }

        infoContentScrollView.snp.remakeConstraints { make in
            make.top.equalTo(infoTagBar.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(controlBar.snp.top).offset(-8)
        }

        controlBar.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupFullscreenConstraints() {
        playerView.snp.remakeConstraints { make in
            playerTopConstraint = make.top.equalToSuperview().constraint
            make.leading.trailing.bottom.equalToSuperview()
            playerAspectConstraint = nil
        }

        closeButton.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(16)
            make.width.height.equalTo(32)
        }

        pipButton.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.trailing.equalToSuperview().offset(-16)
            make.width.height.equalTo(32)
        }

        infoTagBar.snp.remakeConstraints { make in
            make.top.equalTo(view.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(0)
        }

        infoContentScrollView.snp.remakeConstraints { make in
            make.top.equalTo(infoTagBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(0)
        }

        controlBar.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        viewModel.playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.controlBar.updatePlayPauseButton(isPlaying: state.isPlaying)
                self?.handlePlayerState(state)
            }
            .store(in: &cancellables)

        viewModel.currentTimeText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.controlBar.updateCurrentTime(text)
            }
            .store(in: &cancellables)

        viewModel.durationText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.controlBar.updateDuration(text)
            }
            .store(in: &cancellables)

        viewModel.progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.controlBar.updateProgress(progress)
                self?.playerView.currentProgress = progress
            }
            .store(in: &cancellables)

        viewModel.isControlBarVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.controlBar.setVisible(visible)
                self?.nowPlayingView.setVisible(visible)
                let isFullscreen = self?.viewModel.isFullscreen.value ?? false
                self?.infoTagBar.alpha = (visible && !isFullscreen) ? 1 : 0
                self?.infoContentScrollView.alpha = (visible && !isFullscreen) ? 1 : 0
                if visible {
                    self?.nowPlayingView.configure(epgId: self?.viewModel.channel.epgId)
                }
            }
            .store(in: &cancellables)

        viewModel.isFullscreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fullscreen in
                self?.controlBar.updateFullscreenButton(isFullscreen: fullscreen)
                self?.controlBar.setFillButtonVisible(fullscreen)
                self?.infoTagBar.alpha = fullscreen ? 0 : (self?.controlBar.alpha ?? 0)
                self?.infoContentScrollView.alpha = fullscreen ? 0 : (self?.controlBar.alpha ?? 0)
            }
            .store(in: &cancellables)

        viewModel.isLiveStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLive in
                self?.controlBar.hideSlider(isLive)
            }
            .store(in: &cancellables)

        viewModel.isPlayerBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffering in
                buffering ? self?.bufferingIndicator.startAnimating() : self?.bufferingIndicator.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showErrorToast(message)
            }
            .store(in: &cancellables)

        viewModel.isCasting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] casting in
                self?.playerView.isCastingMode = casting
                self?.playerView.isHidden = casting
                self?.castingStatusOverlay.isHidden = !casting
                self?.controlBar.updateCastingButton(isCasting: casting, deviceName: self?.viewModel.castingDeviceName.value)
            }
            .store(in: &cancellables)

        viewModel.castingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if let name = state.currentDevice?.friendlyName {
                    self?.castingStatusOverlay.configure(deviceName: name, state: state)
                }
            }
            .store(in: &cancellables)

        viewModel.castingDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.controlBar.updateCastingButton(isCasting: name != nil, deviceName: name)
            }
            .store(in: &cancellables)

        viewModel.isUsingIJK
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usingIJK in
                guard let self else { return }
                if !usingIJK {
                    self.playerView.attachAVPlayer(self.viewModel.avPlayerService.player)
                }
            }
            .store(in: &cancellables)

        viewModel.ijkRenderView
            .receive(on: DispatchQueue.main)
            .sink { [weak self] renderView in
                guard let self, let renderView else { return }
                self.playerView.attachExternalPlayer(renderView)
            }
            .store(in: &cancellables)
    }

    private func setupControlBarCallbacks() {
        controlBar.onPlayPauseTapped = { [weak self] in
            self?.viewModel.togglePlayPause()
            self?.viewModel.resetAutoHideTimer()
        }

        controlBar.onSeekBegan = { [weak self] in
            self?.viewModel.beginSeek()
        }

        controlBar.onSeekChanged = { [weak self] value in
            self?.viewModel.updateSeek(toProgress: value)
        }

        controlBar.onSeekEnded = { [weak self] value in
            self?.viewModel.endSeek(toProgress: value)
        }

        controlBar.onFullscreenTapped = { [weak self] in
            self?.toggleFullscreen()
        }

        controlBar.onCastingTapped = { [weak self] in
            self?.presentDevicePicker()
        }

        controlBar.onFillTapped = { [weak self] in
            self?.playerView.toggleFill()
        }
    }

    private func setupInfoTagCallbacks() {
        infoTagBar.onStreamInfoTapped = { [weak self] in
            self?.presentStreamInfo()
        }
        infoTagBar.onProgramListTapped = { [weak self] in
            self?.presentProgramList()
        }
        infoTagBar.onChannelTapped = { [weak self] in
            self?.presentChannelInfo()
        }
        infoTagBar.onSourceTapped = { [weak self] in
            self?.presentSourcePicker()
        }
    }

    private func setupPlayerViewCallbacks() {
        playerView.onSingleTap = { [weak self] in
            self?.viewModel.toggleControlBarVisibility()
        }

        playerView.onDoubleTap = { [weak self] in
            self?.viewModel.togglePlayPause()
        }

        playerView.onSeekBegan = { [weak self] in
            self?.viewModel.beginSeek()
        }

        playerView.onSeekChanged = { [weak self] value in
            self?.viewModel.updateSeek(toProgress: value)
        }

        playerView.onSeekEnded = { [weak self] value in
            self?.viewModel.endSeek(toProgress: value)
        }

        playerView.onVolumeChanged = { [weak self] value in
            self?.viewModel.setCastingVolume(value)
        }
    }

    private func handlePlayerState(_ state: PlayerState) {
        switch state {
        case .loading:
            errorOverlay.isHidden = true
            bufferingIndicator.startAnimating()
        case .playing:
            errorOverlay.isHidden = true
            bufferingIndicator.stopAnimating()
        case .failed(let error):
            bufferingIndicator.stopAnimating()
            showErrorOverlay(error.localizedDescription)
        case .idle, .paused, .stopped:
            bufferingIndicator.stopAnimating()
        }
    }

    // MARK: - Actions

    @objc private func viewTapped(_ gesture: UITapGestureRecognizer) {
        guard !viewModel.isControlBarVisible.value else { return }
        let location = gesture.location(in: view)
        // Don't intercept taps on the close button, PiP button, or control bar area
        if closeButton.frame.contains(location) { return }
        if pipButton.frame.contains(location) { return }
        viewModel.toggleControlBarVisibility()
    }

    @objc private func closeTapped() {
        if viewModel.isFullscreen.value {
            // Exit fullscreen first, then dismiss once the rotation completes.
            // A two-tap flow (first to exit FS, second to dismiss) allows the
            // user to dismiss while the rotation is still in flight, locking
            // the app in landscape. One-tap with a delay avoids that.
            closeButton.isEnabled = false
            viewModel.toggleFullscreen()
            exitFullscreen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.dismiss(animated: true)
            }
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func retryTapped() {
        errorOverlay.isHidden = true
        viewModel.startPlayback()
    }

    @objc private func pipTapped() {
        guard !viewModel.isCasting.value else { return }

        guard let rendererView = playerView.detachRenderer() else { return }

        let service = viewModel.activePlayerService
        FloatingPlayerManager.shared.enterFloatingMode(
            playerService: service,
            videoView: rendererView,
            channel: viewModel.channel
        )

        dismiss(animated: true)
    }

    private func autoEnterFloatingMode() {
        guard !viewModel.isCasting.value else { return }
        guard viewModel.playerState.value.isPlaying else { return }
        guard !FloatingPlayerManager.shared.isActive else { return }

        guard let rendererView = playerView.detachRenderer() else { return }

        let service = viewModel.activePlayerService
        FloatingPlayerManager.shared.enterFloatingMode(
            playerService: service,
            videoView: rendererView,
            channel: viewModel.channel
        )

        dismiss(animated: false)
    }

    private func presentDevicePicker() {
        let pickerVM = DevicePickerViewModel()
        let pickerVC = DevicePickerViewController(viewModel: pickerVM)
        pickerVC.onDeviceSelected = { [weak self] device in
            self?.dismiss(animated: true) {
                self?.viewModel.connectToDevice(device)
            }
        }
        let nav = UINavigationController(rootViewController: pickerVC)
        present(nav, animated: true)
    }

    private func toggleFullscreen() {
        let goingFullscreen = !viewModel.isFullscreen.value
        viewModel.toggleFullscreen()

        if goingFullscreen {
            enterFullscreen()
        } else {
            exitFullscreen()
        }
    }

    private func enterFullscreen() {
        // 1. Switch constraints to fill screen
        setupFullscreenConstraints()
        view.layoutIfNeeded()

        // 2. Force landscape
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            guard let scene = view.window?.windowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }

        UIView.animate(withDuration: 0.3) {
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    private func exitFullscreen() {
        setupPortraitConstraints()
        // Reset fill mode when exiting fullscreen
        if playerView.isFillMode {
            _ = playerView.toggleFill()
        }

        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            guard let scene = view.window?.windowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }

        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    // MARK: - Info tag actions

    private func presentStreamInfo() {
        guard let avService = viewModel.activePlayerService as? AVPlayerService,
              let item = avService.player.currentItem else { return }

        var lines: [(String, String)] = []

        // --- Video ---
        let presSize = item.presentationSize
        if presSize != .zero {
            lines.append(("分辨率", "\(Int(presSize.width)) × \(Int(presSize.height))"))
        }

        if let videoTrack = item.asset.tracks(withMediaType: .video).first {
            let formats: [String] = videoTrack.formatDescriptions.compactMap { desc in
                let str = desc as! CMFormatDescription
                let code = CMFormatDescriptionGetMediaSubType(str)
                return fourCharString(code)
            }
            if let codec = formats.first {
                lines.append(("编码格式", mapVideoCodec(codec)))
            }

            let bitrate = videoTrack.estimatedDataRate
            if bitrate > 0 {
                lines.append(("视频码率", String(format: "%.1f Mbps", bitrate / 1_000_000)))
            }

            let fps = videoTrack.nominalFrameRate
            lines.append(("帧率", String(format: "%.1f fps", fps)))

            if let desc = videoTrack.formatDescriptions.first {
                lines.append(("动态范围", videoDynamicRange(desc as! CMFormatDescription)))
            }
        }

        if let ev = item.accessLog()?.events.last, ev.indicatedBitrate > 0 {
            lines.append(("实际码率", String(format: "%.1f Mbps", ev.indicatedBitrate / 1_000_000)))
        }

        // --- Audio ---
        if let audioTrack = item.asset.tracks(withMediaType: .audio).first {
            let audioFormats: [String] = audioTrack.formatDescriptions.compactMap { desc in
                let str = desc as! CMFormatDescription
                let code = CMFormatDescriptionGetMediaSubType(str)
                return fourCharString(code)
            }
            if let audioCodec = audioFormats.first {
                lines.append(("音频编码", mapAudioCodec(audioCodec)))
            }

            if let desc = audioTrack.formatDescriptions.first {
                let cmDesc = desc as! CMFormatDescription
                if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(cmDesc) {
                    let asbd = asbdPtr.pointee
                    let ch = asbd.mChannelsPerFrame
                    let channelText: String
                    switch ch {
                    case 1:  channelText = "单声道 (1.0)"
                    case 2:  channelText = "立体声 (2.0)"
                    case 6:  channelText = "环绕声 (5.1)"
                    case 8:  channelText = "环绕声 (7.1)"
                    default: channelText = "\(ch)声道"
                    }
                    lines.append(("声道数", channelText))

                    let sampleRate = asbd.mSampleRate
                    lines.append(("采样率", String(format: "%.1f kHz", sampleRate / 1000)))

                    lines.append(("音频类型", audioTypeFromASBD(asbd)))
                }
            }

            let audioBitrate = audioTrack.estimatedDataRate
            if audioBitrate > 0 {
                lines.append(("音频码率", String(format: "%.0f kbps", audioBitrate / 1000)))
            }
        }

        lines.append(("播放类型", viewModel.isUsingIJK.value ? "IJK软解" : "AVPlayer硬解"))

        if lines.isEmpty {
            lines.append(("提示", "流信息加载中，请稍后再试"))
        }
        showInlineContent(title: "视频流信息", rows: lines)
    }

    // MARK: - Stream info helpers

    private func mapVideoCodec(_ codec: String) -> String {
        switch codec {
        case "avc1", "h264", "H264": return "H.264 (AVC)"
        case "hvc1", "hev1", "H265": return "H.265 (HEVC)"
        case "mp4v": return "MPEG-4"
        case "av01": return "AV1"
        case "dvh1", "dvhe": return "Dolby Vision"
        default: return codec
        }
    }

    private func mapAudioCodec(_ codec: String) -> String {
        switch codec {
        case "aac ", "mp4a", "AAC ": return "AAC"
        case "opus": return "Opus"
        case "ac-3", "ac3 ": return "Dolby Digital (AC-3)"
        case "ec-3", "eac3": return "Dolby Digital Plus (E-AC-3)"
        case "alac": return "Apple Lossless (ALAC)"
        case "flac": return "FLAC"
        case "samr": return "AMR"
        case "twos": return "LPCM"
        default: return codec
        }
    }

    private func videoDynamicRange(_ desc: CMFormatDescription) -> String {
        let ext = CMFormatDescriptionGetExtensions(desc) as? [CFString: Any]

        if let tf = ext?[kCMFormatDescriptionExtension_TransferFunction] as? String {
            switch tf {
            case "SMPTE ST 2084 (PQ)":
                return "HDR (PQ)"
            case "ITU-R BT.2100 HLG", "ARIB STD-B67 (HLG)":
                return "HDR (HLG)"
            case "ITU-R BT.2020":
                return "HDR10"
            default:
                break
            }
        }

        if let primaries = ext?[kCMFormatDescriptionExtension_ColorPrimaries] as? String {
            if primaries.contains("2020") { return "HDR" }
        }

        return "SDR"
    }

    private func audioTypeFromASBD(_ asbd: AudioStreamBasicDescription) -> String {
        let ch = asbd.mChannelsPerFrame
        let fmt = asbd.mFormatID
        let bits = asbd.mBitsPerChannel

        var type = ""
        switch fmt {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD:
            type = "AAC"
            if fmt == kAudioFormatMPEG4AAC_HE { type = "HE-AAC" }
            if fmt == kAudioFormatMPEG4AAC_LD { type = "AAC-LD" }
        case kAudioFormatMPEGLayer3:
            type = "MP3"
        case kAudioFormatAC3:
            type = "Dolby Digital"
        case kAudioFormatEnhancedAC3:
            type = "Dolby Digital Plus"
        case kAudioFormatOpus:
            type = "Opus"
        case kAudioFormatFLAC:
            type = "FLAC"
        case kAudioFormatLinearPCM:
            type = "LPCM"
        default:
            type = "Unknown"
        }

        if bits > 0 { type += " \(bits)bit" }
        return type
    }

    private func presentProgramList() {
        let channelId = viewModel.channel.id
        let epgId = viewModel.channel.epgId ?? channelId

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = Date()
            let start = now.addingTimeInterval(-7200) // include currently playing program
            let end = now.addingTimeInterval(86400)
            let programs: [Program]
            do {
                programs = try DatabaseManager.shared.fetchPrograms(for: epgId, from: start, to: end)
            } catch {
                programs = []
            }

            let rows: [(String, String)] = programs.prefix(10).map { p in
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let time = "\(formatter.string(from: p.startTime))-\(formatter.string(from: p.endTime))"
                return (time, p.title)
            }

            DispatchQueue.main.async {
                let name = self?.viewModel.channel.name ?? ""
                if rows.isEmpty {
                    self?.showInlineContent(title: "\(name) — 节目单", rows: [("提示", "暂无节目数据")])
                } else {
                    self?.showInlineContent(title: "\(name) — 节目单", rows: rows)
                }
            }
        }
    }

    private func presentChannelInfo() {
        let ch = viewModel.channel
        var rows: [(String, String)] = [
            ("频道名称", ch.name),
            ("分组", ch.group ?? "未分组"),
            ("EPG ID", ch.epgId ?? "-"),
            ("收藏", ch.isFavorite ? "已收藏" : "未收藏")
        ]
        if let program = (try? DatabaseManager.shared.fetchCurrentProgram(for: ch.epgId ?? ch.id)) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let time = "\(formatter.string(from: program.startTime))-\(formatter.string(from: program.endTime))"
            rows.insert(("正在播出", "\(program.title) (\(time))"), at: 0)
        }
        showInlineContent(title: "频道信息", rows: rows)
    }

    private func presentSourcePicker() {
        let currentURL = viewModel.channel.url
        showInlineContent(title: "线路选择", rows: [("当前线路", currentURL)])
    }

    // MARK: - Inline content

    private func showInlineContent(title: String, rows: [(String, String)]) {
        infoContentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        infoContentStack.addArrangedSubview(titleLabel)

        let titleSpacer = UIView()
        titleSpacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        infoContentStack.addArrangedSubview(titleSpacer)

        for (key, value) in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fill
            row.alignment = .top
            row.spacing = 12
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)

            let keyLabel = UILabel()
            keyLabel.text = key
            keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
            keyLabel.textColor = UIColor(hex: "#B2BEC3")
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.textColor = UIColor(hex: "#DFE6E9")
            valueLabel.numberOfLines = 0

            row.addArrangedSubview(keyLabel)
            row.addArrangedSubview(valueLabel)
            infoContentStack.addArrangedSubview(row)

            let sep = UIView()
            sep.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            infoContentStack.addArrangedSubview(sep)
        }

        // Scroll to top
        infoContentScrollView.setContentOffset(.zero, animated: false)
    }

    private func showErrorOverlay(_ message: String) {
        if let label = errorOverlay.viewWithTag(100) as? UILabel {
            label.text = message
        }
        errorOverlay.isHidden = false
        errorOverlay.alpha = 0
        UIView.animate(withDuration: 0.3) { self.errorOverlay.alpha = 1 }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow the view-level tap to coexist with PlayerView's gestures
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle touches on interactive subviews
        let location = touch.location(in: view)
        if controlBar.alpha > 0.5, controlBar.frame.contains(location) { return false }
        if errorOverlay.alpha > 0.5, !errorOverlay.isHidden { return false }
        return true
    }

    private func showErrorToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.alpha = 0

        view.addSubview(label)
        label.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.equalTo(40)
            make.leading.greaterThanOrEqualToSuperview().offset(40)
        }

        UIView.animate(withDuration: 0.3) { label.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.5) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

// MARK: - Helpers

private func fourCharString(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes.filter { $0 >= 32 && $0 < 127 }, encoding: .ascii) ?? "\(code)"
}
