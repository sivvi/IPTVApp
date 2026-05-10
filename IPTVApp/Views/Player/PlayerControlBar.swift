import UIKit
import SnapKit

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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = 12
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

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

        fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        fullscreenButton.tintColor = .white
        fullscreenButton.addTarget(self, action: #selector(fullscreenAction), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            playPauseButton, castingButton, currentTimeLabel, progressSlider, durationLabel, fullscreenButton
        ])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        addSubview(stack)

        playPauseButton.snp.makeConstraints { $0.width.height.equalTo(44) }
        castingButton.snp.makeConstraints { $0.width.height.equalTo(36) }
        fullscreenButton.snp.makeConstraints { $0.width.height.equalTo(44) }
        currentTimeLabel.snp.makeConstraints { $0.width.equalTo(42) }
        durationLabel.snp.makeConstraints { $0.width.equalTo(42) }

        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(safeAreaLayoutGuide).offset(-8)
        }
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
        let name = isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
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
