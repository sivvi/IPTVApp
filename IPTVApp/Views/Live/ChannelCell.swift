import UIKit
import SnapKit
import Kingfisher

final class ChannelCell: UITableViewCell {
    static let reuseIdentifier = "ChannelCell"

    private let previewContainer = UIView()
    private let fallbackImageView = UIImageView()

    private let nameLabel = UILabel()
    private let programLabel = UILabel()
    private let favoriteIcon = UIImageView()
    private let statusDot = UIView()
    private let healthLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fallbackImageView.kf.cancelDownloadTask()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .white
        selectionStyle = .none

        previewContainer.clipsToBounds = true
        previewContainer.layer.cornerRadius = 8
        previewContainer.backgroundColor = UIColor(hex: "#F1F2F6")

        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.clipsToBounds = true
        previewContainer.addSubview(fallbackImageView)
        fallbackImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = UIColor(hex: "#2D3436")

        programLabel.font = .systemFont(ofSize: 13)
        programLabel.textColor = UIColor(hex: "#636E72")

        favoriteIcon.image = UIImage(systemName: "star.fill")
        favoriteIcon.tintColor = UIColor(hex: "#FF6B35")
        favoriteIcon.isHidden = true

        statusDot.layer.cornerRadius = 4
        statusDot.backgroundColor = UIColor(hex: "#B2BEC3")

        healthLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        healthLabel.textAlignment = .right
        healthLabel.textColor = UIColor(hex: "#B2BEC3")
        healthLabel.numberOfLines = 2

        contentView.addSubview(previewContainer)
        contentView.addSubview(nameLabel)
        contentView.addSubview(programLabel)
        contentView.addSubview(favoriteIcon)
        contentView.addSubview(statusDot)
        contentView.addSubview(healthLabel)

        previewContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(80)
            make.height.equalTo(48)
        }

        statusDot.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.top.equalToSuperview().offset(16)
            make.width.height.equalTo(8)
        }

        healthLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.top.equalTo(statusDot.snp.bottom).offset(4)
            make.width.equalTo(52)
        }

        favoriteIcon.snp.makeConstraints { make in
            make.trailing.equalTo(healthLabel.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }

        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(previewContainer.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(14)
            make.trailing.equalTo(favoriteIcon.snp.leading).offset(-8)
        }
        programLabel.snp.makeConstraints { make in
            make.leading.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(4)
            make.trailing.equalTo(nameLabel)
        }
    }

    // MARK: - Configure

    func configure(channel: Channel, currentProgram: Program?, health: StreamHealth?) {
        nameLabel.text = channel.name
        programLabel.text = currentProgram?.title ?? "暂无节目信息"
        favoriteIcon.isHidden = !channel.isFavorite

        updateHealth(health)

        if let health, health.isReachable, let thumbnailData = health.thumbnailData {
            fallbackImageView.image = UIImage(data: thumbnailData)
            fallbackImageView.contentMode = .scaleAspectFill
            fallbackImageView.tintColor = nil
        } else if let logoUrl = channel.logoUrl, let url = URL(string: logoUrl) {
            fallbackImageView.kf.setImage(
                with: url,
                placeholder: UIImage(systemName: "tv"),
                options: [.transition(.fade(0.2)), .cacheOriginalImage]
            )
            fallbackImageView.contentMode = .scaleAspectFit
            fallbackImageView.tintColor = nil
        } else {
            fallbackImageView.image = UIImage(systemName: "tv")
            fallbackImageView.contentMode = .scaleAspectFit
            fallbackImageView.tintColor = UIColor(hex: "#B2BEC3")
        }
    }

    func updateHealth(_ health: StreamHealth?) {
        if let health {
            switch health.healthLevel {
            case 2:
                statusDot.backgroundColor = UIColor(hex: "#00B894")
            case 1:
                statusDot.backgroundColor = UIColor(hex: "#FDCB6E")
            default:
                statusDot.backgroundColor = UIColor(hex: "#FF6B35")
            }

            if let ms = health.pingMs {
                healthLabel.text = "\(ms)ms\n\(health.streamType)"
            } else {
                healthLabel.text = "N/A"
            }

            if health.isReachable {
                healthLabel.textColor = UIColor(hex: "#636E72")
            } else {
                statusDot.backgroundColor = UIColor(hex: "#B2BEC3")
                healthLabel.textColor = UIColor(hex: "#B2BEC3")
            }
        } else {
            statusDot.backgroundColor = UIColor(hex: "#B2BEC3")
            healthLabel.text = "—"
            healthLabel.textColor = UIColor(hex: "#B2BEC3")
        }

        // Update thumbnail when health data arrives
        if let health, health.isReachable, let data = health.thumbnailData {
            fallbackImageView.image = UIImage(data: data)
            fallbackImageView.contentMode = .scaleAspectFill
            fallbackImageView.tintColor = nil
        }
    }
}
