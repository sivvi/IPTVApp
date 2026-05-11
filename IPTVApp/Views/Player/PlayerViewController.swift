import UIKit
import SnapKit
import Combine

final class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {

    private let viewModel: PlayerViewModel
    private let playerView = PlayerView()
    private let controlBar = PlayerControlBar()
    private let closeButton = UIButton(type: .system)
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private let errorOverlay = UIView()
    private let nowPlayingView = EPGNowPlayingView()
    private let castingStatusOverlay = CastingStatusOverlay()
    private let viewTapRecognizer = UITapGestureRecognizer()

    private var playerAspectConstraint: Constraint?
    private var playerTopConstraint: Constraint?
    private var cancellables = Set<AnyCancellable>()

    init(channel: Channel) {
        self.viewModel = PlayerViewModel(channel: channel)
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
        viewModel.startPlayback()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.resetAutoHideTimer()
        nowPlayingView.configure(epgId: viewModel.channel.epgId)
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

        if let avService = viewModel.playerService as? AVPlayerService {
            playerView.playerLayer.player = avService.player
        }

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 16
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        controlBar.alpha = 0
        view.addSubview(controlBar)

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
            make.trailing.equalToSuperview().offset(-16)
            make.width.height.equalTo(32)
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
                if visible {
                    self?.nowPlayingView.configure(epgId: self?.viewModel.channel.epgId)
                }
            }
            .store(in: &cancellables)

        viewModel.isFullscreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fullscreen in
                self?.controlBar.updateFullscreenButton(isFullscreen: fullscreen)
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
        // Don't intercept taps on the close button or control bar area
        if closeButton.frame.contains(location) { return }
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
