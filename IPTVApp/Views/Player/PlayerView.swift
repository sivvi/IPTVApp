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

    // MARK: - Renderers

    private let rendererContainer = UIView()

    private var avLayerView: AVPlayerLayerView = {
        let v = AVPlayerLayerView()
        v.isUserInteractionEnabled = false
        return v
    }()

    private var externalVideoView: UIView? {
        didSet { externalVideoView?.isUserInteractionEnabled = false }
    }

    var playerLayer: AVPlayerLayer { avLayerView.playerLayer }

    func attachAVPlayer(_ player: AVPlayer) {
        externalVideoView?.removeFromSuperview()
        externalVideoView = nil
        avLayerView.playerLayer.player = player
        if avLayerView.superview == nil {
            rendererContainer.addSubview(avLayerView)
            avLayerView.snp.remakeConstraints { $0.edges.equalToSuperview() }
        }
    }

    func attachExternalPlayer(_ videoView: UIView) {
        avLayerView.playerLayer.player = nil
        avLayerView.removeFromSuperview()
        externalVideoView?.removeFromSuperview()
        externalVideoView = videoView
        rendererContainer.addSubview(videoView)
        videoView.snp.remakeConstraints { $0.edges.equalToSuperview() }
    }

    /// Removes and returns the current renderer view (AVPlayerLayerView or external IJK view).
    func detachRenderer() -> UIView? {
        if let ext = externalVideoView {
            ext.removeFromSuperview()
            externalVideoView = nil
            return ext
        }
        if avLayerView.superview != nil {
            avLayerView.removeFromSuperview()
            return avLayerView
        }
        return nil
    }

    /// Re-attaches a renderer view (from floating window) back into this player view.
    func attachRenderer(_ view: UIView) {
        view.removeFromSuperview()
        if view is AVPlayerLayerView {
            externalVideoView?.removeFromSuperview()
            externalVideoView = nil
            // avLayerView is let — re-add the detached one, or use the passed one
            if view !== avLayerView {
                avLayerView.playerLayer.player = nil
                avLayerView.removeFromSuperview()
                (view as? AVPlayerLayerView).map { avLayerView = $0 }
            }
        } else {
            avLayerView.playerLayer.player = nil
            avLayerView.removeFromSuperview()
            externalVideoView = view
        }
        rendererContainer.addSubview(view)
        view.snp.remakeConstraints { $0.edges.equalToSuperview() }
    }

    // MARK: - Volume (pan gesture)

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

        rendererContainer.backgroundColor = .clear
        addSubview(rendererContainer)
        rendererContainer.snp.makeConstraints { $0.edges.equalToSuperview() }

        avLayerView.playerLayer.videoGravity = .resizeAspect
        rendererContainer.addSubview(avLayerView)
        avLayerView.snp.makeConstraints { $0.edges.equalToSuperview() }

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

// MARK: - AVPlayerLayer-backed view

final class AVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
