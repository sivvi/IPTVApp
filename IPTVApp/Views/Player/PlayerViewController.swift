import UIKit
import SnapKit
import Combine

final class PlayerViewController: UIViewController {

    private let viewModel: PlayerViewModel
    private let playerView = PlayerView()
    private let controlBar = PlayerControlBar()
    private let closeButton = UIButton(type: .system)
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private let errorOverlay = UIView()

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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if viewModel.isFullscreen.value {
            exitFullscreen()
        }
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        viewModel.isFullscreen.value ? .allButUpsideDown : .portrait
    }

    override var prefersStatusBarHidden: Bool {
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

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        view.addSubview(bufferingIndicator)
        bufferingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        setupErrorOverlay()
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

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("重新播放", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.backgroundColor = UIColor(hex: "#FF6B35")
        retryButton.layer.cornerRadius = 8
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        stack.addArrangedSubview(retryButton)
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

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func retryTapped() {
        errorOverlay.isHidden = true
        viewModel.startPlayback()
    }

    private func toggleFullscreen() {
        let goingFullscreen = !viewModel.isFullscreen.value
        viewModel.toggleFullscreen()

        UIView.animate(withDuration: 0.3) {
            if goingFullscreen {
                self.setupFullscreenConstraints()
            } else {
                self.setupPortraitConstraints()
            }
            self.view.layoutIfNeeded()
            self.setNeedsStatusBarAppearanceUpdate()
        }

        if goingFullscreen {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }

    private func exitFullscreen() {
        viewModel.toggleFullscreen()
        UIView.animate(withDuration: 0.25) {
            self.setupPortraitConstraints()
            self.view.layoutIfNeeded()
        }
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
    }

    private func showErrorOverlay(_ message: String) {
        if let label = errorOverlay.viewWithTag(100) as? UILabel {
            label.text = message
        }
        errorOverlay.isHidden = false
        errorOverlay.alpha = 0
        UIView.animate(withDuration: 0.3) { self.errorOverlay.alpha = 1 }
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
