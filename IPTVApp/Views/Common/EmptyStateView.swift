import UIKit
import SnapKit

final class EmptyStateView: UIView {
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private var actionButton: UIButton?
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        iconLabel.font = .systemFont(ofSize: 48)
        iconLabel.textAlignment = .center

        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = UIColor(hex: "#636E72")
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        addSubview(iconLabel)
        addSubview(titleLabel)

        iconLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-20)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconLabel.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(32)
            make.trailing.lessThanOrEqualToSuperview().offset(-32)
        }
    }

    func configure(icon: String, title: String, actionTitle: String?, action: (() -> Void)?) {
        iconLabel.text = icon
        titleLabel.text = title

        actionButton?.removeFromSuperview()

        if let actionTitle, let action {
            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(hex: "#FF6B35")
            button.layer.cornerRadius = 12
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            addSubview(button)

            button.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(16)
                make.centerX.equalToSuperview()
                make.width.equalTo(160)
                make.height.equalTo(44)
            }
            actionButton = button
        }
    }
}
