import UIKit
import AVKit
import MediaPlayer

final class PlayerView: UIView {

    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onSeekBegan: (() -> Void)?
    var onSeekChanged: ((Float) -> Void)?
    var onSeekEnded: ((Float) -> Void)?
    var onVolumeChanged: ((Float) -> Void)?

    var currentProgress: Float = 0
    var isCastingMode: Bool = false

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private let volumeView = MPVolumeView()
    private var volumeSlider: UISlider? {
        volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    private var isHorizontalPan = false
    private var directionDetermined = false
    private var isLeftSide = false
    private var initialProgress: Float = 0
    private var initialBrightness: CGFloat = 0
    private var initialVolume: Float = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        volumeView.isHidden = true
        volumeView.alpha = 0.01
        addSubview(volumeView)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(pan)
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap() {
        onDoubleTap?()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self)
        let location = pan.location(in: self)

        switch pan.state {
        case .began:
            directionDetermined = false

        case .changed:
            if !directionDetermined {
                let dx = abs(translation.x)
                let dy = abs(translation.y)
                isHorizontalPan = dx > dy
                directionDetermined = true

                if isHorizontalPan {
                    initialProgress = currentProgress
                    onSeekBegan?()
                } else {
                    isLeftSide = location.x < bounds.width / 2
                    initialBrightness = UIScreen.main.brightness
                    initialVolume = volumeSlider?.value ?? 0
                }
            }

            if isHorizontalPan {
                let delta = Float(translation.x / bounds.width)
                let newProgress = max(0, min(1, initialProgress + delta))
                onSeekChanged?(newProgress)
            } else {
                let delta = CGFloat(-translation.y / bounds.height)
                if isLeftSide {
                    UIScreen.main.brightness = max(0, min(1, initialBrightness + delta))
                } else if isCastingMode {
                    let newVolume = max(0, min(1, initialVolume + Float(delta)))
                    onVolumeChanged?(newVolume)
                } else {
                    volumeSlider?.value = max(0, min(1, initialVolume + Float(delta)))
                }
            }

        case .ended, .cancelled:
            if isHorizontalPan {
                let delta = Float(translation.x / bounds.width)
                let newProgress = max(0, min(1, initialProgress + delta))
                onSeekEnded?(newProgress)
            }

        default:
            break
        }
    }
}
