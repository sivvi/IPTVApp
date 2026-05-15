import UIKit
import SnapKit

final class FloatingPlayerView: UIView {

    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?

    private let videoContainer = UIView()
    private let closeButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private var initialCenter: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .black
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
        clipsToBounds = false

        videoContainer.backgroundColor = .black
        videoContainer.layer.cornerRadius = 8
        videoContainer.clipsToBounds = true
        addSubview(videoContainer)
        videoContainer.snp.makeConstraints { $0.edges.equalToSuperview() }

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(6)
            make.width.height.equalTo(24)
        }

        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expandButton.tintColor = .white
        expandButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        expandButton.layer.cornerRadius = 12
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        addSubview(expandButton)
        expandButton.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().offset(6)
            make.width.height.equalTo(24)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(expandTapped))
        addGestureRecognizer(tap)
    }

    // MARK: - Video

    func attachVideo(_ view: UIView) {
        videoContainer.addSubview(view)
        view.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    func detachVideo() -> UIView? {
        let view = videoContainer.subviews.first
        view?.removeFromSuperview()
        videoContainer.subviews.forEach { $0.removeFromSuperview() }
        return view
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func expandTapped() {
        onExpand?()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        switch pan.state {
        case .began:
            initialCenter = center
        case .changed:
            let translation = pan.translation(in: superview)
            center = CGPoint(x: initialCenter.x + translation.x,
                             y: initialCenter.y + translation.y)
        case .ended, .cancelled:
            // Snap to nearest edge
            let margin: CGFloat = 12
            var target = center
            let safeLeft = margin + bounds.width / 2
            let safeRight = superview.bounds.width - margin - bounds.width / 2
            let safeTop = margin + superview.safeAreaInsets.top + bounds.height / 2
            let safeBottom = superview.bounds.height - margin - superview.safeAreaInsets.bottom - bounds.height / 2

            target.x = target.x < superview.bounds.width / 2 ? safeLeft : safeRight
            target.y = max(safeTop, min(safeBottom, target.y))

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.center = target
            }
        default:
            break
        }
    }
}
