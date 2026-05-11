import UIKit
import SnapKit
import MediaPlayer

final class PlayerControlBar: UIView {

    var onPlayPauseTapped: (() -> Void)?
    var onSeekBegan: (() -> Void)?
    var onSeekChanged: ((Float) -> Void)?
    var onSeekEnded: ((Float) -> Void)?
    var onFullscreenTapped: (() -> Void)?
    var onCastingTapped: (() -> Void)?

    private let playPauseButton = UIButton(type: .system)
    private let castingButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let progressSlider = UISlider()
    private let durationLabel = UILabel()
    private let fullscreenButton = UIButton(type: .system)

    private let volumeIcon = UIImageView()
    private let volumeSlider = MPVolumeView()
    private var volumeObserver: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        observeVolume()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let obs = volumeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = 12
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        // Volume row
        volumeIcon.tintColor = .white
        volumeIcon.contentMode = .scaleAspectFit
        updateVolumeIcon()
        addSubview(volumeIcon)

        volumeSlider.showsRouteButton = false
        volumeSlider.tintColor = UIColor(hex: "#FF6B35")
        volumeSlider.setVolumeThumbImage(makeThumb(size: 12), for: .normal)
        if let slider = volumeSlider.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = UIColor(hex: "#FF6B35")
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        }
        addSubview(volumeSlider)

        // Playback row
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(playPauseAction), for: .touchUpInside)

        castingButton.setImage(UIImage(systemName: "airplayvideo"), for: .normal)
        castingButton.tintColor = .white
        castingButton.addTarget(self, action: #selector(castingAction), for: .touchUpInside)

        currentTimeLabel.text = "00:00"
        currentTimeLabel.textColor = .white
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        progressSlider.minimumTrackTintColor = UIColor(hex: "#FF6B35")
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressSlider.setThumbImage(makeThumb(size: 14), for: .normal)
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp), for: .touchUpInside)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp), for: .touchUpOutside)

        durationLabel.text = "00:00"
        durationLabel.textColor = .white
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        fullscreenButton.setImage(UIImage(systemName: "rectangle.arrowtriangle.2.outward"), for: .normal)
        fullscreenButton.tintColor = .white
        fullscreenButton.addTarget(self, action: #selector(fullscreenAction), for: .touchUpInside)

        addSubview(playPauseButton)
        addSubview(castingButton)
        addSubview(fullscreenButton)
        addSubview(currentTimeLabel)
        addSubview(progressSlider)
        addSubview(durationLabel)

        volumeIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.top.equalToSuperview().offset(6)
            make.width.height.equalTo(22)
        }

        volumeSlider.snp.makeConstraints { make in
            make.leading.equalTo(volumeIcon.snp.trailing).offset(4)
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalTo(volumeIcon)
        }

        playPauseButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.top.equalTo(volumeIcon.snp.bottom).offset(4)
            make.bottom.equalTo(safeAreaLayoutGuide).offset(-8)
            make.width.height.equalTo(44)
        }

        castingButton.snp.makeConstraints { make in
            make.leading.equalTo(playPauseButton.snp.trailing).offset(8)
            make.centerY.equalTo(playPauseButton)
            make.width.height.equalTo(36)
        }

        fullscreenButton.snp.makeConstraints { make in
            make.leading.equalTo(castingButton.snp.trailing).offset(8)
            make.centerY.equalTo(playPauseButton)
            make.width.height.equalTo(44)
        }

        currentTimeLabel.snp.makeConstraints { make in
            make.leading.equalTo(fullscreenButton.snp.trailing).offset(8)
            make.centerY.equalTo(playPauseButton)
            make.width.equalTo(42)
        }

        durationLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalTo(playPauseButton)
            make.width.equalTo(42)
        }

        progressSlider.snp.makeConstraints { make in
            make.leading.equalTo(currentTimeLabel.snp.trailing).offset(8)
            make.trailing.equalTo(durationLabel.snp.leading).offset(-8)
            make.centerY.equalTo(playPauseButton)
        }
    }

    private func observeVolume() {
        updateVolumeIcon()
        volumeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateVolumeIcon()
        }
    }

    private func updateVolumeIcon() {
        let vol = AVAudioSession.sharedInstance().outputVolume
        let name: String
        switch vol {
        case 0:       name = "speaker.slash.fill"
        case ..<0.33: name = "speaker.wave.1.fill"
        case ..<0.66: name = "speaker.wave.2.fill"
        default:      name = "speaker.wave.3.fill"
        }
        volumeIcon.image = UIImage(systemName: name)
    }

    func updateProgress(_ progress: Float, animated: Bool = true) {
        progressSlider.setValue(progress, animated: animated)
    }

    func updateCurrentTime(_ text: String) {
        currentTimeLabel.text = text
    }

    func updateDuration(_ text: String) {
        durationLabel.text = text
    }

    func updatePlayPauseButton(isPlaying: Bool) {
        let name = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: name), for: .normal)
    }

    func updateFullscreenButton(isFullscreen: Bool) {
        let name = isFullscreen ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward"
        fullscreenButton.setImage(UIImage(systemName: name), for: .normal)
    }

    func setVisible(_ visible: Bool, animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.25 : 0) {
            self.alpha = visible ? 1 : 0
        }
    }

    func hideSlider(_ hidden: Bool) {
        progressSlider.isHidden = hidden
        currentTimeLabel.isHidden = hidden
        if hidden {
            durationLabel.text = "直播"
        }
    }

    @objc private func playPauseAction() {
        onPlayPauseTapped?()
    }

    @objc private func sliderTouchDown() {
        onSeekBegan?()
    }

    @objc private func sliderValueChanged() {
        onSeekChanged?(progressSlider.value)
    }

    @objc private func sliderTouchUp() {
        onSeekEnded?(progressSlider.value)
    }

    @objc private func fullscreenAction() {
        onFullscreenTapped?()
    }

    @objc private func castingAction() {
        onCastingTapped?()
    }

    func updateCastingButton(isCasting: Bool, deviceName: String?) {
        let symbolName = isCasting ? "airplayvideo" : "airplayvideo"
        castingButton.setImage(UIImage(systemName: symbolName), for: .normal)
        castingButton.tintColor = isCasting ? UIColor(hex: "#4ECDC4") : .white
    }

    private func makeThumb(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
