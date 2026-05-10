import UIKit
import SnapKit

final class DeviceCell: UITableViewCell {

    static let reuseIdentifier = "DeviceCell"

    private let deviceIconView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let cachedBadge = UILabel()
    private let signalIndicator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        deviceIconView.contentMode = .scaleAspectFit
        deviceIconView.tintColor = UIColor(hex: "#636E72")
        deviceIconView.image = UIImage(systemName: "tv")
        contentView.addSubview(deviceIconView)

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = UIColor(hex: "#2D3436")
        contentView.addSubview(nameLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor(hex: "#636E72")
        contentView.addSubview(subtitleLabel)

        cachedBadge.text = "已记住"
        cachedBadge.font = .systemFont(ofSize: 11)
        cachedBadge.textColor = UIColor(hex: "#00B894")
        cachedBadge.isHidden = true
        contentView.addSubview(cachedBadge)

        signalIndicator.backgroundColor = UIColor(hex: "#00B894")
        signalIndicator.layer.cornerRadius = 4
        signalIndicator.isHidden = true
        contentView.addSubview(signalIndicator)

        deviceIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }

        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(deviceIconView.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(12)
        }

        cachedBadge.snp.makeConstraints { make in
            make.leading.equalTo(nameLabel.snp.trailing).offset(8)
            make.centerY.equalTo(nameLabel)
        }

        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(2)
            make.bottom.equalToSuperview().offset(-12)
        }

        signalIndicator.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(8)
        }
    }

    func configure(device: DLNADevice, isConnected: Bool = false) {
        nameLabel.text = device.friendlyName

        var subtitle = device.manufacturer ?? ""
        if let model = device.modelName {
            subtitle += subtitle.isEmpty ? model : " · \(model)"
        }
        subtitleLabel.text = subtitle.isEmpty ? "DLNA 设备" : subtitle
        cachedBadge.isHidden = !device.isCached
        signalIndicator.isHidden = !isConnected
        signalIndicator.backgroundColor = isConnected ? UIColor(hex: "#00B894") : UIColor(hex: "#B2BEC3")

        accessoryType = isConnected ? .checkmark : .disclosureIndicator
        tintColor = UIColor(hex: "#FF6B35")

        if let iconUrl = device.iconUrl, let url = URL(string: iconUrl) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.deviceIconView.image = image
                    }
                }
            }.resume()
        }
    }
}
