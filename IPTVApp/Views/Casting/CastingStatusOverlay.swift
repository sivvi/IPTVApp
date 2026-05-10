import UIKit
import SnapKit

final class CastingStatusOverlay: UIView {

    var onDisconnectTapped: (() -> Void)?

    private let deviceIconView = UIImageView()
    private let statusLabel = UILabel()
    private let deviceNameLabel = UILabel()
    private let hintLabel = UILabel()
    private let disconnectButton = UIButton(type: .system)
    private let waveLayer = CAShapeLayer()
    private var waveAnimation: CABasicAnimation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.85)

        deviceIconView.image = UIImage(systemName: "tv.inset.filled")
        deviceIconView.tintColor = UIColor(hex: "#4ECDC4")
        deviceIconView.contentMode = .scaleAspectFit
        addSubview(deviceIconView)

        statusLabel.text = "正在投屏到"
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        deviceNameLabel.textColor = .white
        deviceNameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        deviceNameLabel.textAlignment = .center
        addSubview(deviceNameLabel)

        hintLabel.text = "点击断开投屏"
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textAlignment = .center
        addSubview(hintLabel)

        disconnectButton.setTitle("断开投屏", for: .normal)
        disconnectButton.setTitleColor(UIColor(hex: "#FF6B35"), for: .normal)
        disconnectButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        disconnectButton.layer.borderColor = UIColor(hex: "#FF6B35").cgColor
        disconnectButton.layer.borderWidth = 1
        disconnectButton.layer.cornerRadius = 8
        disconnectButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
        disconnectButton.addTarget(self, action: #selector(disconnectAction), for: .touchUpInside)
        addSubview(disconnectButton)

        deviceIconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-60)
            make.width.height.equalTo(56)
        }

        statusLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(deviceIconView.snp.bottom).offset(16)
        }

        deviceNameLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(statusLabel.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(32)
        }

        hintLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(deviceNameLabel.snp.bottom).offset(12)
        }

        disconnectButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(hintLabel.snp.bottom).offset(24)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    func configure(deviceName: String, state: CastingState) {
        deviceNameLabel.text = deviceName

        switch state {
        case .connecting:
            statusLabel.text = "正在连接..."
        case .playing:
            statusLabel.text = "正在投屏到"
        case .paused:
            statusLabel.text = "投屏已暂停 —"
        case .connected:
            statusLabel.text = "已连接到"
        default:
            break
        }
    }

    @objc private func disconnectAction() {
        onDisconnectTapped?()
    }

    @objc private func handleTap() {
        onDisconnectTapped?()
    }
}
